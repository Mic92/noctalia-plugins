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
| `showCount`       | `true`                    | Show the number next to the icon         |
| `prometheusUrl`   | empty                     | Rewrites the origin of alert links       |
| `ignoreAlerts`    | `[]`                      | Alert names that are never shown         |

`iconColor`, `hideWhenZero` and `showCount` are per-widget settings.

Silenced, inhibited, and muted alerts are left out of the count and shown in a
folded section of the panel. Right click the widget to refresh.

## IPC

```bash
noctalia msg plugin mic92/alertmanager:service all toggle   # open/close the panel
noctalia msg plugin mic92/alertmanager:service all refresh  # force a re-poll
```

Bind `toggle` to a key if you want the panel without clicking the bar.
