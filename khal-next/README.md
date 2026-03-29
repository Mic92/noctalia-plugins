# khal-next

Bar widget showing the next upcoming [khal] event with a live countdown, plus
a click-through agenda panel.

[khal]: https://github.com/pimutils/khal

![screenshot placeholder]()

## What it does

- **Bar pill**: collapsed calendar icon by default. Hover reveals a compact
  countdown (`23m`), tooltip shows the full time range + title. Within the
  "imminent" window (default 15 min) or once the event has started, the pill
  auto-expands and turns red/amber so you can't miss it.
- **Click**: agenda panel — day-grouped upcoming events with clickable
  meeting URLs.
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
| `hideWhenEmpty`   | true    | Hide widget entirely if nothing's scheduled   |
| `khalArgs`        | `""`    | Extra args, e.g. `-a work -d holidays`        |
| `iconColor`       | primary | Icon tint when idle                           |
