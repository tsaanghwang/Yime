param(
    [string]$InstallRoot = "C:\Program Files (x86)\YIME"
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

. (Join-Path $PSScriptRoot "pime-registry-cleanup.ps1")

$stopScript = Join-Path $PSScriptRoot "dev-stop-pime.ps1"
if (Test-Path -LiteralPath $stopScript) {
    & $stopScript -InstallRoots @($InstallRoot) -Quiet
}

Reset-PIMETextServiceProfiles -InstallRoot $InstallRoot

Write-Host "Language profile registry cleanup completed."
Write-Host "Switch away from Yime, then switch back to refresh the input method list."
