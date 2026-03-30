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
    label: tr("settings.url-label")
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
    label: tr("settings.prometheus-url-label")
  }

  NTextInput {
    Layout.fillWidth: true
    text: cfg.prometheusUrl ?? defaults.prometheusUrl ?? ""
    placeholderText: "https://metrics.example.com"
    onEditingFinished: {
      cfg.prometheusUrl = text;
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

  NToggle {
    Layout.fillWidth: true
    label: tr("settings.show-count-label")
    checked: (cfg.showCount ?? defaults.showCount) !== false
    onToggled: function(checked) {
      cfg.showCount = checked;
      pluginApi?.saveSettings();
    }
  }

  NLabel {
    label: tr("settings.ignore-alerts-label")
  }

  NTextInput {
    Layout.fillWidth: true
    text: (cfg.ignoreAlerts ?? defaults.ignoreAlerts ?? []).join(", ")
    placeholderText: "Watchdog, DeadManSwitch"
    onEditingFinished: {
      cfg.ignoreAlerts = text.split(",").map(function(s) { return s.trim(); }).filter(function(s) { return s.length > 0; });
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
