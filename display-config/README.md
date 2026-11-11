# display-config

Change monitor mode, scale, rotation and layout on [niri] from the bar, and
save layouts as [kanshi] profiles so they come back when you dock.

[niri]: https://github.com/YaLTeR/niri
[kanshi]: https://sr.ht/~emersion/kanshi/

![display-config panel](https://github.com/Mic92/noctalia-plugins/releases/download/assets/display-config-screenshot.png)

## Panel

- **Per output:** on/off toggle, mode (★ = preferred), scale, rotation.
  The last lit output can't be switched off.
- **Arrange** (exactly two monitors): external right/left/above/below,
  external only, laptop only. Positions are computed from logical sizes so
  edges touch. With three or more, use wdisplays and save the result.
- **Kanshi profiles:** click to switch (✓ = active), right-click to
  overwrite with the current layout or delete. Type a name and hit
  **Save current** to snapshot what's on screen.

Every change starts a keep/revert countdown (12 s by default). If a bad
mode blanks your only screen, just wait and it rolls back.

## Bar widget

- Icon plus number of lit outputs; tooltip lists each output's mode.
- Shows the countdown while a change is unconfirmed.
- Flashes after a hotplug.
- **Left click:** panel. **Right click:** keep a pending change, otherwise
  refresh.

## Kanshi

Profiles saved here go into `~/.config/kanshi/noctalia.conf`, which the
plugin rewrites wholesale. Include it once from your main config:

```
include ~/.config/kanshi/noctalia.conf
```

External monitors are matched by make/model/serial, so profiles survive
dock port shuffles. Profiles from the main config are listed and switchable
but never edited.

## IPC

```sh
noctalia msg plugin mic92/display-config:service all toggle
noctalia msg plugin mic92/display-config:service all kanshiSwitch docked
noctalia msg plugin mic92/display-config:service all kanshiSave desk
noctalia msg plugin mic92/display-config:service all arrange extend-right
noctalia msg plugin mic92/display-config:service all set '{"name":"eDP-1","scale":1.5}'
noctalia msg plugin mic92/display-config:service all keep   # or: revert
```

## Requirements

- `niri`
- `kanshi` + `kanshictl` (optional)
- `wdisplays` (optional, for 3+ monitors)
