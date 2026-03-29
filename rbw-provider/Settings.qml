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

  NLabel {
    label: tr("settings.clear-after-label")
  }

  NText {
    text: tr("settings.clear-after-description")
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
  }

  NSpinBox {
    from: 5
    to: 600
    suffix: "s"
    value: cfg.clearAfterSeconds ?? defaults.clearAfterSeconds
    onValueModified: {
      cfg.clearAfterSeconds = value;
      pluginApi?.saveSettings();
    }
  }
}
