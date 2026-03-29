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
  property var mailService: pluginApi?.mainInstance?.mailService || null

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  readonly property string iconColorKey: cfg.iconColor ?? defaults.iconColor
  readonly property bool hideWhenZero: cfg.hideWhenZero ?? defaults.hideWhenZero
  readonly property int unreadCount: mailService?.unreadCount ?? 0
  readonly property string fetchState: mailService?.fetchState ?? "idle"

  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"

  readonly property string currentIcon: {
    if (fetchState === "error") return "mail-exclamation";
    if (unreadCount > 0) return "mail";
    return "mail-opened";
  }

  readonly property color iconColor: {
    if (fetchState === "error") return Color.mError;
    return Color.resolveColorKey(iconColorKey);
  }

  readonly property bool shouldHide: hideWhenZero && unreadCount === 0 && fetchState !== "error"

  implicitWidth: shouldHide ? 0 : pill.width
  implicitHeight: shouldHide ? 0 : pill.height
  visible: !shouldHide

  BarPill {
    id: pill
    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: root.currentIcon
    text: root.unreadCount.toString()
    forceOpen: root.unreadCount > 0
    autoHide: true
    customTextIconColor: root.iconColor

    onClicked: root.launchMailClient()

    onRightClicked: {
      PanelService.showContextMenu(contextMenu, root, screen);
    }
  }

  function launchMailClient() {
    var cmd = cfg.clickCommand ?? defaults.clickCommand;
    if (cmd && cmd.trim() !== "") {
      Quickshell.execDetached(["sh", "-lc", cmd]);
      Logger.i("MailCount", "Launching:", cmd);
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": pluginApi?.tr("menu.open") || "Open mail",
        "action": "open",
        "icon": "mail"
      },
      {
        "label": pluginApi?.tr("menu.refresh") || "Refresh",
        "action": "refresh",
        "icon": "refresh"
      },
      {
        "label": pluginApi?.tr("menu.settings") || "Settings",
        "action": "settings",
        "icon": "settings"
      }
    ]

    onTriggered: function(action) {
      contextMenu.close();
      PanelService.closeContextMenu(screen);
      if (action === "open") {
        root.launchMailClient();
      } else if (action === "refresh") {
        mailService?.refresh();
      } else if (action === "settings") {
        BarService.openPluginSettings(root.screen, pluginApi.manifest);
      }
    }
  }
}
