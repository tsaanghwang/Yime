param(
    [string[]]$InstallRoots = @(
        "C:\Program Files (x86)\YIME"
    ),
    [switch]$Quiet,
    [switch]$Auto,
    [string]$TargetUserSid
)

$ErrorActionPreference = "Stop"
$ownershipHelper = Join-Path $PSScriptRoot 'dual-product\rime-pime-ownership.ps1'
if (-not (Test-Path -LiteralPath $ownershipHelper -PathType Leaf)) { throw 'Required Rime/PIME ownership helper is unavailable.' }
. $ownershipHelper
$TargetUserSid = Assert-YimePimeTargetSid $TargetUserSid

function Write-Step {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host $Message
    }
}

if (-not $Quiet -and -not $Auto) {
    Write-Host ""
    Write-Host "Before reinstall, please:"
    Write-Host "  1. Switch input method to English or another IME (not Yime)."
    Write-Host "  2. Close apps where you are typing (Notepad, browser, IDE, etc.)."
    Write-Host ""
    Read-Host "Press Enter when ready"
    Write-Host ""
} elseif (-not $Quiet -and $Auto) {
    Write-Host "Auto mode: checking Rime/PIME is closed; no force stop or shared quit event will be sent."
    Write-Host ""
}

try {
    Stop-YimePimeOwnedProcesses -InstallRoots $InstallRoots -TargetUserSid $TargetUserSid | Out-Null
} catch {
    if (-not $Quiet) {
        Write-Host 'Rime/PIME is not admitted for maintenance; save and close this product, or repair an unrecognized root separately.'
        Write-Host $_.Exception.Message
    }
    exit 3
}

$dllUsers = & tasklist.exe /m PIMETextService.dll 2>$null
if ($LASTEXITCODE -eq 0 -and $dllUsers -and ($dllUsers.Count -gt 1)) {
    if (-not $Quiet) {
        Write-Host ""
        Write-Host "Warning: PIMETextService.dll is still loaded (often explorer.exe):"
        $dllUsers | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        Write-Host "Will skip full uninstall and do an in-place install (go-backend can still update)."
        Write-Host "For a clean reinstall, reboot Windows first, then run this script again."
        Write-Host ""
    }
    exit 2
}

Write-Step "Rime/PIME maintenance admitted: no owned runtime process is active."
exit 0
