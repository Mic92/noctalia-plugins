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

      // Buffer until we see a full JSON line, then dispatch.
      parser: SplitParser {
        onRead: line => {
          try {
            var req = JSON.parse(line);
            root._dispatch(conn, req);
          } catch (e) {
            Logger.w("SshAskpass", "bad request:", line, e);
            conn.write(JSON.stringify({ok: false}) + "\n");
          }
        }
      }
    }
  }

  function _dispatch(conn, req) {
    Logger.i("SshAskpass", "request mode=" + req.mode);
    if (window !== null) {
      // One prompt at a time. ssh-agent serialises signing anyway, but be
      // defensive against a misbehaving caller.
      Logger.w("SshAskpass", "busy, rejecting");
      conn.write(JSON.stringify({ok: false}) + "\n");
      return;
    }

    var comp = Qt.createComponent("AskpassWindow.qml");
    if (comp.status !== Component.Ready) {
      Logger.w("SshAskpass", "component error:", comp.errorString());
      conn.write(JSON.stringify({ok: false}) + "\n");
      return;
    }

    window = comp.createObject(root, {
      mode: req.mode || "prompt",
      promptText: req.text || "",
      pluginApi: Qt.binding(() => root.pluginApi)
    });

    window.done.connect(function(ok, value) {
      conn.write(JSON.stringify({ok: ok, value: value}) + "\n");
      if (window) {
        window.destroy();
        window = null;
      }
    });

    window.visible = true;
  }

  Component.onCompleted: {
    Logger.i("SshAskpass", "listening on", sockPath);
  }
}
