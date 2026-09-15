[CmdletBinding()]
param(
    [ValidateRange(10, 500)][int]$Iterations = 50,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e5b\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E5-B evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$testLog = Join-Path $outputDir 'go-test.txt'
$binDir = Join-Path $outputDir 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$indexTool = Join-Path $binDir 'yimecore-index.exe'
$broker = Join-Path $binDir 'YimeBroker.exe'
$processTool = Join-Path $binDir 'yimebroker-process-experiment.exe'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimebroker ./cmd/yimebroker ./cmd/yimebroker-process-experiment ./internal/processmemory -count=1 2>&1 | Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E5-B tests failed; see $testLog" }
    & go test ./input_methods/yime -run '^TestNativeBackendKeepsRimeOwnedCandidatePaging$' -count=1 2>&1 | Tee-Object -FilePath $testLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Native paging ownership guard failed; see $testLog" }
    & go build -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -o $broker ./cmd/yimebroker
    if ($LASTEXITCODE -ne 0) { throw 'Could not build YimeBroker.' }
    & go build -o $processTool ./cmd/yimebroker-process-experiment
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimebroker-process-experiment.' }
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

    $evidencePath = Join-Path $outputDir "$mode-process.json"
    & $processTool -broker $broker -mode $mode -index $indexPath -probes $probePath -output $evidencePath -iterations $Iterations
    if ($LASTEXITCODE -ne 0) { throw "Broker process experiment failed for $mode; see $evidencePath" }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $modeResults += [ordered]@{
        mode = $mode
        source_sha256 = $build.build.source_sha256
        index_sha256 = $build.build.index_sha256
        index_verified = [bool]$build.verified
        startup_latency_ns = $evidence.startup_latency_ns
        direct_latency = $evidence.direct_latency
        process_latency = $evidence.process_latency
        message_latency = $evidence.message_latency
        workflow_p95_ratio = $evidence.workflow_p95_ratio
        broker_process_memory = $evidence.broker_process_memory
        crash_recovery = $evidence.crash_recovery
        hang_recovery = $evidence.hang_recovery
        correctness_passed = [bool]$evidence.correctness_passed
        latency_gate_passed = [bool]$evidence.latency_gate_passed
        memory_gate_passed = [bool]$evidence.memory_gate_passed
        clean_shutdown_passed = [bool]$evidence.clean_shutdown_passed
        passed = [bool]$evidence.passed
        evidence_path = $evidencePath
    }
}

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\yimebroker\protocol.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher.go',
    'go-backend\input_methods\yime\yimebroker\stdio.go',
    'go-backend\input_methods\yime\yimebroker\stdio_test.go',
    'go-backend\internal\processmemory\processmemory_windows.go',
    'go-backend\cmd\yimebroker\main.go',
    'go-backend\cmd\yimebroker-process-experiment\main.go',
    'go-backend\cmd\yimebroker-process-experiment\process_windows.go',
    'go-backend\input_methods\yime\yimecore\testdata\e2_sentence_probes.json',
    'tools\yimecore\run-e5b-broker-process-experiment.ps1'
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
    tool_version = 'yimebroker-e5b-process-acceptance-v1'
    stage = 'e5b'
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
    source_hashes_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHashesPath).Hash.ToLowerInvariant()
    iterations = $Iterations
    transport = [ordered]@{
        framing = 'one strict JSON request and response per line over anonymous pipes'
        trusted_client_identity_out_of_band = $true
        supervisor_response_timeout_ms = 100
    }
    gates = [ordered]@{
        maximum_p95_workflow_ratio = 4.0
        maximum_p95_message_ms = 10.0
        maximum_p99_message_ms = 20.0
        maximum_single_message_ms = 50.0
        maximum_working_set_bytes = 134217728
        maximum_exit_or_hang_recovery_ms = 2000
    }
    modes = $modeResults
    all_indices_verified = -not ($modeResults.index_verified -contains $false)
    all_correctness_passed = -not ($modeResults.correctness_passed -contains $false)
    all_latency_gates_passed = -not ($modeResults.latency_gate_passed -contains $false)
    all_memory_gates_passed = -not ($modeResults.memory_gate_passed -contains $false)
    all_crash_recoveries_passed = -not ($modeResults.crash_recovery.passed -contains $false)
    all_hang_recoveries_passed = -not ($modeResults.hang_recovery.passed -contains $false)
    all_clean_shutdowns_passed = -not ($modeResults.clean_shutdown_passed -contains $false)
    native_rime_paging_ownership_preserved = $true
    limitations = @(
        'standalone anonymous-pipe process experiment only; no named-pipe identity adapter, TSF, installed runtime or package switch',
        'fault recovery opens a fresh session and replays the current trace; persisted user-model recovery is not implemented',
        'no production supervisor lifecycle, background startup registration or automatic index generation switch',
        'production server.exe, PIMELauncher and native Rime factory remain unchanged'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host "YimeBroker E5-B evidence: $outputDir"
if (-not $summary.all_indices_verified -or -not $summary.all_correctness_passed -or
    -not $summary.all_latency_gates_passed -or -not $summary.all_memory_gates_passed -or
    -not $summary.all_crash_recoveries_passed -or -not $summary.all_hang_recoveries_passed -or
    -not $summary.all_clean_shutdowns_passed -or -not $summary.native_rime_paging_ownership_preserved) {
    throw "One or more E5-B gates failed; see $summaryPath"
}
