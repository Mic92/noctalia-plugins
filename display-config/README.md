# display-config

Configure monitor resolution, scale, position and power from the noctalia bar.
A GUI for `niri msg output` — think of it as a compositor-native `arandr`.

![display-config panel](https://github.com/Mic92/noctalia-plugins/releases/download/assets/display-config-screenshot.png)

## What it does

**Bar widget** — monitor icon with a count badge. Turns highlighted for a few
seconds after a hotplug so you notice the dock connected. Right-click for a
quick menu:

- Your saved presets
- Quick two-monitor arrangements: extend left/right, external-only, internal-only
- "Open wdisplays" for the drag-and-drop layout editor
- Refresh

**Panel** (left-click) — per-output controls:

- Power on/off
- Mode (resolution + refresh rate)
- Scale
- Position
- Transform (rotation)

Changes are applied with a 15-second revert countdown, so a bad mode that kills
your only display undoes itself.

## Presets

Set up your layout once, save it with a name, switch with one click from the bar
menu. Handy for the classic "laptop only" ↔ "docked at desk" dance.

Presets are saved in the plugin's `settings.json` and applied via the
compositor's IPC, so they survive shell restarts and don't need a separate
daemon like kanshi.

## Backends

| Backend     | Status                                       |
| ----------- | -------------------------------------------- |
| `niri`      | Fully supported                              |
| `hyprland`  | Query only — apply is stubbed, patches welcome |
| `sway`      | Query only — apply is stubbed                |
| `wlr-randr` | Query only — apply is stubbed                |

Pick yours in Settings → Plugins → Display Config. If you're on one of the
stubbed backends, the panel still shows what's connected and the wdisplays
button works; you just can't apply changes from the plugin directly yet.

## Settings

| Setting        | Default   | Purpose                           |
| -------------- | --------- | --------------------------------- |
| `backend`      | `niri`    | Which compositor IPC to speak     |
| `pollInterval` | `5`       | Seconds between output re-queries |
| `iconColor`    | `primary` | Bar icon tint                     |
| `presets`      | `[]`      | Saved layouts (edited via the UI) |

## IPC

```bash
noctalia-shell ipc call plugin:display-config toggle           # open/close panel
noctalia-shell ipc call plugin:display-config refresh          # re-query outputs
noctalia-shell ipc call plugin:display-config preset "docked"  # apply named preset
noctalia-shell ipc call plugin:display-config arrange extend-right
```

The `preset` call makes it easy to bind layouts to keys or trigger them from a
udev rule / autorandr-style hook.

## Requirements

- `niri` (or your chosen backend's CLI) on `PATH`
- `wdisplays` (optional) — launched from the panel for 3+ monitor drag-and-drop
  arrangement, since pairwise quick-arrange stops making sense past two outputs
