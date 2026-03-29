import QtQuick
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi: null

  // Expose service to bar widget via mainInstance
  property alias mailService: mailService

  QtObject {
    id: mailService

    property int unreadCount: 0
    property string fetchState: "idle" // "idle", "loading", "success", "error"
    property string errorMessage: ""

    function refresh() {
      var cfg = pluginApi?.pluginSettings || {};
      var defaults = pluginApi?.manifest?.metadata?.defaultSettings || {};
      var cmd = cfg.countCommand ?? defaults.countCommand;

      fetchState = "loading";
      countProcess.command = ["sh", "-c", cmd];
      countProcess.running = true;
    }
  }

  Process {
    id: countProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function(exitCode) {
      if (exitCode !== 0) {
        mailService.fetchState = "error";
        mailService.errorMessage = stderr.text || ("exit " + exitCode);
        Logger.w("MailCount", "count command failed:", exitCode, stderr.text);
        return;
      }

      var n = parseInt(stdout.text.trim(), 10);
      if (isNaN(n)) {
        mailService.fetchState = "error";
        mailService.errorMessage = "Non-numeric output: " + stdout.text;
        Logger.w("MailCount", "Non-numeric output:", stdout.text);
        return;
      }

      mailService.unreadCount = n;
      mailService.fetchState = "success";
      Logger.d("MailCount", "Unread:", n);
    }
  }

  Timer {
    id: pollTimer
    repeat: true
    running: pluginApi !== null
    triggeredOnStart: true
    interval: {
      var cfg = pluginApi?.pluginSettings || {};
      var defaults = pluginApi?.manifest?.metadata?.defaultSettings || {};
      var secs = cfg.pollInterval ?? defaults.pollInterval;
      return secs * 1000;
    }
    onTriggered: mailService.refresh()
  }

  IpcHandler {
    target: "plugin:mail-count"
    function refresh() {
      mailService.refresh();
    }
  }
}
