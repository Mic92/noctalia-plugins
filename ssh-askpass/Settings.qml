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
    label: tr("settings.confirm-method-label")
  }

  NText {
    text: tr("settings.confirm-method-description")
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
  }

  NComboBox {
    Layout.fillWidth: true
    model: [
      { key: "click", name: tr("settings.method-click") },
      { key: "fingerprint", name: tr("settings.method-fingerprint") }
    ]
    currentKey: cfg.confirmMethod ?? defaults.confirmMethod
    onSelected: function (key) {
      cfg.confirmMethod = key;
      pluginApi?.saveSettings();
    }
  }

  NLabel {
    label: tr("settings.timeout-label")
  }

  NText {
    text: tr("settings.timeout-description")
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
  }

  NSpinBox {
    from: 5
    to: 300
    suffix: "s"
    value: cfg.confirmTimeoutSec ?? defaults.confirmTimeoutSec
    onValueModified: {
      cfg.confirmTimeoutSec = value;
      pluginApi?.saveSettings();
    }
  }
}
