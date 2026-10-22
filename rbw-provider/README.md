# rbw-provider

Bitwarden in the noctalia launcher, via [`rbw`](https://github.com/doy/rbw).
Type `/rbw github`, pick the entry, and the password lands in the focused input field.

![rbw-provider in the launcher](https://github.com/Mic92/noctalia-plugins/releases/download/assets/rbw-provider-screenshot.png)

## Usage

Open the launcher, type `/rbw ` followed by a query. Results match on entry
name, username, and folder. Select an entry to get a second-level menu:

| Action          | What happens                                         |
| --------------- | ---------------------------------------------------- |
| Type password   | Auto-pasted into the focused window                  |
| Type username   | Auto-pasted into the focused window                  |
| Type TOTP code  | Current `rbw code` auto-pasted                       |
| Copy password   | Clipboard only, no auto-type                         |

`/rbw !` re-reads the vault after `rbw add` or `rbw sync`.

**Auto-type** closes the launcher, puts the secret on the clipboard with
`wl-copy --sensitive`, then simulates `Ctrl+Shift+V`. This sidesteps niri bug
#2314 where `wtype`'s virtual-keyboard protocol corrupts the keymap on arbitrary
text — the modifier combo doesn't trip it.

The clipboard is cleared after `clearAfterSeconds` (default 45s). `--sensitive`
tells cliphist not to record the entry, and the secret is piped straight from
`rbw` into `wl-copy` — it never sits in a Luau string or shows up in
`argv`.

## Settings

| Setting             | Default | Purpose                             |
| ------------------- | ------- | ----------------------------------- |
| `clearAfterSeconds` | `45`    | Clipboard auto-clear timeout        |

## Keybinding

```bash
noctalia msg panel-toggle launcher "/rbw "
```

## Requirements

- [`rbw`](https://github.com/doy/rbw) — configured and `rbw login`'d
- `wl-copy` (wl-clipboard)
- `wtype`

If the vault is locked, the provider runs `rbw unlock` first (which may pop a
pinentry), then fetches the entry list.
