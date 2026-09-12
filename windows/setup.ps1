# =============================================================================
# setup.ps1 - SecureMind Claude Guard Shell Setup (Windows)
# Run once from C:\Base as Administrator:
#   powershell.exe -ExecutionPolicy Bypass -File C:\Base\setup.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

$BASE_DIR   = "C:\Base"
$GUARD_PS1  = "$BASE_DIR\claude-guard-shell.ps1"
$RULES_FILE = "$BASE_DIR\destructive_matchers.rules"
$LOG_DIR    = "$BASE_DIR\logs"

function Write-Step { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Claude Code Remote Control Setup"           -ForegroundColor Cyan
Write-Host "  SecureMind Tech Solutions (Windows Port)"  -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Check files exist ---

Write-Step "Checking required files..."
if (-not (Test-Path $GUARD_PS1))  { Write-Fail "Missing: $GUARD_PS1" }
if (-not (Test-Path $RULES_FILE)) { Write-Fail "Missing: $RULES_FILE" }
Write-Step "Guard script and rules file found."

# --- 2. Create logs directory ---

Write-Step "Creating logs directory..."
New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
Write-Step "Logs directory: $LOG_DIR"

# --- 3. Check Node.js ---

Write-Step "Checking Node.js..."
$nodeVersion = node --version 2>$null
if (-not $nodeVersion) {
    Write-Warn "Node.js not found."
    Write-Host "  Install options:" -ForegroundColor Yellow
    Write-Host "    winget install OpenJS.NodeJS.LTS" -ForegroundColor White
    Write-Host "    Or download from: https://nodejs.org" -ForegroundColor White
    Write-Host ""
    $install = Read-Host "Attempt to install Node.js via winget now? (y/N)"
    if ($install -eq 'y' -or $install -eq 'Y') {
        winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("PATH","User")
        $nodeVersion = node --version 2>$null
        if (-not $nodeVersion) { Write-Fail "Node.js install failed. Install manually then re-run setup." }
    } else {
        Write-Fail "Node.js is required. Install it then re-run setup.ps1."
    }
}
Write-Step "Node.js: $nodeVersion"

# --- 4. Check / install Claude Code ---

Write-Step "Checking Claude Code CLI..."
$claudePath = (Get-Command claude -ErrorAction SilentlyContinue).Source
if (-not $claudePath) {
    Write-Step "Installing Claude Code globally via npm..."
    npm install -g @anthropic-ai/claude-code
    $claudePath = (Get-Command claude -ErrorAction SilentlyContinue).Source
    if (-not $claudePath) { Write-Fail "Claude Code installation failed." }
}
Write-Step "Claude Code: $claudePath"

# --- 5. Verify Claude login ---

Write-Step "Checking Claude login status..."
$credPath = "$env:USERPROFILE\.claude\credentials.json"
if (-not (Test-Path $credPath)) {
    Write-Warn "Not logged in yet. After setup, run:  claude login"
} else {
    Write-Step "Claude credentials found - good to go."
}

# --- 6. Pre-accept workspace trust ---

Write-Step "Pre-accepting workspace trust for $BASE_DIR..."
$claudeJsonPath = "$env:USERPROFILE\.claude.json"
$claudeData = @{}
if (Test-Path $claudeJsonPath) {
    try {
        $raw = Get-Content $claudeJsonPath -Raw
        $parsed = $raw | ConvertFrom-Json
        $claudeData = @{}
        $parsed.PSObject.Properties | ForEach-Object { $claudeData[$_.Name] = $_.Value }
    } catch {}
}
if (-not $claudeData.ContainsKey('projects')) {
    $claudeData['projects'] = @{}
}
if ($claudeData['projects'] -isnot [hashtable]) {
    $claudeData['projects'] = @{}
}
$claudeData['projects'][$BASE_DIR] = @{ hasTrustDialogAccepted = $true }
$claudeData | ConvertTo-Json -Depth 10 | Set-Content -Path $claudeJsonPath -Encoding UTF8
Write-Step "hasTrustDialogAccepted set for $BASE_DIR"

# --- 7. Set CLAUDE_GUARD_RULES as user environment variable ---

Write-Step "Setting CLAUDE_GUARD_RULES environment variable..."
[System.Environment]::SetEnvironmentVariable("CLAUDE_GUARD_RULES", $RULES_FILE, "User")
$env:CLAUDE_GUARD_RULES = $RULES_FILE
Write-Step "CLAUDE_GUARD_RULES = $RULES_FILE"

# --- 8. Install the PreToolUse hook config ---
# Without this file the guard is never invoked and the machine is unprotected,
# so treat a failure here as fatal rather than warning and continuing.

Write-Step "Installing guard hook config..."
$CLAUDE_DIR     = "$BASE_DIR\.claude"
$SETTINGS_FILE  = "$CLAUDE_DIR\settings.json"
New-Item -ItemType Directory -Path $CLAUDE_DIR -Force | Out-Null

$hookCommand = "powershell.exe -NonInteractive -ExecutionPolicy Bypass -File $GUARD_PS1"
$settings = [ordered]@{
    trustWorkspace = $true
    hooks = [ordered]@{
        PreToolUse = @(
            [ordered]@{
                # Bash alone is not enough on Windows: the PowerShell tool is the
                # primary shell, and Write/Edit would otherwise be an unguarded
                # route to the rules file itself.
                matcher = "Bash|PowerShell|Write|Edit|NotebookEdit"
                hooks = @(
                    [ordered]@{ type = "command"; command = $hookCommand }
                )
            }
        )
    }
}

if (Test-Path $SETTINGS_FILE) {
    $backup = "$SETTINGS_FILE.bak"
    Copy-Item $SETTINGS_FILE $backup -Force
    Write-Warn "Existing settings.json backed up to $backup"
}

$settings | ConvertTo-Json -Depth 10 | Set-Content -Path $SETTINGS_FILE -Encoding UTF8

try {
    $null = Get-Content $SETTINGS_FILE -Raw | ConvertFrom-Json
} catch {
    Write-Fail "Wrote $SETTINGS_FILE but it is not valid JSON - guard would not load."
}
Write-Step "Hook config: $SETTINGS_FILE"

# --- 9. Verify the guard actually blocks ---

Write-Step "Verifying guard blocks a known-dangerous command..."
$probe = '{"tool_name":"Bash","tool_input":{"command":"ufw disable"}}'
$probe | & powershell.exe -NonInteractive -ExecutionPolicy Bypass -File $GUARD_PS1 2>&1 | Out-Null
if ($LASTEXITCODE -eq 2) {
    Write-Step "Guard verified - dangerous command blocked (exit 2)."
} else {
    Write-Fail "Guard did NOT block a known-dangerous command (exit $LASTEXITCODE). Check $RULES_FILE."
}

# --- Done ---

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Guard shell : $GUARD_PS1" -ForegroundColor White
Write-Host "Rules file  : $RULES_FILE" -ForegroundColor White
Write-Host "Logs        : $LOG_DIR\guard.log" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. If not logged in yet:"
Write-Host "       claude login"
Write-Host ""
Write-Host "  2. Start Claude Code Remote Control:"
Write-Host "       powershell.exe -File C:\Base\start-claude-remote.ps1"
Write-Host ""
Write-Host "  3. On your phone:"
Write-Host "       Open Claude app -> menu -> Pair with your desktop"
Write-Host ""
Write-Host "  4. To allow a destructive op intentionally:"
Write-Host '       $env:CLAUDE_ALLOW_DESTRUCTIVE="1"; claude --dangerously-skip-permissions'
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Yellow
Write-Host "  Get-Content C:\Base\logs\guard.log -Tail 50   # view guard log"
Write-Host "  Get-Content C:\Base\logs\guard.log -Wait      # tail live"
Write-Host ""
