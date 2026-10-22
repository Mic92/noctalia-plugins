# fprint-notify

Shows a noctalia overlay whenever `fprintd` is waiting for a fingerprint scan.

![screenshot](https://github.com/Mic92/noctalia-plugins/releases/download/assets/fprint-notify-screenshot.png)

## Why

`pam_fprintd` blocks the PAM conversation with only a terminal message
(`Place your finger on the reader`). If you run `sudo` in a background
terminal or from a script you'll never notice it's waiting. This plugin
watches the `net.reactivated.Fprint.Device.Verify*` D-Bus signals on the
system bus and shows a small overlay at the top of the screen. It sits above
fullscreen windows and never takes keyboard focus, so typing continues in the
terminal.

## Setup

Enable fprintd auth for sudo in your NixOS config:

```nix
security.pam.services.sudo.fprintAuth = true;
```

Then enable `mic92/fprint-notify` in noctalia. No bar widget; a background
service tails `gdbus monitor` and reconnects when fprintd restarts.

## Settings

- `showSuccessToast` (default `true`) — briefly show "Authenticated" on match
- `staleTimeoutSec` (default `30`) — hide a stuck "touch sensor" overlay if
  the PAM client died without stopping verification
