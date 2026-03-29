// noctalia-ssh-askpass: SSH_ASKPASS stub that proxies to the noctalia shell.
//
// The OpenSSH askpass contract:
//   argv[1]           prompt text
//   SSH_ASKPASS_PROMPT env: "confirm" => yes/no mode (exit code is the answer)
//   stdout            passphrase (prompt mode only)
//   exit 0            OK / approve
//   exit !0           cancel / deny
//
// We speak line-delimited JSON to $XDG_RUNTIME_DIR/noctalia-ssh-askpass.sock
// which the ssh-askpass noctalia plugin listens on. If the socket isn't there
// (shell not running) we fail closed — ssh-agent will report "agent refused".
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
)

type request struct {
	Mode string `json:"mode"`
	Text string `json:"text"`
}

type response struct {
	OK    bool   `json:"ok"`
	Value string `json:"value"`
}

func main() {
	prompt := ""
	if len(os.Args) > 1 {
		prompt = strings.Join(os.Args[1:], " ")
	}

	mode := "prompt"
	if os.Getenv("SSH_ASKPASS_PROMPT") == "confirm" {
		mode = "confirm"
	}

	rt := os.Getenv("XDG_RUNTIME_DIR")
	if rt == "" {
		fmt.Fprintln(os.Stderr, "noctalia-ssh-askpass: XDG_RUNTIME_DIR not set")
		os.Exit(1)
	}
	sock := filepath.Join(rt, "noctalia-ssh-askpass.sock")

	conn, err := net.Dial("unix", sock)
	if err != nil {
		fmt.Fprintf(os.Stderr, "noctalia-ssh-askpass: dial %s: %v\n", sock, err)
		os.Exit(1)
	}
	defer conn.Close()

	reqb, _ := json.Marshal(request{Mode: mode, Text: prompt})
	if _, err := conn.Write(append(reqb, '\n')); err != nil {
		fmt.Fprintf(os.Stderr, "noctalia-ssh-askpass: write: %v\n", err)
		os.Exit(1)
	}

	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		fmt.Fprintf(os.Stderr, "noctalia-ssh-askpass: read: %v\n", err)
		os.Exit(1)
	}

	var resp response
	if err := json.Unmarshal(line, &resp); err != nil {
		fmt.Fprintf(os.Stderr, "noctalia-ssh-askpass: bad response: %v\n", err)
		os.Exit(1)
	}

	if !resp.OK {
		os.Exit(1)
	}

	if mode == "prompt" {
		fmt.Print(resp.Value)
	}
	os.Exit(0)
}
