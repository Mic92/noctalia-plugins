# voice-assistant

Shows what a voice assistant found, next to what it says: a route as a
timeline, places as a list. Built for
[my assistant](https://github.com/Mic92/dotfiles/tree/main/pkgs/voice-assistant),
but anything that can write a JSON file can use it.

The panel never takes keyboard focus and closes itself after a timeout;
hovering it keeps it open. Cards and the header button open their link.

## Showing a view

Write the view to a file and hand its path to the service:

```sh
cat > "$XDG_RUNTIME_DIR/view.json" <<'EOF'
{
  "kind": "timeline",
  "icon": "train",
  "title": "To Laim",
  "subtitle": "25 mins · 6.9 km · by public transport",
  "url": "https://www.google.com/maps/dir/?api=1&destination=Laim",
  "items": [
    { "glyph": "walk", "title": "Walk", "meta": "10 min" },
    { "glyph": "train", "title": "U5", "detail": "Odeonsplatz → Laimer Platz", "meta": "12:13 – 12:24" }
  ]
}
EOF
noctalia msg plugin mic92/voice-assistant:service all show "$XDG_RUNTIME_DIR/view.json"
noctalia msg plugin mic92/voice-assistant:service all hide
```

| Field      | Purpose                                                        |
| ---------- | -------------------------------------------------------------- |
| `kind`     | `timeline` joins the items with a line, `list` makes them cards |
| `title`    | Heading (required)                                             |
| `subtitle` | Line under the heading                                         |
| `icon`     | Tabler glyph next to the heading                               |
| `url`      | Opened by the header button                                    |
| `items`    | Rows: `title`, and optionally `glyph`, `detail`, `meta`, `url` |

## Settings

| Setting      | Default | Purpose                              |
| ------------ | ------- | ------------------------------------ |
| `timeoutSec` | `45`    | Seconds until the panel closes again |
