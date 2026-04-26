# display-config

Change monitor resolution, scale, layout and power from the noctalia bar — and
save the result as a [kanshi] profile so it comes back automatically next time
you dock.

[kanshi]: https://sr.ht/~emersion/kanshi/

![display-config panel](https://github.com/Mic92/noctalia-plugins/releases/download/assets/display-config-screenshot.png)

## Quick start

1. Left-click the monitor icon in the bar to open the panel.
2. Tweak each output: turn it on/off, pick a resolution, adjust scale.
3. For two monitors, hit one of the **Arrange** buttons (extend right, external
   above, laptop only, …) instead of fiddling with coordinates.
4. Happy with it? Open the **Kanshi profiles** dropdown, type a name, pick
   **＋ Save current layout as '…'**. Done — that layout now applies itself
   whenever those exact monitors are connected.

Every change gets a 12-second "Keep / Revert" bar. If a bad mode blacks out
your only screen, just wait — it rolls back on its own.

## Kanshi profiles

This is where layouts live long-term. One searchable dropdown does it all:

- **Pick a profile** → switches to it. The active one shows a ✓.
- **Type a new name** → a **＋ Save current layout as '…'** row appears at the
  bottom; pick it to snapshot what's on screen right now.
- **⟳** next to the dropdown re-snapshots the selected profile in place; **🗑**
  deletes it. Both stay greyed for profiles from your main config so the
  plugin never edits a file it doesn't own.

Profiles you save here go into `~/.config/kanshi/noctalia.conf`. Add this line
to your main `~/.config/kanshi/config` once so kanshi loads them:

```
include ~/.config/kanshi/noctalia.conf
```

> **Tip:** saved profiles match external monitors by make/model/serial (not
> `DP-3`), so they survive reboots and dock port-shuffles. The laptop panel
> stays `eDP-1` because that name never changes.

Don't run kanshi? Turn the integration off in settings and use **Presets**
instead — same one-click switching, just without the auto-apply on hotplug.

## Bar widget

- **Left-click** — open the panel
- **Right-click** — quick menu: your kanshi profiles, two-monitor arrangements,
  open wdisplays, refresh
- The icon pulses briefly after a hotplug so you notice the dock connected.

## Three or more monitors?

The quick-arrange buttons only handle a pair. With 3+ outputs the panel shows
an **Open wdisplays** button instead — drag your monitors into place there,
close it, then save the result as a kanshi profile from the panel.

## Settings

Settings → Plugins → Display Config.

| Setting | Default | What it does |
| --- | --- | --- |
| Backend | `niri` | Compositor to talk to (others are read-only for now) |
| Kanshi integration | on | Show the profile section and talk to `kanshictl` |
| Kanshi config directory | *(auto)* | Override if your config lives somewhere unusual |
| Poll interval | 5 s | How often to re-check connected outputs |
| Icon colour | primary | Bar icon tint |

## Scripting

```bash
noctalia-shell ipc call plugin:display-config toggle              # open/close panel
noctalia-shell ipc call plugin:display-config kanshiSwitch docked # switch profile
noctalia-shell ipc call plugin:display-config kanshiSave desk     # save current layout
noctalia-shell ipc call plugin:display-config arrange extend-right
noctalia-shell ipc call plugin:display-config keep                # confirm pending change
```

Bind `kanshiSwitch` to a key for instant layout flips without opening the
panel.

## Requirements

- `niri` on `PATH`
- `kanshi` + `kanshictl` — optional, but you want them for the good stuff
- `wdisplays` — optional, for drag-and-drop arranging with 3+ monitors
