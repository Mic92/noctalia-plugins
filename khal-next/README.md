# khal-next

Bar widget showing the next upcoming [khal] event with a live countdown, plus
a click-through agenda panel.

[khal]: https://github.com/pimutils/khal

![screenshot placeholder]()

## What it does

- **Bar pill**: `23m · team sync` — countdown, then `now · team sync` once
  started. Turns red within a configurable "imminent" window (default 15 min).
  Collapses to just an icon when the next event is further off.
- **Panel** (click): agenda grouped by day, with clickable meeting URLs.
- **Middle-click** / `join` IPC: `xdg-open` the next event's location — for
  Google Meet / Jitsi / Zoom URLs that drops you straight into the meeting.

All-day events are shown in the panel but only surface in the pill if nothing
timed is coming up.

## Requirements

- `khal` configured and populated (typically via `vdirsyncer`)
- `jq` (to flatten khal's per-day JSON output)
- khal's `longdateformat` / `datetimeformat` left at the default
  `YYYY-MM-DD [HH:MM]` — the plugin parses that literally.

## IPC

```sh
noctalia-shell ipc call plugin:khal-next toggle   # toggle agenda panel
noctalia-shell ipc call plugin:khal-next refresh  # re-run khal
noctalia-shell ipc call plugin:khal-next join     # xdg-open next location
```

Bind `join` in your compositor for a one-key "jump into meeting".

## Settings

| Setting           | Default | Notes                                         |
| ----------------- | ------- | --------------------------------------------- |
| `lookaheadDays`   | 7       | How far ahead `khal list` looks               |
| `pollInterval`    | 300     | Seconds between khal runs                     |
| `imminentMinutes` | 15      | Red + expanded when next event ≤ this         |
| `maxTitleWidth`   | 24      | Pill title truncation                         |
| `hideWhenEmpty`   | true    | Hide widget entirely if nothing's scheduled   |
| `khalArgs`        | `""`    | Extra args, e.g. `-a work -d holidays`        |
| `iconColor`       | primary | Icon tint when idle                           |
