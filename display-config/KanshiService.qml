import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Persistence + auto-apply layer for display layouts. Owns
// $XDG_CONFIG_HOME/kanshi/noctalia.conf and only ever rewrites profile
// blocks there, so the user's hand-written main config is never touched.
// That file is the single source of truth — nothing is mirrored into
// plugin settings.
Item {
  id: root

  // Wired from Main.qml.
  property var pluginApi: null
  property var displayService: null

  property string activeProfile: ""
  property bool available: false

  readonly property string configDir: (pluginApi?.pluginSettings?.kanshiConfigDir) || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/kanshi")
  readonly property bool enabled: pluginApi?.pluginSettings?.kanshiEnabled ?? pluginApi?.manifest?.metadata?.defaultSettings?.kanshiEnabled ?? false

  // FileView watches both configs and mirrors them into plain string
  // properties on load, so this binding stays a pure function of those
  // (calling text() here directly would loop: blockLoading makes the
  // first read fire loaded() mid-evaluation).
  readonly property var profiles: {
    var seen = {}, out = [];
    var add = function (txt, managed) {
      for (var m, re = /^\s*profile\s+([^\s{]+)/gm; (m = re.exec(txt)); ) {
        if (seen[m[1]])
          continue;
        seen[m[1]] = true;
        out.push({
                   "name": m[1],
                   "managed": managed
                 });
      }
    };
    add(managedFile.content, true);
    add(mainFile.content, false);
    return out;
  }

  function refresh() {
    if (enabled)
      statusProc.running = true;
  }

  function switchProfile(name) {
    ctl(["switch", name]);
  }
  function reload() {
    ctl(["reload"]);
  }
  function ctl(args) {
    ctlProc.command = ["kanshictl"].concat(args);
    ctlProc.running = true;
  }

  // Render the current compositor state as a kanshi profile block.
  // External monitors with a serial use "make model serial" (stable across
  // reboots/docks); internal panels and serial-less outputs fall back to
  // the connector name so we never emit the "Unknown" placeholder.
  function renderProfile(name) {
    var lines = ["profile " + name + " {"];
    for (var i = 0; i < displayService.outputs.length; i++) {
      var o = displayService.outputs[i];
      var internal = /^(edp|lvds|dsi)/i.test(o.name);
      var crit = (!internal && o.serial) ? '"' + [o.make || "Unknown", o.model || "Unknown", o.serial].join(" ") + '"' : o.name;
      var parts = ["  output", crit];
      if (!o.enabled) {
        parts.push("disable");
      } else {
        parts.push("enable");
        if (o.currentMode)
          parts.push("mode " + o.currentMode);
        if (o.position)
          parts.push("position " + o.position.x + "," + o.position.y);
        if (o.scale)
          parts.push("scale " + o.scale);
        if (o.transform && o.transform !== "normal")
          parts.push("transform " + o.transform);
      }
      lines.push(parts.join(" "));
    }
    lines.push("}");
    return lines.join("\n") + "\n";
  }

  // The managed file only ever contains blocks we wrote ourselves (no
  // nested braces), so a non-greedy match to the next top-level `}` is a
  // safe "parser".
  function withoutProfile(text, name) {
    var esc = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return text.replace(new RegExp("^profile\\s+" + esc + "\\s*\\{[^]*?\\n\\}\\n?", "m"), "");
  }

  function saveProfile(name) {
    // kanshi profile names are bare tokens; refuse anything that would
    // break the grammar instead of writing a file the daemon rejects.
    if (!/^[\w.+-]+$/.test(name)) {
      ToastService.showNotice("Kanshi", "Invalid profile name (use letters, digits, . _ + -)", "alert-triangle");
      return;
    }
    if (displayService.outputs.length === 0)
      return;
    managedFile.write(withoutProfile(managedFile.read(), name) + renderProfile(name));
    ToastService.showNotice("Kanshi", "Saved profile '" + name + "'", "device-floppy");
  }

  function deleteProfile(name) {
    managedFile.write(withoutProfile(managedFile.read(), name));
  }

  FileView {
    id: mainFile
    property string content: ""
    path: root.enabled ? root.configDir + "/config" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: content = text()
  }

  FileView {
    id: managedFile
    // `content` is what callers read/edit; text() only reflects the last
    // disk load, so a second save before the watch→reload round-trip would
    // otherwise base itself on stale bytes and drop the first.
    property string content: ""
    path: root.enabled ? root.configDir + "/noctalia.conf" : ""
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: content = text()
    function read() {
      waitForJob();
      return content;
    }
    function write(s) {
      content = s;
      setText(s);
    }
    // setText() is async/atomic; tell kanshi only once the bytes are on disk.
    onSaved: root.reload()
    onSaveFailed: function (err) {
      ToastService.showNotice("Kanshi", "Failed to write " + path + ": " + FileViewError.toString(err), "alert-triangle");
    }
  }

  // Polled every pollInterval; kept separate from ctlProc so the timer
  // can't overwrite a user-initiated switch/reload mid-flight.
  Process {
    id: statusProc
    command: ["kanshictl", "status"]
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function (exitCode) {
      root.available = (exitCode === 0);
      try {
        root.activeProfile = JSON.parse(stdout.text || "{}").current_profile || "";
      } catch (e) {
        root.activeProfile = "";
      }
    }
  }

  Process {
    id: ctlProc
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        var msg = (stderr.text || stdout.text || "").trim();
        Logger.w("DisplayConfig", "kanshictl", command[1], "failed:", msg);
        ToastService.showNotice("Kanshi", msg || "kanshictl failed", "alert-triangle");
      }
      displayService?.fetchOutputs();
      root.refresh();
    }
  }
}
