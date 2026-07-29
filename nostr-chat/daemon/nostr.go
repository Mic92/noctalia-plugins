package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"fiatjaf.com/nostr"
	"fiatjaf.com/nostr/keyer"
	"fiatjaf.com/nostr/nip19"
	"fiatjaf.com/nostr/nip59"
)

// Gift-wrap created_at is randomised up to 2 days into the past
// (NIP-59), so subscribe with a 3-day margin below last-seen.
const nip59Margin = 3 * 24 * time.Hour

type Keys struct {
	SK nostr.SecretKey
	PK nostr.PubKey
}

func loadKeys(raw string) (Keys, error) {
	raw = strings.TrimSpace(raw)
	var sk nostr.SecretKey
	if strings.HasPrefix(raw, "nsec") {
		prefix, val, err := nip19.Decode(raw)
		if err != nil || prefix != "nsec" {
			return Keys{}, fmt.Errorf("decode nsec: %w", err)
		}
		sk = val.(nostr.SecretKey)
	} else {
		var err error
		if sk, err = nostr.SecretKeyFromHex(raw); err != nil {
			return Keys{}, fmt.Errorf("parse hex sk: %w", err)
		}
	}
	return Keys{SK: sk, PK: nostr.GetPublicKey(sk)}, nil
}

// Rumor is the unwrapped inner event, reduced to what routing needs.
type Rumor struct {
	ID      string
	Kind    nostr.Kind
	PubKey  string
	Content string
	TS      int64
	ETag    string     // reaction target (kind-7) or reply parent (kind-14)
	Tags    nostr.Tags // kind-15 carries file-type / decryption-* tags
}

// Listener subscribes to kind-1059 gift wraps addressed to us and
// unwraps them. nip17.ListenForMessages is not used because it drops
// anything that isn't kind-14, but peers also wrap kind-7 reactions
// and kind-15 files.
type Listener struct {
	pool   *nostr.Pool
	kr     nostr.Keyer
	keys   Keys
	relays []string

	// resub is kicked when a publish times out on a socket that still
	// claims to be connected; the watchdog then drops all connections.
	resub chan struct{}

	// A websocket can stay connected while the relay's side of the REQ
	// silently dies (issue #12). Every publish includes a self-addressed
	// wrap, so each relay that OK'd it must echo it back on the live
	// subscription. pendingEcho maps "wrapID|relay" to publish time;
	// the watchdog resubscribes when an entry outlives echoTimeout.
	echoMu       sync.Mutex
	pendingEcho  map[string]time.Time
	echoTimeout  time.Duration
	livenessTick time.Duration

	// OnHealth receives the connected relay set on every watchdog tick,
	// so the panel shows relay reality rather than "socket is up".
	OnHealth func(connected []string)
}

func NewListener(keys Keys, relays []string) *Listener {
	kr := keyer.NewPlainKeySigner(keys.SK)
	pool := nostr.NewPool()
	// Answer AUTH challenges inline so NIP-42 relays don't CLOSE the sub.
	pool.RelayOptions.AuthHandler = func(ctx context.Context, _ *nostr.Relay, ev *nostr.Event) error {
		return kr.SignEvent(ctx, ev)
	}
	return &Listener{
		pool: pool, kr: kr, keys: keys, relays: relays,
		resub:        make(chan struct{}, 1),
		pendingEcho:  make(map[string]time.Time),
		echoTimeout:  45 * time.Second,
		livenessTick: 30 * time.Second,
	}
}

// Run blocks until ctx is done, emitting unwrapped rumors on ch.
// Per-relay reconnect/backoff lives in the pool; this loop restarts
// only when the watchdog tears the pool down or every relay CLOSED.
// `since` is re-read each round so a late drop doesn't re-fetch hours.
func (l *Listener) Run(ctx context.Context, since func() int64, ch chan<- Rumor) {
	for ctx.Err() == nil {
		subCtx, subCancel := context.WithCancel(ctx)
		go l.watchLiveness(subCtx, func() { l.dropConnections(); subCancel() })
		l.subscribeOnce(subCtx, since(), ch)
		subCancel()
		slog.Warn("subscription closed, reconnecting")
		select {
		case <-ctx.Done():
			return
		case <-time.After(time.Second):
		}
	}
}

// dropConnections evicts every pooled relay so the next subscribe
// redials from scratch instead of reusing a black-holed socket.
func (l *Listener) dropConnections() {
	for url, r := range l.pool.Relays.Range {
		if r != nil {
			r.Close()
		}
		l.pool.Relays.Delete(url)
	}
}

func echoKey(id nostr.ID, relay string) string {
	return id.Hex() + "|" + nostr.NormalizeURL(relay)
}

// expectEcho records that relay accepted our self-addressed wrap and
// now owes it back on the live subscription.
func (l *Listener) expectEcho(id nostr.ID, relay string) {
	l.echoMu.Lock()
	l.pendingEcho[echoKey(id, relay)] = time.Now()
	l.echoMu.Unlock()
}

func (l *Listener) markEchoed(id nostr.ID, relay string) {
	l.echoMu.Lock()
	delete(l.pendingEcho, echoKey(id, relay))
	l.echoMu.Unlock()
}

// staleEcho returns a relay whose accepted wrap never came back within
// echoTimeout — its REQ is dead even though the socket is connected.
func (l *Listener) staleEcho() (string, bool) {
	l.echoMu.Lock()
	defer l.echoMu.Unlock()
	for key, at := range l.pendingEcho {
		if time.Since(at) > l.echoTimeout {
			return key, true
		}
	}
	return "", false
}

func (l *Listener) resetEchoes() {
	l.echoMu.Lock()
	l.pendingEcho = make(map[string]time.Time)
	l.echoMu.Unlock()
}

// watchLiveness forces a resubscribe (via cancel) when:
//   - wall clock jumped ahead of the monotonic ticker (suspend/resume),
//   - a publish timed out on a "connected" socket (resub channel),
//   - an accepted self-wrap was never echoed back (stale REQ, issue #12),
//   - no relay has been connected for three consecutive ticks.
//
// It also reports the connected set to OnHealth on every tick.
func (l *Listener) watchLiveness(ctx context.Context, cancel func()) {
	tick := l.livenessTick
	var deadTicks int
	for {
		before := time.Now().Unix()
		select {
		case <-ctx.Done():
			return
		case <-time.After(tick):
		case <-l.resub:
			slog.Info("publish timeout, forcing resubscribe")
			cancel()
			return
		}
		gap := time.Duration(time.Now().Unix()-before)*time.Second - tick
		if gap > time.Minute {
			slog.Info("time jump, resubscribing", "gap", gap.Round(time.Second))
			cancel()
			return
		}

		if key, stale := l.staleEcho(); stale {
			slog.Warn("published wrap never echoed by subscription, resubscribing", "echo", key)
			cancel()
			return
		}

		up := l.Connected()
		slog.Debug("relay health", "connected", up, "of", len(l.relays))
		if l.OnHealth != nil {
			l.OnHealth(up)
		}
		if len(up) == 0 {
			deadTicks++
			if deadTicks >= 3 {
				slog.Warn("no relay connected for 90s, resubscribing")
				cancel()
				return
			}
		} else {
			deadTicks = 0
		}
	}
}

// Connected returns the relays with an open websocket right now.
func (l *Listener) Connected() []string {
	var up []string
	for _, url := range l.relays {
		if r, ok := l.pool.Relays.Load(nostr.NormalizeURL(url)); ok && r != nil && r.IsConnected() {
			up = append(up, url)
		}
	}
	return up
}

func (l *Listener) subscribeOnce(ctx context.Context, since int64, ch chan<- Rumor) {
	adj := nostr.Timestamp(since) - nostr.Timestamp(nip59Margin.Seconds())
	if adj < 0 {
		adj = 0
	}
	slog.Info("subscribing", "relays", l.relays, "since", since, "adjusted", int64(adj))
	l.resetEchoes()
	filter := nostr.Filter{
		Kinds: []nostr.Kind{nostr.KindGiftWrap},
		Tags:  nostr.TagMap{"p": {l.keys.PK.Hex()}},
		Since: adj,
	}
	// CheckDuplicate runs per relay per event before dedup collapses the
	// copies — the only place we can see which relay echoed our wrap.
	var seenMu sync.Mutex
	seen := make(map[nostr.ID]struct{})
	opts := nostr.SubscriptionOptions{
		CheckDuplicate: func(id nostr.ID, relay string) bool {
			l.markEchoed(id, relay)
			seenMu.Lock()
			defer seenMu.Unlock()
			if _, dup := seen[id]; dup {
				return true
			}
			seen[id] = struct{}{}
			return false
		},
	}
	events, closed := l.pool.SubscribeManyNotifyClosed(ctx, l.relays, filter, opts)
	go func() {
		for c := range closed {
			slog.Warn("relay closed subscription", "relay", c.Relay.URL, "reason", c.Reason, "auth_handled", c.HandledAuth)
		}
	}()
	for ev := range events {
		rumor, err := nip59.GiftUnwrap(ev.Event,
			func(pk nostr.PubKey, ct string) (string, error) {
				return l.kr.Decrypt(ctx, ct, pk)
			})
		if err != nil {
			// Not ours or malformed — skip quietly.
			continue
		}
		select {
		case ch <- toRumor(rumor):
		case <-ctx.Done():
			return
		}
	}
}

func toRumor(ev nostr.Event) Rumor {
	r := Rumor{
		ID: ev.ID.Hex(), Kind: ev.Kind, PubKey: ev.PubKey.Hex(),
		Content: ev.Content, TS: int64(ev.CreatedAt), Tags: ev.Tags,
	}
	if e := ev.Tags.Find("e"); e != nil {
		r.ETag = e[1]
	}
	return r
}

// Outgoing is a built-but-unpublished DM, so callers can echo locally
// before the network round-trip.
type Outgoing struct {
	Rumor  Rumor
	toThem nostr.Event
	toUs   nostr.Event
}

// Wraps serialises both gift-wrap events for the outbox so they survive
// a daemon restart.
func (o Outgoing) Wraps() (them, us string) {
	t, _ := json.Marshal(o.toThem)
	u, _ := json.Marshal(o.toUs)
	return string(t), string(u)
}

// prepare builds an unsigned rumor and gift-wraps it for the recipient
// and for ourselves. The returned Rumor carries the final id so the
// self-copy arriving via the listen loop dedups cleanly.
func (l *Listener) prepare(ctx context.Context, to string, kind nostr.Kind, content string, extraTags nostr.Tags) (Outgoing, error) {
	recipient, err := nostr.PubKeyFromHex(to)
	if err != nil {
		return Outgoing{}, fmt.Errorf("recipient pubkey: %w", err)
	}
	rumor := nostr.Event{
		Kind:      kind,
		Content:   content,
		Tags:      append(nostr.Tags{{"p", to}}, extraTags...),
		CreatedAt: nostr.Now(),
		PubKey:    l.keys.PK,
	}
	rumor.ID = rumor.GetID()

	wrap := func(pk nostr.PubKey) (nostr.Event, error) {
		return nip59.GiftWrap(rumor, pk,
			func(s string) (string, error) { return l.kr.Encrypt(ctx, s, pk) },
			func(e *nostr.Event) error { return l.kr.SignEvent(ctx, e) },
			nil)
	}
	toThem, err := wrap(recipient)
	if err != nil {
		return Outgoing{}, fmt.Errorf("wrap recipient: %w", err)
	}
	toUs, err := wrap(l.keys.PK)
	if err != nil {
		return Outgoing{}, fmt.Errorf("wrap self: %w", err)
	}
	return Outgoing{Rumor: toRumor(rumor), toThem: toThem, toUs: toUs}, nil
}

// Prepare builds a kind-14 chat rumor. replyTo, if non-empty, becomes
// an e-tag so the peer can thread the response.
func (l *Listener) Prepare(ctx context.Context, to, content, replyTo string) (Outgoing, error) {
	var extra nostr.Tags
	if replyTo != "" {
		extra = nostr.Tags{{"e", replyTo}}
	}
	return l.prepare(ctx, to, 14, content, extra)
}

// PrepareFile builds a kind-15 file rumor with encryption metadata.
func (l *Listener) PrepareFile(ctx context.Context, to, url string, enc *encryptedFile) (Outgoing, error) {
	return l.prepare(ctx, to, KindFileMessage, url, nostr.Tags{
		{"file-type", enc.Mime},
		{"encryption-algorithm", "aes-gcm"},
		{"decryption-key", enc.KeyHex},
		{"decryption-nonce", enc.NonceHex},
		{"x", enc.SHA256Hex},
		{"ox", enc.OxHex},
	})
}

// PublishRaw sends serialised gift-wraps from the outbox to relays the
// subscription loop already opened — no dialing here, so a dead relay
// can't head-of-line block the outbox drain. Reconnection is the listen
// loop's job; the outbox retries once it's back.
func (l *Listener) PublishRaw(ctx context.Context, rumorID, themJSON, usJSON string) error {
	var them, us nostr.Event
	if err := json.Unmarshal([]byte(themJSON), &them); err != nil {
		return fmt.Errorf("decode wrap-them: %w", err)
	}
	if err := json.Unmarshal([]byte(usJSON), &us); err != nil {
		return fmt.Errorf("decode wrap-us: %w", err)
	}
	return l.publishConnected(ctx, rumorID, us.ID, them, us)
}

// publishConnected fans the wraps out to every open relay in parallel,
// each with its own 3s deadline. echoID is the self-addressed wrap:
// relays that OK it must echo it back, which is how a dead REQ is
// detected. A timeout on a "connected" socket flags a pool reset.
func (l *Listener) publishConnected(ctx context.Context, rumorID string, echoID nostr.ID, evs ...nostr.Event) error {
	var ok, fail, skip atomic.Int32
	var stuck atomic.Bool
	var wg sync.WaitGroup
	for _, url := range l.relays {
		r, loaded := l.pool.Relays.Load(nostr.NormalizeURL(url))
		if !loaded || r == nil || !r.IsConnected() {
			skip.Add(1)
			continue
		}
		wg.Add(1)
		go func(url string, r *nostr.Relay) {
			defer wg.Done()
			pctx, cancel := context.WithTimeout(ctx, 3*time.Second)
			defer cancel()
			for _, ev := range evs {
				err := r.Publish(pctx, ev)
				if err == nil {
					ok.Add(1)
					slog.Debug("relay accepted", "relay", url)
					if ev.ID == echoID {
						l.expectEcho(echoID, url)
					}
					continue
				}
				fail.Add(1)
				if errors.Is(err, context.DeadlineExceeded) && ctx.Err() == nil {
					// No OK despite IsConnected(): the path is dead.
					// Flag a redial and stop using this pipe.
					stuck.Store(true)
					slog.Debug("relay timeout", "relay", url)
				} else {
					slog.Debug("relay rejected", "relay", url, "err", err)
				}
				return
			}
		}(url, r)
	}
	wg.Wait()
	slog.Debug("publish done", "rumor", rumorID[:8], "ok", ok.Load(), "fail", fail.Load(), "skip", skip.Load())
	if stuck.Load() {
		select {
		case l.resub <- struct{}{}:
		default:
		}
	}
	if ok.Load() == 0 {
		if int(skip.Load()) == len(l.relays) {
			return ErrNoRelayConnected
		}
		return fmt.Errorf("publish: no relay accepted")
	}
	return nil
}

// ErrNoRelayConnected means we never reached a relay, as opposed to a
// rejection — publishLoop defers without inflating the retry counter.
var ErrNoRelayConnected = errors.New("publish: no relay connected")
