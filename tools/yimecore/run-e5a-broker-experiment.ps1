[CmdletBinding()]
param(
    [ValidateRange(10, 1000)][int]$Iterations = 100,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e5a\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E5-A evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$testLog = Join-Path $outputDir 'go-test.txt'
$binDir = Join-Path $outputDir 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$indexTool = Join-Path $binDir 'yimecore-index.exe'
$brokerTool = Join-Path $binDir 'yimebroker-experiment.exe'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimebroker ./cmd/yimebroker-experiment -count=1 2>&1 | Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E5-A tests failed; see $testLog" }
    & go test ./input_methods/yime -run '^TestNativeBackendKeepsRimeOwnedCandidatePaging$' -count=1 2>&1 | Tee-Object -FilePath $testLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Native paging ownership guard failed; see $testLog" }
    & go build -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -o $brokerTool ./cmd/yimebroker-experiment
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimebroker-experiment.' }
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

    $evidencePath = Join-Path $outputDir "$mode-broker.json"
    & $brokerTool -mode $mode -index $indexPath -probes $probePath -output $evidencePath -iterations $Iterations
    if ($LASTEXITCODE -ne 0) { throw "Broker experiment failed for $mode; see $evidencePath" }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $modeResults += [ordered]@{
        mode = $mode
        source_sha256 = $build.build.source_sha256
        index_sha256 = $build.build.index_sha256
        index_verified = [bool]$build.verified
        direct_latency = $evidence.direct_latency
        broker_latency = $evidence.broker_latency
        broker_message_latency = $evidence.broker_message_latency
        p95_workflow_ratio = $evidence.p95_workflow_ratio
        p99_workflow_ratio = $evidence.p99_workflow_ratio
        direct_allocation = $evidence.direct_allocation
        broker_allocation = $evidence.broker_allocation
        process_memory = $evidence.process_memory
        robustness = $evidence.robustness
        correctness_passed = [bool]$evidence.correctness_passed
        latency_gate_passed = [bool]$evidence.latency_gate_passed
        allocation_gate_passed = [bool]$evidence.allocation_gate_passed
        session_cleanup_passed = [bool]$evidence.session_cleanup_passed
        passed = [bool]$evidence.passed
        evidence_path = $evidencePath
    }
}

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\engineapi\engine.go',
    'go-backend\input_methods\yime\yimebroker\protocol.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher_test.go',
    'go-backend\input_methods\yime\yimecore\testdata\e2_sentence_probes.json',
    'go-backend\cmd\yimebroker-experiment\main.go',
    'tools\yimecore\run-e5a-broker-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $absolutePath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) { throw "Missing experiment source: $absolutePath" }
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath
    [ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashesPath = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sourceHashesPath -Encoding utf8

$goVersion = (& go version).Trim()
$summary = [ordered]@{
    tool_version = 'yimebroker-e5a-acceptance-v1'
    stage = 'e5a'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    go_version = $goVersion
    os_arch = 'windows/' + $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant()
    source_boundary = $dataRoot
    output_boundary = $outputDir
    probe_path = $probePath
    probe_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $probePath).Hash.ToLowerInvariant()
    source_hashes_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHashesPath).Hash.ToLowerInvariant()
    iterations = $Iterations
    protocol = [ordered]@{
        version = 1
        max_message_bytes = 262144
        trusted_client_identity_out_of_band = $true
        maximum_sessions = 64
        maximum_sessions_per_client = 4
        operation_timeout_ms = 50
    }
    gates = [ordered]@{
        maximum_p95_workflow_ratio = 2.0
        maximum_p99_workflow_ratio = 2.5
        maximum_p95_message_ms = 2.0
        maximum_p99_message_ms = 5.0
        maximum_single_message_ms = 50.0
        maximum_incremental_allocation_bytes_per_message = 65536
    }
    modes = $modeResults
    all_indices_verified = -not ($modeResults.index_verified -contains $false)
    all_correctness_passed = -not ($modeResults.correctness_passed -contains $false)
    all_latency_gates_passed = -not ($modeResults.latency_gate_passed -contains $false)
    all_allocation_gates_passed = -not ($modeResults.allocation_gate_passed -contains $false)
    all_robustness_gates_passed = -not ($modeResults.robustness.all_passed -contains $false)
    all_sessions_cleaned_up = -not ($modeResults.session_cleanup_passed -contains $false)
    native_rime_paging_ownership_preserved = $true
    limitations = @(
        'in-process protocol experiment only; no named pipe, TSF, installed runtime or package switch',
        'logical timeout evicts the session but cannot kill a blocked in-process Go call; hard recovery requires a separate Broker process experiment',
        'no asynchronous user-model flush or crash-consistent Broker journal in this stage',
        'production server.exe, PIMELauncher and native Rime factory remain unchanged'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host "YimeBroker E5-A evidence: $outputDir"
if (-not $summary.all_indices_verified -or -not $summary.all_correctness_passed -or
    -not $summary.all_latency_gates_passed -or -not $summary.all_allocation_gates_passed -or
    -not $summary.all_robustness_gates_passed -or -not $summary.all_sessions_cleaned_up -or
    -not $summary.native_rime_paging_ownership_preserved) {
    throw "One or more E5-A gates failed; see $summaryPath"
}
