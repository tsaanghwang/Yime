[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e5f\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E5-F evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$testLog = Join-Path $outputDir 'go-test.txt'
$binDir = Join-Path $outputDir 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$indexTool = Join-Path $binDir 'yimecore-index.exe'
$broker = Join-Path $binDir 'YimeBroker.exe'
$experiment = Join-Path $binDir 'yimebroker-idempotency-experiment.exe'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimecore ./input_methods/yime/yimebroker ./cmd/yimebroker ./cmd/yimebroker-idempotency-experiment -count=1 2>&1 | Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E5-F tests failed; see $testLog" }
    & go test ./input_methods/yime -run '^TestNativeBackendKeepsRimeOwnedCandidatePaging$' -count=1 2>&1 | Tee-Object -FilePath $testLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Native paging ownership guard failed; see $testLog" }
    & go build -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -o $broker ./cmd/yimebroker
    if ($LASTEXITCODE -ne 0) { throw 'Could not build YimeBroker.' }
    & go build -o $experiment ./cmd/yimebroker-idempotency-experiment
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimebroker-idempotency-experiment.' }
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
    $evidencePath = Join-Path $modeDir 'idempotency.json'
    & $experiment -broker $broker -index $indexPath -mode $mode -snapshot (Join-Path $modeDir 'model.json') `
        -journal (Join-Path $modeDir 'journal.log') -output $evidencePath
    if ($LASTEXITCODE -ne 0) { throw "E5-F experiment failed for $mode; see $evidencePath" }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $modeResults += [ordered]@{
        mode = $mode
        source_sha256 = $build.build.source_sha256
        index_sha256 = $build.build.index_sha256
        index_verified = [bool]$build.verified
        mutation_id = $evidence.mutation_id
        selected_text = $evidence.selected_text
        response_lost_after_persistence = [bool]$evidence.response_lost_after_persistence
        process_exit_detected = [bool]$evidence.process_exit_detected
        retry_commit_passed = [bool]$evidence.retry_commit_passed
        retry_echo_passed = [bool]$evidence.retry_echo_passed
        conflict_rejected = [bool]$evidence.conflict_rejected
        recovered_generation = [long]$evidence.recovered_generation
        single_mutation_passed = [bool]$evidence.single_mutation_passed
        recovery_ns = [long]$evidence.recovery_ns
        clean_shutdown_passed = [bool]$evidence.clean_shutdown_passed
        passed = [bool]$evidence.passed
        evidence_path = $evidencePath
    }
}

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\yimebroker\protocol.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher_test.go',
    'go-backend\input_methods\yime\yimebroker\index_manager.go',
    'go-backend\input_methods\yime\yimebroker\usermodel_store.go',
    'go-backend\input_methods\yime\yimebroker\usermodel_store_test.go',
    'go-backend\input_methods\yime\yimecore\engine.go',
    'go-backend\input_methods\yime\yimecore\usermodel.go',
    'go-backend\input_methods\yime\yimecore\usermodel_test.go',
    'go-backend\cmd\yimebroker\main.go',
    'go-backend\cmd\yimebroker-idempotency-experiment\main.go',
    'go-backend\cmd\yimebroker-idempotency-experiment\process_windows.go',
    'go-backend\cmd\yimebroker-idempotency-experiment\process_stub.go',
    'tools\yimecore\run-e5f-idempotency-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot $relativePath)
    [ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashesPath = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sourceHashesPath -Encoding utf8

$summary = [ordered]@{
    tool_version = 'yimebroker-e5f-idempotency-acceptance-v1'
    stage = 'e5f'
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
    maximum_recovery_ms = 2000
    modes = $modeResults
    all_indices_verified = -not ($modeResults.index_verified -contains $false)
    all_lost_response_windows_recovered = -not ($modeResults.retry_commit_passed -contains $false)
    all_retry_ids_echoed = -not ($modeResults.retry_echo_passed -contains $false)
    all_conflicts_rejected = -not ($modeResults.conflict_rejected -contains $false)
    all_generations_single = -not (($modeResults | Where-Object { $_.recovered_generation -ne 1 -or -not $_.single_mutation_passed }).Count)
    all_recoveries_within_limit = -not (($modeResults | Where-Object { $_.recovery_ns -gt 2000000000 }).Count)
    all_clean_shutdowns_passed = -not ($modeResults.clean_shutdown_passed -contains $false)
    native_rime_paging_ownership_preserved = $true
    limitations = @(
        'idempotency is active only when the caller supplies a globally unique mutation_id on select; legacy selects without it retain E5-C at-least-once semantics',
        'the durable request ledger is included in the user-model snapshot and remains bounded by the existing one-million-item model limit; retention and compaction policy remain a later maintenance item',
        'production transport, TSF, installed runtime and default Rime factory remain unchanged'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host "YimeBroker E5-F evidence: $outputDir"
if (-not $summary.all_indices_verified -or -not $summary.all_lost_response_windows_recovered -or
    -not $summary.all_retry_ids_echoed -or -not $summary.all_conflicts_rejected -or
    -not $summary.all_generations_single -or -not $summary.all_recoveries_within_limit -or
    -not $summary.all_clean_shutdowns_passed -or -not $summary.native_rime_paging_ownership_preserved) {
    throw "One or more E5-F gates failed; see $summaryPath"
}
