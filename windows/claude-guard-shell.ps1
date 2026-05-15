# =============================================================================
# claude-guard-shell.ps1
# SecureMind Claude Guard Shell - Windows Port
# Runs as a Claude Code PreToolUse hook for Bash tool calls
#
# Exit 0  = allow command
# Exit 2  = block command (stderr shown as error in Claude)
#
# Rules file format:  action|id|regex  (.NET regex syntax)
#   deny    = permanently blocked, no override
#   confirm = blocked unless CLAUDE_ALLOW_DESTRUCTIVE=1
# =============================================================================

param()

# --- Config ---

$RulesFile = if ($env:CLAUDE_GUARD_RULES) { $env:CLAUDE_GUARD_RULES } else { "C:\Base\destructive_matchers.rules" }
$LogFile   = "C:\Base\logs\guard.log"

# --- Logging ---

function Write-GuardLog {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try {
        $dir = Split-Path $LogFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $LogFile -Value "[$ts] $Message" -ErrorAction SilentlyContinue
    } catch {}
}

# --- Validate rules file ---

if (-not (Test-Path $RulesFile)) {
    [Console]::Error.WriteLine("claude-guard: rules file not found: $RulesFile")
    exit 2
}

# --- Read hook JSON from stdin ---

$inputJson = [Console]::In.ReadToEnd()

if (-not $inputJson.Trim()) { exit 0 }

try {
    $hookData = $inputJson | ConvertFrom-Json
} catch {
    exit 0
}

# Extract the command string from the Bash tool input
$cmd = $hookData.tool_input.command
if (-not $cmd) { exit 0 }

# --- CLAUDE_ALLOW_DESTRUCTIVE override ---

if ($env:CLAUDE_ALLOW_DESTRUCTIVE -eq '1') {
    [Console]::Error.WriteLine("claude-guard: CLAUDE_ALLOW_DESTRUCTIVE=1 set - skipping all rule checks")
    Write-GuardLog "OVERRIDE (CLAUDE_ALLOW_DESTRUCTIVE=1): $cmd"
    exit 0
}

# --- Load and evaluate rules ---

$rules = Get-Content $RulesFile -ErrorAction Stop | Where-Object {
    $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#')
}

foreach ($rule in $rules) {
    $parts = $rule -split '\|', 3
    if ($parts.Count -lt 3) { continue }

    $action  = $parts[0].Trim()
    $ruleId  = $parts[1].Trim()
    $pattern = $parts[2].Trim()

    if (-not $pattern) { continue }

    $matched = $false
    try {
        $matched = $cmd -match $pattern
    } catch {
        # Bad regex in rules file - skip silently
        continue
    }

    if ($matched) {
        switch ($action) {
            'deny' {
                Write-GuardLog "DENIED [$ruleId]: $cmd"
                [Console]::Error.WriteLine("claude-guard: [DENY] rule '$ruleId' - command permanently blocked")
                [Console]::Error.WriteLine("cmd: $cmd")
                exit 2
            }
            'confirm' {
                Write-GuardLog "BLOCKED [$ruleId] (needs CLAUDE_ALLOW_DESTRUCTIVE=1): $cmd"
                [Console]::Error.WriteLine("claude-guard: [BLOCK] rule '$ruleId' - requires explicit override")
                [Console]::Error.WriteLine("cmd: $cmd")
                [Console]::Error.WriteLine("To run intentionally: set CLAUDE_ALLOW_DESTRUCTIVE=1 and restart Claude")
                exit 2
            }
            default {
                [Console]::Error.WriteLine("claude-guard: invalid action '$action' in rules file (rule: $ruleId)")
                exit 2
            }
        }
    }
}

# --- All rules passed - allow ---

Write-GuardLog "ALLOWED: $cmd"
exit 0
