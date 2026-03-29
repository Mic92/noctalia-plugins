# ssh-askpass

Native noctalia dialog for `SSH_ASKPASS`.

![ssh-askpass confirm dialog](https://github.com/Mic92/noctalia-plugins/releases/download/assets/ssh-askpass-screenshot.png)

 Unlike lxqt-openssh-askpass this
actually honours `SSH_ASKPASS_PROMPT=confirm` and shows an Allow/Deny dialog
instead of a confusing empty password box.

## How it works

```
ssh-tpm-agent ──exec──▶ noctalia-ssh-askpass ──unix sock──▶ noctalia plugin
                        (stub binary)                       (QML dialog)
                             ▲                                   │
                             └───── {"ok":true,"value":"..."} ◀──┘
```

The plugin runs a `SocketServer` on `$XDG_RUNTIME_DIR/noctalia-ssh-askpass.sock`.
The stub is a ~50 line Go program that speaks the OpenSSH askpass contract on
one side and line-delimited JSON on the other.

## Setup

1. Build the stub: `go build -o ~/.local/bin/noctalia-ssh-askpass ./stub`
2. Enable the plugin in noctalia
3. Set `SSH_ASKPASS=~/.local/bin/noctalia-ssh-askpass` in your agent's
   environment (systemd unit, shell rc, etc.)

## Modes

- **confirm** (`SSH_ASKPASS_PROMPT=confirm`): Allow/Deny buttons, Enter=Allow,
  Esc=Deny. Used by `ssh-add -c` / `ssh-tpm-add -c`.
- **prompt** (default): password field for key passphrases.

## Settings

- `confirmTimeoutSec` (default 30): auto-deny after this many seconds so a
  forgotten prompt doesn't wedge the agent.
