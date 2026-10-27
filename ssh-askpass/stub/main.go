// noctalia-ssh-askpass: SSH_ASKPASS stub that proxies to the noctalia shell.
//
// The OpenSSH askpass contract:
//
//	argv[1]            prompt text
//	SSH_ASKPASS_PROMPT "confirm" => yes/no mode (exit code is the answer)
//	stdout             passphrase (prompt mode only)
//	exit 0             OK / approve, anything else cancels / denies
//
// Plugin IPC is one-way, so the request carries the path of a reply file
// inside a fresh 0700 directory under $XDG_RUNTIME_DIR. The plugin writes
// {"ok":bool,"value":string} there. Every failure path denies.
package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// Longer than the dialog's own auto-deny so queued requests get their turn.
const waitTimeout = 10 * time.Minute

type request struct {
	ID     string `json:"id"`
	Mode   string `json:"mode"`
	Prompt string `json:"prompt"`
	Reply  string `json:"reply"`
}

type response struct {
	OK    bool   `json:"ok"`
	Value string `json:"value"`
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "noctalia-ssh-askpass: "+format+"\n", args...)
	os.Exit(1)
}

func findDisplay(rt string) (string, error) {
	socks, err := filepath.Glob(filepath.Join(rt, "noctalia-*.sock"))
	if err != nil {
		return "", err
	}
	var displays []string
	for _, sock := range socks {
		display := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(sock), "noctalia-"), ".sock")
		if fi, err := os.Stat(filepath.Join(rt, display)); err == nil && fi.Mode()&os.ModeSocket != 0 {
			displays = append(displays, display)
		}
	}
	switch len(displays) {
	case 0:
		return "", fmt.Errorf("WAYLAND_DISPLAY not set and no running noctalia found in %s", rt)
	case 1:
		return displays[0], nil
	default:
		return "", fmt.Errorf("WAYLAND_DISPLAY not set and several noctalia instances running: %s", strings.Join(displays, ", "))
	}
}

func ask(rt string, req request) (response, error) {
	payload, err := json.Marshal(req)
	if err != nil {
		return response{}, err
	}
	cmd := exec.Command("noctalia", "msg", "plugin", "mic92/ssh-askpass:service", "all", "ask", string(payload))
	if os.Getenv("WAYLAND_DISPLAY") == "" {
		display, err := findDisplay(rt)
		if err != nil {
			return response{}, err
		}
		cmd.Env = append(os.Environ(), "WAYLAND_DISPLAY="+display)
	}
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return response{}, fmt.Errorf("noctalia msg: %w", err)
	}

	deadline := time.Now().Add(waitTimeout)
	for time.Now().Before(deadline) {
		data, err := os.ReadFile(req.Reply)
		if err == nil {
			var resp response
			if err := json.Unmarshal(data, &resp); err != nil {
				return response{}, fmt.Errorf("bad reply: %w", err)
			}
			return resp, nil
		}
		if !os.IsNotExist(err) {
			return response{}, err
		}
		time.Sleep(100 * time.Millisecond)
	}
	return response{}, fmt.Errorf("no answer within %s", waitTimeout)
}

func main() {
	mode := "prompt"
	if os.Getenv("SSH_ASKPASS_PROMPT") == "confirm" {
		mode = "confirm"
	}

	rt := os.Getenv("XDG_RUNTIME_DIR")
	if rt == "" {
		fail("XDG_RUNTIME_DIR not set")
	}
	base := filepath.Join(rt, "noctalia-ssh-askpass")
	if err := os.MkdirAll(base, 0o700); err != nil {
		fail("%v", err)
	}
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		fail("%v", err)
	}
	id := hex.EncodeToString(raw[:])
	// 0700 keeps the passphrase private regardless of the shell's umask.
	dir := filepath.Join(base, id)
	if err := os.Mkdir(dir, 0o700); err != nil {
		fail("%v", err)
	}
	// The plugin skips requests whose directory is gone, so removing it
	// on every exit path also withdraws the prompt.
	cleanup := func() { _ = os.RemoveAll(dir) }
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	go func() {
		<-sigs
		cleanup()
		os.Exit(1)
	}()

	resp, err := ask(rt, request{
		ID:     id,
		Mode:   mode,
		Prompt: strings.Join(os.Args[1:], " "),
		Reply:  filepath.Join(dir, "reply"),
	})
	cleanup()
	if err != nil {
		fail("%v", err)
	}
	if !resp.OK {
		os.Exit(1)
	}
	if mode == "prompt" {
		fmt.Print(resp.Value)
	}
}
