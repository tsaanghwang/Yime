param(
    [string]$RepoRoot = $PSScriptRoot,
    [string]$InstallRoot = "C:\Program Files (x86)\YIME",
    [Parameter(Mandatory)][string]$TargetUserSid
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "tools\dev-install.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing script: $scriptPath"
}

& $scriptPath -RepoRoot $RepoRoot -InstallRoot $InstallRoot -TargetUserSid $TargetUserSid
