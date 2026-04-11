import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Thin view layer. All state — history, dedup, outbox, reconnect —
// lives in nostr-chatd. A single persistent unix socket carries NDJSON
// both ways: we write commands, the daemon writes events. On connect
// (and every reconnect) we send a replay; that's the whole resync
// protocol.
Item {
  id: root

  property var pluginApi: null
  property alias chat: chat

  function cfg(key) {
    const s = pluginApi?.pluginSettings || {};
    const d = pluginApi?.manifest?.metadata?.defaultSettings || {};
    return s[key] ?? d[key];
  }

  // XDG_RUNTIME_DIR is guaranteed by systemd-logind; without it rbw
  // (and thus the daemon) can't run either, so no fallback needed.
  // Quickshell.env returns QVariant — String() avoids "undefined/…".
  readonly property string sockPath:
    String(Quickshell.env("XDG_RUNTIME_DIR")) + "/nostr-chatd.sock"

  // Mirror of the daemon's typed enums. QML has no real enum type for
  // dynamic JS, but a frozen object at least centralises the strings
  // so a rename is one grep instead of six.
  readonly property var ev: Object.freeze({
    status: "status", msg: "msg", sent: "sent", retry: "retry",
    ack: "ack", img: "img", error: "error",
  })
  readonly property var cmd: Object.freeze({
    send: "send", sendFile: "send-file", replay: "replay",
    markRead: "mark-read", retry: "retry", cancel: "cancel",
  })
  readonly property var state: Object.freeze({
    pending: "pending", sent: "sent", cancelled: "cancelled",
  })

  QtObject {
    id: chat
    property string peerName: ""   // from daemon's NOSTR_CHAT_DISPLAY_NAME
    property bool streaming: false
    property int relaysUp: 0
    property int relaysTotal: 0
    property var relays: []        // connected URLs, for the header tooltip
    property string lastError: ""
    property var messages: []   // [{id, from, text, ts, ack, image, replyTo, state, tries}]
    property var replyTarget: null  // {id, text} — set by Panel when user clicks a bubble

    function send(text) {
      if (!text.trim()) return;
      root.sockSend({
        cmd: root.cmd.send, text: text,
        replyTo: replyTarget ? replyTarget.id : undefined,
      });
      replyTarget = null;
    }
    function sendFile(path, unlink) {
      if (!path) return;
      // NFilePicker returns bare paths; strip file:// just in case.
      if (path.startsWith("file://")) path = decodeURIComponent(path.slice(7));
      root.sockSend({ cmd: root.cmd.sendFile, path: path, unlink: !!unlink });
    }
    function retry(id)  { root.sockSend({ cmd: root.cmd.retry,  id: id }); }
    function cancel(id) { root.sockSend({ cmd: root.cmd.cancel, id: id }); }

    // Patch a single message in place and reassign so ListView refreshes.
    function patch(id, props) {
      const arr = messages.slice();
      const i = arr.findIndex(x => x.id === id);
      if (i < 0) return;
      arr[i] = Object.assign({}, arr[i], props);
      messages = arr;
    }
  }

  // Errors shouldn't outlive their toast. Per-bubble ⚠ is the durable
  // signal; this line is just transient context.
  Timer {
    id: errorTimer
    interval: 10000
    onTriggered: chat.lastError = ""
  }

  // Open the panel idempotently. Upstream openPluginPanel() has a bug:
  // when the slot already holds our plugin it calls panel.toggle(),
  // slamming it shut mid-read. Guard on panelOpenScreen ourselves.
  function showPanel() {
    if (pluginApi?.panelOpenScreen) { sockSend({ cmd: cmd.markRead }); return; }
    pluginApi?.withCurrentScreen(s => pluginApi.openPanel(s));
    sockSend({ cmd: cmd.markRead });
  }

  // Persistent bidirectional socket. On connect we ask for a replay;
  // the daemon answers with status + recent messages on the same pipe.
  // A disconnect (daemon restart, suspend) just triggers the reconnect
  // timer — next connect replays again, so the ListView converges
  // without any booted/handshake dance.
  //
  // Loader wrapper: Quickshell's Socket keeps its QLocalSocket alive
  // after a failed connect (errorOccurred fires, disconnected doesn't),
  // and setConnected(true) only dials when that pointer is null — so
  // one refused/not-found leaves it wedged forever. Recreating the
  // whole Socket is the only QML-side way to drop the stale handle.
  Loader {
    id: sock
    sourceComponent: sockComponent
    readonly property bool connected: item?.connected ?? false
  }
  Component {
    id: sockComponent
    Socket {
      path: root.sockPath
      connected: true
      parser: SplitParser { onRead: line => root.recv(line) }
      onConnectionStateChanged: {
        if (connected) {
          reconnect.stop();
          reconnect.interval = 500;
          chat.lastError = "";
          // sock.item may still be null here (Loader hasn't published
          // it yet when QLocalSocket connects synchronously during
          // construction), so write through `this`, not sockSend().
          write(JSON.stringify({ cmd: root.cmd.replay, n: root.cfg("maxHistory") || 200 }) + "\n");
          flush();
        } else {
          chat.streaming = false;
          reconnect.start();
        }
      }
      onError: (e) => {
        chat.lastError = "daemon unreachable";
        Logger.w("NostrChat", "socket", e, "path", path);
        reconnect.start();
      }
    }
  }
  Timer {
    id: reconnect
    interval: 500
    // Cap under the daemon's RestartSec so we're waiting when it
    // returns, not the other way round.
    onTriggered: {
      // Tear down and rebuild — see Loader comment for why a simple
      // `connected = true` can't recover from a refused connect.
      sock.active = false; sock.active = true;
      interval = Math.min(interval * 2, 4000);
    }
  }
  function sockSend(c) {
    if (!sock.item?.connected) return;  // replay-on-connect covers the gap
    sock.item.write(JSON.stringify(c) + "\n");
    sock.item.flush();
  }

  // One NDJSON line from the daemon.
  function recv(raw) {
    let ev;
    try { ev = JSON.parse(raw); }
    catch (e) { Logger.w("NostrChat", "bad ipc json", raw); return; }

    switch (ev.kind) {
    case root.ev.status:
      chat.streaming   = ev.streaming;
      chat.relaysUp    = ev.relaysUp || 0;
      chat.relaysTotal = ev.relaysTotal || chat.relaysTotal;
      chat.relays      = ev.relays || [];
      chat.peerName    = ev.name || chat.peerName;
      break;

    case root.ev.msg: {
      const m = ev.msg;
      // Daemon dedups; we just keep a bounded in-memory mirror for the
      // ListView. Insert-sort by ts since replay + live can interleave.
      const entry = {
        id: m.id, text: m.content, ts: m.ts * 1000, ack: m.ack,
        image: m.image || "", replyTo: m.replyTo || "",
        state: m.state || state.sent, tries: 0,
        from: m.dir === "out" ? "me" : "peer",
      };
      let arr = chat.messages.slice();
      let i = arr.length;
      while (i > 0 && arr[i-1].ts > entry.ts) i--;
      // Skip if already mirrored (replay after a live insert).
      if (arr.some(x => x.id === entry.id)) return;
      arr.splice(i, 0, entry);
      const max = cfg("maxHistory") || 200;
      if (arr.length > max) arr = arr.slice(-max);
      chat.messages = arr;

      // Auto-open on live bot replies. The daemon marks replayed
      // history as read, so shell startup won't pop the panel for
      // yesterday's conversation.
      if (m.dir === "in" && !m.read) root.showPanel();
      break;
    }

    case root.ev.sent:
      if (ev.state === state.cancelled) {
        chat.messages = chat.messages.filter(x => x.id !== ev.target);
      } else {
        chat.patch(ev.target, { state: state.sent, tries: 0 });
      }
      break;

    case root.ev.retry:
      // Mark the specific bubble ⚠ — the user can tap to force a retry
      // or drop it. Toast only on the first failure so backoff doesn't
      // spam the notification stack.
      chat.patch(ev.target, { tries: ev.tries });
      if (ev.tries === 1)
        ToastService.showError((chat.peerName || "nostr-chat") + ": send failed, retrying");
      break;

    case root.ev.ack:
      chat.patch(ev.target, { ack: ev.mark });
      break;

    case root.ev.img:
      chat.patch(ev.target, { image: ev.image });
      break;

    case root.ev.error:
      chat.lastError = ev.text;
      errorTimer.restart();
      ToastService.showError((chat.peerName || "nostr-chat") + ": " + ev.text);
      break;
    }
  }

  property real _lastTap: 0
  IpcHandler {
    target: "plugin:nostr-chat"

    function tap() {
      const now = Date.now();
      if (now - root._lastTap < 400) toggle();
      root._lastTap = now;
    }
    function toggle() {
      sockSend({ cmd: root.cmd.markRead });
      pluginApi?.withCurrentScreen(s => pluginApi.togglePanel(s));
    }
    function send(text: string) { chat.send(text); }

    // Close the panel before a screenshot bind fires. Slurp can't
    // select through a layer-shell overlay, and you don't want the
    // chat in the capture anyway. The actual grim/slurp runs from
    // the niri keybind — spawning it *from* noctalia stacks slurp's
    // surface below the shell's own layers, making the crosshair
    // invisible. Compositor-spawned processes get correct ordering.
    function hide() {
      pluginApi?.withCurrentScreen(s => pluginApi.closePanel(s));
    }

    // Receives the captured path from the keybind script. Asks the
    // daemon to unlink after caching — the source is a mktemp in
    // $XDG_RUNTIME_DIR we don't want to accumulate. The paperclip
    // button calls chat.sendFile directly without this flag.
    function sendFile(path: string) { chat.sendFile(path, true); }
  }

}
