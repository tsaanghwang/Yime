param([Parameter(Mandatory)][string]$BuildScript)

$ErrorActionPreference = 'Stop'
$processPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
Remove-Item Env:PATH -ErrorAction SilentlyContinue
$env:PATH = $processPath
. (Join-Path $PSScriptRoot 'initialize-dev-environment.ps1')
& (Join-Path $PSScriptRoot 'assert-win32-build-prerequisites.ps1') -RequireToolchain

& $BuildScript --sanitized
exit $LASTEXITCODE
