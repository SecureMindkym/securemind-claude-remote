# =============================================================================
# guard-test.ps1 - regression suite for the SecureMind Claude guard (Windows)
#
#   powershell.exe -ExecutionPolicy Bypass -File C:\Base\windows\guard-test.ps1
#
# Every case below is DATA. It is piped to the guard as hook JSON on stdin and
# is never executed. Run this after any edit to destructive_matchers.rules.
# =============================================================================

param(
    [string]$BaseDir = 'C:\Base'
)

$GUARD = Join-Path $BaseDir 'claude-guard-shell.ps1'
$RULES = Join-Path $BaseDir 'destructive_matchers.rules'

if (-not (Test-Path $GUARD)) { Write-Host "Guard not found: $GUARD" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $RULES)) { Write-Host "Rules not found: $RULES" -ForegroundColor Red; exit 1 }

$script:pass = 0
$script:fail = 0

function Invoke-Guard {
    param($ToolName, $Payload, [switch]$Override)
    $json = @{ tool_name = $ToolName; tool_input = $Payload } | ConvertTo-Json -Compress
    $prev = $env:CLAUDE_ALLOW_DESTRUCTIVE
    $env:CLAUDE_ALLOW_DESTRUCTIVE = $(if ($Override) { '1' } else { '' })
    $null = $json | powershell.exe -NonInteractive -ExecutionPolicy Bypass -File $GUARD 2>&1
    $code = $LASTEXITCODE
    $env:CLAUDE_ALLOW_DESTRUCTIVE = $prev
    if ($code -eq 2) { 'BLOCK' } else { 'ALLOW' }
}

function Assert {
    param($Got, $Expect, $Label)
    if ($Got -eq $Expect) {
        $script:pass++
        Write-Host ("  PASS  {0,-5} {1}" -f $Got, $Label)
    } else {
        $script:fail++
        Write-Host ("  FAIL  {0,-5} (want {1}) {2}" -f $Got, $Expect, $Label) -ForegroundColor Red
    }
}

function Cmd { param($c, $e) Assert (Invoke-Guard 'Bash' @{ command = $c }) $e $c }
function Wrt { param($p, $e) Assert (Invoke-Guard 'Write' @{ file_path = $p; content = 'x' }) $e "[Write] $p" }
function CmdOverride { param($c, $e) Assert (Invoke-Guard 'Bash' @{ command = $c } -Override) $e "[override] $c" }

Write-Host "`nGuard : $GUARD"
Write-Host "Rules : $RULES`n"

Write-Host "-- shell commands must be blocked --"
Cmd 'ufw disable'                                     'BLOCK'
Cmd 'netsh advfirewall set allprofiles state off'     'BLOCK'
Cmd 'reg export HKLM\SAM sam.reg'                     'BLOCK'
Cmd 'reg save HKLM\SYSTEM sys.hiv'                    'BLOCK'
Cmd 'vssadmin delete shadows /all /quiet'             'BLOCK'
Cmd 'wbadmin delete catalog -quiet'                   'BLOCK'
Cmd 'Add-MpPreference -ExclusionPath C:\tmp'          'BLOCK'
Cmd 'powershell.exe -enc SQBFAFgA'                    'BLOCK'
Cmd 'Get-Content server.pem'                          'BLOCK'
Cmd 'takeown /f C:\Windows\System32'                  'BLOCK'

Write-Host "`n-- flag order must not downgrade a deny --"
# The path may appear before or after the switches; both must still be denied.
Cmd 'Remove-Item -Recurse -Force C:\Windows\System32' 'BLOCK'
Cmd 'Remove-Item C:\Windows\System32 -Recurse -Force' 'BLOCK'
Cmd 'del /s C:\Windows\explorer.exe'                  'BLOCK'

Write-Host "`n-- guard must protect its own config --"
Cmd "Set-Content $RULES `"`""                         'BLOCK'
Cmd "echo x > $RULES"                                 'BLOCK'
Cmd "Remove-Item -Recurse -Force $BaseDir"            'BLOCK'
Cmd "rm -rf $BaseDir"                                 'BLOCK'
Wrt $RULES                                            'BLOCK'
Wrt (Join-Path $BaseDir '.claude\settings.json')      'BLOCK'
Wrt $GUARD                                            'BLOCK'

Write-Host "`n-- override lifts confirm but never deny --"
CmdOverride 'ufw disable'                             'BLOCK'
CmdOverride 'reg export HKLM\SAM sam.reg'             'BLOCK'
CmdOverride 'vssadmin delete shadows /all /quiet'     'BLOCK'
CmdOverride 'Add-MpPreference -ExclusionPath C:\tmp'  'BLOCK'
CmdOverride "Remove-Item -Recurse -Force $BaseDir"    'BLOCK'
CmdOverride "Set-Content $RULES `"`""                 'ALLOW'
CmdOverride 'Remove-Item .\node_modules -Recurse'     'ALLOW'

Write-Host "`n-- ordinary work must not be blocked --"
Cmd 'git status'                                      'ALLOW'
Cmd 'git commit -m "fix: update parser"'              'ALLOW'
Cmd 'npm run build'                                   'ALLOW'
Cmd "Get-Content $BaseDir\logs\guard.log -Tail 20"    'ALLOW'
Cmd 'powershell.exe -NonInteractive -ExecutionPolicy Bypass -File C:\x.ps1' 'ALLOW'
Wrt 'C:\Users\dev\project\index.js'                   'ALLOW'

Write-Host "`n-- every rule must be a valid .NET regex --"
$rules = Get-Content $RULES | Where-Object { $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') }
$badRegex = @()
foreach ($line in $rules) {
    $parts = $line -split '\|', 3
    if ($parts.Count -lt 3) { continue }
    try { [void][regex]::new($parts[2]) } catch { $badRegex += $parts[1] }
}
Assert ($(if ($badRegex.Count -eq 0) { 'ALLOW' } else { 'BLOCK' })) 'ALLOW' "$($rules.Count) rules compile"
if ($badRegex.Count) { $badRegex | ForEach-Object { Write-Host "        bad regex: $_" -ForegroundColor Red } }

# POSIX bracket classes are a Linux-rules import and match nothing useful here.
$posix = @($rules | Select-String -SimpleMatch '[[:')
Assert ($(if ($posix.Count -eq 0) { 'ALLOW' } else { 'BLOCK' })) 'ALLOW' 'no POSIX classes (Linux rules file)'

Write-Host ""
if ($script:fail -eq 0) {
    Write-Host "PASS - $($script:pass) checks" -ForegroundColor Green
    exit 0
} else {
    Write-Host "FAIL - $($script:fail) of $($script:pass + $script:fail) checks failed" -ForegroundColor Red
    exit 1
}
