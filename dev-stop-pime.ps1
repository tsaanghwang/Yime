$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "tools\dev-stop-pime.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing script: $scriptPath"
}

& $scriptPath @args
exit $LASTEXITCODE
