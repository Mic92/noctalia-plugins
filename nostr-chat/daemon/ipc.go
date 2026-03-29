package main

import (
	"bufio"
	"context"
	"encoding/json"
	"log/slog"
	"net"
	"os"
	"sync"
)

// EventKind tags what the shell should do with a pushed Event. Typed
// so adding a new kind forces touching both the push sites and this
// list, instead of stringly drifting.
type EventKind string

const (
	EvStatus EventKind = "status" // streaming bool, pubkey, unread count
	EvMsg    EventKind = "msg"    // a Message (new or replayed)
	EvSent   EventKind = "sent"   // relay accepted, or State=Cancelled if user dropped it
	EvRetry  EventKind = "retry"  // publish failed, backing off; Tries + error text
	EvAck    EventKind = "ack"    // kind-7 reaction landed on one of our outgoing messages
	EvImg    EventKind = "img"    // async download finished; attach local path to a prior msg
	EvError  EventKind = "error"  // something worth a toast
)

type Event struct {
	Kind   EventKind `json:"kind"`
	Msg    *Message  `json:"msg,omitempty"`
	Target string    `json:"target,omitempty"` // ack/img/sent/retry: rumor id
	Mark   string    `json:"mark,omitempty"`   // ack: reaction content
	Image  string    `json:"image,omitempty"`  // img: local file path
	State  State     `json:"state,omitempty"`  // sent
	Tries  int       `json:"tries,omitempty"`  // retry: attempt count
	// status fields
	Streaming bool   `json:"streaming,omitempty"`
	PubKey    string `json:"pubkey,omitempty"`
	Name      string `json:"name,omitempty"` // display label for the panel header
	Unread    int    `json:"unread,omitempty"`
	Text      string `json:"text,omitempty"` // error
}

// PushFunc delivers an Event to the shell. Abstracted so tests can
// capture events in a channel instead of writing to a real socket.
type PushFunc func(Event)

// Cmd names a socket command. Same rationale as EventKind: the switch
// in handleCommand is the only consumer, so a typo here fails loudly
// at the default branch instead of silently doing nothing.
type Cmd string

const (
	CmdSend     Cmd = "send"
	CmdSendFile Cmd = "send-file"
	CmdReplay   Cmd = "replay"
	CmdMarkRead Cmd = "mark-read"
	CmdRetry    Cmd = "retry"
	CmdCancel   Cmd = "cancel"
)

// Command from the shell over the unix socket.
type Command struct {
	Cmd     Cmd    `json:"cmd"`
	Text    string `json:"text,omitempty"`    // send
	ReplyTo string `json:"replyTo,omitempty"` // send: e-tag target (rumor id)
	Path    string `json:"path,omitempty"`    // send-file: local file to upload
	Unlink  bool   `json:"unlink,omitempty"`  // send-file: remove Path after caching (for mktemp sources)
	N       int    `json:"n,omitempty"`       // replay: how many recent messages
	ID      string `json:"id,omitempty"`      // retry/cancel: rumor id
}

// Bridge is a persistent bidirectional unix socket: the shell writes
// NDJSON commands and reads NDJSON events on the same connection. This
// replaces the old split transport (one-shot socket for commands,
// `exec noctalia-shell ipc call` per event) that forked a child for
// every push — 200 on a replay — bloating the Go thread pool and
// delivering events out of order.
//
// The shell keeps the socket open for its lifetime and auto-reconnects
// on error, sending a replay command on each connect. That's the whole
// resync protocol: no booted flag, no IpcHandler round-trip, no exec.
type Bridge struct {
	mu    sync.Mutex
	conns map[net.Conn]struct{}
}

func NewBridge() *Bridge { return &Bridge{conns: map[net.Conn]struct{}{}} }

// Push writes ev as one NDJSON line to every connected client. A write
// error means the client is gone — drop it; the next connect will
// replay from sqlite.
func (b *Bridge) Push(ev Event) {
	line, _ := json.Marshal(ev)
	line = append(line, '\n')
	b.mu.Lock()
	defer b.mu.Unlock()
	for c := range b.conns {
		if _, err := c.Write(line); err != nil {
			delete(b.conns, c)
			c.Close()
		}
	}
}

// Serve accepts connections until ctx is done. Each connection is
// registered for Push broadcasts and its reads are dispatched to
// handle.
func (b *Bridge) Serve(ctx context.Context, path string, handle func(Command)) error {
	_ = os.Remove(path)
	ln, err := net.Listen("unix", path)
	if err != nil {
		return err
	}
	slog.Info("socket listening", "path", path)
	go func() { <-ctx.Done(); ln.Close() }()
	for {
		conn, err := ln.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			slog.Warn("accept", "err", err)
			continue
		}
		b.mu.Lock()
		b.conns[conn] = struct{}{}
		b.mu.Unlock()
		go b.read(conn, handle)
	}
}

func (b *Bridge) read(c net.Conn, handle func(Command)) {
	defer func() {
		b.mu.Lock()
		delete(b.conns, c)
		b.mu.Unlock()
		c.Close()
	}()
	sc := bufio.NewScanner(c)
	for sc.Scan() {
		var cmd Command
		if err := json.Unmarshal(sc.Bytes(), &cmd); err != nil {
			slog.Warn("bad command", "raw", sc.Text(), "err", err)
			continue
		}
		handle(cmd)
	}
}
