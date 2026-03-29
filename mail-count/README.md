# mail-count

Unread mail count in the noctalia bar. Backend-agnostic: runs any shell
command that prints a number to stdout — works with notmuch, mu, plain
maildir, or anything else you can script.

The pill expands when there's unread mail and collapses to just the icon
when inbox zero. Click to launch your mail client.

![mail-count widget](https://github.com/Mic92/noctalia-plugins/releases/download/assets/mail-count-screenshot.png)

## Settings

Available in Settings → Plugins → Mail Count:

| Setting        | Default                                   | Purpose                             |
| -------------- | ----------------------------------------- | ----------------------------------- |
| `countCommand` | `notmuch count tag:unread and tag:inbox`  | Must print an integer to stdout     |
| `clickCommand` | `xdg-open mailto:`                        | Run on left click (empty = no-op)   |
| `pollInterval` | `60`                                      | Seconds between polls               |
| `hideWhenZero` | `false`                                   | Hide widget entirely when count = 0 |
| `iconColor`    | `primary`                                 | Icon tint                           |

## Example count commands

```sh
# notmuch
notmuch count tag:unread and tag:inbox

# mu
mu find flag:unread maildir:/INBOX 2>/dev/null | wc -l

# plain maildir
find ~/Maildir/INBOX/new -type f | wc -l

# multiple maildirs
find ~/mail/*/INBOX/new -type f | wc -l
```

## Refresh after sync

Polling every minute is fine, but for instant updates add this to your
sync script or notmuch `post-new` hook:

```sh
qs -c noctalia-shell ipc call plugin:mail-count refresh 2>/dev/null || true
```
