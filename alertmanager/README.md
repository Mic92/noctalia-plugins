# alertmanager

Shows a count of active Prometheus Alertmanager alerts in the noctalia bar.
Click to open a panel with the full list, grouped by alertname, with labels,
annotations, and a link back to the alert source.

The bar widget stays quiet (`iconColor`) when nothing's firing and goes red when
there is — quick glance tells you if the world is on fire without having to open
a dashboard.

![alertmanager panel](https://github.com/Mic92/noctalia-plugins/releases/download/assets/alertmanager-screenshot.png)

## Settings

Available in Settings → Plugins → Alertmanager:

| Setting           | Default                   | Purpose                                  |
| ----------------- | ------------------------- | ---------------------------------------- |
| `alertmanagerUrl` | `http://localhost:9093`   | Base URL of your Alertmanager instance   |
| `pollInterval`    | `30`                      | Seconds between `/api/v2/alerts` fetches |
| `iconColor`       | `primary`                 | Bar icon color when everything is OK     |
| `hideWhenZero`    | `false`                   | Hide widget entirely when no alerts      |

Silenced, inhibited, and muted alerts are filtered out — the count only reflects
things that actually want attention.

## IPC

```bash
noctalia-shell ipc call plugin:alertmanager toggle   # open/close the panel
noctalia-shell ipc call plugin:alertmanager refresh  # force a re-poll
```

Bind `toggle` to a key if you want the panel without clicking the bar.

## Requirements

Just `wget` on `PATH` (used instead of Qt's network stack so the URL can be a
mesh/VPN name that only your resolver knows about).
