param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$TimeoutMinutes = 20
)

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Real Rime integration tests require Windows.'
}

$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$goBackendRoot = Join-Path $repoRoot 'go-backend'
$rimeRoot = Join-Path $goBackendRoot 'input_methods\yime'
foreach ($requiredPath in @(
    (Join-Path $goBackendRoot 'go.mod'),
    (Join-Path $rimeRoot 'rime.dll'),
    (Join-Path $rimeRoot 'data\yime_variable.schema.yaml')
)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Real Rime test prerequisite was not found: $requiredPath"
    }
}

if (-not $env:GOCACHE) {
    $env:GOCACHE = Join-Path $repoRoot '.tmp\go-cache'
}
if (-not $env:GOTMPDIR) {
    $env:GOTMPDIR = Join-Path $repoRoot '.tmp\go-tmp'
}
New-Item -ItemType Directory -Path $env:GOCACHE, $env:GOTMPDIR -Force | Out-Null

$previousRealRime = $env:YIME_RUN_REAL_RIME_TESTS
$env:YIME_RUN_REAL_RIME_TESTS = '1'
Push-Location $goBackendRoot
try {
    & go test ./input_methods/yime -run '^TestRealRime' -count=1 -timeout "${TimeoutMinutes}m"
    if ($LASTEXITCODE -ne 0) {
        throw "Real Rime integration tests failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
    if ($null -eq $previousRealRime) {
        Remove-Item Env:YIME_RUN_REAL_RIME_TESTS -ErrorAction SilentlyContinue
    } else {
        $env:YIME_RUN_REAL_RIME_TESTS = $previousRealRime
    }
}

Write-Host 'Real Rime integration verification passed.'
