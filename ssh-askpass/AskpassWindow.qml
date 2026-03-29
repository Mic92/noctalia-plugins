import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Widgets
import qs.Services.UI

// Dual-mode askpass dialog, styled after the polkit-agent plugin so the two
// auth surfaces feel consistent.
//
// mode == "confirm": Allow/Deny buttons only, Enter=Allow Esc=Deny
// mode == "prompt":  password field, Enter submits, Esc cancels
PanelWindow {
  id: win

  property string mode: "prompt"
  property string promptText: ""
  property var pluginApi: null

  signal done(bool ok, string value)

  property bool _finished: false
  function finish(ok, value) {
    if (_finished) return;
    _finished = true;
    // Kill fprintd-verify if still running so it releases the device
    // before the next PAM client (sudo etc.) wants it.
    if (fprintVerify.running)
      fprintVerify.signal(15);
    done(ok, value);
  }

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  readonly property real shadowPadding: Style.shadowBlurMax + Style.marginL
  readonly property bool isConfirm: mode === "confirm"
  readonly property bool useFingerprint: isConfirm && cfg("confirmMethod") === "fingerprint"

  // fprintd-verify status line, e.g. "Verify result: verify-no-match (done)"
  property string fprintStatus: ""

  implicitWidth: 420 * Style.uiScaleRatio + shadowPadding * 2
  implicitHeight: contentLayout.implicitHeight + Style.marginL * 2 + shadowPadding * 2
  color: "transparent"

  function tr(key) {
    return pluginApi?.tr(key) ?? key;
  }

  function cfg(key) {
    var s = pluginApi?.pluginSettings || {};
    var d = pluginApi?.manifest?.metadata?.defaultSettings || {};
    return (key in s) ? s[key] : d[key];
  }

  // fprintd-verify exits 0 on match, non-zero otherwise. We treat its
  // exit code as the Allow/Deny decision. Stderr carries human-readable
  // status ("Verifying: right-index-finger", "verify-no-match") which we
  // surface in the dialog so the user knows what's happening.
  Process {
    id: fprintVerify
    command: ["fprintd-verify"]
    running: win.visible && win.useFingerprint && !win._finished

    stdout: SplitParser {
      onRead: line => { if (line) win.fprintStatus = line; }
    }
    stderr: SplitParser {
      onRead: line => { if (line) win.fprintStatus = line; }
    }

    onExited: (code, status) => {
      if (win._finished) return;
      // code 0 = verify-match. Anything else (no-match, device busy,
      // disconnected) is a deny — fail closed.
      win.finish(code === 0, "");
    }
  }

  // Auto-deny on timeout so a forgotten prompt doesn't leave the agent wedged.
  Timer {
    id: timeout
    interval: cfg("confirmTimeoutSec") * 1000
    running: win.visible
    onTriggered: win.finish(false, "")
  }

  Item {
    id: contentContainer
    anchors.fill: parent
    anchors.margins: win.shadowPadding
    focus: true

    Keys.onPressed: function(event) {
      if (Keybinds.checkKey(event, "escape", Settings)) {
        win.finish(false, "");
        event.accepted = true;
      } else if (Keybinds.checkKey(event, "enter", Settings)) {
        if (win.useFingerprint) {
          // No Enter-to-allow when fingerprint is required.
        } else if (win.isConfirm) {
          win.finish(true, "");
        } else if (passwordInput.text !== "") {
          win.finish(true, passwordInput.text);
        }
        event.accepted = true;
      }
    }

    NDropShadow {
      anchors.fill: bg
      source: bg
      autoPaddingEnabled: true
      z: -1
    }

    Rectangle {
      id: bg
      anchors.fill: parent
      radius: Style.radiusL
      color: Qt.alpha(Color.mSurface, 0.95)
      border.color: Color.mOutline
      border.width: Style.borderS
    }

    ColumnLayout {
      id: contentLayout
      anchors.centerIn: parent
      width: parent.width - Style.marginL * 2
      spacing: Style.marginM

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NImageRounded {
          Layout.preferredWidth: Style.fontSizeXXL * 2
          Layout.preferredHeight: Style.fontSizeXXL * 2
          imagePath: ""
          fallbackIcon: win.useFingerprint ? "fingerprint"
                       : win.isConfirm ? "key" : "lock"
          borderWidth: 0
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS

          NText {
            text: win.isConfirm ? win.tr("title-confirm") : win.tr("title-prompt")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NText {
            text: win.useFingerprint && win.fprintStatus
                  ? win.fprintStatus
                  : win.promptText
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }
        }
      }

      NTextInput {
        id: passwordInput
        Layout.fillWidth: true
        visible: !win.isConfirm
        placeholderText: win.tr("placeholder-passphrase")
        inputItem.echoMode: TextInput.Password
        onAccepted: win.finish(true, passwordInput.text)
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        spacing: Style.marginM

        Item { Layout.fillWidth: true }

        NButton {
          text: win.isConfirm ? win.tr("button-deny") : win.tr("button-cancel")
          backgroundColor: Color.mSurfaceVariant
          textColor: Color.mOnSurfaceVariant
          outlined: false
          onClicked: win.finish(false, "")
        }

        NButton {
          text: win.isConfirm ? win.tr("button-allow") : win.tr("button-ok")
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          // In fingerprint mode there is no Allow button — the sensor is
          // the button. Keeping Deny/Esc as the escape hatch.
          visible: !win.useFingerprint
          enabled: win.isConfirm || passwordInput.text !== ""
          onClicked: {
            if (win.isConfirm)
              win.finish(true, "");
            else
              win.finish(true, passwordInput.text);
          }
        }
      }
    }
  }

  Component.onCompleted: {
    if (!isConfirm)
      passwordInput.inputItem.forceActiveFocus();
    else
      contentContainer.forceActiveFocus();
  }
}
