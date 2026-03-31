import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  property var alertService: pluginApi?.mainInstance?.alertService || null

  readonly property var activeAlerts: alertService?.activeAlerts ?? []
  readonly property var silencedAlerts: alertService?.silencedAlerts ?? []
  readonly property int alertCount: alertService?.alertCount ?? 0
  readonly property string fetchState: alertService?.fetchState ?? "idle"

  function tr(key, args) {
    return pluginApi?.tr(key, args) ?? key;
  }

  function severityRank(s) {
    if (s === "critical") return 0;
    if (s === "warning") return 1;
    return 2;
  }

  // Group alerts by alertname for sectioned display.
  // Each group carries its worst severity so the header can be colour-coded
  // and the list sorted critical-first.
  readonly property var groupedAlerts: {
    var alerts = root.activeAlerts;
    var groups = {};
    for (var i = 0; i < alerts.length; i++) {
      var name = alerts[i].labels.alertname || "Unknown";
      var sev = alerts[i].labels.severity || "warning";
      if (!groups[name]) {
        groups[name] = { name: name, alerts: [], severity: sev };
      }
      groups[name].alerts.push(alerts[i]);
      if (severityRank(sev) < severityRank(groups[name].severity)) {
        groups[name].severity = sev;
      }
    }
    var result = [];
    for (var key in groups) result.push(groups[key]);
    result.sort(function(a, b) {
      var r = severityRank(a.severity) - severityRank(b.severity);
      if (r !== 0) return r;
      if (b.alerts.length !== a.alerts.length) return b.alerts.length - a.alerts.length;
      return a.name.localeCompare(b.name);
    });
    return result;
  }

  readonly property var groupedSilenced: {
    var alerts = root.silencedAlerts;
    var groups = {};
    for (var i = 0; i < alerts.length; i++) {
      var name = alerts[i].labels.alertname || "Unknown";
      var sev = alerts[i].labels.severity || "warning";
      if (!groups[name]) {
        groups[name] = { name: name, alerts: [], severity: sev };
      }
      groups[name].alerts.push(alerts[i]);
      if (severityRank(sev) < severityRank(groups[name].severity)) {
        groups[name].severity = sev;
      }
    }
    var result = [];
    for (var key in groups) result.push(groups[key]);
    result.sort(function(a, b) {
      var r = severityRank(a.severity) - severityRank(b.severity);
      if (r !== 0) return r;
      if (b.alerts.length !== a.alerts.length) return b.alerts.length - a.alerts.length;
      return a.name.localeCompare(b.name);
    });
    return result;
  }

  function rewriteGeneratorUrl(url) {
    var cfg = pluginApi?.pluginSettings || {};
    var defaults = pluginApi?.manifest?.metadata?.defaultSettings || {};
    var promBase = cfg.prometheusUrl ?? defaults.prometheusUrl ?? "";
    if (promBase.length > 0) {
      return url.replace(/^https?:\/\/[^\/]+/, promBase);
    }
    return url;
  }

  implicitWidth: 420
  implicitHeight: contentColumn.implicitHeight + Style.marginL * 2

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
        icon: root.alertCount > 0 ? "alert-circle" : "circle-check"
        pointSize: Style.fontSizeXL
        color: root.alertCount > 0 ? Color.mError : Color.mPrimary
      }

      NText {
        text: {
          if (root.fetchState === "error")
            return root.tr("panel.header-error");
          if (root.alertCount === 0)
            return root.tr("panel.header-all-clear");
          return pluginApi?.trp("panel.header-active", root.alertCount) ?? (root.alertCount + " active alerts");
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
        onClicked: alertService?.fetchAlerts()
      }

      NIconButton {
        icon: "external-link"
        baseSize: 32
        tooltipText: root.tr("panel.open-alertmanager")
        onClicked: {
          var cfg = pluginApi?.pluginSettings || {};
          var defaults = pluginApi?.manifest?.metadata?.defaultSettings || {};
          var url = cfg.alertmanagerUrl ?? defaults.alertmanagerUrl;
          Qt.openUrlExternally(url);
        }
      }
    }

    NDivider {}

    // Alert list
    Flickable {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: Math.min(alertList.implicitHeight, 400)
      contentHeight: alertList.implicitHeight
      clip: true

      ColumnLayout {
        id: alertList
        width: parent.width
        spacing: Style.marginS

        // Error state
        NText {
          visible: root.fetchState === "error"
          text: alertService?.errorMessage ?? root.tr("panel.unknown-error")
          color: Color.mError
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
        }

        // Empty state
        NText {
          visible: root.fetchState === "success" && root.alertCount === 0
          text: root.tr("panel.no-active-alerts")
          color: Color.mOnSurfaceVariant
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          font.pixelSize: Style.fontSizeL
        }

        // Grouped alert sections
        Repeater {
          model: root.groupedAlerts

          delegate: ColumnLayout {
            id: groupDelegate

            // Auto-expand critical groups and the sole group so urgent
            // alerts are visible without an extra click.
            property bool expanded: modelData.severity === "critical"
              || root.groupedAlerts.length === 1

            Layout.fillWidth: true
            spacing: Style.marginXS

            // Section header (clickable to fold/unfold)
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: sectionHeaderRow.implicitHeight + Style.marginS * 2
              Layout.topMargin: index > 0 ? Style.marginS : 0
              radius: Style.radiusS
              color: sectionHeaderMouse.containsMouse ? Color.mSurfaceVariant : "transparent"

              RowLayout {
                id: sectionHeaderRow
                anchors.fill: parent
                anchors.leftMargin: Style.marginS
                anchors.rightMargin: Style.marginS
                anchors.topMargin: Style.marginS
                anchors.bottomMargin: Style.marginS
                spacing: Style.marginS

                NIcon {
                  icon: groupDelegate.expanded ? "chevron-down" : "chevron-right"
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurfaceVariant
                }

                // Severity dot — lets you triage without expanding.
                Rectangle {
                  implicitWidth: Style.fontSizeS * 0.7
                  implicitHeight: implicitWidth
                  radius: implicitWidth / 2
                  color: {
                    if (modelData.severity === "critical") return Color.mError;
                    if (modelData.severity === "warning") return Color.mTertiary;
                    return Color.mPrimary;
                  }
                }

                NText {
                  text: modelData.name
                  font.bold: true
                  font.pixelSize: Style.fontSizeM
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                }

                NText {
                  text: modelData.alerts.length.toString()
                  font.pixelSize: Style.fontSizeS
                  color: Color.mOnSurfaceVariant
                }
              }

              MouseArea {
                id: sectionHeaderMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: groupDelegate.expanded = !groupDelegate.expanded
              }
            }

            // Alerts in this section (only visible when expanded)
            Repeater {
              model: groupDelegate.expanded ? modelData.alerts : []

              delegate: Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: alertItemColumn.implicitHeight + Style.marginM * 2
                radius: Style.radiusM
                color: Color.mSurfaceVariant

                ColumnLayout {
                  id: alertItemColumn
                  anchors.fill: parent
                  anchors.margins: Style.marginM
                  spacing: Style.marginXS

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    NIcon {
                      icon: {
                        var severity = modelData.labels.severity || "warning";
                        if (severity === "critical") return "alert-octagon";
                        if (severity === "warning") return "alert-triangle";
                        return "info";
                      }
                      pointSize: Style.fontSizeM
                      color: {
                        var severity = modelData.labels.severity || "warning";
                        if (severity === "critical") return Color.mError;
                        if (severity === "warning") return Color.mTertiary;
                        return Color.mPrimary;
                      }
                    }

                    NText {
                      text: modelData.labels.host || modelData.labels.instance || ""
                      font.pixelSize: Style.fontSizeS
                      color: Color.mOnSurface
                      Layout.fillWidth: true
                    }
                  }

                  NText {
                    visible: text !== ""
                    text: {
                      if (modelData.annotations) {
                        return modelData.annotations.description
                          || modelData.annotations.summary
                          || "";
                      }
                      return "";
                    }
                    font.pixelSize: Style.fontSizeS
                    color: Color.mOnSurfaceVariant
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modelData.generatorURL) {
                      Qt.openUrlExternally(root.rewriteGeneratorUrl(modelData.generatorURL));
                    }
                  }
                }
              }
            }
          }
        }

        // Silenced/inhibited alerts section
        NDivider {
          Layout.fillWidth: true
          Layout.topMargin: Style.marginM
          visible: root.groupedSilenced.length > 0
        }

        NText {
          visible: root.groupedSilenced.length > 0
          text: root.tr("panel.silenced-header")
          font.pixelSize: Style.fontSizeS
          font.bold: true
          color: Color.mOnSurfaceVariant
          Layout.fillWidth: true
          Layout.topMargin: Style.marginS
          opacity: 0.6
        }

        Repeater {
          model: root.groupedSilenced

          delegate: ColumnLayout {
            id: silencedDelegate

            property bool expanded: false

            Layout.fillWidth: true
            spacing: Style.marginXS
            opacity: 0.5

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: silencedHeaderRow.implicitHeight + Style.marginS * 2
              Layout.topMargin: index > 0 ? Style.marginS : 0
              radius: Style.radiusS
              color: silencedHeaderMouse.containsMouse ? Color.mSurfaceVariant : "transparent"

              RowLayout {
                id: silencedHeaderRow
                anchors.fill: parent
                anchors.leftMargin: Style.marginS
                anchors.rightMargin: Style.marginS
                anchors.topMargin: Style.marginS
                anchors.bottomMargin: Style.marginS
                spacing: Style.marginS

                NIcon {
                  icon: silencedDelegate.expanded ? "chevron-down" : "chevron-right"
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: modelData.name + " (" + modelData.alerts.length + ")"
                  font.bold: true
                  font.pixelSize: Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                  Layout.fillWidth: true
                }
              }

              MouseArea {
                id: silencedHeaderMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: silencedDelegate.expanded = !silencedDelegate.expanded
              }
            }

            Repeater {
              model: silencedDelegate.expanded ? modelData.alerts : []

              delegate: Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: silencedItemCol.implicitHeight + Style.marginM * 2
                radius: Style.radiusM
                color: Qt.alpha(Color.mSurfaceVariant, 0.5)

                ColumnLayout {
                  id: silencedItemCol
                  anchors.fill: parent
                  anchors.margins: Style.marginM
                  spacing: Style.marginXS

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    NIcon {
                      icon: "volume-off"
                      pointSize: Style.fontSizeM
                      color: Color.mOnSurfaceVariant
                    }

                    NText {
                      text: modelData.labels.host || modelData.labels.instance || ""
                      font.pixelSize: Style.fontSizeS
                      color: Color.mOnSurfaceVariant
                      Layout.fillWidth: true
                    }
                  }

                  NText {
                    visible: text !== ""
                    text: {
                      if (modelData.annotations) {
                        return modelData.annotations.description
                          || modelData.annotations.summary
                          || "";
                      }
                      return "";
                    }
                    font.pixelSize: Style.fontSizeS
                    color: Color.mOnSurfaceVariant
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modelData.generatorURL) {
                      Qt.openUrlExternally(root.rewriteGeneratorUrl(modelData.generatorURL));
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
