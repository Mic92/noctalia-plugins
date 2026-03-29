import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Watches fprintd on the system bus and surfaces verification events as
// shell toasts. The point is to give `sudo` (or any PAM client using
// pam_fprintd) a visual desktop cue — otherwise the only hint that a
// fingerprint is expected is a blocked terminal prompt that's easy to miss.
//
// Quickshell has no native system-bus DBus client, and fprintd exposes one
// Device object per reader whose path we don't know up front, so we tail
// `gdbus monitor` and parse its line-oriented output. Same long-running
// Process pattern the display-config plugin uses.
Item {
  id: root

  property var pluginApi: null

  // Exposed via mainInstance in case a future bar widget wants to bind a
  // persistent indicator instead of relying on the transient toast.
  property bool verifyInProgress: false
  property string lastResult: ""

  function cfg(key) {
    var s = pluginApi?.pluginSettings || {};
    var d = pluginApi?.manifest?.metadata?.defaultSettings || {};
    return (key in s) ? s[key] : d[key];
  }

  Process {
    id: monitor
    // No --object-path: watch every device under this name so we don't have
    // to enumerate /net/reactivated/Fprint/Device/N first.
    command: ["gdbus", "monitor", "--system", "--dest", "net.reactivated.Fprint"]
    running: pluginApi !== null

    stdout: SplitParser {
      onRead: line => root._parse(line)
    }

    onRunningChanged: {
      // gdbus exits if fprintd restarts; bring the monitor back.
      if (!running && pluginApi !== null) {
        Logger.w("FprintNotify", "gdbus monitor exited, restarting");
        restartTimer.start();
      }
    }
  }

  Timer {
    id: restartTimer
    interval: 1000
    onTriggered: monitor.running = true
  }

  // A PAM client that dies without VerifyStop would leave our toast stuck;
  // time it out defensively.
  Timer {
    id: staleTimer
    interval: root.cfg("staleTimeoutSec") * 1000
    onTriggered: {
      if (root.verifyInProgress) {
        Logger.w("FprintNotify", "Verify stuck in-progress, clearing");
        root.verifyInProgress = false;
        ToastService.dismissToast();
      }
    }
  }

  function _parse(line) {
    // gdbus monitor lines look like:
    //   /net/reactivated/Fprint/Device/0: net.reactivated.Fprint.Device.VerifyFingerSelected ('right-index-finger',)
    //   /net/reactivated/Fprint/Device/0: net.reactivated.Fprint.Device.VerifyStatus ('verify-match', true)
    if (line.indexOf("VerifyFingerSelected") !== -1) {
      var m = line.match(/\('([^']+)'/);
      _onStarted(m ? m[1] : "");
      return;
    }
    if (line.indexOf("VerifyStatus") !== -1) {
      var m2 = line.match(/\('([^']+)',\s*(true|false)\)/);
      if (m2)
        _onStatus(m2[1], m2[2] === "true");
      return;
    }
  }

  function _onStarted(finger) {
    verifyInProgress = true;
    lastResult = "";
    staleTimer.restart();
    Logger.i("FprintNotify", "Verify started:", finger);

    ToastService.showNotice(
      "Touch fingerprint sensor",
      _prettyFinger(finger),
      "fingerprint",
      // Long duration: we dismiss explicitly on VerifyStatus. This only
      // guards the case where that signal never arrives.
      staleTimer.interval
    );
  }

  function _onStatus(result, done) {
    lastResult = result;
    Logger.i("FprintNotify", "Verify status:", result, "done:", done);

    if (!done) {
      // Retryable intermediate: swipe too short, finger not centered, etc.
      ToastService.showWarning(_prettyResult(result), "Try again");
      staleTimer.restart();
      return;
    }

    verifyInProgress = false;
    staleTimer.stop();
    ToastService.dismissToast();

    if (result === "verify-match") {
      if (cfg("showSuccessToast"))
        ToastService.showNotice("Authenticated", "", "fingerprint", 1500);
    } else if (result === "verify-no-match") {
      ToastService.showError("Fingerprint not recognized");
    }
    // verify-disconnected / verify-unknown-error: stay quiet, the PAM
    // conversation will surface its own error in the terminal.
  }

  function _prettyFinger(f) {
    // fprintd uses identifiers like "right-index-finger".
    return f.replace(/-/g, " ");
  }

  function _prettyResult(r) {
    return r.replace(/^verify-/, "").replace(/-/g, " ");
  }

  Component.onCompleted: {
    Logger.i("FprintNotify", "Monitoring net.reactivated.Fprint on system bus");
  }
}
