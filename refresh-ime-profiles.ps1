param(
    [string]$InstallRoot = "C:\Program Files (x86)\YIME"
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "tools\refresh-ime-profiles.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing script: $scriptPath"
}

& $scriptPath -InstallRoot $InstallRoot
