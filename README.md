# securemind-claude-remote

Claude Code Remote Control setup — with a guard shell that makes `--dangerously-skip-permissions` safe enough for a business machine.

Supports **Ubuntu/Linux** and **Windows Server / Windows 10+**.

## The problem

Claude Code Remote Control requires `--dangerously-skip-permissions` to bypass the interactive trust prompt when running as a service. But that flag also disables all `settings.json` deny rules, leaving the machine fully exposed.

## The solution

A guard shell sits at the OS level, **below** Claude Code, intercepting every command before execution — regardless of what flags Claude runs with.

```
Phone sends task
   ↓
Claude Code (--dangerously-skip-permissions, no prompts)
   ↓
Guard shell  ← blocks dangerous commands HERE
   ↓
OS executes safe commands only
```

On **Linux** the guard replaces `$SHELL` so it intercepts every bash invocation.  
On **Windows** it runs as a `PreToolUse` hook that reads the command from Claude's hook JSON before execution.

---

## Linux (Ubuntu) Install

```bash
git clone https://github.com/SecureMindkym/securemind-claude-remote.git
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

---

## Windows Install

### Requirements
- Windows 10 / Windows Server 2016 or later
- PowerShell 5.1+
- Node.js (installer at https://nodejs.org)
- Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)
- GitHub CLI (optional, for repo operations — https://cli.github.com)

### Steps

1. Clone the repo and copy the Windows files to `C:\Base`:

```powershell
git clone https://github.com/SecureMindkym/securemind-claude-remote.git C:\Base\securemind-claude-remote
Copy-Item C:\Base\securemind-claude-remote\windows\* C:\Base\ -Recurse
```

2. Run the setup script as Administrator:

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\Base\setup.ps1
```

3. Log in to Claude if you haven't already:

```powershell
claude login
```

4. Start Claude Code Remote Control:

```powershell
powershell.exe -File C:\Base\start-claude-remote.ps1
```

5. Pair your phone:

```
Claude app → menu → Pair with your desktop
```

### How the Windows guard works

The guard runs as a `PreToolUse` hook configured in `.claude\settings.json`. When Claude attempts any Bash tool call, Windows executes `claude-guard-shell.ps1` first — it reads the command from Claude's hook JSON and checks it against `destructive_matchers.rules` using .NET regex. If a rule matches, it exits with code 2 and Claude sees the block message instead of running the command.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NonInteractive -File C:\\Base\\windows\\claude-guard-shell.ps1"
          }
        ]
      }
    ]
  }
}
```

---

## What gets blocked

| Category | Examples | Action |
|---|---|---|
| Filesystem | `rm -rf /`, `dd` to block device, `Remove-Item -Recurse C:\` | deny (permanent) |
| Audit data | `rm ~/securemind/clients`, `rm ~/securemind/reports` | deny (permanent) |
| Firewall | `ufw disable`, `iptables -F`, `netsh advfirewall set allprofiles state off` | deny (permanent) |
| Credentials | `cat .env`, `cat id_rsa`, `printenv`, `reg export HKLM\SAM` | deny (permanent) |
| SSH | Delete SSH keys, edit `sshd_config` | deny (permanent) |
| Sudoers / UAC | `visudo`, edit `/etc/sudoers` | deny (permanent) |
| Package removal | `apt remove`, `pip uninstall`, `choco uninstall` | confirm |
| Services | `systemctl stop`, `Stop-Service`, `sc stop` | confirm |
| Power | `shutdown`, `reboot`, `Restart-Computer` | confirm |
| Git destructive | `git reset --hard`, `git clean -fdx` | confirm |
| Remote send | `nc` to IP, `rsync` to remote | confirm |

**deny** = always blocked, no override  
**confirm** = blocked unless `CLAUDE_ALLOW_DESTRUCTIVE=1`

---

## Override for intentional destructive operations

**Linux:**
```bash
CLAUDE_ALLOW_DESTRUCTIVE=1 ~/start-claude-remote.sh
```

**Windows:**
```powershell
$env:CLAUDE_ALLOW_DESTRUCTIVE='1'
powershell.exe -File C:\Base\start-claude-remote.ps1
```

---

## Add or edit rules

**Linux:** Rules live at `~/.claude-guard/destructive_matchers.rules` after install.  
**Windows:** Rules live at `C:\Base\destructive_matchers.rules`.

Changes take effect immediately — no restart needed.

Format:
```
action|id|regex
```

Linux rules use POSIX regex (`[[:space:]]`, `[[:alnum:]]`).  
Windows rules use .NET regex (`\s`, `\w`, `[^\s]`).

---

## Useful commands

**Linux:**
```bash
sudo systemctl status claude-code
sudo systemctl restart claude-code
sudo systemctl stop claude-code
tmux attach -t claude-remote   # view live session (Ctrl+B D to detach)
```

**Windows:**
```powershell
Get-Content C:\Base\logs\guard.log -Tail 50   # view guard log
Get-Content C:\Base\logs\guard.log -Wait      # tail live
```

---

## Files

```
setup.sh                          # Linux installer
claude-guard-shell.sh             # Linux guard shell (replaces $SHELL)
destructive_matchers.rules        # Linux policy rules (POSIX regex)

windows/
  setup.ps1                       # Windows installer
  claude-guard-shell.ps1          # Windows guard (PreToolUse hook)
  start-claude-remote.ps1         # Windows launcher
  destructive_matchers.rules      # Windows policy rules (.NET regex)

.claude/
  settings.json                   # Hook configuration (Windows PreToolUse)
```

---

## Credits

Remote Control setup pattern by SecureMind Tech Solutions.  
Guard shell architecture inspired by [hexcodex-cyber/codex-high-auto](https://github.com/hexcodex-cyber/codex-high-auto).
