# ssh-askpass

Native noctalia dialog for `SSH_ASKPASS`.

![ssh-askpass confirm dialog](https://github.com/Mic92/noctalia-plugins/releases/download/assets/ssh-askpass-screenshot.png)

Unlike lxqt-openssh-askpass this
actually honours `SSH_ASKPASS_PROMPT=confirm` and shows an Allow/Deny dialog
instead of a confusing empty password box.

## How it works

```
ssh-tpm-agent ──exec──▶ noctalia-ssh-askpass ──noctalia msg plugin──▶ service ──▶ dialog panel
                        (stub binary)                                                  │
                             ▲                                                         │
                             └──── $XDG_RUNTIME_DIR/noctalia-ssh-askpass/<id>/reply ◀───┘
```

Plugin IPC is one-way, so the stub creates a private (0700) directory per
request and passes the reply path along. The service queues concurrent
requests and shows them one at a time. The stub fails closed when noctalia
isn't running, and removing its directory (exit, signal, 10 minute timeout)
withdraws a queued request.

## Setup

1. Build the stub: `nix build .#noctalia-ssh-askpass`.
2. Enable `mic92/ssh-askpass` in noctalia.
3. Set `SSH_ASKPASS` to the stub in your agent's environment. `noctalia` must
   be on its `PATH`. If `WAYLAND_DISPLAY` is unset, which happens when the
   agent starts before the desktop session, the stub looks for the shell's
   socket in `$XDG_RUNTIME_DIR`.

## Modes

- **confirm** (`SSH_ASKPASS_PROMPT=confirm`): Allow/Deny buttons, Enter=Allow,
  Esc=Deny. Used by `ssh-add -c` / `ssh-tpm-add -c`.
- **prompt** (default): password field for key passphrases.

## Settings

- `confirmTimeoutSec` (default 30): auto-deny after this many seconds so a
  forgotten prompt doesn't wedge the agent.
- `confirmMethod` (default `"click"`): how confirm-mode prompts are answered.
  - `"click"` — Allow/Deny buttons, Enter=Allow.
  - `"fingerprint"` — spawns `fprintd-verify`; a match allows, anything else
    denies. No Allow button, Esc/timeout still deny. Requires `fprintd` with
    an enrolled finger.

### Fingerprint mode caveats

This is a **user-presence check**, not a cryptographic binding. It stops an
unattended terminal or background script from silently using your agent, but
an attacker with code execution in your session can bypass it (patch the
plugin, talk to the agent socket directly, LD_PRELOAD the stub). Key material
protection is the TPM's job.

`fprintd` only lets one client claim the reader at a time. If `sudo` (via
`pam_fprintd`) grabs it while this dialog is up, one side will fail with
"device already claimed". The dialog fails closed in that case.
