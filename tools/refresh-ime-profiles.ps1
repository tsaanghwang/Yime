param(
    [string]$InstallRoot = "C:\Program Files (x86)\YIME",
    [Parameter(Mandatory)][string]$TargetUserSid
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this script from an elevated PowerShell session."
    }
}

Assert-Admin

$ownershipHelper = Join-Path $PSScriptRoot 'dual-product\rime-pime-ownership.ps1'
if (-not (Test-Path -LiteralPath $ownershipHelper -PathType Leaf)) { throw 'Required Rime/PIME ownership helper is unavailable.' }
. $ownershipHelper
$TargetUserSid = Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit

. (Join-Path $PSScriptRoot "pime-registry-cleanup.ps1")

$stopScript = Join-Path $PSScriptRoot "dev-stop-pime.ps1"
if (Test-Path -LiteralPath $stopScript) {
    & $stopScript -InstallRoots @($InstallRoot) -TargetUserSid $TargetUserSid -Quiet
}

Reset-PIMETextServiceProfiles -InstallRoot $InstallRoot -TargetUserSid $TargetUserSid

Write-Host "Language profile registry cleanup completed."
Write-Host "Switch away from Yime, then switch back to refresh the input method list."
