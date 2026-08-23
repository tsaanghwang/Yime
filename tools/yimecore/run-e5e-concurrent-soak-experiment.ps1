[CmdletBinding()]
param(
    [ValidateRange(30, 3600)][int]$DurationSeconds = 120,
    [ValidateRange(2, 16)][int]$BrokerProcesses = 4,
    [ValidateRange(2, 32)][int]$SharedClients = 8,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e5e\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E5-E evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$testLog = Join-Path $outputDir 'go-test.txt'
$binDir = Join-Path $outputDir 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$indexTool = Join-Path $binDir 'yimecore-index.exe'
$broker = Join-Path $binDir 'YimeBroker.exe'
$stressTool = Join-Path $binDir 'yimebroker-stress-experiment.exe'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimebroker ./cmd/yimebroker ./cmd/yimebroker-stress-experiment ./internal/processmemory -count=1 2>&1 | Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E5-E tests failed; see $testLog" }
    & go test ./input_methods/yime -run '^TestNativeBackendKeepsRimeOwnedCandidatePaging$' -count=1 2>&1 | Tee-Object -FilePath $testLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Native paging ownership guard failed; see $testLog" }
    & go build -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -o $broker ./cmd/yimebroker
    if ($LASTEXITCODE -ne 0) { throw 'Could not build YimeBroker.' }
    & go build -o $stressTool ./cmd/yimebroker-stress-experiment
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimebroker-stress-experiment.' }
}
finally {
    Pop-Location
}

$probePath = Join-Path $goBackend 'input_methods\yime\yimecore\testdata\e2_sentence_probes.json'
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
    $evidencePath = Join-Path $outputDir "$mode-soak.json"
    & $stressTool -broker $broker -index $indexPath -probes $probePath -mode $mode -output $evidencePath `
        -duration "${DurationSeconds}s" -processes $BrokerProcesses -clients $SharedClients
    if ($LASTEXITCODE -ne 0) { throw "E5-E concurrent soak failed for $mode; see $evidencePath" }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $modeResults += [ordered]@{
        mode = $mode
        source_sha256 = $build.build.source_sha256
        index_sha256 = $build.build.index_sha256
        index_verified = [bool]$build.verified
        concurrent_warmup_ns = [long]$evidence.concurrent_warmup_ns
        completed_requests = [long]$evidence.completed_requests
        completed_traces = [long]$evidence.completed_traces
        throughput_requests_per_second = [double]$evidence.throughput_requests_per_second
        latency_histogram_bucket_ns = [long]$evidence.latency_histogram_bucket_ns
        percentile_semantics = $evidence.percentile_semantics
        in_process_latency = $evidence.in_process_latency
        pipe_latency = $evidence.pipe_latency
        baseline_memory = $evidence.baseline_memory
        final_memory = $evidence.final_memory
        peak_memory = $evidence.peak_memory
        forced_recovery = $evidence.forced_recovery
        errors = [long]$evidence.errors
        incorrect_commits = [long]$evidence.incorrect_commits
        active_sessions_after_close = [int]$evidence.active_sessions_after_close
        clean_shutdowns = [bool]$evidence.clean_shutdowns
        correctness_passed = [bool]$evidence.correctness_passed
        latency_gate_passed = [bool]$evidence.latency_gate_passed
        throughput_gate_passed = [bool]$evidence.throughput_gate_passed
        memory_gate_passed = [bool]$evidence.memory_gate_passed
        duration_gate_passed = [bool]$evidence.duration_gate_passed
        recovery_gate_passed = [bool]$evidence.recovery_gate_passed
        passed = [bool]$evidence.passed
        evidence_path = $evidencePath
    }
}

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\yimebroker\protocol.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher.go',
    'go-backend\input_methods\yime\yimebroker\index_manager.go',
    'go-backend\cmd\yimebroker\main.go',
    'go-backend\cmd\yimebroker-stress-experiment\main.go',
    'go-backend\cmd\yimebroker-stress-experiment\main_test.go',
    'go-backend\cmd\yimebroker-stress-experiment\process_windows.go',
    'go-backend\cmd\yimebroker-stress-experiment\process_stub.go',
    'go-backend\input_methods\yime\yimecore\testdata\e2_sentence_probes.json',
    'go-backend\internal\processmemory\processmemory_windows.go',
    'tools\yimecore\run-e5e-concurrent-soak-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $absolutePath = Join-Path $repoRoot $relativePath
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath
    [ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashesPath = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sourceHashesPath -Encoding utf8

$summary = [ordered]@{
    tool_version = 'yimebroker-e5e-concurrent-soak-acceptance-v1'
    stage = 'e5e'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    go_version = (& go version).Trim()
    os_arch = 'windows/' + $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant()
    source_boundary = $dataRoot
    output_boundary = $outputDir
    probe_path = $probePath
    probe_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $probePath).Hash.ToLowerInvariant()
    broker_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $broker).Hash.ToLowerInvariant()
    stress_tool_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $stressTool).Hash.ToLowerInvariant()
    source_hashes_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHashesPath).Hash.ToLowerInvariant()
    duration_seconds_per_mode = $DurationSeconds
    standalone_broker_processes = $BrokerProcesses
    shared_dispatcher_clients = $SharedClients
    gates = [ordered]@{
        minimum_completed_requests_per_mode = 100000
        maximum_p95_message_ms = 10.0
        maximum_p99_message_ms = 20.0
        maximum_single_message_ms = 50.0
        minimum_total_throughput_requests_per_second = 500.0
        maximum_forced_recovery_ms = 2000
        maximum_working_set_bytes_per_actual_process_budget = 201326592
        maximum_warm_to_final_working_set_growth_bytes = 100663296
    }
    evidence_collection = [ordered]@{
        latency_histogram_bucket_ns = 10000
        percentile_values_are_conservative_bucket_upper_bounds = $true
        maximum_latency_is_exact = $true
        storage_is_bounded_independently_of_request_count = $true
    }
    modes = $modeResults
    all_indices_verified = -not ($modeResults.index_verified -contains $false)
    all_correctness_passed = -not ($modeResults.correctness_passed -contains $false)
    all_latency_gates_passed = -not ($modeResults.latency_gate_passed -contains $false)
    all_throughput_gates_passed = -not ($modeResults.throughput_gate_passed -contains $false)
    all_memory_gates_passed = -not ($modeResults.memory_gate_passed -contains $false)
    all_duration_gates_passed = -not ($modeResults.duration_gate_passed -contains $false)
    all_recovery_gates_passed = -not ($modeResults.recovery_gate_passed -contains $false)
    all_sessions_released = -not (($modeResults | Where-Object { $_.active_sessions_after_close -ne 0 }).Count)
    all_clean_shutdowns_passed = -not ($modeResults.clean_shutdowns -contains $false)
    native_rime_paging_ownership_preserved = $true
    limitations = @(
        'multi-client concurrency is exercised against one shared Dispatcher while standalone anonymous-pipe Broker processes each bind one out-of-band trusted identity',
        'this stage does not provide or validate the future production multi-connection named-pipe transport or TSF host lifecycle',
        'the forced recycle uses the same immutable index and replays one current probe; durable learning and index switching have separate E5-C and E5-D evidence',
        'production server.exe, PIMELauncher, native Rime factory and installed runtime remain unchanged'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host "YimeBroker E5-E evidence: $outputDir"
if (-not $summary.all_indices_verified -or -not $summary.all_correctness_passed -or
    -not $summary.all_latency_gates_passed -or -not $summary.all_throughput_gates_passed -or
    -not $summary.all_memory_gates_passed -or -not $summary.all_duration_gates_passed -or
    -not $summary.all_recovery_gates_passed -or -not $summary.all_sessions_released -or
    -not $summary.all_clean_shutdowns_passed -or -not $summary.native_rime_paging_ownership_preserved) {
    throw "One or more E5-E gates failed; see $summaryPath"
}
