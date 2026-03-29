import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  spacing: Style.marginM

  function tr(key) {
    return pluginApi?.tr(key) ?? key;
  }

  NHeader {
    label: tr("settings.title")
    Layout.fillWidth: true
  }

  NDivider {}

  NToggle {
    Layout.fillWidth: true
    label: tr("settings.show-success-label")
    description: tr("settings.show-success-description")
    checked: cfg.showSuccessToast ?? defaults.showSuccessToast
    onToggled: function (checked) {
      cfg.showSuccessToast = checked;
      pluginApi?.saveSettings();
    }
  }

  NLabel {
    label: tr("settings.stale-timeout-label")
  }

  NText {
    text: tr("settings.stale-timeout-description")
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
  }

  NSpinBox {
    from: 5
    to: 300
    suffix: "s"
    value: cfg.staleTimeoutSec ?? defaults.staleTimeoutSec
    onValueModified: {
      cfg.staleTimeoutSec = value;
      pluginApi?.saveSettings();
    }
  }
}
