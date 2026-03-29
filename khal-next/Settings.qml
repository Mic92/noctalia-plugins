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

  NLabel { label: tr("settings.lookahead-label") }

  NSpinBox {
    from: 1
    to: 31
    value: cfg.lookaheadDays ?? defaults.lookaheadDays
    onValueModified: { cfg.lookaheadDays = value; pluginApi?.saveSettings(); }
  }

  NLabel { label: tr("settings.poll-interval-label") }

  NSpinBox {
    from: 30
    to: 3600
    stepSize: 30
    value: cfg.pollInterval ?? defaults.pollInterval
    onValueModified: { cfg.pollInterval = value; pluginApi?.saveSettings(); }
  }

  NLabel { label: tr("settings.imminent-label") }

  NText {
    text: tr("settings.imminent-description")
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
  }

  NSpinBox {
    from: 1
    to: 120
    value: cfg.imminentMinutes ?? defaults.imminentMinutes
    onValueModified: { cfg.imminentMinutes = value; pluginApi?.saveSettings(); }
  }

  NLabel { label: tr("settings.max-title-label") }

  NSpinBox {
    from: 8
    to: 80
    value: cfg.maxTitleWidth ?? defaults.maxTitleWidth
    onValueModified: { cfg.maxTitleWidth = value; pluginApi?.saveSettings(); }
  }

  NToggle {
    Layout.fillWidth: true
    label: tr("settings.hide-when-empty-label")
    checked: cfg.hideWhenEmpty ?? defaults.hideWhenEmpty
    onToggled: function(checked) { cfg.hideWhenEmpty = checked; pluginApi?.saveSettings(); }
  }

  NLabel { label: tr("settings.khal-args-label") }

  NText {
    text: tr("settings.khal-args-description")
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
  }

  NTextInput {
    Layout.fillWidth: true
    text: cfg.khalArgs ?? defaults.khalArgs
    placeholderText: "-a work -d holidays"
    onEditingFinished: { cfg.khalArgs = text; pluginApi?.saveSettings(); }
  }

  NLabel { label: tr("settings.icon-color-label") }

  NColorChoice {
    selectedColor: cfg.iconColor ?? defaults.iconColor
    onColorSelected: function(color) { cfg.iconColor = color; pluginApi?.saveSettings(); }
  }
}
