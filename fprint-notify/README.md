# fprint-notify

Pops a noctalia toast whenever `fprintd` is waiting for a fingerprint scan.

![screenshot](https://github.com/Mic92/noctalia-plugins/releases/download/assets/fprint-notify-screenshot.png)

## Why

`pam_fprintd` blocks the PAM conversation with only a terminal message
(`Place your finger on the reader`). If you run `sudo` in a background
terminal or from a script you'll never notice it's waiting. This plugin
watches the `net.reactivated.Fprint.Device.Verify*` D-Bus signals on the
system bus and surfaces them as desktop toasts.

## Setup

Enable fprintd auth for sudo in your NixOS config:

```nix
security.pam.services.sudo.fprintAuth = true;
```

Then enable this plugin in noctalia. No bar widget — it runs headless and
only emits toasts.

## Settings

- `showSuccessToast` (default `true`) — brief "Authenticated" toast on match
- `staleTimeoutSec` (default `30`) — clear a stuck "touch sensor" toast if
  the PAM client died without stopping verification
