[CmdletBinding()]
param(
    [ValidateRange(10, 500)][int]$Selections = 30,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e5c\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E5-C evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$testLog = Join-Path $outputDir 'go-test.txt'
$binDir = Join-Path $outputDir 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$indexTool = Join-Path $binDir 'yimecore-index.exe'
$broker = Join-Path $binDir 'YimeBroker.exe'
$durabilityTool = Join-Path $binDir 'yimebroker-user-model-experiment.exe'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimecore ./input_methods/yime/yimebroker ./cmd/yimebroker ./cmd/yimebroker-user-model-experiment -count=1 2>&1 | Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E5-C tests failed; see $testLog" }
    & go test ./input_methods/yime -run '^TestNativeBackendKeepsRimeOwnedCandidatePaging$' -count=1 2>&1 | Tee-Object -FilePath $testLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Native paging ownership guard failed; see $testLog" }
    & go build -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -o $broker ./cmd/yimebroker
    if ($LASTEXITCODE -ne 0) { throw 'Could not build YimeBroker.' }
    & go build -o $durabilityTool ./cmd/yimebroker-user-model-experiment
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimebroker-user-model-experiment.' }
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

    $snapshotPath = Join-Path $outputDir "$mode-user-model.json"
    $journalPath = Join-Path $outputDir "$mode-user-model.journal"
    $evidencePath = Join-Path $outputDir "$mode-durability.json"
    & $durabilityTool -broker $broker -mode $mode -index $indexPath -snapshot $snapshotPath `
        -journal $journalPath -output $evidencePath -selections $Selections
    if ($LASTEXITCODE -ne 0) { throw "User-model durability experiment failed for $mode; see $evidencePath" }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $modeResults += [ordered]@{
        mode = $mode
        source_sha256 = $build.build.source_sha256
        index_sha256 = $build.build.index_sha256
        index_verified = [bool]$build.verified
        selected_text = $evidence.selected_text
        selections = $evidence.selections
        durable_select_latency = $evidence.durable_select_latency
        snapshot_absent_at_crash = [bool]$evidence.snapshot_absent_at_crash
        crash_detected = [bool]$evidence.crash_detected
        crash_recovery_ns = $evidence.crash_recovery_ns
        torn_tail_bytes = $evidence.torn_tail_bytes
        torn_tail_truncated = [bool]$evidence.torn_tail_truncated
        recovered_generation = $evidence.recovered_generation
        recovered_ranking_passed = [bool]$evidence.recovered_ranking_passed
        snapshot_sha256 = $evidence.snapshot_sha256
        journal_sha256 = $evidence.journal_sha256
        corruption_rejected = [bool]$evidence.corruption_rejected
        latency_gate_passed = [bool]$evidence.latency_gate_passed
        recovery_gate_passed = [bool]$evidence.recovery_gate_passed
        passed = [bool]$evidence.passed
        evidence_path = $evidencePath
    }
}

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\yimecore\engine.go',
    'go-backend\input_methods\yime\yimecore\usermodel.go',
    'go-backend\input_methods\yime\yimecore\usermodel_test.go',
    'go-backend\input_methods\yime\yimebroker\usermodel_store.go',
    'go-backend\input_methods\yime\yimebroker\usermodel_store_test.go',
    'go-backend\cmd\yimebroker\main.go',
    'go-backend\cmd\yimebroker-user-model-experiment\main.go',
    'go-backend\cmd\yimebroker-user-model-experiment\process_windows.go',
    'tools\yimecore\run-e5c-user-model-durability-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $absolutePath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) { throw "Missing experiment source: $absolutePath" }
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath
    [ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashesPath = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sourceHashesPath -Encoding utf8

$summary = [ordered]@{
    tool_version = 'yimebroker-e5c-user-model-acceptance-v1'
    stage = 'e5c'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    go_version = (& go version).Trim()
    os_arch = 'windows/' + $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant()
    source_boundary = $dataRoot
    output_boundary = $outputDir
    broker_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $broker).Hash.ToLowerInvariant()
    source_hashes_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHashesPath).Hash.ToLowerInvariant()
    selections_per_mode = $Selections
    durability = [ordered]@{
        journal = 'strict line JSON with source identity, monotonic generation, SHA-256 hash chain and fsync before selection response'
        snapshot = 'deterministic model payload with SHA-256 and same-directory atomic replace'
        recovery = 'validate complete chain, replay generations newer than snapshot, truncate only incomplete final record'
    }
    gates = [ordered]@{
        maximum_durable_select_p99_ms = 20.0
        maximum_single_durable_select_ms = 50.0
        maximum_crash_recovery_ms = 2000
    }
    modes = $modeResults
    all_indices_verified = -not ($modeResults.index_verified -contains $false)
    all_snapshot_absence_probes_passed = -not ($modeResults.snapshot_absent_at_crash -contains $false)
    all_torn_tails_truncated = -not ($modeResults.torn_tail_truncated -contains $false)
    all_generations_recovered = -not (($modeResults | Where-Object { $_.recovered_generation -ne $Selections }).Count)
    all_rankings_recovered = -not ($modeResults.recovered_ranking_passed -contains $false)
    all_corruption_rejected = -not ($modeResults.corruption_rejected -contains $false)
    all_latency_gates_passed = -not ($modeResults.latency_gate_passed -contains $false)
    all_recovery_gates_passed = -not ($modeResults.recovery_gate_passed -contains $false)
    native_rime_paging_ownership_preserved = $true
    limitations = @(
        'acknowledged selections are durable before response, but a crash after journal sync and before the response may retain one selection whose response outcome was unknown',
        'journal compaction and retention policy are not implemented; snapshots prevent replay cost growth but the append log remains for audit',
        'user-model source identity remains bound to the exact index identity; index migration is handled separately in E5-D',
        'production PIME, TSF and installed runtime remain unchanged'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host "YimeBroker E5-C evidence: $outputDir"
if (-not $summary.all_indices_verified -or -not $summary.all_snapshot_absence_probes_passed -or
    -not $summary.all_torn_tails_truncated -or -not $summary.all_generations_recovered -or
    -not $summary.all_rankings_recovered -or -not $summary.all_corruption_rejected -or
    -not $summary.all_latency_gates_passed -or -not $summary.all_recovery_gates_passed -or
    -not $summary.native_rime_paging_ownership_preserved) {
    throw "One or more E5-C gates failed; see $summaryPath"
}
