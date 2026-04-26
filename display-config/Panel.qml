import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  property var displayService: pluginApi?.mainInstance?.displayService || null
  property var kanshiService: pluginApi?.mainInstance?.kanshiService || null

  readonly property var outputs: displayService?.outputs ?? []
  readonly property int outputCount: displayService?.outputCount ?? 0
  readonly property int enabledCount: displayService?.enabledCount ?? 0
  readonly property string fetchState: displayService?.fetchState ?? "idle"

  property var cfg: pluginApi?.pluginSettings || ({})

  function tr(key, args) {
    return pluginApi?.tr(key, args) ?? key;
  }

  implicitWidth: 560
  implicitHeight: contentColumn.implicitHeight + Style.marginL * 2

  // Revert-countdown state mirrored from the service so the confirm bar
  // lives inside the panel instead of only in a toast (which might land on
  // a monitor that just went dark).
  readonly property bool revertPending: displayService?.revertPending ?? false
  readonly property int revertSeconds: displayService?.revertSecondsLeft ?? 0

  ColumnLayout {
    id: contentColumn
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM

    // Header
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NIcon {
        icon: "device-desktop"
        pointSize: Style.fontSizeXL
        color: Color.mPrimary
      }

      NText {
        text: {
          if (root.fetchState === "error")
            return root.tr("panel.header-error");
          return pluginApi?.trp("panel.header-enabled", root.outputCount, {
                   enabled: root.enabledCount,
                   total: root.outputCount
                 }) ?? (root.enabledCount + "/" + root.outputCount + " outputs enabled");
        }
        font.pixelSize: Style.fontSizeL
        font.bold: true
        color: Color.mOnSurface
        Layout.fillWidth: true
      }

      NIconButton {
        icon: "refresh"
        baseSize: 32
        tooltipText: root.tr("panel.refresh")
        onClicked: displayService?.fetchOutputs()
      }

      NIconButton {
        icon: "external-link"
        baseSize: 32
        tooltipText: root.tr("panel.open-wdisplays")
        onClicked: {
          wdisplaysLauncher.startDetached();
          pluginApi?.closePanel(pluginApi.panelOpenScreen);
        }
      }
    }

    // Launch wdisplays for drag-and-drop arrangement — the proper tool for
    // 3+ monitor layouts that the quick-arrange buttons can't handle.
    // startDetached() is required: running=true ties the child to this
    // Process object, which is destroyed the moment closePanel() tears down
    // the panel delegate, killing wdisplays before its window appears.
    Process {
      id: wdisplaysLauncher
      command: ["sh", "-c", "command -v wdisplays >/dev/null && exec wdisplays || notify-send 'wdisplays not installed'"]
    }

    // Sticky confirm bar — shows whenever a change is pending revert.
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: confirmRow.implicitHeight + Style.marginM * 2
      visible: root.revertPending
      radius: Style.radiusM
      color: Color.mTertiary

      RowLayout {
        id: confirmRow
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        NIcon {
          icon: "alert-triangle"
          pointSize: Style.fontSizeL
          color: Color.mOnTertiary
        }

        NText {
          text: root.tr("panel.reverting-in", { seconds: root.revertSeconds })
          font.pixelSize: Style.fontSizeM
          font.bold: true
          color: Color.mOnTertiary
          Layout.fillWidth: true
        }

        NButton {
          text: root.tr("panel.revert")
          icon: "restore"
          outlined: true
          onClicked: displayService?.doRevert()
        }

        NButton {
          text: root.tr("panel.keep")
          icon: "check"
          onClicked: displayService?.confirmRevert()
        }
      }
    }

    NDivider {}

    // Output list
    Flickable {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: Math.min(outputList.implicitHeight, 500)
      contentHeight: outputList.implicitHeight
      clip: true

      ColumnLayout {
        id: outputList
        width: parent.width
        spacing: Style.marginM

        // Error state
        NText {
          visible: root.fetchState === "error"
          text: displayService?.errorMessage ?? root.tr("panel.unknown-error")
          color: Color.mError
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
        }

        // Per-output cards
        Repeater {
          model: root.outputs
          delegate: OutputCard {
            displayService: root.displayService
            tr: root.tr
          }
        }

        // With 3+ outputs the pairwise arrange math would leave the extras
        // overlapping — point at the tools that actually handle N monitors.
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.outputCount > 2
          spacing: Style.marginS

          NDivider {}

          NText {
            text: root.tr("panel.many-monitors-hint", { count: root.outputCount })
            font.pixelSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          NButton {
            Layout.fillWidth: true
            icon: "external-link"
            text: root.tr("panel.open-wdisplays")
            onClicked: {
              wdisplaysLauncher.startDetached();
              pluginApi?.closePanel(pluginApi.panelOpenScreen);
            }
          }
        }

        // Arrange — one-click layouts computed from logical sizes so nobody
        // has to reason about x/y coordinates. Gated to exactly two outputs
        // like KDE's Super+P OSD: the preset math only positions a pair, and
        // silently leaving a third monitor overlapping is worse than hiding
        // the buttons. For 3+ monitors, use saved presets instead.
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.outputCount === 2
          spacing: Style.marginS

          NDivider {}

          NText {
            text: root.tr("panel.arrange")
            font.bold: true
            font.pixelSize: Style.fontSizeM
            color: Color.mOnSurface
          }

          GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: Style.marginS
            columnSpacing: Style.marginS

            NButton {
              Layout.fillWidth: true
              icon: "arrow-bar-right"
              text: root.tr("panel.extend-right")
              onClicked: displayService?.applyArrangement("extend-right")
            }
            NButton {
              Layout.fillWidth: true
              icon: "arrow-bar-left"
              text: root.tr("panel.extend-left")
              onClicked: displayService?.applyArrangement("extend-left")
            }
            NButton {
              Layout.fillWidth: true
              icon: "arrow-bar-to-up"
              text: root.tr("panel.external-above")
              onClicked: displayService?.applyArrangement("stack-above")
            }
            NButton {
              Layout.fillWidth: true
              icon: "arrow-bar-to-down"
              text: root.tr("panel.external-below")
              onClicked: displayService?.applyArrangement("stack-below")
            }
            NButton {
              Layout.fillWidth: true
              icon: "device-desktop"
              text: root.tr("panel.external-only")
              onClicked: displayService?.applyArrangement("external-only")
            }
            NButton {
              Layout.fillWidth: true
              icon: "device-laptop"
              text: root.tr("panel.laptop-only")
              onClicked: displayService?.applyArrangement("internal-only")
            }
          }
        }

        // Kanshi profiles — the persistent, auto-applied counterpart to
        // the ad-hoc controls above.
        ColumnLayout {
          Layout.fillWidth: true
          visible: kanshiService?.enabled ?? false
          spacing: Style.marginS

          NDivider {}

          KanshiPicker {
            Layout.fillWidth: true
            kanshiService: root.kanshiService
            tr: root.tr
          }
        }

        // Presets
        ColumnLayout {
          Layout.fillWidth: true
          visible: (cfg.presets || []).length > 0
          spacing: Style.marginS

          NDivider {}

          NText {
            text: root.tr("panel.presets")
            font.bold: true
            font.pixelSize: Style.fontSizeM
            color: Color.mOnSurface
          }

          Flow {
            Layout.fillWidth: true
            spacing: Style.marginS

            Repeater {
              model: cfg.presets || []

              delegate: NButton {
                icon: "layout"
                text: modelData.name
                onClicked: displayService?.applyPreset(modelData)
              }
            }
          }
        }
      }
    }
  }
}
