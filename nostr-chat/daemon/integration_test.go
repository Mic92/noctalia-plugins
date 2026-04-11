package main

import (
	"context"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"fiatjaf.com/nostr"
	"fiatjaf.com/nostr/eventstore/slicestore"
	"fiatjaf.com/nostr/khatru"
)

// startTestRelay spins up an in-process khatru relay backed by an
// in-memory slice store. Lifted from opencrow's testutil — small enough
// to copy rather than pull in a cross-repo dependency.
func startTestRelay(t *testing.T) string {
	t.Helper()
	relay := khatru.NewRelay()
	store := &slicestore.SliceStore{}
	if err := store.Init(); err != nil {
		t.Fatalf("init slice store: %v", err)
	}
	relay.UseEventstore(store, 500)
	srv := httptest.NewServer(relay)
	t.Cleanup(srv.Close)
	return "ws" + strings.TrimPrefix(srv.URL, "http")
}

// harness runs a Daemon against a test relay with push events captured
// on a channel. Commands go in via the real unix socket so the IPC
// framing is exercised end-to-end.
type harness struct {
	d      *Daemon
	keys   Keys
	events chan Event
	sock   string
	cancel context.CancelFunc
}

func newHarness(t *testing.T, relay, peer string, extraRelays ...string) *harness {
	return newHarnessWithKey(t, relay, peer, nostr.Generate(), extraRelays...)
}

func newHarnessWithKey(t *testing.T, relay, peer string, sk nostr.SecretKey, extraRelays ...string) *harness {
	t.Helper()
	dir := t.TempDir()
	keys := Keys{SK: sk, PK: nostr.GetPublicKey(sk)}
	cfg := Config{
		PeerPubKey: peer,
		Relays:     append([]string{relay}, extraRelays...),
		Name:       "test",
		Socket:     filepath.Join(dir, "sock"),
		StateDir:   filepath.Join(dir, "state"),
		CacheDir:   filepath.Join(dir, "cache"),
	}
	store, err := OpenStore(cfg.StateDir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { store.Close() })

	events := make(chan Event, 64)
	d := NewDaemon(cfg, keys, store, func(ev Event) { events <- ev })

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go d.Run(ctx, NewBridge())

	return &harness{d: d, keys: keys, events: events, sock: cfg.Socket, cancel: cancel}
}

// send writes one Command to the daemon's socket, the same way the QML
// side does: connect, one NDJSON line, close.
func (h *harness) send(t *testing.T, c Command) {
	t.Helper()
	// serveSocket may not have bound yet on the very first call.
	var conn net.Conn
	var err error
	for i := 0; i < 50; i++ {
		conn, err = net.Dial("unix", h.sock)
		if err == nil {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if err != nil {
		t.Fatalf("dial socket: %v", err)
	}
	defer conn.Close()
	b, _ := json.Marshal(c)
	if _, err := conn.Write(append(b, '\n')); err != nil {
		t.Fatalf("write socket: %v", err)
	}
}

// expect pulls events until one of the given kind arrives, or times
// out. Intermediate events are dropped — tests only assert on the ones
// they care about, so ordering jitter between e.g. EvMsg and EvSent
// doesn't make them flaky.
func (h *harness) expect(t *testing.T, kind EventKind, d time.Duration) Event {
	t.Helper()
	deadline := time.After(d)
	for {
		select {
		case ev := <-h.events:
			if ev.Kind == kind {
				return ev
			}
		case <-deadline:
			t.Fatalf("timed out waiting for %s event", kind)
			return Event{}
		}
	}
}

// TestSendRoundTrip: write a send command to the socket, verify the
// local echo, the peer receiving the gift-wrap, and the EvSent
// confirmation once the relay accepts.
func TestSendRoundTrip(t *testing.T) {
	t.Parallel()
	relay := startTestRelay(t)

	// Peer listens first so its pubkey can be the daemon's PeerPubKey.
	peerSK := nostr.Generate()
	peerKeys := Keys{SK: peerSK, PK: nostr.GetPublicKey(peerSK)}
	peer := NewListener(peerKeys, []string{relay})

	h := newHarness(t, relay, peerKeys.PK.Hex())

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	peerCh := make(chan Rumor, 4)
	go peer.Run(ctx, func() int64 { return 0 }, peerCh)

	h.send(t, Command{Cmd: CmdSend, Text: "hello peer"})

	// Local echo: EvMsg with our pubkey, pending state.
	echo := h.expect(t, EvMsg, 5*time.Second)
	if echo.Msg == nil || echo.Msg.Content != "hello peer" {
		t.Fatalf("echo = %+v", echo)
	}
	if echo.Msg.Dir != DirOut || echo.Msg.State != StatePending {
		t.Errorf("echo dir/state = %s/%s, want out/pending", echo.Msg.Dir, echo.Msg.State)
	}
	rumorID := echo.Msg.ID

	// Peer receives the unwrapped rumor.
	var got Rumor
	select {
	case got = <-peerCh:
	case <-time.After(5 * time.Second):
		t.Fatal("peer did not receive rumor")
	}
	if got.Content != "hello peer" || got.Kind != 14 {
		t.Errorf("peer got %+v", got)
	}
	if got.PubKey != h.keys.PK.Hex() {
		t.Errorf("peer saw pubkey %s, want %s", got.PubKey, h.keys.PK.Hex())
	}
	if got.ID != rumorID {
		t.Errorf("peer rumor id %s != echo id %s", got.ID, rumorID)
	}

	// publishLoop confirms relay acceptance.
	sent := h.expect(t, EvSent, 5*time.Second)
	if sent.Target != rumorID || sent.State != StateSent {
		t.Errorf("sent event = %+v, want target=%s state=sent", sent, rumorID)
	}
}

// TestSendWhileOffline: send with no relay reachable. Must echo
// locally, surface one EvRetry, and not inflate tries — so the item
// fires immediately once a relay appears instead of sitting in backoff.
func TestSendWhileOffline(t *testing.T) {
	t.Parallel()

	peerSK := nostr.Generate()
	peerPK := nostr.GetPublicKey(peerSK)

	// Dead port — subscription never connects, publishConnected skips.
	h := newHarness(t, "ws://127.0.0.1:1", peerPK.Hex())

	h.send(t, Command{Cmd: CmdSend, Text: "queued"})

	echo := h.expect(t, EvMsg, 5*time.Second)
	if echo.Msg == nil || echo.Msg.State != StatePending {
		t.Fatalf("echo = %+v, want pending", echo)
	}

	retry := h.expect(t, EvRetry, 5*time.Second)
	if retry.Tries != 1 {
		t.Errorf("tries = %d, want 1 (defer surfaces once)", retry.Tries)
	}

	// No second EvRetry — defer is silent after the first.
	select {
	case ev := <-h.events:
		if ev.Kind == EvRetry {
			t.Fatalf("unexpected second EvRetry: %+v", ev)
		}
	case <-time.After(300 * time.Millisecond):
	}

	// Outbox row should sit at tries=1, next_at=0 — ready to fire the
	// instant a relay comes back rather than stuck in exponential
	// backoff after N ticks offline.
	items, err := h.d.store.PendingOutbox(context.Background(), time.Now().Unix())
	if err != nil {
		t.Fatalf("outbox: %v", err)
	}
	if len(items) != 1 || items[0].Tries != 1 {
		t.Errorf("outbox = %+v, want 1 item at tries=1", items)
	}
}

// TestIncomingMessage: peer publishes a DM, daemon surfaces it as an
// EvMsg with dir=in and stores it for replay. Both sides run as full
// harnesses so the peer publishes via its own outbox/subscription —
// same connected-only path as production, no test-only dial shortcut.
func TestIncomingMessage(t *testing.T) {
	t.Parallel()
	relay := startTestRelay(t)

	// Bootstrap: each harness needs the other's pubkey at construction,
	// so generate h's key first, build peer, then rebuild h with the
	// real key via newHarnessWithKey.
	hSK := nostr.Generate()
	hPK := nostr.GetPublicKey(hSK)
	peer := newHarness(t, relay, hPK.Hex())
	h := newHarnessWithKey(t, relay, peer.keys.PK.Hex(), hSK)

	peer.send(t, Command{Cmd: CmdSend, Text: "ping from peer"})
	peer.expect(t, EvSent, 5*time.Second) // wait until relay accepted

	ev := h.expect(t, EvMsg, 5*time.Second)
	if ev.Msg == nil || ev.Msg.Content != "ping from peer" {
		t.Fatalf("incoming msg = %+v", ev)
	}
	if ev.Msg.Dir != DirIn {
		t.Errorf("dir = %s, want in", ev.Msg.Dir)
	}
	if ev.Msg.PubKey != peer.keys.PK.Hex() {
		t.Errorf("pubkey = %s, want %s", ev.Msg.PubKey, peer.keys.PK.Hex())
	}

	// Replay should return the stored message.
	h.send(t, Command{Cmd: CmdReplay, N: 10})
	h.expect(t, EvStatus, 5*time.Second) // replay leads with a status
	replayed := h.expect(t, EvMsg, 5*time.Second)
	if replayed.Msg == nil || replayed.Msg.ID != ev.Msg.ID {
		t.Errorf("replayed %+v, want id %s", replayed, ev.Msg.ID)
	}
}

// TestStrangerIgnored: a DM from a pubkey that is neither us nor the
// configured peer must not produce an EvMsg. Guards against the
// github-notifier-spams-our-p-tag failure mode noted in handleRumor.
func TestStrangerIgnored(t *testing.T) {
	t.Parallel()
	relay := startTestRelay(t)

	hSK := nostr.Generate()
	hPK := nostr.GetPublicKey(hSK)
	// Stranger targets h; h is configured for a third, unrelated peer.
	stranger := newHarness(t, relay, hPK.Hex())
	peerSK := nostr.Generate()
	h := newHarnessWithKey(t, relay, nostr.GetPublicKey(peerSK).Hex(), hSK)

	stranger.send(t, Command{Cmd: CmdSend, Text: "spam"})
	stranger.expect(t, EvSent, 5*time.Second)

	select {
	case ev := <-h.events:
		if ev.Kind == EvMsg {
			t.Fatalf("stranger message leaked through: %+v", ev)
		}
	case <-time.After(500 * time.Millisecond):
		// good — nothing surfaced
	}
}

func wsAccept(key string) string {
	h := sha1.Sum([]byte(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	return base64.StdEncoding.EncodeToString(h[:])
}

// startZombieRelay accepts the websocket upgrade and then never reads
// or writes another byte. To the pool it looks IsConnected(), so
// publishConnected will try it; the old sequential loop with a shared
// 5s context would burn that budget here before reaching a good relay.
func startZombieRelay(t *testing.T) string {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hj, ok := w.(http.Hijacker)
		if !ok {
			http.Error(w, "no hijack", 500)
			return
		}
		key := r.Header.Get("Sec-WebSocket-Key")
		conn, buf, err := hj.Hijack()
		if err != nil {
			return
		}
		_, _ = buf.WriteString("HTTP/1.1 101 Switching Protocols\r\n" +
			"Upgrade: websocket\r\nConnection: Upgrade\r\n" +
			"Sec-WebSocket-Accept: " + wsAccept(key) + "\r\n\r\n")
		_ = buf.Flush()
		<-r.Context().Done()
		_ = conn.Close()
	}))
	t.Cleanup(srv.Close)
	return "ws" + strings.TrimPrefix(srv.URL, "http")
}

// TestPublishWithZombieRelay: one good relay plus one zombie that
// upgrades then black-holes. publishConnected must still get an ack
// from the good relay within its per-relay timeout instead of the
// zombie head-of-line blocking the whole batch.
func TestPublishWithZombieRelay(t *testing.T) {
	t.Parallel()
	good := startTestRelay(t)
	zombie := startZombieRelay(t)

	peerSK := nostr.Generate()
	peerPK := nostr.GetPublicKey(peerSK)
	// Zombie listed first so a sequential loop would hit it first.
	h := newHarness(t, zombie, peerPK.Hex(), good)

	// Wait for the pool to actually open the zombie so publishConnected
	// doesn't just skip it. The good relay's REQ will land too but we
	// only need the zombie's IsConnected() to flip.
	deadline := time.After(5 * time.Second)
	for {
		if r, ok := h.d.lst.pool.Relays.Load(nostr.NormalizeURL(zombie)); ok && r != nil && r.IsConnected() {
			break
		}
		select {
		case <-deadline:
			t.Fatal("zombie never connected")
		case <-time.After(20 * time.Millisecond):
		}
	}

	h.send(t, Command{Cmd: CmdSend, Text: "survives zombie"})
	h.expect(t, EvMsg, 5*time.Second)

	// 4s budget: good relay round-trip is ~ms; the per-relay 3s timeout
	// on the zombie runs concurrently. Under the old shared-5s code the
	// good relay never got a turn and EvSent never arrived.
	start := time.Now()
	sent := h.expect(t, EvSent, 4*time.Second)
	if sent.State != StateSent {
		t.Fatalf("sent = %+v", sent)
	}
	t.Logf("EvSent after %s", time.Since(start).Round(time.Millisecond))
}

// TestReplayStatusReflectsRelays: replaying before any relay connects
// must report streaming=false; after a real subscription is up,
// streaming=true. Guards against the previous hard-coded `true`.
func TestReplayStatusReflectsRelays(t *testing.T) {
	t.Parallel()
	peerPK := nostr.GetPublicKey(nostr.Generate())

	offline := newHarness(t, "ws://127.0.0.1:1", peerPK.Hex())
	offline.send(t, Command{Cmd: CmdReplay, N: 1})
	st := offline.expect(t, EvStatus, 5*time.Second)
	if st.Streaming || st.RelaysUp != 0 || st.RelaysTotal != 1 {
		t.Errorf("offline replay: streaming=%v up=%d/%d, want false 0/1",
			st.Streaming, st.RelaysUp, st.RelaysTotal)
	}

	relay := startTestRelay(t)
	online := newHarness(t, relay, peerPK.Hex())
	deadline := time.After(5 * time.Second)
	for len(online.d.lst.Connected()) == 0 {
		select {
		case <-deadline:
			t.Fatal("relay never connected")
		case <-time.After(20 * time.Millisecond):
		}
	}
	online.send(t, Command{Cmd: CmdReplay, N: 1})
	st = online.expect(t, EvStatus, 5*time.Second)
	if !st.Streaming || st.RelaysUp != 1 || st.RelaysTotal != 1 || len(st.Relays) != 1 {
		t.Errorf("online replay: streaming=%v up=%d/%d relays=%v, want true 1/1",
			st.Streaming, st.RelaysUp, st.RelaysTotal, st.Relays)
	}
}
