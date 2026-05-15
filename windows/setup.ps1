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
