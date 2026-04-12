// nostr-chatd bridges a noctalia-shell chat panel to a Nostr NIP-17 peer.
//
// It replaces a brittle QML→Python→nak pipeline with a single process
// that links fiatjaf.com/nostr directly, persists history in sqlite,
// and pushes events into the shell via `quickshell ipc call`. The shell
// talks back over a unix socket with one-line JSON commands.
//
// Design: the daemon is the source of truth. Shell restarts are free
// (it asks for a replay), daemon restarts are cheap (sqlite dedup +
// outbox), and nothing is lost if either side is down when a message
// arrives or is sent.
package main

import (
	"cmp"
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"fiatjaf.com/nostr"
)

type Config struct {
	PeerPubKey string
	Relays     []string
	Blossom    []string // upload targets for send-file
	SecretCmd  string   // shell command that prints the nsec to stdout
	Name       string   // display label pushed to the shell in status events
	Socket     string
	StateDir   string
	CacheDir   string // downloaded attachments
}

func loadConfig() Config {
	home, _ := os.UserHomeDir()
	xdg := func(env, fallback string) string {
		return cmp.Or(os.Getenv(env), filepath.Join(home, fallback))
	}
	runtime := cmp.Or(os.Getenv("XDG_RUNTIME_DIR"), fmt.Sprintf("/run/user/%d", os.Getuid()))
	c := Config{
		PeerPubKey: os.Getenv("NOSTR_CHAT_PEER_PUBKEY"),
		SecretCmd:  os.Getenv("NOSTR_CHAT_SECRET_CMD"),
		Name:       cmp.Or(os.Getenv("NOSTR_CHAT_DISPLAY_NAME"), "Chat"),
		Socket:     filepath.Join(runtime, "nostr-chatd.sock"),
		StateDir:   filepath.Join(xdg("XDG_STATE_HOME", ".local/state"), "nostr-chatd"),
		CacheDir:   filepath.Join(xdg("XDG_CACHE_HOME", ".cache"), "nostr-chatd", "media"),
	}
	c.Relays = splitList(os.Getenv("NOSTR_CHAT_RELAYS"))
	c.Blossom = splitList(os.Getenv("NOSTR_CHAT_BLOSSOM"))
	flag.StringVar(&c.Socket, "socket", c.Socket, "unix socket path")
	flag.StringVar(&c.StateDir, "state", c.StateDir, "sqlite state dir")
	flag.Parse()
	return c
}

func splitList(s string) []string {
	var out []string
	for _, r := range strings.Split(s, ",") {
		if r = strings.TrimSpace(r); r != "" {
			out = append(out, r)
		}
	}
	return out
}

// fetchSecret runs a shell command and returns its trimmed stdout.
// `sh -c` lets the module pass anything — `rbw get foo`, `pass show
// nostr/identity`, `cat /run/agenix/nsec` — without the daemon caring
// which backend is in play.
func fetchSecret(shcmd string) (string, error) {
	if shcmd == "" {
		return "", fmt.Errorf("NOSTR_CHAT_SECRET_CMD is empty")
	}
	// /bin/sh is one of the few FHS paths NixOS guarantees — using it
	// directly means the systemd unit's PATH only needs the tools the
	// secret command itself calls, not a shell.
	out, err := exec.Command("/bin/sh", "-c", shcmd).Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return "", fmt.Errorf("secret command failed: %w: %s", err, ee.Stderr)
		}
		return "", fmt.Errorf("secret command: %w", err)
	}
	return strings.TrimSpace(string(out)), nil
}

func main() {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelDebug})))
	cfg := loadConfig()

	if cfg.PeerPubKey == "" || len(cfg.Relays) == 0 {
		slog.Error("missing NOSTR_CHAT_PEER_PUBKEY or NOSTR_CHAT_RELAYS")
		os.Exit(1)
	}

	sec, err := fetchSecret(cfg.SecretCmd)
	if err != nil {
		slog.Error("fetch secret", "err", err)
		os.Exit(1)
	}
	keys, err := loadKeys(sec)
	if err != nil {
		slog.Error("load keys", "err", err)
		os.Exit(1)
	}
	slog.Info("identity", "pubkey", keys.PK.Hex())
	slog.Info("config",
		"peer", cfg.PeerPubKey,
		"relays", cfg.Relays,
		"blossom", cfg.Blossom,
		"socket", cfg.Socket,
		"state", cfg.StateDir,
		"cache", cfg.CacheDir,
	)

	store, err := OpenStore(cfg.StateDir)
	if err != nil {
		slog.Error("open store", "err", err)
		os.Exit(1)
	}
	defer store.Close()

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()

	br := NewBridge()
	d := NewDaemon(cfg, keys, store, br.Push)
	if err := d.Run(ctx, br); err != nil {
		slog.Error("daemon", "err", err)
		os.Exit(1)
	}
}

// Daemon wires the listener, store, socket and publish loop together.
// Extracted from main so tests can drive the real event loop with an
// in-memory relay and a channel-backed push instead of a real socket.
type Daemon struct {
	cfg   Config
	keys  Keys
	store *Store
	lst   *Listener
	push  PushFunc
}

func NewDaemon(cfg Config, keys Keys, store *Store, push PushFunc) *Daemon {
	d := &Daemon{
		cfg:   cfg,
		keys:  keys,
		store: store,
		lst:   NewListener(keys, cfg.Relays),
		push:  push,
	}
	// Streaming status follows actual relay connectivity, not the unix
	// socket. Push on count change (not every 30s tick) so the header's
	// n/m updates promptly when a relay drops without flooding IPC.
	last := -1
	d.lst.OnHealth = func(up []string) {
		if len(up) == last {
			return
		}
		last = len(up)
		d.push(d.statusEvent(up, 0))
	}
	return d
}

// Run blocks until ctx is done. It starts the relay subscription,
// socket server and publish loop, then dispatches rumors and commands
// on the calling goroutine. br may be nil in tests that inject
// commands directly.
func (d *Daemon) Run(ctx context.Context, br *Bridge) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Rumors and commands funnel through this goroutine so the common
	// path (text in/out) never contends on the store. File upload and
	// download spawn their own goroutines and hit sqlite directly —
	// safe because modernc.org/sqlite serialises via busy_timeout, and
	// the only shared row is the rumor id whose ON CONFLICT handles
	// the race.
	rumors := make(chan Rumor, 64)
	cmds := make(chan Command, 16)

	// Anything timestamped before we started is backfill, not a live
	// reply — mark it read so the shell doesn't auto-open the panel for
	// three days of history on first run.
	startedAt := time.Now().Unix()
	// Closure so reconnects pick up the watermark handleRumor has been
	// advancing, instead of replaying from the boot-time value.
	go d.lst.Run(ctx, func() int64 {
		ts, _ := d.store.GetInt(ctx, "last_seen_ts")
		return ts
	}, rumors)

	if br != nil {
		go func() {
			if err := br.Serve(ctx, d.cfg.Socket, func(c Command) { cmds <- c }); err != nil {
				slog.Error("socket", "err", err)
				cancel()
			}
		}()
	}

	// Publishing blocks on slow/dead relays (nostr.0cx.de takes the full
	// 15s timeout when down). Run it in its own goroutine so a stalled
	// publish can't delay the next send's local echo or an incoming
	// rumor's IPC push. The main loop only does fast work: sqlite +
	// crypto + a socket write.
	drainNow := make(chan struct{}, 1)
	kick := func() {
		select {
		case drainNow <- struct{}{}:
		default:
		}
	}
	kick() // flush anything a prior crash left behind
	go d.publishLoop(ctx, drainNow)

	for {
		select {
		case <-ctx.Done():
			return nil
		case r := <-rumors:
			slog.Debug("rumor", "kind", r.Kind, "from", r.PubKey[:8], "id", r.ID[:8], "ts", r.TS)
			d.handleRumor(ctx, r, startedAt)
		case c := <-cmds:
			slog.Debug("command", "cmd", c.Cmd, "n", c.N, "reply_to", c.ReplyTo, "path", c.Path)
			d.handleCommand(ctx, c, kick)
		}
	}
}

func (d *Daemon) handleRumor(ctx context.Context, r Rumor, startedAt int64) {
	store, cfg, keys := d.store, d.cfg, d.keys
	switch r.Kind {
	case nostr.KindReaction:
		// Gift-wrapped kind-7 reaction — read receipt. Only trust the
		// configured peer; anyone can p-tag us.
		if r.PubKey != cfg.PeerPubKey || r.ETag == "" {
			return
		}
		mark := r.Content
		if mark == "" || mark == "+" {
			mark = "✓"
		}
		if err := store.SetAck(ctx, r.ETag, mark); err != nil {
			slog.Warn("set ack", "err", err)
			return
		}
		d.push(Event{Kind: EvAck, Target: r.ETag, Mark: mark})

	default:
		// kind 14 chat, kind 15 file, or anything else the peer wraps —
		// store them all, the UI only cares about in/out.
		mine := r.PubKey == keys.PK.Hex()
		if !mine && r.PubKey != cfg.PeerPubKey {
			return // e.g. github-notifier spamming our p-tag
		}
		content := r.Content
		if r.Kind == KindFileMessage {
			content = "📎 " + cmp.Or(tagValue(r.Tags, "file-type"), "file")
		}
		dir := DirIn
		if mine {
			dir = DirOut
		}
		m := Message{
			ID: r.ID, PubKey: r.PubKey, Content: content, TS: r.TS,
			Dir:     dir,
			Read:    mine || r.TS < startedAt,
			ReplyTo: r.ETag, // kind-14 e-tag = threaded reply target
		}
		inserted, err := store.InsertMessage(ctx, m)
		if err != nil {
			slog.Warn("insert", "err", err)
			return
		}
		if !inserted {
			return // dedup hit — replay after restart
		}
		// Only advance the watermark. Rumors interleave across relays;
		// a late-delivered older message would roll it back and the
		// next restart over-fetches the gap.
		if cur, _ := store.GetInt(ctx, "last_seen_ts"); r.TS > cur {
			_ = store.SetInt(ctx, "last_seen_ts", r.TS)
		}
		d.push(Event{Kind: EvMsg, Msg: &m})

		// kind-15: download runs off the main loop so a slow Blossom
		// server can't stall incoming text. When done, patch the row
		// and push an "img" event — the shell updates the bubble in
		// place, same pattern as acks.
		if r.Kind == KindFileMessage {
			go func(r Rumor) {
				slog.Info("downloading attachment", "url", r.Content, "id", r.ID[:8])
				p, err := downloadFile(ctx, r.Content, cfg.CacheDir, r.Tags)
				if err != nil {
					slog.Warn("download", "url", r.Content, "err", err)
					return
				}
				slog.Info("attachment saved", "id", r.ID[:8], "path", p)
				if err := store.SetImage(ctx, r.ID, p); err != nil {
					slog.Warn("set image", "err", err)
				}
				d.push(Event{Kind: EvImg, Target: r.ID, Image: p})
			}(r)
		}
	}
}

func (d *Daemon) handleCommand(ctx context.Context, c Command, kick func()) {
	store, lst, cfg, keys := d.store, d.lst, d.cfg, d.keys
	switch c.Cmd {
	case CmdSend:
		if strings.TrimSpace(c.Text) == "" {
			return
		}
		// Build + echo synchronously (microseconds), then hand off to
		// the outbox for the slow publish. The user sees their message
		// the instant they hit enter; the ack mark follows when the
		// bot's reaction lands.
		out, err := lst.Prepare(ctx, cfg.PeerPubKey, c.Text, c.ReplyTo)
		if err != nil {
			slog.Error("prepare", "err", err)
			d.push(Event{Kind: EvError, Text: "prepare: " + err.Error()})
			return
		}
		m := Message{
			ID: out.Rumor.ID, PubKey: out.Rumor.PubKey, Content: out.Rumor.Content,
			TS: out.Rumor.TS, Dir: DirOut, Read: true, ReplyTo: c.ReplyTo,
			State: StatePending,
		}
		if ok, _ := store.InsertMessage(ctx, m); ok {
			d.push(Event{Kind: EvMsg, Msg: &m})
		}
		them, us := out.Wraps()
		if _, err := store.Enqueue(ctx, out.Rumor.ID, them, us); err != nil {
			slog.Error("enqueue", "err", err)
			return
		}
		kick()

	case CmdSendFile:
		if c.Path == "" {
			return
		}
		// Upload runs in a goroutine — encrypt is fast but the PUT to
		// Blossom can take seconds. Once uploaded we have serialisable
		// wraps and enqueue them like text, so file sends get the same
		// retry/cancel and connected-only publish path. If the daemon
		// dies mid-upload the user re-attaches; post-upload the outbox
		// survives the restart.
		go func(path string, unlink bool) {
			slog.Info("uploading file", "path", path, "unlink", unlink)
			// Copy into CacheDir first — the local echo points Image
			// at this path and it's persisted to sqlite, so the source
			// needs to outlive the keybind script's mktemp and survive
			// replay after logout. Hash-named like downloads so repeat
			// sends of the same file dedupe.
			cached, err := cacheLocalFile(path, cfg.CacheDir)
			if unlink {
				// Best-effort: the source was a mktemp the caller wants
				// gone. Do it even if caching failed so a broken upload
				// doesn't leak tmpfs.
				_ = os.Remove(path)
			}
			if err != nil {
				d.push(Event{Kind: EvError, Text: "cache: " + err.Error()})
				return
			}
			enc, err := encryptFile(cached)
			if err != nil {
				d.push(Event{Kind: EvError, Text: "encrypt: " + err.Error()})
				return
			}
			uctx, cancel := context.WithTimeout(ctx, 60*time.Second)
			defer cancel()
			url, err := blossomUpload(uctx, cfg.Blossom, enc, keys)
			if err != nil {
				slog.Error("blossom upload", "path", path, "err", err)
				d.push(Event{Kind: EvError, Text: "upload: " + err.Error()})
				return
			}
			slog.Info("blossom upload ok", "url", url, "mime", enc.Mime)
			out, err := lst.PrepareFile(uctx, cfg.PeerPubKey, url, enc)
			if err != nil {
				d.push(Event{Kind: EvError, Text: "prepare file: " + err.Error()})
				return
			}
			// Echo locally with the cached copy as the image — no need
			// to round-trip through Blossom to see what we just sent.
			m := Message{
				ID: out.Rumor.ID, PubKey: out.Rumor.PubKey,
				Content: "📎 " + enc.Mime, TS: out.Rumor.TS,
				Dir: DirOut, Read: true, Image: cached,
			}
			m.State = StatePending
			if ok, _ := store.InsertMessage(uctx, m); ok {
				d.push(Event{Kind: EvMsg, Msg: &m})
			}
			them, us := out.Wraps()
			if _, err := store.Enqueue(uctx, out.Rumor.ID, them, us); err != nil {
				slog.Error("enqueue file", "err", err)
				return
			}
			kick()
		}(c.Path, c.Unlink)

	case CmdReplay:
		n := c.N
		if n <= 0 {
			n = 50
		}
		msgs, err := store.Recent(ctx, n)
		if err != nil {
			slog.Warn("recent", "err", err)
			return
		}
		unread, _ := store.UnreadCount(ctx)
		d.push(d.statusEvent(d.lst.Connected(), unread))
		for _, m := range msgs {
			m := m
			d.push(Event{Kind: EvMsg, Msg: &m})
		}

	case CmdMarkRead:
		if err := store.MarkAllRead(ctx); err != nil {
			slog.Warn("mark-read", "err", err)
		}

	case CmdRetry:
		if c.ID == "" {
			return
		}
		if err := store.OutboxRetryNow(ctx, c.ID); err != nil {
			slog.Warn("retry-now", "err", err)
			return
		}
		kick()

	case CmdCancel:
		if c.ID == "" {
			return
		}
		if err := store.OutboxCancel(ctx, c.ID); err != nil {
			slog.Warn("cancel", "err", err)
			return
		}
		// Tell the shell to drop the bubble — reuse EvSent with a
		// sentinel state so we don't need another event kind.
		d.push(Event{Kind: EvSent, Target: c.ID, State: StateCancelled})

	default:
		slog.Warn("unknown cmd", "cmd", c.Cmd)
	}
}

// statusEvent builds the status push in one place so replay and the
// health watchdog can't drift on which fields they fill.
func (d *Daemon) statusEvent(up []string, unread int) Event {
	return Event{
		Kind: EvStatus, Streaming: len(up) > 0,
		RelaysUp: len(up), RelaysTotal: len(d.cfg.Relays), Relays: up,
		PubKey: d.keys.PK.Hex(), Name: d.cfg.Name, Unread: unread,
	}
}

// publishLoop drains the outbox on its own goroutine. Gift-wraps are
// persisted alongside the outbox row so retries publish the same rumor
// id the local echo used — the peer's ack then lands on the bubble the
// user actually sees.
func (d *Daemon) publishLoop(ctx context.Context, kick <-chan struct{}) {
	store, lst := d.store, d.lst
	tick := time.NewTicker(30 * time.Second)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-kick:
		case <-tick.C:
		}
		items, err := store.PendingOutbox(ctx, time.Now().Unix())
		if err != nil {
			slog.Warn("outbox scan", "err", err)
			continue
		}
		if len(items) > 0 {
			slog.Debug("draining outbox", "pending", len(items))
		}
		for _, it := range items {
			err := lst.PublishRaw(ctx, it.RumorID, it.WrapThem, it.WrapUs)
			if errors.Is(err, ErrNoRelayConnected) {
				// Not a real try — we never reached anyone. Defer to the
				// next tick without bumping tries, so backoff stays low
				// and the item fires the moment a relay returns. Surface
				// the ⚠ once (tries 0→1) so the user sees something's
				// wrong, but don't re-toast every 30s during an outage.
				if it.Tries == 0 {
					_ = store.OutboxRetry(ctx, it.ID, 0)
					d.push(Event{Kind: EvRetry, Target: it.RumorID, Tries: 1, Text: err.Error()})
				}
				slog.Debug("publish deferred, no relay", "rumor", it.RumorID)
				continue
			}
			if err != nil {
				delay := time.Duration(1<<min(it.Tries, 8)) * time.Second
				_ = store.OutboxRetry(ctx, it.ID, time.Now().Add(delay).Unix())
				slog.Warn("publish failed, will retry",
					"rumor", it.RumorID, "tries", it.Tries+1, "delay", delay, "err", err)
				// Per-bubble ⚠ instead of a generic toast — the user can
				// tap to retry or cancel.
				d.push(Event{Kind: EvRetry, Target: it.RumorID, Tries: it.Tries + 1, Text: err.Error()})
				continue
			}
			slog.Debug("published", "outbox_id", it.ID, "rumor", it.RumorID)
			_ = store.OutboxDone(ctx, it.ID)
			_ = store.SetState(ctx, it.RumorID, StateSent)
			d.push(Event{Kind: EvSent, Target: it.RumorID, State: StateSent})
		}
	}
}
