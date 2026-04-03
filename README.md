# securemind-claude-remote

Claude Code Remote Control setup for Ubuntu — with a guard shell that makes `--dangerously-skip-permissions` safe enough for a business machine.

## The problem

Claude Code Remote Control requires `--dangerously-skip-permissions` to bypass the interactive trust prompt when running as a service. But that flag also disables all `settings.json` deny rules, leaving the machine fully exposed.

## The solution

A guard shell sits at the OS level, **below** Claude Code, intercepting every bash command before execution — regardless of what flags Claude runs with.

```
Phone sends task
   ↓
Claude Code (--dangerously-skip-permissions, no prompts)
   ↓
claude-guard-shell.sh  ← blocks dangerous commands HERE
   ↓
/bin/bash executes safe commands only
```

## Install

```bash
git clone https://github.com/securemindtechsolutions/securemind-claude-remote.git
cd securemind-claude-remote
sudo bash setup.sh
```

Then log in if you haven't already:

```bash
claude login
sudo systemctl restart claude-code
```

Pair your phone:

```
Claude app → menu → Pair with your desktop
```

## What gets blocked

| Category | Examples | Action |
|---|---|---|
| Filesystem | `rm -rf /`, `dd` to block device | deny (permanent) |
| Audit data | `rm ~/securemind/clients`, `rm ~/securemind/reports` | deny (permanent) |
| Firewall | `ufw disable`, `iptables -F` | deny (permanent) |
| Credentials | `cat .env`, `cat id_rsa`, `printenv` | deny (permanent) |
| SSH | Delete SSH keys, edit `sshd_config` | deny (permanent) |
| Sudoers | `visudo`, edit `/etc/sudoers` | deny (permanent) |
| Package removal | `apt remove`, `pip uninstall` | confirm |
| Services | `systemctl stop`, `service restart` | confirm |
| Power | `shutdown`, `reboot` | confirm |
| Git destructive | `git reset --hard`, `git clean -fdx` | confirm |
| Remote send | `nc` to IP, `rsync` to remote | confirm |

**deny** = always blocked, no override  
**confirm** = blocked unless `CLAUDE_ALLOW_DESTRUCTIVE=1`

## Override for intentional destructive operations

```bash
CLAUDE_ALLOW_DESTRUCTIVE=1 ~/start-claude-remote.sh
sudo systemctl restart claude-code
```

## Add or edit rules

Rules live at `~/.claude-guard/destructive_matchers.rules` after install. Changes take effect immediately — no restart needed.

Format:
```
action|id|regex
```

## Useful commands

```bash
# Service management
sudo systemctl status claude-code
sudo systemctl restart claude-code
sudo systemctl stop claude-code

# View the live session
tmux attach -t claude-remote
# Detach without stopping: Ctrl+B then D

# Check guard shell is active
echo $SHELL
```

## Files

```
setup.sh                          # Main installer
guard/
  claude-guard-shell.sh           # Guard shell — intercepts all commands
  destructive_matchers.rules      # Regex policy rules
```

## Credits

Remote Control setup pattern by SecureMind Tech Solutions.  
Guard shell architecture inspired by [hexcodex-cyber/codex-high-auto](https://github.com/hexcodex-cyber/codex-high-auto).
