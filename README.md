# noctalia-plugins

A grab-bag of plugins for [noctalia-shell]. Built for my own desktop but
packaged here so others can steal the useful bits.

[noctalia-shell]: https://github.com/noctalia-dev/noctalia

| Plugin                             | What it does                                                        | Surface         |
| ---------------------------------- | ------------------------------------------------------------------- | --------------- |
| [`alertmanager`](./alertmanager)   | Prometheus Alertmanager: alert count in the bar, details in a panel | bar + panel     |
| [`display-config`](./display-config) | Change monitor resolution/scale/position/power from the bar       | bar + panel     |
| [`nostr-chat`](./nostr-chat)       | DM a Nostr peer (bot or human) in a slide-out panel. Images, history, the lot | panel |
| [`rbw-provider`](./rbw-provider)   | Bitwarden search in the launcher via `rbw` — copy password/TOTP     | launcher        |

## Install

noctalia-shell loads anything under `~/.config/noctalia/plugins/<id>/`. Pick
one:

**Clone the whole thing:**

```bash
git clone https://github.com/Mic92/noctalia-plugins ~/.config/noctalia/plugins
```

**Or cherry-pick via symlinks** (lets you keep your own plugins alongside):

```bash
git clone https://github.com/Mic92/noctalia-plugins ~/.config/noctalia/shared-plugins
ln -s ../shared-plugins/alertmanager ~/.config/noctalia/plugins/alertmanager
ln -s ../shared-plugins/rbw-provider ~/.config/noctalia/plugins/rbw-provider
# …
```

Then restart noctalia-shell and enable the plugin in Settings → Plugins.

> [!NOTE]
> `nostr-chat` also needs a Go daemon running — see its [README](./nostr-chat/README.md).

## Plugins

### alertmanager

Polls `/api/v2/alerts` and shows a count badge in the bar. Click for the full
list with labels, annotations and silence links. Turns red when something's
firing, stays out of the way when it isn't.

Configure `alertmanagerUrl` and `pollInterval` in the plugin's settings panel.

### display-config

A GUI for `niri msg output` (other compositors welcome, patches accepted). Lists
connected outputs, lets you toggle power, pick a mode, set scale, and drag
positions. Saves named presets — one click to switch between "laptop only",
"docked 3-screen", etc.

For more than two monitors it can shell out to `wdisplays` for the drag-and-drop
arrangement, then read back the result.

### nostr-chat

A chat panel backed by a small Go daemon that speaks NIP-17 DMs. Originally
built to talk to an [OpenCrow] LLM bot ("plot my CPU usage" → chart renders
inline) but it's just a DM client — point it at any pubkey.

Has its own [README](./nostr-chat/README.md) with NixOS module, keybinds, and
hacking notes.

[OpenCrow]: https://github.com/pinpox/opencrow

### rbw-provider

Type `rbw <query>` in the launcher, hit Enter on a match, password lands in your
clipboard (auto-cleared after `clearAfterSeconds`). `Ctrl+Enter` copies the TOTP
instead.

Needs [`rbw`](https://github.com/doy/rbw) installed and unlocked.

## License

MIT
