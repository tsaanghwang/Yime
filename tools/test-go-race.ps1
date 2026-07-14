[CmdletBinding()]
param(
    [string]$GccPath = 'C:\msys64\ucrt64\bin\gcc.exe',
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $root 'go-backend'
$cache = Join-Path $root '.tmp\gocache'
$temp = Join-Path $root '.tmp\go-tmp'

if (-not (Test-Path -LiteralPath $GccPath -PathType Leaf)) {
    throw "MSYS2 UCRT64 GCC was not found: $GccPath"
}

New-Item -ItemType Directory -Force -Path $cache, $temp | Out-Null
$env:CGO_ENABLED = '1'
$env:CC = $GccPath
$gccDir = Split-Path -Parent $GccPath
if (($env:PATH -split ';') -notcontains $gccDir) {
    $env:PATH = "$gccDir;$env:PATH"
}
$env:GOCACHE = $cache
$env:GOTMPDIR = $temp

Push-Location $backend
try {
    & go test -race ./... -timeout "${TimeoutSeconds}s"
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}
