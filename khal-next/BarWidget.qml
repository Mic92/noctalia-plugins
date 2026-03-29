import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  property var calService: pluginApi?.mainInstance?.calService || null

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  readonly property string iconColorKey: cfg.iconColor ?? defaults.iconColor
  readonly property bool hideWhenEmpty: cfg.hideWhenEmpty ?? defaults.hideWhenEmpty
  readonly property int imminentMinutes: cfg.imminentMinutes ?? defaults.imminentMinutes

  readonly property var nextEvent: calService?.nextEvent || null
  readonly property string fetchState: calService?.fetchState ?? "idle"

  // Ticking wall clock so the countdown text re-evaluates between polls.
  property var now: new Date()
  Timer {
    running: root.visible
    repeat: true
    interval: 30000
    onTriggered: root.now = new Date()
  }

  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"

  // Minutes until start (negative = already started).
  readonly property int minutesUntil: {
    if (!nextEvent || nextEvent.allDay) return 0;
    return Math.round((nextEvent.start.getTime() - now.getTime()) / 60000);
  }

  readonly property bool inProgress: nextEvent && !nextEvent.allDay && minutesUntil <= 0
  readonly property bool imminent: nextEvent && !nextEvent.allDay &&
                                   minutesUntil > 0 && minutesUntil <= imminentMinutes

  // User-pinned reveal. Click toggles this; the pill stays expanded until
  // clicked again or the current nextEvent changes (so you don't pin
  // yesterday's meeting forever).
  property bool pinned: false
  property var pinnedEvent: null

  onNextEventChanged: {
    if (pinned && pinnedEvent !== nextEvent) pinned = false;
  }

  function fmtCountdown(mins) {
    if (mins < 60) return mins + "m";
    var h = Math.floor(mins / 60);
    if (h < 24) {
      var m = mins % 60;
      return m > 0 ? (h + "h" + m) : (h + "h");
    }
    return Math.floor(h / 24) + "d";
  }

  // Pill text stays compact (just the countdown) so expanding doesn't
  // shove the rest of the bar around. Title lives in the tooltip.
  readonly property string pillText: {
    if (!nextEvent) return "";
    if (nextEvent.allDay) return "today";
    if (inProgress) return "now";
    return fmtCountdown(minutesUntil);
  }

  readonly property string tooltip: {
    if (!nextEvent) return "";
    var t = nextEvent.title;
    if (nextEvent.allDay) return t;
    var when = Qt.formatTime(nextEvent.start, "HH:mm") + "–" +
               Qt.formatTime(nextEvent.end, "HH:mm");
    return when + "  " + t;
  }

  readonly property string currentIcon: {
    if (fetchState === "error") return "calendar-exclamation";
    if (inProgress) return "player-play";
    return "calendar-event";
  }

  readonly property color iconColor: {
    if (fetchState === "error") return Color.mError;
    if (inProgress) return Color.mTertiary;
    if (imminent) return Color.mError;
    return Color.resolveColorKey(iconColorKey);
  }

  readonly property bool shouldHide: hideWhenEmpty && !nextEvent && fetchState !== "error"

  implicitWidth: shouldHide ? 0 : pill.width
  implicitHeight: shouldHide ? 0 : pill.height
  visible: !shouldHide

  BarPill {
    id: pill
    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: root.currentIcon
    text: root.pillText
    tooltipText: root.tooltip
    // Collapsed by default; hover reveals, click pins. Imminent / in-progress
    // still force it open so you can't miss those.
    autoHide: true
    forceOpen: root.pinned || root.imminent || root.inProgress
    customTextIconColor: root.iconColor

    onClicked: {
      root.pinned = !root.pinned;
      if (root.pinned) root.pinnedEvent = root.nextEvent;
    }

    // Middle-click: agenda panel. Join moved to context menu / IPC only,
    // since accidental middle-clicks into a meeting are worse than an
    // extra right-click.
    onMiddleClicked: {
      if (pluginApi) pluginApi.openPanel(root.screen, root);
    }

    onRightClicked: PanelService.showContextMenu(contextMenu, root, screen)
  }

  function openLocation() {
    var loc = nextEvent && nextEvent.location;
    if (loc && loc.trim() !== "")
      Quickshell.execDetached(["xdg-open", loc]);
  }

  NPopupContextMenu {
    id: contextMenu

    model: {
      var m = [];
      if (root.nextEvent && root.nextEvent.location)
        m.push({ label: pluginApi?.tr("menu.join") ?? "Join", action: "join", icon: "external-link" });
      m.push({ label: pluginApi?.tr("menu.agenda") ?? "Agenda", action: "agenda", icon: "calendar" });
      m.push({ label: pluginApi?.tr("menu.refresh") ?? "Refresh", action: "refresh", icon: "refresh" });
      m.push({ label: pluginApi?.tr("menu.settings") ?? "Settings", action: "settings", icon: "settings" });
      return m;
    }

    onTriggered: function(action) {
      contextMenu.close();
      PanelService.closeContextMenu(screen);
      if (action === "join") root.openLocation();
      else if (action === "agenda") pluginApi?.openPanel(root.screen, root);
      else if (action === "refresh") calService?.refresh();
      else if (action === "settings") BarService.openPluginSettings(root.screen, pluginApi.manifest);
    }
  }
}
