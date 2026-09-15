[CmdletBinding()]
param(
    [int]$Entries = 20000,
    [int]$Iterations = 1000,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$goBackend = Join-Path $repoRoot 'go-backend'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputRoot = Join-Path $repoRoot ".tmp\yimecore-experiment\e0\$stamp"
}
$outputDir = [System.IO.Path]::GetFullPath($OutputRoot)
$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
$allowedPrefix = $allowedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "E0 evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to resolve Git commit.'
}
$dirty = [bool]((& git -C $repoRoot status --porcelain).Count)

$testLog = Join-Path $outputDir 'go-test.txt'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/engineapi ./input_methods/yime/yimecore ./cmd/yimecore-experiment 2>&1 |
        Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) {
        throw "YimeCore E0 tests failed; see $testLog"
    }

    $benchmarkLog = Join-Path $outputDir 'go-benchmark.txt'
    & go test -run '^$' -bench '^BenchmarkSessionReplay$' -benchmem -benchtime=1s ./input_methods/yime/yimecore 2>&1 |
        Tee-Object -FilePath $benchmarkLog
    if ($LASTEXITCODE -ne 0) {
        throw "YimeCore E0 benchmark failed; see $benchmarkLog"
    }

    $manifest = Join-Path $outputDir 'manifest.json'
    $dirtyArgument = '-git-dirty=' + $dirty.ToString().ToLowerInvariant()
    & go run ./cmd/yimecore-experiment `
        -output $manifest `
        -entries $Entries `
        -iterations $Iterations `
        -git-commit $commit `
        $dirtyArgument
    if ($LASTEXITCODE -ne 0) {
        throw "YimeCore E0 experiment failed; see $manifest"
    }
}
finally {
    Pop-Location
}

$sourceFiles = @(
    'README.md',
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\engineapi\engine.go',
    'go-backend\input_methods\yime\yimecore\index.go',
    'go-backend\input_methods\yime\yimecore\engine.go',
    'go-backend\input_methods\yime\yimecore\engine_test.go',
    'go-backend\input_methods\yime\yimecore\dependency_boundary_test.go',
    'go-backend\input_methods\yime\yimecore_experiment_guard_test.go',
    'go-backend\cmd\yimecore-experiment\main.go',
    'tools\yimecore\run-e0-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $absolutePath = Join-Path $repoRoot $relativePath
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath
    [ordered]@{
        path = $relativePath.Replace('\', '/')
        sha256 = $hash.Hash.ToLowerInvariant()
    }
}
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $outputDir 'source-hashes.json') -Encoding utf8

Write-Host "YimeCore E0 evidence: $outputDir"
