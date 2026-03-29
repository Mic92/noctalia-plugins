import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// UI-only settings. Daemon config (peer pubkey, relays, blossom, rbw
// entry) lives in the home-manager module — it needs to be known at
// systemd unit start, before the shell is even running.
ColumnLayout {
  id: root
  property var pluginApi: null
  spacing: Style.marginM

  function s(k, d) { return pluginApi?.pluginSettings?.[k] ?? d; }
  function set(k, v) { pluginApi?.setPluginSetting?.(k, v); }
  function tr(k) { return pluginApi?.tr(k) ?? k; }

  NText {
    Layout.fillWidth: true
    text: tr("settings.nixos-hint")
    wrapMode: Text.Wrap
    color: Color.mOnSurfaceVariant
  }

  NSpinBox {
    Layout.fillWidth: true
    label: tr("settings.history-limit-label")
    description: tr("settings.history-limit-description")
    from: 20; to: 1000; stepSize: 20
    value: s("maxHistory", 200)
    onValueModified: set("maxHistory", value)
  }
}
