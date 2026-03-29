# rbw-provider

Bitwarden in the noctalia launcher, via [`rbw`](https://github.com/doy/rbw).
Type `>rbw github`, hit Enter, password lands in the focused input field.

## Usage

Open the launcher, type `>rbw ` followed by a query. Results match on entry
name, username, and folder. Select an entry to get a second-level menu:

| Action          | What happens                                         |
| --------------- | ---------------------------------------------------- |
| Type password   | Auto-pasted into the focused window                  |
| Type username   | Auto-pasted into the focused window                  |
| Type TOTP code  | Current `rbw code` auto-pasted                       |
| Copy password   | Clipboard only, no auto-type                         |

The default action (Enter on the entry itself) is "Type password".

**Auto-type** closes the launcher, puts the secret on the clipboard with
`wl-copy --sensitive`, then simulates `Ctrl+Shift+V`. This sidesteps niri bug
#2314 where `wtype`'s virtual-keyboard protocol corrupts the keymap on arbitrary
text — the modifier combo doesn't trip it.

The clipboard is cleared after `clearAfterSeconds` (default 45s). `--sensitive`
tells cliphist not to record the entry, and the secret is piped straight from
`rbw` into `wl-copy` — it never sits in a QML string buffer or shows up in
`argv`.

## Settings

| Setting             | Default | Purpose                             |
| ------------------- | ------- | ----------------------------------- |
| `clearAfterSeconds` | `45`    | Clipboard auto-clear timeout        |

## IPC

```bash
noctalia-shell ipc call plugin:rbw-provider toggle
```

Opens the launcher pre-filled with `>rbw ` — bind this to a key for one-shortcut
password access.

## Requirements

- [`rbw`](https://github.com/doy/rbw) — configured and `rbw login`'d
- `wl-copy` (wl-clipboard)
- `wtype`

If the vault is locked, the provider runs `rbw unlock` first (which may pop a
pinentry), then fetches the entry list.
