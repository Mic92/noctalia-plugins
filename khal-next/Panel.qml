import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  property var calService: pluginApi?.mainInstance?.calService || null

  readonly property var events: calService?.events ?? []
  readonly property string fetchState: calService?.fetchState ?? "idle"

  function tr(key, args) {
    return pluginApi?.tr(key, args) ?? key;
  }

  property var now: new Date()

  // Bucket events by day for sectioned display. Only keep days that still
  // have future events (past entries from today drop off as time passes).
  readonly property var groupedEvents: {
    var out = [], byKey = {};
    var nowMs = now.getTime();
    for (var i = 0; i < events.length; i++) {
      var ev = events[i];
      if (ev.end.getTime() <= nowMs) continue;
      var key = Qt.formatDate(ev.start, "yyyy-MM-dd");
      if (!byKey[key]) {
        byKey[key] = { date: ev.start, events: [] };
        out.push(byKey[key]);
      }
      byKey[key].events.push(ev);
    }
    return out;
  }

  function dayLabel(d) {
    var today = new Date();
    var tomorrow = new Date(today.getTime() + 86400000);
    var key = Qt.formatDate(d, "yyyy-MM-dd");
    if (key === Qt.formatDate(today, "yyyy-MM-dd")) return tr("panel.today");
    if (key === Qt.formatDate(tomorrow, "yyyy-MM-dd")) return tr("panel.tomorrow");
    return Qt.formatDate(d, "dddd, MMM d");
  }

  implicitWidth: 420
  implicitHeight: Math.min(600, contentColumn.implicitHeight + Style.marginL * 2)

  ColumnLayout {
    id: contentColumn
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NIcon {
        icon: "calendar-event"
        pointSize: Style.fontSizeXL
        color: Color.mPrimary
      }

      NText {
        text: {
          if (fetchState === "error") return tr("panel.header-error");
          if (groupedEvents.length === 0) return tr("panel.header-empty");
          return tr("panel.header");
        }
        font.pixelSize: Style.fontSizeL
        font.bold: true
        color: Color.mOnSurface
        Layout.fillWidth: true
      }

      NIconButton {
        icon: "refresh"
        baseSize: 32
        tooltipText: tr("panel.refresh")
        onClicked: calService?.refresh()
      }
    }

    NDivider { Layout.fillWidth: true }

    NText {
      visible: fetchState === "error"
      text: calService?.errorMessage || ""
      font.pixelSize: Style.fontSizeS
      color: Color.mError
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
    }

    Flickable {
      id: scroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: Math.min(agendaColumn.implicitHeight, 480)
      contentHeight: agendaColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      ColumnLayout {
        id: agendaColumn
        width: scroll.width
        spacing: Style.marginM

        Repeater {
          model: root.groupedEvents

          delegate: ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NText {
              text: root.dayLabel(modelData.date)
              font.pixelSize: Style.fontSizeS
              font.bold: true
              color: Color.mOnSurfaceVariant
              Layout.fillWidth: true
            }

            Repeater {
              model: modelData.events

              delegate: Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: evRow.implicitHeight + Style.marginM * 2
                radius: Style.radiusM
                color: evMouse.containsMouse ? Color.mSurfaceVariant : "transparent"

                property bool hasLink: modelData.location &&
                                       /^https?:\/\//.test(modelData.location)

                RowLayout {
                  id: evRow
                  anchors.fill: parent
                  anchors.margins: Style.marginM
                  spacing: Style.marginM

                  // Time gutter. Fixed width keeps titles aligned; wide
                  // enough for "HH:mm–HH:mm" so nothing ellipsizes.
                  NText {
                    text: modelData.allDay
                          ? root.tr("panel.all-day")
                          : Qt.formatTime(modelData.start, "HH:mm") + "–" +
                            Qt.formatTime(modelData.end, "HH:mm")
                    font.pixelSize: Style.fontSizeS
                    font.family: Settings.data.ui.fontFixed
                    color: Color.mOnSurfaceVariant
                    Layout.preferredWidth: 92
                    Layout.alignment: Qt.AlignTop
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    NText {
                      text: modelData.title
                      font.pixelSize: Style.fontSizeM
                      color: Color.mOnSurface
                      Layout.fillWidth: true
                      elide: Text.ElideRight
                    }

                    NText {
                      visible: modelData.location !== ""
                      text: modelData.location
                      font.pixelSize: Style.fontSizeXS
                      color: hasLink ? Color.mPrimary : Color.mOnSurfaceVariant
                      Layout.fillWidth: true
                      elide: Text.ElideRight
                    }
                  }

                  NIcon {
                    visible: hasLink
                    icon: "external-link"
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurfaceVariant
                  }
                }

                MouseArea {
                  id: evMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: hasLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                  enabled: hasLink
                  onClicked: Quickshell.execDetached(["xdg-open", modelData.location])
                }
              }
            }
          }
        }

        NText {
          visible: root.groupedEvents.length === 0 && root.fetchState === "success"
          text: root.tr("panel.nothing-scheduled")
          font.pixelSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
