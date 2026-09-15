[CmdletBinding()]
param(
    [int]$Iterations = 100,
    [string]$OutputRoot,
    [ValidateSet('e1', 'e2')]
    [string]$Stage = 'e1'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$probeName = if ($Stage -eq 'e2') { 'e2_sentence_probes.json' } else { 'e1_probes.json' }
$probePath = Join-Path $goBackend "input_methods\yime\yimecore\testdata\$probeName"
$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputRoot = Join-Path $allowedRoot "$Stage\$stamp"
}
$outputDir = [System.IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "E1 evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$testLog = Join-Path $outputDir 'go-test.txt'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimecore ./cmd/yimecore-index ./cmd/yimecore-index-bench ./cmd/yimecore-rime-compare 2>&1 |
        Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) {
        throw "YimeCore E1 tests failed; see $testLog"
    }

    $binDir = Join-Path $outputDir 'bin'
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    $indexTool = Join-Path $binDir 'yimecore-index.exe'
    $benchTool = Join-Path $binDir 'yimecore-index-bench.exe'
    $rimeCompareTool = Join-Path $binDir 'yimecore-rime-compare.exe'
    & go build -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -o $benchTool ./cmd/yimecore-index-bench
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index-bench.' }
    & go build -o $rimeCompareTool ./cmd/yimecore-rime-compare
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-rime-compare.' }
}
finally {
    Pop-Location
}

$modes = @(
    [ordered]@{ mode = 'full'; source = 'yime_full.dict.yaml' },
    [ordered]@{ mode = 'variable'; source = 'yime_variable.dict.yaml' },
    [ordered]@{ mode = 'shorthand'; source = 'yime_shorthand.dict.yaml' }
)
$modeResults = @()
foreach ($definition in $modes) {
    $mode = $definition.mode
    $source = Join-Path $dataRoot $definition.source
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing source dictionary: $source"
    }
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash.ToLowerInvariant()
    $buildHashes = @()
    $buildManifests = @()
    foreach ($run in @('a', 'b')) {
        $runDir = Join-Path $outputDir "build-$run"
        New-Item -ItemType Directory -Force -Path $runDir | Out-Null
        $indexPath = Join-Path $runDir "$mode.yidx"
        $manifestPath = Join-Path $runDir "$mode-build.json"
        & $indexTool `
            -mode $mode `
            -source $source `
            -output $indexPath `
            -manifest $manifestPath `
            -allowed-source-root $dataRoot `
            -allowed-output-root $outputDir
        if ($LASTEXITCODE -ne 0) {
            throw "Index build failed for $mode run $run"
        }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $fileHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $indexPath).Hash.ToLowerInvariant()
        if ($manifest.build.source_sha256 -ne $sourceHash) {
            throw "Source hash mismatch for $mode run $run"
        }
        if ($manifest.build.index_sha256 -ne $fileHash -or -not $manifest.verified) {
            throw "Index verification mismatch for $mode run $run"
        }
        $buildHashes += $fileHash
        $buildManifests += $manifest
    }
    $deterministic = $buildHashes[0] -eq $buildHashes[1]
    if (-not $deterministic) {
        throw "Consecutive index builds differ for $mode"
    }

    $benchPath = Join-Path $outputDir "$mode-query.json"
    & $benchTool `
        -index (Join-Path $outputDir "build-a\$mode.yidx") `
        -probes $probePath `
        -mode $mode `
        -iterations $Iterations `
        -output $benchPath
    if ($LASTEXITCODE -ne 0) {
        throw "Index query experiment failed for $mode"
    }
    $bench = Get-Content -LiteralPath $benchPath -Raw | ConvertFrom-Json
    $modeResults += [ordered]@{
        mode = $mode
        source_sha256 = $sourceHash
        index_sha256 = $buildHashes[0]
        deterministic = $deterministic
        parsed_records = $buildManifests[0].build.parsed_records
        indexed_records = $buildManifests[0].build.indexed_records
        duplicate_records = $buildManifests[0].build.duplicate_records
        index_bytes = $buildManifests[0].build.index_bytes
        build_elapsed_ns = $buildManifests[0].build.build_elapsed_ns
        peak_observed_heap_bytes = $buildManifests[0].build.peak_observed_heap_bytes
        open_elapsed_ns = $buildManifests[0].open_elapsed_ns
        query_passed = $bench.passed
        query_p50_ns = $bench.latency.p50_ns
        query_p95_ns = $bench.latency.p95_ns
        query_p99_ns = $bench.latency.p99_ns
        query_max_ns = $bench.latency.max_ns
        runtime_heap_delta_bytes = $bench.heap_delta_bytes
        runtime_working_set_bytes = $bench.process_memory.working_set_bytes
        runtime_private_bytes = $bench.process_memory.private_bytes
    }
}

$rimeRoot = Join-Path $goBackend 'input_methods\yime'
$previousPath = $env:PATH
$rimeEvidenceFiles = @()
$rimeModeEvidence = @()
try {
    $env:PATH = "$rimeRoot;$env:PATH"
    foreach ($definition in $modes) {
        $mode = $definition.mode
        $rimeEvidencePath = Join-Path $outputDir "rime-$mode.json"
        & $rimeCompareTool `
            -data-root $dataRoot `
            -probes $probePath `
            -output $rimeEvidencePath `
            -iterations $Iterations `
            -mode $mode
        if ($LASTEXITCODE -ne 0) {
            throw "Real Rime baseline comparison failed for $mode."
        }
        $rimeEvidence = Get-Content -LiteralPath $rimeEvidencePath -Raw | ConvertFrom-Json
        if (-not $rimeEvidence.passed -or $rimeEvidence.modes.Count -ne 1) {
            throw "Real Rime baseline evidence is incomplete for $mode."
        }
        $rimeEvidenceFiles += $rimeEvidencePath
        $rimeModeEvidence += [ordered]@{
            mode = $mode
            evidence_path = $rimeEvidencePath
            report = $rimeEvidence.modes[0]
            process_memory = $rimeEvidence.process_memory
        }
    }
}
finally {
    $env:PATH = $previousPath
}
$comparisons = @()
foreach ($modeResult in $modeResults) {
    $rimeEvidence = $rimeModeEvidence | Where-Object { $_.mode -eq $modeResult.mode } | Select-Object -First 1
    if ($null -eq $rimeEvidence) {
        throw "Missing Rime baseline for $($modeResult.mode)"
    }
    $rimeMode = $rimeEvidence.report
    $p95Ratio = [double]$modeResult.query_p95_ns / [double]$rimeMode.latency.p95_ns
    $p99Ratio = [double]$modeResult.query_p99_ns / [double]$rimeMode.latency.p99_ns
    $workingSetRatio = [double]$modeResult.runtime_working_set_bytes / [double]$rimeEvidence.process_memory.working_set_bytes
    $privateRatio = [double]$modeResult.runtime_private_bytes / [double]$rimeEvidence.process_memory.private_bytes
    $comparisons += [ordered]@{
        mode = $modeResult.mode
        yimecore_p50_ns = $modeResult.query_p50_ns
        yimecore_p95_ns = $modeResult.query_p95_ns
        yimecore_p99_ns = $modeResult.query_p99_ns
        rime_p50_ns = $rimeMode.latency.p50_ns
        rime_p95_ns = $rimeMode.latency.p95_ns
        rime_p99_ns = $rimeMode.latency.p99_ns
        p95_ratio_yimecore_over_rime = $p95Ratio
        p99_ratio_yimecore_over_rime = $p99Ratio
        yimecore_working_set_bytes = $modeResult.runtime_working_set_bytes
        rime_working_set_bytes = $rimeEvidence.process_memory.working_set_bytes
        working_set_ratio_yimecore_over_rime = $workingSetRatio
        yimecore_private_bytes = $modeResult.runtime_private_bytes
        rime_private_bytes = $rimeEvidence.process_memory.private_bytes
        private_ratio_yimecore_over_rime = $privateRatio
        correctness_passed = [bool]$modeResult.query_passed -and [bool]$rimeMode.passed
        latency_gate_passed = $p95Ratio -le 1.10 -and $p99Ratio -le 1.20
        memory_gate_passed = $workingSetRatio -le 1.20
    }
}

$summary = [ordered]@{
    tool_version = "yimecore-$Stage-index-experiment-v3"
    stage = $Stage
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    source_boundary = $dataRoot
    output_boundary = $outputDir
    probe_path = $probePath
    iterations = $Iterations
    modes = $modeResults
    rime_baselines = $rimeEvidenceFiles
    comparisons = $comparisons
    all_deterministic = -not ($modeResults.deterministic -contains $false)
    all_queries_passed = -not ($modeResults.query_passed -contains $false)
    all_rime_queries_passed = -not ($rimeModeEvidence.report.passed -contains $false)
    all_latency_gates_passed = -not ($comparisons.latency_gate_passed -contains $false)
    all_memory_gates_passed = -not ($comparisons.memory_gate_passed -contains $false)
    limitations = if ($Stage -eq 'e2') {
        @(
            'curated deterministic segmentation and generated-sentence probes only',
            'no language-model context, user learning, IPC or TSF',
            'working-set snapshots compare fresh per-mode command processes after the matched probe workload'
        )
    } else {
        @(
            'whole-word and prefix lookup only',
            'no learning, IPC or TSF',
            'working-set snapshots compare fresh per-mode command processes after the matched probe workload'
        )
    }
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding utf8

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\yimecore\index.go',
    'go-backend\input_methods\yime\yimecore\engine.go',
    'go-backend\input_methods\yime\yimecore\indexfile.go',
    'go-backend\input_methods\yime\yimecore\indexfile_test.go',
    'go-backend\input_methods\yime\yimecore\sentence.go',
    'go-backend\input_methods\yime\yimecore\sentence_test.go',
    'go-backend\input_methods\yime\yimecore\mappedfile_windows.go',
    'go-backend\input_methods\yime\yimecore\mappedfile_other.go',
    'go-backend\input_methods\yime\yimecore\testdata\e1_probes.json',
    'go-backend\input_methods\yime\yimecore\testdata\e2_sentence_probes.json',
    'go-backend\internal\processmemory\processmemory_windows.go',
    'go-backend\internal\processmemory\processmemory_stub.go',
    'go-backend\cmd\yimecore-index\main.go',
    'go-backend\cmd\yimecore-index-bench\main.go',
    'go-backend\cmd\yimecore-rime-compare\main_windows.go',
    'go-backend\cmd\yimecore-rime-compare\main_stub.go',
    'tools\yimecore\run-e1-index-experiment.ps1',
    'tools\yimecore\run-e2-sentence-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $absolutePath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        throw "Missing experiment evidence source: $absolutePath"
    }
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath
    [ordered]@{
        path = $relativePath.Replace('\', '/')
        sha256 = $hash.Hash.ToLowerInvariant()
    }
}
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $outputDir 'source-hashes.json') -Encoding utf8

Write-Host "YimeCore $Stage evidence: $outputDir"
if (-not $summary.all_deterministic -or
    -not $summary.all_queries_passed -or
    -not $summary.all_rime_queries_passed -or
    -not $summary.all_latency_gates_passed -or
    -not $summary.all_memory_gates_passed) {
    throw "One or more $Stage acceptance gates failed; see $summaryPath"
}
