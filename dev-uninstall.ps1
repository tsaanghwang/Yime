param(
    [string]$InstallRoot = "C:\Program Files (x86)\PIME",
    [switch]$KeepInstallRoot
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "tools\dev-uninstall.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing script: $scriptPath"
}

& $scriptPath -InstallRoot $InstallRoot -KeepInstallRoot:$KeepInstallRoot
