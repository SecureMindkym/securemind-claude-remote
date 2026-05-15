# =============================================================================
# start-claude-remote.ps1 - SecureMind Claude Guard (Windows)
# Starts Claude Code with --remote-control and the guard hook active
#
# Usage:
#   powershell.exe -File C:\Base\start-claude-remote.ps1
#
# To allow destructive ops for this session:
#   $env:CLAUDE_ALLOW_DESTRUCTIVE='1'
#   powershell.exe -File C:\Base\start-claude-remote.ps1
# =============================================================================

$BASE_DIR   = "C:\Base"
$RULES_FILE = "$BASE_DIR\destructive_matchers.rules"
$LOG_DIR    = "$BASE_DIR\logs"

# --- Validate setup ---

if (-not (Test-Path "$BASE_DIR\claude-guard-shell.ps1")) {
    Write-Host "[ERROR] Guard shell not found. Run setup.ps1 first." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $RULES_FILE)) {
    Write-Host "[ERROR] Rules file not found: $RULES_FILE" -ForegroundColor Red
    exit 1
}

# --- Set environment ---

$env:CLAUDE_GUARD_RULES = $RULES_FILE
New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null

# --- Show status ---

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Claude Code Remote Control"                 -ForegroundColor Cyan
Write-Host "  SecureMind Guard: ACTIVE"                  -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Rules file : $RULES_FILE" -ForegroundColor White
Write-Host "  Guard log  : $LOG_DIR\guard.log" -ForegroundColor White

if ($env:CLAUDE_ALLOW_DESTRUCTIVE -eq '1') {
    Write-Host "  Override   : CLAUDE_ALLOW_DESTRUCTIVE=1 (confirm rules bypassed)" -ForegroundColor Yellow
} else {
    Write-Host "  Override   : off (all rules enforced)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Starting Claude Code - working dir: $BASE_DIR" -ForegroundColor White
Write-Host "Press Ctrl+C to stop." -ForegroundColor Gray
Write-Host ""

# --- Launch Claude from C:\Base so .claude\settings.json hook is loaded ---

Set-Location $BASE_DIR

claude --dangerously-skip-permissions --remote-control --name $env:COMPUTERNAME
