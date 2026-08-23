[CmdletBinding()]
param(
    [int]$Iterations = 500,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e3\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E3 evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$testLog = Join-Path $outputDir 'go-test.txt'
$rimeLog = Join-Path $outputDir 'real-rime-forget.txt'
$binDir = Join-Path $outputDir 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$indexTool = Join-Path $binDir 'yimecore-index.exe'
$learningTool = Join-Path $binDir 'yimecore-learning-experiment.exe'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimecore ./cmd/yimecore-learning-experiment 2>&1 | Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E3 tests failed; see $testLog" }
    & go build -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -o $learningTool ./cmd/yimecore-learning-experiment
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-learning-experiment.' }

    $previousRealRime = $env:YIME_RUN_REAL_RIME_TESTS
    $env:YIME_RUN_REAL_RIME_TESTS = '1'
    try {
        & go test -v ./input_methods/yime -run '^(TestRealRimeQuickForgetAvailableInAllSchemas|TestRealRimeExplicitCandidateForgetAvailableInAllSchemas)$' -count=1 2>&1 |
            Tee-Object -FilePath $rimeLog
        if ($LASTEXITCODE -ne 0) { throw "Real Rime forget observation failed; see $rimeLog" }
    }
    finally {
        if ($null -eq $previousRealRime) {
            Remove-Item Env:YIME_RUN_REAL_RIME_TESTS -ErrorAction SilentlyContinue
        } else {
            $env:YIME_RUN_REAL_RIME_TESTS = $previousRealRime
        }
    }
}
finally {
    Pop-Location
}

$definitions = @(
    [ordered]@{ mode = 'full'; source = 'yime_full.dict.yaml' },
    [ordered]@{ mode = 'variable'; source = 'yime_variable.dict.yaml' },
    [ordered]@{ mode = 'shorthand'; source = 'yime_shorthand.dict.yaml' }
)
$modeResults = @()
foreach ($definition in $definitions) {
    $mode = $definition.mode
    $source = Join-Path $dataRoot $definition.source
    $indexPath = Join-Path $outputDir "$mode.yidx"
    $buildPath = Join-Path $outputDir "$mode-build.json"
    & $indexTool -mode $mode -source $source -output $indexPath -manifest $buildPath `
        -allowed-source-root $dataRoot -allowed-output-root $outputDir
    if ($LASTEXITCODE -ne 0) { throw "Index build failed for $mode" }
    $build = Get-Content -LiteralPath $buildPath -Raw | ConvertFrom-Json
    $modelPath = Join-Path $outputDir "$mode-user-model.json"
    $learningPath = Join-Path $outputDir "$mode-learning.json"
    & $learningTool -index $indexPath -mode $mode -model $modelPath -output $learningPath -iterations $Iterations
    if ($LASTEXITCODE -ne 0) { throw "Learning experiment failed for $mode" }
    $learning = Get-Content -LiteralPath $learningPath -Raw | ConvertFrom-Json
    $modeResults += [ordered]@{
        mode = $mode
        source_sha256 = $build.build.source_sha256
        index_sha256 = $build.build.index_sha256
        index_verified = [bool]$build.verified
        selected_text = $learning.selected_text
        learned_snapshot_sha256 = $learning.learned_snapshot_sha256
        promotion_passed = [bool]$learning.promotion_passed
        persistence_passed = [bool]$learning.persistence_passed
        forget_passed = [bool]$learning.forget_passed
        p95_overhead_ratio = $learning.p95_overhead_ratio
        p99_overhead_ratio = $learning.p99_overhead_ratio
        latency_gate_passed = [bool]$learning.latency_gate_passed
        passed = [bool]$learning.passed
    }
}

$summary = [ordered]@{
    tool_version = 'yimecore-e3a-learning-experiment-v1'
    stage = 'e3a'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    source_boundary = $dataRoot
    output_boundary = $outputDir
    iterations = $Iterations
    modes = $modeResults
    all_indices_verified = -not ($modeResults.index_verified -contains $false)
    all_promotions_passed = -not ($modeResults.promotion_passed -contains $false)
    all_persistence_passed = -not ($modeResults.persistence_passed -contains $false)
    all_forget_passed = -not ($modeResults.forget_passed -contains $false)
    all_latency_gates_passed = -not ($modeResults.latency_gate_passed -contains $false)
    real_rime_forget_observation_passed = $true
    limitations = @(
        'whole-candidate selection frequency only; contextual ranking remains E3-B',
        'explicit model flush only; Broker scheduling and crash recovery are not implemented',
        'no Rime userdb read, migration or mutation'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding utf8

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\engineapi\engine.go',
    'go-backend\input_methods\yime\yimecore\engine.go',
    'go-backend\input_methods\yime\yimecore\usermodel.go',
    'go-backend\input_methods\yime\yimecore\usermodel_test.go',
    'go-backend\input_methods\yime\yimecore\atomicreplace_windows.go',
    'go-backend\input_methods\yime\yimecore\atomicreplace_other.go',
    'go-backend\cmd\yimecore-learning-experiment\main.go',
    'tools\yimecore\run-e3-learning-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot $relativePath)
    [ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $outputDir 'source-hashes.json') -Encoding utf8

Write-Host "YimeCore E3-A evidence: $outputDir"
if (-not $summary.all_indices_verified -or -not $summary.all_promotions_passed -or
    -not $summary.all_persistence_passed -or -not $summary.all_forget_passed -or
    -not $summary.all_latency_gates_passed -or -not $summary.real_rime_forget_observation_passed) {
    throw "One or more E3-A gates failed; see $summaryPath"
}
