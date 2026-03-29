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
    label: tr("settings.count-command-label")
  }

  NText {
    text: tr("settings.count-command-description")
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
  }

  NTextInput {
    Layout.fillWidth: true
    text: cfg.countCommand ?? defaults.countCommand
    placeholderText: defaults.countCommand
    onEditingFinished: {
      cfg.countCommand = text;
      pluginApi?.saveSettings();
    }
  }

  NLabel {
    label: tr("settings.click-command-label")
  }

  NText {
    text: tr("settings.click-command-description")
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
  }

  NTextInput {
    Layout.fillWidth: true
    text: cfg.clickCommand ?? defaults.clickCommand
    placeholderText: defaults.clickCommand
    onEditingFinished: {
      cfg.clickCommand = text;
      pluginApi?.saveSettings();
    }
  }

  NLabel {
    label: tr("settings.poll-interval-label")
  }

  NSpinBox {
    from: 5
    to: 3600
    value: cfg.pollInterval ?? defaults.pollInterval
    onValueModified: {
      cfg.pollInterval = value;
      pluginApi?.saveSettings();
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: tr("settings.hide-when-zero-label")
    checked: cfg.hideWhenZero ?? defaults.hideWhenZero
    onToggled: function(checked) {
      cfg.hideWhenZero = checked;
      pluginApi?.saveSettings();
    }
  }

  NLabel {
    label: tr("settings.icon-color-label")
  }

  NColorChoice {
    selectedColor: cfg.iconColor ?? defaults.iconColor
    onColorSelected: function(color) {
      cfg.iconColor = color;
      pluginApi?.saveSettings();
    }
  }
}
