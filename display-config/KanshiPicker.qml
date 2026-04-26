import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Kanshi profile switcher/saver. A searchable dropdown lists profiles from
// both the user's config (read-only) and the plugin-managed file; the
// search field doubles as the "new profile name" input via a synthetic
// "＋ Save as…" row (GitHub-label-picker style).
ColumnLayout {
  id: root

  property var kanshiService: null
  property var tr: function (k, a) {
    return k;
  }

  spacing: Style.marginS

  // Track which dropdown entry is selected so the update/delete buttons
  // can act on it; defaults to the active profile so "open panel → update"
  // hits the one you're actually using.
  property string selectedProfile: kanshiService?.activeProfile ?? ""
  readonly property string saveKey: "__save_new__"

  readonly property bool selectedIsManaged: {
    var ps = kanshiService?.profiles ?? [];
    for (var i = 0; i < ps.length; i++)
      if (ps[i].name === selectedProfile)
        return ps[i].managed;
    return false;
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NText {
      text: root.tr("panel.kanshi-profiles")
      font.bold: true
      font.pixelSize: Style.fontSizeM
      color: Color.mOnSurface
      Layout.fillWidth: true
    }

    NText {
      visible: kanshiService && !kanshiService.available
      text: root.tr("panel.kanshi-unavailable")
      font.pixelSize: Style.fontSizeXS
      color: Color.mError
    }

    NIconButton {
      icon: "refresh"
      baseSize: 28
      tooltipText: root.tr("panel.kanshi-reload")
      onClicked: kanshiService?.reload()
    }
  }

  // NSearchableComboBox needs a ListModel (with .key/.name); the synthetic
  // save row's label is rewritten on every keystroke so it both shows the
  // target name and survives the combo's fuzzy filter.
  ListModel {
    id: profileModel
  }

  function rebuildModel() {
    profileModel.clear();
    var ps = kanshiService?.profiles ?? [];
    for (var i = 0; i < ps.length; i++) {
      profileModel.append({
                            "key": ps[i].name,
                            "name": ps[i].name,
                            "badges": [ps[i].name === kanshiService.activeProfile ? {
                                         "icon": "check"
                                       } : {}, ps[i].managed ? {
                                         "icon": "pencil"
                                       } : {}]
                          });
    }
    profileModel.append({
                          "key": root.saveKey,
                          "name": saveRowLabel(""),
                          "badges": [{
                              "icon": "device-floppy"
                            }]
                        });
  }

  function saveRowLabel(typed) {
    return typed !== "" ? root.tr("panel.kanshi-save-as", {
                                    "name": typed
                                  }) : root.tr("panel.kanshi-save-as-hint");
  }

  Connections {
    target: kanshiService
    function onProfilesChanged() {
      root.rebuildModel();
    }
    function onActiveProfileChanged() {
      // Panel may open before the first status poll lands; adopt the
      // active profile once known so ⟳/🗑 enable correctly.
      if (root.selectedProfile === "")
        root.selectedProfile = kanshiService.activeProfile;
      root.rebuildModel();
    }
  }
  Component.onCompleted: rebuildModel()

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NSearchableComboBox {
      id: combo
      Layout.fillWidth: true
      popupHeight: 220
      model: profileModel
      // Default would fire selected() on every ↑/↓ — i.e. switch profile
      // (reconfigure all monitors) per keystroke, and arrowing onto the
      // "＋ Save as" row would save. Require an explicit click/Enter.
      selectOnNavigation: false
      placeholder: root.tr("panel.kanshi-pick-placeholder")
      currentKey: root.selectedProfile
      // selected() fires from the delegate before the popup's
      // onVisibleChanged clears searchText, so the typed name is still
      // available here when the synthetic save row is picked.
      onSelected: function (key) {
        if (key === root.saveKey) {
          var name = searchText.trim();
          if (name === "")
            return; // hint row clicked with nothing typed — no-op
          kanshiService?.saveProfile(name);
          root.selectedProfile = name;
          return;
        }
        root.selectedProfile = key;
        kanshiService?.switchProfile(key);
      }
      onSearchTextChanged: {
        var idx = profileModel.count - 1;
        if (idx >= 0 && profileModel.get(idx).key === root.saveKey) {
          profileModel.setProperty(idx, "name", root.saveRowLabel(searchText.trim()));
          filterModel();
        }
      }
    }

    NIconButton {
      icon: "refresh-dot"
      baseSize: 32
      enabled: root.selectedIsManaged
      tooltipText: root.tr("panel.kanshi-update")
      onClicked: kanshiService?.saveProfile(root.selectedProfile)
    }

    NIconButton {
      icon: "trash"
      baseSize: 32
      enabled: root.selectedIsManaged
      tooltipText: root.tr("settings.delete-preset-tooltip")
      onClicked: {
        kanshiService?.deleteProfile(root.selectedProfile);
        root.selectedProfile = "";
      }
    }
  }
}
