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

  NHeader {
    label: "Mail Count Settings"
    Layout.fillWidth: true
  }

  NDivider {}

  NLabel {
    label: "Count command"
  }

  NText {
    text: "Shell command that prints the number of unread messages to stdout."
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
    label: "Click command"
  }

  NText {
    text: "Command executed when the widget is clicked (e.g. your mail client). Leave empty to disable."
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
    label: "Poll interval (seconds)"
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
    label: "Hide widget when count is zero"
    checked: cfg.hideWhenZero ?? defaults.hideWhenZero
    onToggled: function(checked) {
      cfg.hideWhenZero = checked;
      pluginApi?.saveSettings();
    }
  }

  NLabel {
    label: "Icon color"
  }

  NColorChoice {
    selectedColor: cfg.iconColor ?? defaults.iconColor
    onColorSelected: function(color) {
      cfg.iconColor = color;
      pluginApi?.saveSettings();
    }
  }
}
