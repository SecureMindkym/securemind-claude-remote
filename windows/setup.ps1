# =============================================================================
# setup.ps1 - SecureMind Claude Guard Shell Setup (Windows)
# Run once from C:\Base as Administrator:
#   powershell.exe -ExecutionPolicy Bypass -File C:\Base\setup.ps1
#
# Headless (starts at boot, nobody logged in), as a local account whose
# password you have, e.g. "claude":
#   powershell.exe -ExecutionPolicy Bypass -File C:\Base\setup.ps1 -TaskUser claude
# =============================================================================

param(
    [string]$TaskUser   # register the ClaudeRemoteControl task to run as this account at startup
)

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

# --- 5. Work out whose profile Claude runs under ---
# The pre-accepted settings and the login must be in the profile of the account the
# task runs as, not necessarily the admin running this script.

$ProfileDir = $env:USERPROFILE
if ($TaskUser) {
    $prof = Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$TaskUser" } | Select-Object -First 1
    $ProfileDir = if ($prof) { $prof.LocalPath } else { "C:\Users\$TaskUser" }
    New-Item -ItemType Directory -Path "$ProfileDir\.claude" -Force | Out-Null
}
Write-Step "Claude profile: $ProfileDir"

Write-Step "Checking Claude login status..."
if (-not (Test-Path "$ProfileDir\.claude\.credentials.json")) {
    Write-Warn "Not logged in yet for this profile. See 'Log in' in the README."
} else {
    Write-Step "Claude credentials found - good to go."
}

# --- 6. Pre-accept first-run screens ---
# A fresh profile stops at onboarding, the bypass-permissions warning and the folder-trust
# prompt. Run headless, nobody sees them, Claude never registers with Remote Control and
# the machine never shows up in the app. Accept them up front.

Write-Step "Pre-accepting onboarding and workspace trust for $BASE_DIR..."
$claudeJsonPath = "$ProfileDir\.claude.json"
$claudeData = [pscustomobject]@{}
if (Test-Path $claudeJsonPath) {
    try { $claudeData = Get-Content $claudeJsonPath -Raw | ConvertFrom-Json } catch {}
}
$claudeData | Add-Member -Force hasCompletedOnboarding $true
if (-not $claudeData.projects) { $claudeData | Add-Member -Force projects ([pscustomobject]@{}) }
foreach ($key in @($BASE_DIR, ($BASE_DIR -replace '\\', '/'))) {
    $entry = $claudeData.projects.$key
    if ($entry) { $entry | Add-Member -Force hasTrustDialogAccepted $true }
    else { $claudeData.projects | Add-Member -Force $key ([pscustomobject]@{ hasTrustDialogAccepted = $true }) }
}
$claudeData | ConvertTo-Json -Depth 20 | Set-Content -Path $claudeJsonPath -Encoding UTF8

$userSettingsPath = "$ProfileDir\.claude\settings.json"
$userSettings = [pscustomobject]@{}
if (Test-Path $userSettingsPath) {
    try { $userSettings = Get-Content $userSettingsPath -Raw | ConvertFrom-Json } catch {}
}
$userSettings | Add-Member -Force skipDangerousModePermissionPrompt $true
$userSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $userSettingsPath -Encoding UTF8
Write-Step "Onboarding, trust and bypass prompt pre-accepted"

# --- 7. Set CLAUDE_GUARD_RULES as user environment variable ---

Write-Step "Setting CLAUDE_GUARD_RULES environment variable..."
[System.Environment]::SetEnvironmentVariable("CLAUDE_GUARD_RULES", $RULES_FILE, "User")
$env:CLAUDE_GUARD_RULES = $RULES_FILE
Write-Step "CLAUDE_GUARD_RULES = $RULES_FILE"

# --- 8. Register the ClaudeRemoteControl task (optional) ---
# Stored password (LogonType Password) + AtStartup, so it comes back after a reboot with
# nobody logged in. An at-logon interactive task stays dead until someone logs in.

if ($TaskUser) {
    Write-Step "Registering scheduled task ClaudeRemoteControl as $TaskUser..."
    $cred = Get-Credential -UserName "$env:COMPUTERNAME\$TaskUser" -Message "Password for $TaskUser (stored in the task)"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $BASE_DIR\start-claude-remote.ps1" `
        -WorkingDirectory $BASE_DIR
    $triggers = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogOn -User $cred.UserName))
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew
    Unregister-ScheduledTask -TaskName ClaudeRemoteControl -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName ClaudeRemoteControl -Action $action -Trigger $triggers -Settings $settings `
        -User $cred.UserName -Password $cred.GetNetworkCredential().Password -RunLevel Highest | Out-Null
    & icacls $ProfileDir\.claude.json $ProfileDir\.claude /setowner $cred.UserName /T /C /Q | Out-Null
    Write-Step "Task registered. Start now with:  Start-ScheduledTask ClaudeRemoteControl"
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
Write-Host "  1. If not logged in yet (as the account Claude runs under):"
Write-Host "       claude auth login"
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
