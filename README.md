# noctalia-plugins

A grab-bag of plugins for [noctalia] v5. Built for my own desktop but
packaged here so others can steal the useful bits.

[noctalia]: https://github.com/noctalia-dev/noctalia

| Plugin                               | What it does                                                            | Surface           |
| ------------------------------------ | ----------------------------------------------------------------------- | ----------------- |
| [`alertmanager`](./alertmanager)     | Prometheus Alertmanager: alert count in the bar, details in a panel     | bar + panel       |
| [`fprint-notify`](./fprint-notify)   | Overlay when fprintd wants a fingerprint (so sudo doesn't block silently) | overlay panel   |
| [`mail-count`](./mail-count)         | Unread mail count in the bar via any shell command (notmuch/mu/maildir) | bar               |
| [`rbw-provider`](./rbw-provider)     | Bitwarden search in the launcher via `rbw`: type/copy password, TOTP    | launcher          |
| [`ssh-askpass`](./ssh-askpass)       | `SSH_ASKPASS` backend with real Allow/Deny buttons for `ssh-add -c`     | dialog            |

Plugin ids are `mic92/<directory>`.

## Install

Add the checkout as a path source in your noctalia config and enable the
plugins you want:

```toml
[[plugins.source]]
name = "mic92"
kind = "path"
location = "~/src/noctalia-plugins"

[plugins]
enabled = ["mic92/alertmanager", "mic92/ssh-askpass"]
```

`ssh-askpass` needs its Go stub; see its README or
`nix build github:Mic92/noctalia-plugins#noctalia-ssh-askpass`.

## Development

Scripts are Luau, type-checked in strict mode against the plugin API
definitions for the noctalia release we target (`nix flake check` runs
`luau-lsp analyze`). Format with `stylua`.

## License

MIT
