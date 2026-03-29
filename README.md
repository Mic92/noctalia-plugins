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

## License

MIT
