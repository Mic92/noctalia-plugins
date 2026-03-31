import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.Location
import qs.Widgets

DraggableDesktopWidget {
  id: root

  readonly property var now: Time.now
  // widgetScale controls grid size; text stays fixed
  readonly property real gs: widgetScale
  readonly property real pad: Style.marginM
  readonly property real headerHeight: 56
  readonly property real dayHeaderHeight: 44

  readonly property int hourStart: 7
  readonly property int hourEnd: 22
  readonly property int hourCount: hourEnd - hourStart
  readonly property real hourHeight: Math.round(44 * gs)
  readonly property real viewWidth: Math.round(900 * gs)
  readonly property real gutterWidth: 48
  readonly property real daySpacing: 1
  readonly property real gridWidth: viewWidth - gutterWidth - pad * 2
  readonly property real dayColumnWidth: Math.round((gridWidth - 6 * daySpacing) / 7)

  property int weekOffset: 0

  function getWeekStart(date, offset) {
    const d = new Date(date);
    const day = d.getDay();
    const diff = day === 0 ? 6 : day - 1;
    d.setDate(d.getDate() - diff + offset * 7);
    d.setHours(0, 0, 0, 0);
    return d;
  }

  readonly property var weekStart: getWeekStart(now, weekOffset)

  readonly property var weekDays: {
    const days = [];
    for (let i = 0; i < 7; i++) { const d = new Date(weekStart); d.setDate(d.getDate() + i); days.push(d); }
    return days;
  }

  function getISOWeekNumber(date) {
    const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
    const dayNum = d.getUTCDay() || 7;
    d.setUTCDate(d.getUTCDate() + 4 - dayNum);
    const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
    return Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
  }

  readonly property string monthLabel: {
    const first = weekDays[0], last = weekDays[6];
    const f1 = I18n.locale.toString(first, "MMMM yyyy"), f2 = I18n.locale.toString(last, "MMMM yyyy");
    if (f1 === f2) return f1;
    return I18n.locale.toString(first, "MMMM") + " / " + f2;
  }

  readonly property string weekLabel: "Week " + getISOWeekNumber(weekStart)

  readonly property string offsetLabel: {
    if (weekOffset === 0) return "";
    const abs = Math.abs(weekOffset);
    const unit = abs === 1 ? "week" : "weeks";
    return weekOffset > 0 ? abs + " " + unit + " from now" : abs + " " + unit + " ago";
  }

  function isToday(date) { return date.toDateString() === now.toDateString(); }

  // All-day: both start and end fall on local midnight (handles DST)
  function isAllDayEvent(event) {
    const s = new Date(event.start * 1000);
    const e = new Date(event.end * 1000);
    return event.end > event.start
      && s.getHours() === 0 && s.getMinutes() === 0
      && e.getHours() === 0 && e.getMinutes() === 0;
  }

  function formatTime(timestamp) {
    const date = new Date(timestamp * 1000);
    const timeFormat = Settings.data.location.use12hourFormat ? "hh:mm AP" : "HH:mm";
    return I18n.locale.toString(date, timeFormat);
  }

  function tooltipText(ev) {
    let text = ev.summary || "Untitled";
    if (isAllDayEvent(ev)) {
      text += "\nAll day";
    } else {
      text += "\n" + formatTime(ev.start) + " – " + formatTime(ev.end);
    }
    if ((ev.location || "").length > 0)
      text += "\n📍 " + ev.location;
    if ((ev.description || "").length > 0)
      text += "\n" + ev.description;
    return text;
  }

  readonly property var eventsByDay: {
    const events = CalendarService.events;
    const result = [[], [], [], [], [], [], []];
    if (!events || events.length === 0) return result;
    const wsTs = Math.floor(weekStart.getTime() / 1000);
    const weTs = wsTs + 7 * 86400;
    for (const ev of events) {
      if (ev.end <= wsTs || ev.start >= weTs) continue;
      const clampStart = Math.max(ev.start, wsTs);
      const clampEnd = Math.min(ev.end, weTs);
      const startDay = Math.floor((clampStart - wsTs) / 86400);
      const endDay = Math.min(6, Math.floor((clampEnd - 1 - wsTs) / 86400));
      for (let d = Math.max(0, startDay); d <= endDay; d++) {
        const dayStart = wsTs + d * 86400;
        const dayEnd = dayStart + 86400;
        result[d].push({
          summary: ev.summary, location: ev.location, description: ev.description,
          start: ev.start, end: ev.end, uid: ev.uid, calendar: ev.calendar,
          displayStart: Math.max(ev.start, dayStart),
          displayEnd: Math.min(ev.end, dayEnd)
        });
      }
    }
    for (let i = 0; i < 7; i++) result[i].sort((a, b) => a.displayStart - b.displayStart);
    return result;
  }

  readonly property var allDayByDay: {
    const result = [[], [], [], [], [], [], []];
    const seen = [{}, {}, {}, {}, {}, {}, {}];
    for (let i = 0; i < 7; i++)
      for (const ev of eventsByDay[i])
        if (isAllDayEvent(ev) && !seen[i][ev.uid]) {
          seen[i][ev.uid] = true;
          result[i].push(ev);
        }
    return result;
  }

  readonly property int maxAllDay: {
    let m = 0;
    for (let i = 0; i < 7; i++) m = Math.max(m, allDayByDay[i].length);
    return m;
  }

  readonly property var layoutByDay: {
    const result = [];
    for (let d = 0; d < 7; d++) {
      const evs = eventsByDay[d].filter(e => !isAllDayEvent(e));
      if (evs.length === 0) { result.push([]); continue; }
      const groups = [];
      let group = [evs[0]], groupEnd = evs[0].displayEnd;
      for (let i = 1; i < evs.length; i++) {
        if (evs[i].displayStart < groupEnd) {
          group.push(evs[i]);
          groupEnd = Math.max(groupEnd, evs[i].displayEnd);
        } else {
          groups.push(group);
          group = [evs[i]];
          groupEnd = evs[i].displayEnd;
        }
      }
      groups.push(group);
      const dayLayout = [];
      for (const g of groups) {
        const cols = [];
        const assignments = [];
        for (const ev of g) {
          let placed = false;
          for (let c = 0; c < cols.length; c++) {
            if (ev.displayStart >= cols[c]) {
              cols[c] = ev.displayEnd;
              assignments.push({ event: ev, col: c });
              placed = true;
              break;
            }
          }
          if (!placed) {
            assignments.push({ event: ev, col: cols.length });
            cols.push(ev.displayEnd);
          }
        }
        const total = cols.length;
        for (const a of assignments)
          dayLayout.push({ event: a.event, col: a.col, totalCols: total });
      }
      result.push(dayLayout);
    }
    return result;
  }

  readonly property real allDayRowHeight: 20
  readonly property real allDaySectionHeight: Math.max(1, maxAllDay) * allDayRowHeight + Style.marginXS
  readonly property real gridTopPad: Math.ceil(Style.fontSizeXXS * 0.7)

  function eventY(ev) {
    const s = new Date((ev.displayStart || ev.start) * 1000);
    return Math.max(0, (s.getHours() + s.getMinutes() / 60 - hourStart) * hourHeight);
  }

  function eventH(ev) {
    const ds = ev.displayStart || ev.start;
    const de = ev.displayEnd || ev.end;
    return Math.max(18, ((de - ds) / 3600) * hourHeight);
  }

  implicitWidth: viewWidth
  implicitHeight: headerHeight + dayHeaderHeight + allDaySectionHeight + gridTopPad + hourCount * hourHeight + pad * 2
  width: implicitWidth
  height: implicitHeight

  // ── Header ─────────────────────────────────────────────────────────

  RowLayout {
    x: root.pad; y: root.pad
    width: root.viewWidth - root.pad * 2
    height: root.headerHeight
    spacing: Style.marginS
    z: 2

    NIcon { icon: "calendar-event"; pointSize: Style.fontSizeXL; color: Color.mPrimary }

    ColumnLayout {
      spacing: 2; Layout.fillWidth: true
      RowLayout {
        spacing: Style.marginS
        NText { text: root.monthLabel; pointSize: Style.fontSizeL; font.weight: Font.Bold; color: Color.mOnSurface }
        NText { text: "·"; pointSize: Style.fontSizeL; color: Color.mOnSurfaceVariant }
        NText { text: root.weekLabel; pointSize: Style.fontSizeL; font.weight: Font.Medium; color: Color.mPrimary }
      }
      NText {
        opacity: root.weekOffset !== 0 ? 1 : 0
        text: root.weekOffset !== 0 ? root.offsetLabel : " "
        pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant; font.italic: true
      }
    }

    Rectangle {
      Layout.preferredWidth: 28; Layout.preferredHeight: 28
      radius: Style.radiusM
      color: prevMa.containsMouse ? Qt.alpha(Color.mPrimary, 0.15) : "transparent"
      NIcon { anchors.centerIn: parent; icon: "chevron-left"; pointSize: Style.fontSizeM; color: Color.mOnSurface }
      MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.weekOffset -= 1 }
    }

    Rectangle {
      Layout.preferredWidth: 28; Layout.preferredHeight: 28
      radius: Style.radiusM
      opacity: root.weekOffset !== 0 ? 1 : 0; enabled: root.weekOffset !== 0
      color: todayMa.containsMouse ? Qt.alpha(Color.mPrimary, 0.15) : "transparent"
      NText { anchors.centerIn: parent; text: "⦿"; pointSize: Style.fontSizeM; color: Color.mPrimary }
      MouseArea { id: todayMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.weekOffset = 0 }
      Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    Rectangle {
      Layout.preferredWidth: 28; Layout.preferredHeight: 28
      radius: Style.radiusM
      color: nextMa.containsMouse ? Qt.alpha(Color.mPrimary, 0.15) : "transparent"
      NIcon { anchors.centerIn: parent; icon: "chevron-right"; pointSize: Style.fontSizeM; color: Color.mOnSurface }
      MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.weekOffset += 1 }
    }
  }

  // ── Day column headers ─────────────────────────────────────────────

  Row {
    x: root.pad + root.gutterWidth
    y: root.pad + root.headerHeight
    spacing: root.daySpacing; z: 2

    Repeater {
      model: root.weekDays
      Rectangle {
        width: root.dayColumnWidth; height: root.dayHeaderHeight
        radius: Style.radiusS
        color: root.isToday(modelData) ? Qt.alpha(Color.mPrimary, 0.10) : "transparent"
        ColumnLayout {
          anchors.centerIn: parent; spacing: 1
          NText {
            Layout.alignment: Qt.AlignHCenter
            text: I18n.locale.toString(modelData, "ddd").toUpperCase()
            pointSize: Style.fontSizeXXS; font.weight: Font.DemiBold
            color: root.isToday(modelData) ? Color.mPrimary : Color.mOnSurfaceVariant
          }
          NText {
            Layout.alignment: Qt.AlignHCenter; text: modelData.getDate()
            pointSize: Style.fontSizeM
            font.weight: root.isToday(modelData) ? Font.Bold : Font.Medium
            color: root.isToday(modelData) ? Color.mPrimary : Color.mOnSurface
          }
        }
      }
    }
  }

  // ── All-day events ─────────────────────────────────────────────────

  Item {
    x: root.pad + root.gutterWidth
    y: root.pad + root.headerHeight + root.dayHeaderHeight
    width: root.gridWidth; height: root.allDaySectionHeight
    z: 2

    Row {
      spacing: root.daySpacing
      Repeater {
        model: 7
        Item {
          width: root.dayColumnWidth; height: root.allDaySectionHeight
          Repeater {
            model: root.allDayByDay[index]
            Rectangle {
              x: 0; y: model.index * root.allDayRowHeight
              width: root.dayColumnWidth; height: root.allDayRowHeight - 1
              radius: Style.radiusS; color: Qt.alpha(Color.mSecondary, 0.25)
              NText {
                anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 2
                text: modelData.summary || "Untitled"; pointSize: Style.fontSizeXXS
                font.weight: Font.Medium; color: Color.mOnSurface; elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter; maximumLineCount: 1
              }
              MouseArea {
                anchors.fill: parent; hoverEnabled: true
                ToolTip.visible: containsMouse; ToolTip.delay: 400
                ToolTip.text: root.tooltipText(modelData)
              }
            }
          }
        }
      }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.alpha(Color.mOutline, 0.2) }
  }

  // ── Time grid ──────────────────────────────────────────────────────

  Flickable {
    id: gridFlick
    x: root.pad
    y: root.pad + root.headerHeight + root.dayHeaderHeight + root.allDaySectionHeight
    width: root.viewWidth - root.pad * 2
    height: root.gridTopPad + root.hourCount * root.hourHeight
    contentHeight: root.gridTopPad + root.hourCount * root.hourHeight
    clip: true; boundsBehavior: Flickable.StopAtBounds; z: 1

    Item {
      y: root.gridTopPad
      width: gridFlick.width
      height: root.hourCount * root.hourHeight

      Repeater {
        model: root.hourCount
        Item {
          y: index * root.hourHeight; width: gridFlick.width; height: root.hourHeight
          NText {
            x: 0; width: root.gutterWidth - 6
            y: -Math.round(Style.fontSizeXXS * 0.7)
            horizontalAlignment: Text.AlignRight
            text: { const h = root.hourStart + index; return (h < 10 ? "0" : "") + h + ":00"; }
            pointSize: Style.fontSizeXXS; color: Color.mOnSurfaceVariant
          }
          Rectangle { x: root.gutterWidth; width: root.gridWidth; height: 1; color: Qt.alpha(Color.mOutline, 0.12) }
        }
      }

      Rectangle {
        visible: root.weekOffset === 0; x: root.gutterWidth
        y: (root.now.getHours() + root.now.getMinutes() / 60 - root.hourStart) * root.hourHeight
        width: root.gridWidth; height: 2; color: Color.mError; z: 10
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: Color.mError }
      }

      Repeater {
        model: 7
        Item {
          id: dayCol
          x: root.gutterWidth + index * (root.dayColumnWidth + root.daySpacing)
          width: root.dayColumnWidth; height: root.hourCount * root.hourHeight
          required property int index

          Rectangle {
            visible: root.isToday(root.weekDays[dayCol.index])
            anchors.fill: parent; color: Qt.alpha(Color.mPrimary, 0.03)
          }
          Rectangle {
            visible: dayCol.index > 0
            x: -root.daySpacing; width: 1; height: parent.height; color: Qt.alpha(Color.mOutline, 0.08)
          }

          Repeater {
            model: root.layoutByDay[dayCol.index]

            Rectangle {
              readonly property var ev: modelData.event
              readonly property real h: root.eventH(ev)
              readonly property real colW: (root.dayColumnWidth - 4) / modelData.totalCols

              x: 2 + modelData.col * colW
              y: root.eventY(ev)
              width: colW - 1
              height: h
              radius: Style.radiusS
              color: Qt.alpha(Color.mPrimary, 0.18)
              border.width: 1; border.color: Qt.alpha(Color.mPrimary, 0.35)
              clip: true


              ColumnLayout {
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.leftMargin: 6; anchors.rightMargin: 3; anchors.topMargin: 2
                spacing: 0

                NText {
                  Layout.fillWidth: true; text: ev.summary || "Untitled"
                  pointSize: Style.fontSizeXXS; font.weight: Font.DemiBold; color: Color.mOnSurface
                  elide: Text.ElideRight; wrapMode: Text.Wrap
                  maximumLineCount: h > root.hourHeight * 1.5 ? 3 : h > root.hourHeight * 0.6 ? 2 : 1
                }
                NText {
                  Layout.fillWidth: true; visible: h > root.hourHeight * 0.35
                  text: root.formatTime(ev.displayStart || ev.start) + " – " + root.formatTime(ev.displayEnd || ev.end)
                  pointSize: Math.round(Style.fontSizeXXS * 0.85); color: Color.mOnSurfaceVariant
                  elide: Text.ElideRight; maximumLineCount: 1
                }
                NText {
                  Layout.fillWidth: true
                  visible: h > root.hourHeight * 1.2 && (ev.location || "").length > 0
                  text: "📍 " + ev.location
                  pointSize: Math.round(Style.fontSizeXXS * 0.85); color: Color.mOnSurfaceVariant
                  elide: Text.ElideRight; maximumLineCount: 1
                }
              }

              MouseArea {
                anchors.fill: parent; hoverEnabled: true
                ToolTip.visible: containsMouse; ToolTip.delay: 400
                ToolTip.text: root.tooltipText(ev)
              }
            }
          }
        }
      }
    }
  }

  NText {
    visible: !CalendarService.available; anchors.centerIn: parent; z: 2
    text: "Calendar not available"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant
  }
}
