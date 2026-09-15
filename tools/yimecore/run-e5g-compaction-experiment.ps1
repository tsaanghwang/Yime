[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e5g\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E5-G evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$testLog = Join-Path $outputDir 'go-test.txt'
$binDir = Join-Path $outputDir 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$indexTool = Join-Path $binDir 'yimecore-index.exe'
$broker = Join-Path $binDir 'YimeBroker.exe'
$experiment = Join-Path $binDir 'yimebroker-compaction-experiment.exe'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimecore ./input_methods/yime/yimebroker ./cmd/yimebroker ./cmd/yimebroker-compaction-experiment -count=1 2>&1 | Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E5-G tests failed; see $testLog" }
    & go test ./input_methods/yime -run '^TestNativeBackendKeepsRimeOwnedCandidatePaging$' -count=1 2>&1 | Tee-Object -FilePath $testLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Native paging ownership guard failed; see $testLog" }
    & go build -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -o $broker ./cmd/yimebroker
    if ($LASTEXITCODE -ne 0) { throw 'Could not build YimeBroker.' }
    & go build -o $experiment ./cmd/yimebroker-compaction-experiment
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimebroker-compaction-experiment.' }
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
    $modeDir = Join-Path $outputDir $mode
    New-Item -ItemType Directory -Force -Path $modeDir | Out-Null
    $indexPath = Join-Path $modeDir 'index.yidx'
    $buildPath = Join-Path $modeDir 'index-build.json'
    & $indexTool -mode $mode -source (Join-Path $dataRoot $definition.source) -output $indexPath -manifest $buildPath `
        -allowed-source-root $dataRoot -allowed-output-root $outputDir
    if ($LASTEXITCODE -ne 0) { throw "Index build failed for $mode" }
    $build = Get-Content -LiteralPath $buildPath -Raw | ConvertFrom-Json
    $evidencePath = Join-Path $modeDir 'compaction.json'
    & $experiment -broker $broker -index $indexPath -mode $mode -work-root (Join-Path $modeDir 'stages') -output $evidencePath
    if ($LASTEXITCODE -ne 0) { throw "E5-G experiment failed for $mode; see $evidencePath" }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $modeResults += [ordered]@{
        mode = $mode
        source_sha256 = $build.build.source_sha256
        index_sha256 = $build.build.index_sha256
        index_verified = [bool]$build.verified
        selected_text = $evidence.selected_text
        stages = $evidence.stages
        all_stage_crashes_detected = -not ($evidence.stages.crash_detected -contains $false)
        all_rankings_recovered = -not ($evidence.stages.recovered_ranking_passed -contains $false)
        all_retries_idempotent = -not ($evidence.stages.recovered_retry_passed -contains $false)
        all_final_generations_exact = -not (($evidence.stages | Where-Object { $_.final_generation -ne 4 }).Count)
        all_journals_compacted = -not (($evidence.stages | Where-Object { $_.final_journal_bytes -ne 0 }).Count)
        all_v2_snapshots = -not (($evidence.stages | Where-Object { $_.snapshot_schema -ne 'yime-user-model-v2' }).Count)
        all_v1_rollbacks = -not (($evidence.stages | Where-Object { $_.rollback_schema -ne 'yime-user-model-v1' -or $_.rollback_generation -ne 0 }).Count)
        all_recoveries_within_limit = -not (($evidence.stages | Where-Object { $_.recovery_ns -gt 2000000000 }).Count)
        passed = [bool]$evidence.passed
        evidence_path = $evidencePath
    }
}

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\yimecore\usermodel.go',
    'go-backend\input_methods\yime\yimecore\usermodel_test.go',
    'go-backend\input_methods\yime\yimebroker\usermodel_store.go',
    'go-backend\input_methods\yime\yimebroker\usermodel_store_test.go',
    'go-backend\input_methods\yime\yimebroker\atomicreplace_windows.go',
    'go-backend\input_methods\yime\yimebroker\atomicreplace_other.go',
    'go-backend\cmd\yimebroker\main.go',
    'go-backend\cmd\yimebroker-compaction-experiment\main.go',
    'go-backend\cmd\yimebroker-compaction-experiment\process_windows.go',
    'go-backend\cmd\yimebroker-compaction-experiment\process_stub.go',
    'tools\yimecore\run-e5g-compaction-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot $relativePath)
    [ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashesPath = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sourceHashesPath -Encoding utf8

$summary = [ordered]@{
    tool_version = 'yimebroker-e5g-compaction-acceptance-v1'
    stage = 'e5g'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    go_version = (& go version).Trim()
    os_arch = 'windows/' + $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant()
    source_boundary = $dataRoot
    output_boundary = $outputDir
    broker_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $broker).Hash.ToLowerInvariant()
    experiment_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $experiment).Hash.ToLowerInvariant()
    source_hashes_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHashesPath).Hash.ToLowerInvariant()
    compaction_order = @('atomic v2 snapshot publication', 'close old journal', 'atomic empty journal replacement', 'reopen journal')
    crash_stages = @('after_snapshot', 'after_journal_close', 'after_journal_replace')
    modes = $modeResults
    all_indices_verified = -not ($modeResults.index_verified -contains $false)
    all_stage_crashes_detected = -not ($modeResults.all_stage_crashes_detected -contains $false)
    all_rankings_recovered = -not ($modeResults.all_rankings_recovered -contains $false)
    all_retries_idempotent = -not ($modeResults.all_retries_idempotent -contains $false)
    all_final_generations_exact = -not ($modeResults.all_final_generations_exact -contains $false)
    all_journals_compacted = -not ($modeResults.all_journals_compacted -contains $false)
    all_v2_snapshots = -not ($modeResults.all_v2_snapshots -contains $false)
    all_v1_rollbacks = -not ($modeResults.all_v1_rollbacks -contains $false)
    all_recoveries_within_limit = -not ($modeResults.all_recoveries_within_limit -contains $false)
    native_rime_paging_ownership_preserved = $true
    limitations = @(
        'automatic compaction bounds the WAL by the configured mutation interval; the idempotency request ledger remains bounded by the one-million-item model limit and is not age-pruned',
        'the v1 rollback snapshot represents the state immediately before first v2 migration; rolling back intentionally discards learning performed only after migration',
        'production transport, TSF, installed runtime and default Rime factory remain unchanged'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host "YimeBroker E5-G evidence: $outputDir"
if (-not $summary.all_indices_verified -or -not $summary.all_stage_crashes_detected -or
    -not $summary.all_rankings_recovered -or -not $summary.all_retries_idempotent -or
    -not $summary.all_final_generations_exact -or -not $summary.all_journals_compacted -or
    -not $summary.all_v2_snapshots -or -not $summary.all_v1_rollbacks -or
    -not $summary.all_recoveries_within_limit -or -not $summary.native_rime_paging_ownership_preserved) {
    throw "One or more E5-G gates failed; see $summaryPath"
}
