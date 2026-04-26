import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null
  property var displayService: pluginApi?.mainInstance?.displayService || null

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  spacing: Style.marginM

  function tr(key, args) {
    return pluginApi?.tr(key, args) ?? key;
  }

  NHeader {
    label: tr("settings.title")
    Layout.fillWidth: true
  }

  NDivider {}

  NLabel {
    label: tr("settings.backend-label")
  }

  NComboBox {
    Layout.fillWidth: true
    model: [
      { key: "niri", name: "niri" },
      { key: "hyprland", name: tr("settings.backend-stub", { name: "Hyprland" }) },
      { key: "sway", name: tr("settings.backend-stub", { name: "Sway" }) },
      { key: "wlr-randr", name: tr("settings.backend-stub", { name: "wlr-randr" }) }
    ]
    currentKey: cfg.backend ?? defaults.backend
    onSelected: function (key) {
      cfg.backend = key;
      pluginApi?.saveSettings();
      displayService?.fetchOutputs();
    }
  }

  NToggle {
    label: tr("settings.kanshi-enabled-label")
    description: tr("settings.kanshi-enabled-desc")
    checked: cfg.kanshiEnabled ?? defaults.kanshiEnabled
    onToggled: function (checked) {
      cfg.kanshiEnabled = checked;
      pluginApi?.saveSettings();
    }
  }

  NTextInput {
    Layout.fillWidth: true
    visible: cfg.kanshiEnabled ?? defaults.kanshiEnabled
    label: tr("settings.kanshi-config-dir-label")
    placeholderText: "~/.config/kanshi"
    text: cfg.kanshiConfigDir ?? ""
    onEditingFinished: {
      cfg.kanshiConfigDir = text;
      pluginApi?.saveSettings();
    }
  }

  NLabel {
    label: tr("settings.poll-interval-label")
  }

  NSpinBox {
    from: 1
    to: 60
    Component.onCompleted: value = cfg.pollInterval ?? defaults.pollInterval
    onValueChanged: {
      cfg.pollInterval = value;
      pluginApi?.saveSettings();
    }
  }

  NLabel {
    label: tr("settings.icon-color-label")
  }

  NColorChoice {
    currentKey: cfg.iconColor ?? defaults.iconColor
    onSelected: function (key) {
      cfg.iconColor = key;
      pluginApi?.saveSettings();
    }
  }

  NDivider {}

  NLabel {
    label: tr("settings.presets-label", { count: (cfg.presets || []).length })
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NTextInput {
      id: presetNameInput
      Layout.fillWidth: true
      placeholderText: tr("settings.preset-name-placeholder")
    }

    NIconButton {
      icon: "device-floppy"
      tooltipText: tr("settings.save-preset-tooltip")
      enabled: presetNameInput.text.trim() !== ""
      onClicked: {
        displayService?.saveCurrentAsPreset(presetNameInput.text.trim());
        presetNameInput.text = "";
      }
    }
  }

  Repeater {
    model: cfg.presets || []

    delegate: RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NText {
        text: modelData.name
        Layout.fillWidth: true
        color: Color.mOnSurface
      }

      NIconButton {
        icon: "player-play"
        tooltipText: root.tr("settings.apply-preset-tooltip")
        onClicked: displayService?.applyPreset(modelData)
      }

      NIconButton {
        icon: "trash"
        tooltipText: root.tr("settings.delete-preset-tooltip")
        onClicked: {
          var p = cfg.presets || [];
          p.splice(index, 1);
          cfg.presets = p;
          pluginApi?.saveSettings();
        }
      }
    }
  }
}
