import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// One output: name + identity, power toggle, mode picker, scale spinner.
// Changes are applied immediately with the service's revert countdown so a
// bad mode that blacks the screen rolls back on its own.
Rectangle {
  id: root

  required property var modelData
  property var displayService: null
  property var tr: function (k, a) {
    return k;
  }

  Layout.fillWidth: true
  Layout.preferredHeight: cardColumn.implicitHeight + Style.marginM * 2
  radius: Style.radiusM
  color: Color.mSurfaceVariant

  ColumnLayout {
    id: cardColumn
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginS

    // Title row: name + make/model + power toggle
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NIcon {
        icon: modelData.enabled ? "device-desktop" : "device-desktop-off"
        pointSize: Style.fontSizeL
        color: modelData.enabled ? Color.mPrimary : Color.mOnSurfaceVariant
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        NText {
          text: modelData.name
          font.bold: true
          font.pixelSize: Style.fontSizeM
          color: Color.mOnSurface
        }

        NText {
          visible: text !== ""
          text: [modelData.make, modelData.model].filter(function (s) {
            return s && s.trim() !== "";
          }).join(" ")
          font.pixelSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
        }
      }

      NToggle {
        checked: modelData.enabled
        onToggled: function (checked) {
          displayService?.applyOutput(modelData.name, {
                                        "enabled": checked
                                      }, true);
        }
      }
    }

    // Mode selector — group by resolution so the dropdown isn't a wall of
    // near-duplicate 59.94/59.95/60.00 Hz entries. The first
    // (highest-refresh) variant per resolution shows as "3840×1600",
    // later ones as indented "  @59.94".
    RowLayout {
      Layout.fillWidth: true
      visible: modelData.enabled
      spacing: Style.marginS

      NText {
        text: root.tr("panel.mode")
        font.pixelSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
        Layout.preferredWidth: 60
      }

      NComboBox {
        Layout.fillWidth: true
        model: {
          var lm = [];
          var seenRes = {};
          for (var i = 0; i < modelData.modes.length; i++) {
            var m = modelData.modes[i];
            var res = m.width + "×" + m.height;
            var hz = m.refresh.toFixed(2).replace(/\.?0+$/, "");
            var label;
            if (!seenRes[res]) {
              seenRes[res] = true;
              label = res + "  " + hz + "Hz" + (m.preferred ? " ★" : "");
            } else {
              label = "    " + hz + "Hz" + (m.preferred ? " ★" : "");
            }
            lm.push({
                      "key": m.key,
                      "name": label
                    });
          }
          return lm;
        }
        currentKey: modelData.currentMode || ""
        onSelected: function (key) {
          if (key !== modelData.currentMode) {
            displayService?.applyOutput(modelData.name, {
                                          "mode": key
                                        }, true);
          }
        }
      }
    }

    // Scale — debounced so clicking the spin arrows several times results
    // in one compositor call instead of a cascade.
    RowLayout {
      Layout.fillWidth: true
      visible: modelData.enabled
      spacing: Style.marginS

      NText {
        text: root.tr("panel.scale")
        font.pixelSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
        Layout.preferredWidth: 60
      }

      NSpinBox {
        id: scaleSpin
        from: 50
        to: 300
        stepSize: 25
        suffix: "%"
        property bool ready: false
        Component.onCompleted: {
          value = Math.round(modelData.scale * 100);
          ready = true;
        }
        onValueChanged: if (ready) scaleDebounce.restart()
      }

      Timer {
        id: scaleDebounce
        interval: 400
        onTriggered: {
          var newScale = scaleSpin.value / 100.0;
          if (Math.abs(newScale - modelData.scale) > 0.001) {
            displayService?.applyOutput(modelData.name, {
                                          "scale": newScale
                                        }, true);
          }
        }
      }

      Item {
        Layout.fillWidth: true
      }
    }
  }
}
