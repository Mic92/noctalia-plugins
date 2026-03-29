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
  property var alertService: pluginApi?.mainInstance?.alertService || null

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  readonly property string iconColorKey: cfg.iconColor ?? defaults.iconColor
  readonly property bool hideWhenZero: cfg.hideWhenZero ?? defaults.hideWhenZero
  readonly property int alertCount: alertService?.alertCount ?? 0
  readonly property string fetchState: alertService?.fetchState ?? "idle"

  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"

  readonly property string currentIcon: {
    if (fetchState === "loading") return "loader";
    if (fetchState === "error") return "alert-triangle";
    if (alertCount > 0) return "alert-circle";
    return "circle-check";
  }

  readonly property color iconColor: {
    if (fetchState === "error") return Color.mError;
    if (alertCount > 0) return Color.mError;
    return Color.resolveColorKey(iconColorKey);
  }

  readonly property bool shouldHide: hideWhenZero && alertCount === 0 && fetchState !== "error"

  implicitWidth: shouldHide ? 0 : pill.width
  implicitHeight: shouldHide ? 0 : pill.height
  visible: !shouldHide

  BarPill {
    id: pill
    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: root.currentIcon
    text: root.alertCount.toString()
    forceOpen: root.alertCount > 0
    autoHide: true
    customTextIconColor: root.iconColor

    onClicked: {
      if (pluginApi) {
        pluginApi.openPanel(root.screen, root);
      }
    }

    onRightClicked: {
      PanelService.showContextMenu(contextMenu, root, screen);
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": pluginApi?.tr("menu.refresh") ?? "Refresh",
        "action": "refresh",
        "icon": "refresh"
      },
      {
        "label": pluginApi?.tr("menu.open-alertmanager") ?? "Open Alertmanager",
        "action": "open-url",
        "icon": "external-link"
      },
      {
        "label": pluginApi?.tr("menu.settings") ?? "Settings",
        "action": "settings",
        "icon": "settings"
      }
    ]

    onTriggered: function(action) {
      contextMenu.close();
      PanelService.closeContextMenu(screen);
      if (action === "refresh") {
        alertService?.fetchAlerts();
      } else if (action === "open-url") {
        var url = cfg.alertmanagerUrl ?? defaults.alertmanagerUrl;
        Qt.openUrlExternally(url);
      } else if (action === "settings") {
        BarService.openPluginSettings(root.screen, pluginApi.manifest);
      }
    }
  }
}
