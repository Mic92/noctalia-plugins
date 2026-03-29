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
    label: "Alertmanager Settings"
    Layout.fillWidth: true
  }

  NDivider {}

  NLabel {
    label: "Alertmanager URL"
  }

  NTextInput {
    Layout.fillWidth: true
    text: cfg.alertmanagerUrl ?? defaults.alertmanagerUrl
    placeholderText: "http://localhost:9093"
    onEditingFinished: {
      cfg.alertmanagerUrl = text;
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
    label: "Hide widget when no alerts"
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
