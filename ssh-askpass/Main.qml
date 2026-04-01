import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// SSH_ASKPASS backend. A tiny stub executable (see ./stub/) connects to this
// socket, sends a JSON request, and blocks until we write a JSON response.
// This lets ssh-agent / ssh-tpm-agent surface passphrase and confirmation
// prompts as native noctalia dialogs instead of whatever lxqt-openssh-askpass
// decides to draw.
//
// Protocol (line-delimited JSON):
//   request:  {"mode":"confirm"|"prompt","text":"..."}\n
//   response: {"ok":true,"value":"..."}\n   or   {"ok":false}\n
//
// mode=confirm -> show yes/no, value is ignored by the stub (exit code matters)
// mode=prompt  -> show password field, value is the passphrase
Item {
  id: root

  property var pluginApi: null
  property var window: null
  property var windowConn: null  // conn that owns `window`; lets us tear down on disconnect

  // FIFO of {conn, req} for callers that arrive while a dialog is up. Multiple
  // ssh processes spawn independent askpass stubs that can't coordinate, so we
  // serialise here. Stale entries (conn died waiting) are skipped at pop time.
  property var pending: []

  readonly property string sockPath: {
    var rt = Quickshell.env("XDG_RUNTIME_DIR");
    return rt + "/noctalia-ssh-askpass.sock";
  }

  SocketServer {
    id: server
    active: pluginApi !== null
    path: root.sockPath

    handler: Socket {
      id: conn

      // The owning conn dropping must close the active dialog and pump the
      // queue, otherwise we wedge. Queued conns dropping are handled lazily
      // at pop time (connected check) to keep this path simple.
      onConnectedChanged: {
        if (!connected && root.windowConn === conn) {
          root.window?.destroy();
          root.window = null;
          root.windowConn = null;
          root._drain();
        }
      }

      // Buffer until we see a full JSON line, then dispatch.
      parser: SplitParser {
        onRead: line => {
          try {
            var req = JSON.parse(line);
            root._dispatch(conn, req);
          } catch (e) {
            Logger.w("SshAskpass", "bad request:", line, e);
            root._reject(conn);
          }
        }
      }
    }
  }

  function _reject(conn) {
    conn.write(JSON.stringify({ok: false}) + "\n");
    conn.flush(); // server-side socket: must flush or short-lived clients miss the reply
  }

  function _dispatch(conn, req) {
    Logger.i("SshAskpass", "request mode=" + req.mode + " pending=" + pending.length);
    pending.push({conn: conn, req: req});
    _drain();
  }

  // Pop the next live request and show it. Called after every dialog
  // close (done/disconnect), so the queue self-serves.
  function _drain() {
    if (window !== null) return;

    var next;
    while ((next = pending.shift())) {
      // Skip waiters whose stub already gave up.
      if (next.conn.connected) break;
    }
    if (!next) return;

    var comp = Qt.createComponent("AskpassWindow.qml");
    if (comp.status !== Component.Ready) {
      Logger.w("SshAskpass", "component error:", comp.errorString());
      _reject(next.conn);
      Qt.callLater(_drain);
      return;
    }

    var conn = next.conn;
    var w = comp.createObject(root, {
      mode: next.req.mode || "prompt",
      promptText: next.req.text || "",
      pluginApi: Qt.binding(() => root.pluginApi)
    });
    window = w;
    windowConn = conn;

    w.done.connect(function(ok, value) {
      // conn may already be gone; write is a no-op then.
      conn.write(JSON.stringify({ok: ok, value: value}) + "\n");
      conn.flush();
      if (root.window === w) {
        root.window = null;
        root.windowConn = null;
      }
      w.destroy();
      // Next dialog only after this one's destroy has settled.
      Qt.callLater(root._drain);
    });

    w.visible = true;
  }

  Component.onCompleted: {
    Logger.i("SshAskpass", "listening on", sockPath);
  }
}
