param(
    [string]$OutputRoot,
    [ValidateRange(10, 1000)][int]$Iterations = 100
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e2b\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E2-B evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$testLog = Join-Path $outputDir 'go-test.txt'
$rimeLog = Join-Path $outputDir 'real-rime-segment-correction.txt'
$binDir = Join-Path $outputDir 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$indexTool = Join-Path $binDir 'yimecore-index.exe'
$segmentTool = Join-Path $binDir 'yimecore-segment-experiment.exe'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimecore ./cmd/yimecore-segment-experiment 2>&1 | Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E2-B tests failed; see $testLog" }
    & go test ./input_methods/yime -run '^TestNativeBackendKeepsRimeOwnedCandidatePaging$' -count=1 2>&1 | Tee-Object -FilePath $testLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Native paging ownership guard failed; see $testLog" }
    & go build -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -o $segmentTool ./cmd/yimecore-segment-experiment
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-segment-experiment.' }

    $previousRealRime = $env:YIME_RUN_REAL_RIME_TESTS
    $env:YIME_RUN_REAL_RIME_TESTS = '1'
    try {
        & go test -v ./input_methods/yime -run '^(TestRealRimeLongSessionSwitchesFirstMiddleAndFinalSegments|TestRealRimeMiddleSegmentCorrectionRestoresFullSentence)$' -count=1 2>&1 |
            Tee-Object -FilePath $rimeLog
        if ($LASTEXITCODE -ne 0) { throw "Real Rime segment-correction baseline failed; see $rimeLog" }
    }
    finally {
        if ($null -eq $previousRealRime) { Remove-Item Env:YIME_RUN_REAL_RIME_TESTS -ErrorAction SilentlyContinue }
        else { $env:YIME_RUN_REAL_RIME_TESTS = $previousRealRime }
    }
}
finally {
    Pop-Location
}

$probePath = Join-Path $goBackend 'input_methods\yime\yimecore\testdata\e2b_segment_probes.json'
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
    $evidencePath = Join-Path $outputDir "$mode-segment-correction.json"
    & $segmentTool -mode $mode -index $indexPath -probes $probePath -output $evidencePath -iterations $Iterations
    if ($LASTEXITCODE -ne 0) { throw "Segment-correction experiment failed for $mode" }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $modeResults += [ordered]@{
        mode = $mode
        source_sha256 = $build.build.source_sha256
        index_sha256 = $build.build.index_sha256
        index_verified = [bool]$build.verified
        workflow = $evidence.workflow
        latency = $evidence.latency
        process_memory = $evidence.process_memory
        evidence_path = $evidencePath
        passed = [bool]$evidence.passed
    }
}

$summary = [ordered]@{
    tool_version = 'yimecore-e2b-segment-correction-experiment-v1'
    stage = 'e2b'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    source_boundary = $dataRoot
    output_boundary = $outputDir
    probe_path = $probePath
    probe_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $probePath).Hash.ToLowerInvariant()
    iterations = $Iterations
    modes = $modeResults
    all_indices_verified = -not ($modeResults.index_verified -contains $false)
    all_segment_corrections_passed = -not ($modeResults.passed -contains $false)
    real_rime_segment_correction_passed = $true
    native_rime_paging_ownership_preserved = $true
    limitations = @(
        'host-neutral engine experiment only; existing PIME/TSF segment UI and production native backend are unchanged',
        'two-segment first/final replacement probe; longer middle-segment native behavior remains covered by the real-Rime baseline tests',
        'segment constraints are composition-local and are cleared when raw input is edited',
        'no matched YimeCore/Rime latency ratio is claimed; the 50 ms ceiling covers the complete two-correction workflow only',
        'no IPC, Broker scheduling, crash recovery or installation switch'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $summaryPath -Encoding utf8

$sourceFiles = @(
    'docs\project\SENTENCE_SEGMENT_CORRECTION_FEASIBILITY.md',
    'docs\project\SENTENCE_SEGMENT_CORRECTION_TEST_PLAN.md',
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\engineapi\engine.go',
    'go-backend\input_methods\yime\yimecore\engine.go',
    'go-backend\input_methods\yime\yimecore\sentence.go',
    'go-backend\input_methods\yime\yimecore\segment_correction_test.go',
    'go-backend\input_methods\yime\yimecore\testdata\e2b_segment_probes.json',
    'go-backend\cmd\yimecore-segment-experiment\main.go',
    'tools\yimecore\run-e2b-segment-correction-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $absolutePath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) { throw "Missing experiment source: $absolutePath" }
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath
    [ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $outputDir 'source-hashes.json') -Encoding utf8

Write-Host "YimeCore E2-B evidence: $outputDir"
if (-not $summary.all_indices_verified -or -not $summary.all_segment_corrections_passed -or
    -not $summary.real_rime_segment_correction_passed -or -not $summary.native_rime_paging_ownership_preserved) {
    throw "One or more E2-B gates failed; see $summaryPath"
}
