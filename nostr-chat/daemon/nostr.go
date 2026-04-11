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

// nip59Margin: gift-wrap created_at is randomised up to 2 days into the
// past, so subscribing from last-seen alone would miss events. 3 days
// gives a comfortable buffer (same margin nitrous uses).
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

// Rumor is what we extract from an unwrapped gift — just enough to
// route kind-14 vs kind-7 without hauling the full event around.
type Rumor struct {
	ID      string
	Kind    nostr.Kind
	PubKey  string
	Content string
	TS      int64
	ETag    string     // first "e" tag: reaction target (kind-7) or reply parent (kind-14)
	Tags    nostr.Tags // kind-15 needs file-type / decryption-* tags
}

// Listener subscribes to kind-1059 gift wraps addressed to us and
// unwraps them. We don't use nip17.ListenForMessages because it
// silently drops anything that isn't kind-14, but peers may also wrap
// kind-7 reactions (read receipts) and kind-15 files the same way.
type Listener struct {
	pool   *nostr.Pool
	kr     nostr.Keyer
	keys   Keys
	relays []string

	// OnHealth is invoked from the liveness watchdog with the set of
	// currently-connected relay URLs. The daemon hooks this to push
	// EvStatus transitions so the panel's "connected" reflects relay
	// reality, not just "the unix socket is up".
	OnHealth func(connected []string)
}

func NewListener(keys Keys, relays []string) *Listener {
	kr := keyer.NewPlainKeySigner(keys.SK)
	pool := nostr.NewPool(nostr.PoolOptions{
		// Relays that require NIP-42 auth will drop 1059 subs otherwise.
		AuthRequiredHandler: func(ctx context.Context, ev *nostr.Event) error {
			return kr.SignEvent(ctx, ev)
		},
	})
	return &Listener{pool: pool, kr: kr, keys: keys, relays: relays}
}

// Run blocks until ctx is done, emitting unwrapped rumors on ch.
// Pool.SubscribeMany handles per-relay reconnect internally; we only
// loop here to recover from the channel closing entirely (all relays
// dead at once) or when the suspend watchdog fires. `since` is re-read
// from the store on each reconnect so a drop after an hour doesn't
// re-fetch the whole hour.
func (l *Listener) Run(ctx context.Context, since func() int64, ch chan<- Rumor) {
	backoff := time.Second
	for ctx.Err() == nil {
		start := time.Now()
		// Cancel the subscription if we detect a suspend/resume: stale
		// TCP sockets can survive a short sleep looking ESTABLISHED
		// while the relay has long since timed us out. The pool's ping
		// shares a goroutine with writes, so a zombie read socket goes
		// unnoticed while publishes (which open fresh connections)
		// still succeed. Force a full resubscribe.
		subCtx, subCancel := context.WithCancel(ctx)
		go l.watchLiveness(subCtx, func() { l.dropConnections(); subCancel() })
		l.subscribeOnce(subCtx, since(), ch)
		subCancel()
		// A subscription that ran for a while was healthy — reset
		// backoff so a brief blip doesn't leave us at 1-minute delays
		// forever.
		if time.Since(start) > 30*time.Second {
			backoff = time.Second
		}
		slog.Warn("subscription closed, reconnecting", "backoff", backoff)
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
		}
		if backoff < time.Minute {
			backoff *= 2
		}
	}
}

// dropConnections force-closes every pooled relay. EnsureRelay checks
// IsConnected() before reuse, so the next subscribeOnce dials fresh
// sockets instead of inheriting the zombie that triggered the watchdog.
func (l *Listener) dropConnections() {
	for _, r := range l.pool.Relays.Range {
		if r != nil {
			r.Close()
		}
	}
}

// watchLiveness ticks every 30s and forces a resubscribe (via cancel)
// when either condition hits:
//
//   - Wall-clock jumped ahead of the monotonic ticker — suspend/resume.
//     time.After uses CLOCK_MONOTONIC, which pauses during suspend;
//     time.Now().Unix() reads CLOCK_REALTIME, which does not. A 30s
//     tick that "took" 15 minutes of wall time means we slept.
//
//   - No relay has been connected for three consecutive ticks. The
//     pool's per-relay goroutine exits permanently on a CLOSED frame
//     (pool.go subMany), so a healthy relay that sends CLOSED while a
//     dead one is still retrying leaves SubscribeMany's channel open
//     with zero live subs. Our outer Run loop never learns. Nuking the
//     sub and starting fresh gives every relay a new goroutine.
//
// It also reports the connected set on every tick so the daemon can
// surface real streaming status and the journal records which relay is
// the culprit during an outage.
func (l *Listener) watchLiveness(ctx context.Context, cancel func()) {
	const tick = 30 * time.Second
	var deadTicks int
	for {
		before := time.Now().Unix()
		select {
		case <-ctx.Done():
			return
		case <-time.After(tick):
		}
		gap := time.Duration(time.Now().Unix()-before)*time.Second - tick
		if gap > time.Minute {
			slog.Info("time jump, resubscribing", "gap", gap.Round(time.Second))
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

// Connected returns the URLs of relays the pool currently has an open
// websocket to. Cheap enough to call from the replay handler so the
// status it reports matches what the watchdog sees.
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
	filter := nostr.Filter{
		Kinds: []nostr.Kind{nostr.KindGiftWrap},
		Tags:  nostr.TagMap{"p": {l.keys.PK.Hex()}},
		Since: adj,
	}
	for ev := range l.pool.SubscribeMany(ctx, l.relays, filter, nostr.SubscriptionOptions{}) {
		rumor, err := nip59.GiftUnwrap(ev.Event,
			func(pk nostr.PubKey, ct string) (string, error) {
				return l.kr.Decrypt(ctx, ct, pk)
			})
		if err != nil {
			// Not ours, or malformed — a relay serving someone else's
			// p-tag match would hit this. Quietly skip.
			continue
		}
		r := Rumor{
			ID:      rumor.ID.Hex(),
			Kind:    rumor.Kind,
			PubKey:  rumor.PubKey.Hex(),
			Content: rumor.Content,
			TS:      int64(rumor.CreatedAt),
			Tags:    rumor.Tags,
		}
		for _, t := range rumor.Tags {
			if len(t) >= 2 && t[0] == "e" {
				r.ETag = t[1]
				break
			}
		}
		select {
		case ch <- r:
		case <-ctx.Done():
			return
		}
	}
}

// Outgoing holds a built-but-unpublished DM. Split from the publish
// step so callers can echo locally (instant UI feedback) before the
// slow network round-trip.
type Outgoing struct {
	Rumor  Rumor
	toThem nostr.Event
	toUs   nostr.Event
}

// Wraps serialises both gift-wrap events so they can sit in the outbox
// and survive a daemon restart. They're just signed JSON — no secret
// material beyond what the relay will see anyway.
func (o Outgoing) Wraps() (them, us string) {
	t, _ := json.Marshal(o.toThem)
	u, _ := json.Marshal(o.toUs)
	return string(t), string(u)
}

// Prepare builds the kind-14 rumor and both gift wraps. Pure crypto,
// no network — microseconds. The returned Rumor has the final id, so
// the self-copy arriving later via the listen loop dedups cleanly.
// replyTo, if non-empty, is added as an e-tag so the peer can thread
// the response against a prior message.
func (l *Listener) Prepare(ctx context.Context, to, content, replyTo string) (Outgoing, error) {
	recipient, err := nostr.PubKeyFromHex(to)
	if err != nil {
		return Outgoing{}, fmt.Errorf("recipient pubkey: %w", err)
	}
	tags := nostr.Tags{{"p", to}}
	if replyTo != "" {
		tags = append(tags, nostr.Tag{"e", replyTo})
	}
	rumor := nostr.Event{
		Kind:      14,
		Content:   content,
		Tags:      tags,
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
	return Outgoing{
		Rumor: Rumor{
			ID: rumor.ID.Hex(), Kind: rumor.Kind, PubKey: rumor.PubKey.Hex(),
			Content: rumor.Content, TS: int64(rumor.CreatedAt),
		},
		toThem: toThem, toUs: toUs,
	}, nil
}

// PrepareFile builds a kind-15 file rumor with encryption metadata.
// Same Prepare/Publish split as text: caller echoes locally first.
func (l *Listener) PrepareFile(ctx context.Context, to, url string, enc *encryptedFile) (Outgoing, error) {
	recipient, err := nostr.PubKeyFromHex(to)
	if err != nil {
		return Outgoing{}, fmt.Errorf("recipient pubkey: %w", err)
	}
	rumor := nostr.Event{
		Kind:    KindFileMessage,
		Content: url,
		Tags: nostr.Tags{
			{"p", to},
			{"file-type", enc.Mime},
			{"encryption-algorithm", "aes-gcm"},
			{"decryption-key", enc.KeyHex},
			{"decryption-nonce", enc.NonceHex},
			{"x", enc.SHA256Hex},
			{"ox", enc.OxHex},
		},
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
	return Outgoing{
		Rumor: Rumor{
			ID: rumor.ID.Hex(), Kind: rumor.Kind, PubKey: rumor.PubKey.Hex(),
			Content: rumor.Content, TS: int64(rumor.CreatedAt), Tags: rumor.Tags,
		},
		toThem: toThem, toUs: toUs,
	}, nil
}

// PublishRaw sends serialised gift-wraps from the outbox to relays the
// subscription loop has already opened — no EnsureRelay, no 7s dial
// under the per-URL mutex shared with subscribe. A dead relay costs
// ~nothing, so the sequential outbox drain doesn't head-of-line block
// on timeouts. Reconnection is the listen loop's job; we just retry
// once it's back.
//
// This is the only publish path. Text and file sends alike enqueue
// their wraps and let publishLoop drain them, so both get retry/cancel
// and the same rumor id survives across attempts — the peer's ack lands
// on the bubble the user is staring at, not a phantom row.
func (l *Listener) PublishRaw(ctx context.Context, rumorID, themJSON, usJSON string) error {
	var them, us nostr.Event
	if err := json.Unmarshal([]byte(themJSON), &them); err != nil {
		return fmt.Errorf("decode wrap-them: %w", err)
	}
	if err := json.Unmarshal([]byte(usJSON), &us); err != nil {
		return fmt.Errorf("decode wrap-us: %w", err)
	}
	return l.publishConnected(ctx, rumorID, them, us)
}

// publishConnected fans the wraps out to every already-open relay in
// parallel, each with its own 3s deadline. A zombie connection (TCP up,
// app dead — the state watchLiveness eventually reaps) used to soak the
// shared timeout and starve the good relays; now it just times out on
// its own while the others ack.
func (l *Listener) publishConnected(ctx context.Context, rumorID string, evs ...nostr.Event) error {
	var ok, fail, skip atomic.Int32
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
				if err := r.Publish(pctx, ev); err != nil {
					fail.Add(1)
					slog.Debug("relay rejected", "relay", url, "err", err)
				} else {
					ok.Add(1)
					slog.Debug("relay accepted", "relay", url)
				}
			}
		}(url, r)
	}
	wg.Wait()
	slog.Debug("publish done", "rumor", rumorID[:8], "ok", ok.Load(), "fail", fail.Load(), "skip", skip.Load())
	if ok.Load() == 0 {
		if int(skip.Load()) == len(l.relays) {
			return ErrNoRelayConnected
		}
		return fmt.Errorf("publish: no relay accepted")
	}
	return nil
}

// ErrNoRelayConnected means we never reached a relay — the subscription
// hasn't (re)connected yet. Distinct from a rejection so publishLoop
// can defer without inflating the retry counter.
var ErrNoRelayConnected = errors.New("publish: no relay connected")
