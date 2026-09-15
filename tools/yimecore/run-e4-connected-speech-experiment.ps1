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
    $OutputRoot = Join-Path $allowedRoot ('e4b\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E4 evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

function Get-LowerSHA256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$lockPath = Join-Path $repoRoot 'tools\lexicon\data\yime_core_target.lock.json'
$targetLock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$lockedRoles = @(
    'full_mode_dictionary', 'variable_mode_dictionary', 'shorthand_mode_dictionary',
    'psc_neutral_tone_and_erhua_layer', 'explicit_erhua_layer',
    'third_tone_sandhi_layer', 'particle_a_sound_change_layer'
)
$lockChecks = @()
foreach ($role in $lockedRoles) {
    $artifact = $targetLock.artifacts | Where-Object role -eq $role | Select-Object -First 1
    if ($null -eq $artifact) { throw "Target lock lacks role $role" }
    $path = Join-Path $repoRoot ([string]$artifact.path).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Locked E4 artifact is missing: $path" }
    $actual = Get-LowerSHA256 $path
    $matched = $actual -eq ([string]$artifact.sha256).ToLowerInvariant()
    $lockChecks += [ordered]@{ role = $role; path = $artifact.path; expected_sha256 = $artifact.sha256; actual_sha256 = $actual; matched = $matched }
    if (-not $matched) { throw "Locked E4 artifact hash mismatch: $($artifact.path)" }
}

$manifests = @(
    'yime_psc_peripheral_manifest.json',
    'yime_erhua_mixed_manifest.json',
    'yime_third_tone_stage5c_manifest.json',
    'yime_particle_a_stage6d_manifest.json'
)
$manifestChecks = @()
foreach ($name in $manifests) {
    $manifestPath = Join-Path $dataRoot $name
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if (-not [bool]$manifest.summary.passed) { throw "Reviewed module manifest is not passed: $name" }
    foreach ($property in $manifest.output_sha256.PSObject.Properties) {
        $outputPath = Join-Path $dataRoot $property.Name
        if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw "Manifest output is missing: $($property.Name)" }
        $actual = Get-LowerSHA256 $outputPath
        $matched = $actual -eq ([string]$property.Value).ToLowerInvariant()
        $manifestChecks += [ordered]@{ manifest = $name; path = $property.Name; expected_sha256 = $property.Value; actual_sha256 = $actual; matched = $matched }
        if (-not $matched) { throw "Reviewed module output hash mismatch: $($property.Name)" }
    }
}

$modes = @('full', 'variable', 'shorthand')
$importChecks = @()
foreach ($mode in $modes) {
    $sentencePath = Join-Path $dataRoot "yime_sentence_${mode}.dict.yaml"
    $actualImports = @(Get-Content -LiteralPath $sentencePath | Where-Object { $_ -match '^\s+-\s+' } | ForEach-Object { ($_ -replace '^\s+-\s+', '').Trim() })
    $expectedImports = @(
        "yime_$mode",
        "yime_psc_peripheral_sentence_$mode",
        "yime_erhua_mixed_sentence_$mode",
        "yime_third_tone_stage5c_$mode",
        "yime_particle_a_stage6d_$mode"
    )
    $matched = ($actualImports.Count -eq $expectedImports.Count) -and -not (Compare-Object $expectedImports $actualImports -SyncWindow 0)
    $importChecks += [ordered]@{ mode = $mode; path = "yime_sentence_${mode}.dict.yaml"; imports = $actualImports; matched = [bool]$matched }
    if (-not $matched) { throw "Unexpected E4 import closure for $mode" }
}

$testLog = Join-Path $outputDir 'go-test.txt'
$rimeTestLog = Join-Path $outputDir 'real-rime-connected-speech.txt'
$binDir = Join-Path $outputDir 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$indexTool = Join-Path $binDir 'yimecore-index.exe'
$bundleTool = Join-Path $binDir 'yimecore-bundle-experiment.exe'
$rimeCompareTool = Join-Path $binDir 'yimecore-rime-compare.exe'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimecore ./cmd/yimecore-bundle-experiment 2>&1 | Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E4 YimeCore tests failed; see $testLog" }
    & go build -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -o $bundleTool ./cmd/yimecore-bundle-experiment
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-bundle-experiment.' }
    & go build -o $rimeCompareTool ./cmd/yimecore-rime-compare
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-rime-compare.' }

    $previousRealRime = $env:YIME_RUN_REAL_RIME_TESTS
    $env:YIME_RUN_REAL_RIME_TESTS = '1'
    try {
        & go test -v ./input_methods/yime -run '^(TestRealRimeExplicitErhuaMixedRoutesAcrossAllThreeSchemas|TestRealRimeParticleAStage6DDualTrackAcrossAllThreeSchemas|TestRealRimePSCPeripheralAcrossAllThreeSchemas)$' -count=1 2>&1 |
            Tee-Object -FilePath $rimeTestLog
        if ($LASTEXITCODE -ne 0) { throw "Real Rime connected-speech observation failed; see $rimeTestLog" }
    }
    finally {
        if ($null -eq $previousRealRime) { Remove-Item Env:YIME_RUN_REAL_RIME_TESTS -ErrorAction SilentlyContinue }
        else { $env:YIME_RUN_REAL_RIME_TESTS = $previousRealRime }
    }
}
finally {
    Pop-Location
}

$probePath = Join-Path $goBackend 'input_methods\yime\yimecore\testdata\e4_reviewed_alias_probes.json'
$definitions = @(
    [ordered]@{ mode = 'full'; core = 'yime_full.dict.yaml' },
    [ordered]@{ mode = 'variable'; core = 'yime_variable.dict.yaml' },
    [ordered]@{ mode = 'shorthand'; core = 'yime_shorthand.dict.yaml' }
)
$modeResults = @()
foreach ($definition in $definitions) {
    $mode = $definition.mode
    $indexDir = Join-Path $outputDir "indexes\$mode"
    New-Item -ItemType Directory -Force -Path $indexDir | Out-Null
    $sources = [ordered]@{
        core = $definition.core
        'psc-peripheral' = "yime_psc_peripheral_sentence_${mode}.dict.yaml"
        'explicit-erhua' = "yime_erhua_mixed_sentence_${mode}.dict.yaml"
        'third-tone-stage5c' = "yime_third_tone_stage5c_${mode}.dict.yaml"
        'particle-a-stage6d' = "yime_particle_a_stage6d_${mode}.dict.yaml"
    }
    $indexes = [ordered]@{}
    $buildEvidence = [ordered]@{}
    foreach ($entry in $sources.GetEnumerator()) {
        $id = [string]$entry.Key
        $source = Join-Path $dataRoot ([string]$entry.Value)
        $indexPath = Join-Path $indexDir "$id.yidx"
        $buildPath = Join-Path $indexDir "$id-build.json"
        & $indexTool -mode $mode -source $source -output $indexPath -manifest $buildPath `
            -allowed-source-root $dataRoot -allowed-output-root $outputDir
        if ($LASTEXITCODE -ne 0) { throw "Index build failed for $mode/$id" }
        $indexes[$id] = $indexPath
        $buildEvidence[$id] = Get-Content -LiteralPath $buildPath -Raw | ConvertFrom-Json
    }
    $bundlePath = Join-Path $outputDir "bundle-$mode.json"
    $arguments = @('-mode', $mode, '-core-index', $indexes.core, '-probes', $probePath, '-output', $bundlePath, '-iterations', $Iterations)
    foreach ($id in @('psc-peripheral', 'explicit-erhua', 'third-tone-stage5c', 'particle-a-stage6d')) {
        $arguments += @('-module', "$id=$($indexes[$id])")
    }
    & $bundleTool @arguments
    if ($LASTEXITCODE -ne 0) { throw "E4 bundle experiment failed for $mode" }
    $bundle = Get-Content -LiteralPath $bundlePath -Raw | ConvertFrom-Json
    $modeResults += [ordered]@{
        mode = $mode
        bundle_evidence = $bundlePath
        bundle_source_id = $bundle.bundle_source_id
        builds = $buildEvidence
        checks = $bundle.checks
		coverage = $bundle.coverage
        latency = $bundle.latency
        process_memory = $bundle.process_memory
        passed = [bool]$bundle.passed
    }
}

$rimeRoot = Join-Path $goBackend 'input_methods\yime'
$previousPath = $env:PATH
$rimeEvidence = @()
try {
    $env:PATH = "$rimeRoot;$env:PATH"
    foreach ($mode in $modes) {
        $path = Join-Path $outputDir "rime-$mode.json"
        & $rimeCompareTool -data-root $dataRoot -probes $probePath -output $path -iterations $Iterations -mode $mode
        if ($LASTEXITCODE -ne 0) { throw "Real Rime E4 probe comparison failed for $mode" }
        $report = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $rimeEvidence += [ordered]@{ mode = $mode; path = $path; report = $report.modes[0]; process_memory = $report.process_memory; passed = [bool]$report.passed }
    }
}
finally {
    $env:PATH = $previousPath
}

$comparisons = @()
foreach ($modeResult in $modeResults) {
    $rime = $rimeEvidence | Where-Object mode -eq $modeResult.mode | Select-Object -First 1
    $p95Ratio = [double]$modeResult.latency.p95_ns / [double]$rime.report.latency.p95_ns
    $p99Ratio = [double]$modeResult.latency.p99_ns / [double]$rime.report.latency.p99_ns
    $workingSetRatio = [double]$modeResult.process_memory.working_set_bytes / [double]$rime.process_memory.working_set_bytes
    $comparisons += [ordered]@{
        mode = $modeResult.mode
        yimecore_p95_ns = $modeResult.latency.p95_ns
        rime_p95_ns = $rime.report.latency.p95_ns
        p95_ratio_yimecore_over_rime = $p95Ratio
        yimecore_p99_ns = $modeResult.latency.p99_ns
        rime_p99_ns = $rime.report.latency.p99_ns
        p99_ratio_yimecore_over_rime = $p99Ratio
        yimecore_working_set_bytes = $modeResult.process_memory.working_set_bytes
        rime_working_set_bytes = $rime.process_memory.working_set_bytes
        working_set_ratio_yimecore_over_rime = $workingSetRatio
        correctness_passed = [bool]$modeResult.passed -and [bool]$rime.passed
        latency_gate_passed = $p95Ratio -le 1.10 -and $p99Ratio -le 1.20
        memory_gate_passed = $workingSetRatio -le 1.20
    }
}

$summary = [ordered]@{
    tool_version = 'yimecore-e4b-connected-speech-bundle-experiment-v2'
    stage = 'e4b'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    source_boundary = $dataRoot
    output_boundary = $outputDir
    target_lock = [ordered]@{ path = $lockPath; lock_id = $targetLock.lock_id; checks = $lockChecks; passed = -not ($lockChecks.matched -contains $false) }
    module_manifest_checks = $manifestChecks
    import_closure_checks = $importChecks
    probe_path = $probePath
    probe_sha256 = Get-LowerSHA256 $probePath
    iterations = $Iterations
    modes = $modeResults
    rime_baselines = $rimeEvidence
    comparisons = $comparisons
    all_locked_hashes_verified = -not ($lockChecks.matched -contains $false) -and -not ($manifestChecks.matched -contains $false)
    all_import_closures_verified = -not ($importChecks.matched -contains $false)
    all_bundle_checks_passed = -not ($modeResults.passed -contains $false)
	all_full_coverage_checks_passed = -not ($modeResults.coverage.passed -contains $false)
    all_rime_checks_passed = -not ($rimeEvidence.passed -contains $false)
    all_latency_gates_passed = -not ($comparisons.latency_gate_passed -contains $false)
    all_memory_gates_passed = -not ($comparisons.memory_gate_passed -contains $false)
    limitations = @(
        'only existing reviewed PSC, explicit erhua, Stage5C and Stage6D dictionary records are indexed; no runtime rule inference',
        'module rollback is validated at immutable bundle construction; no production configuration switch exists yet',
        'contextual neutral-tone Stage3 research records and productive erhua remain excluded',
        'no cross-unknown-word-boundary rule, candidate-text rewrite, IPC or TSF change'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $summaryPath -Encoding utf8

$sourceFiles = @(
    'docs\project\MANDARIN_CONNECTED_SPEECH_PLAN.md',
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\engineapi\engine.go',
    'go-backend\input_methods\yime\yimecore\bundle.go',
    'go-backend\input_methods\yime\yimecore\bundle_test.go',
    'go-backend\input_methods\yime\yimecore\engine.go',
    'go-backend\input_methods\yime\yimecore\index.go',
	'go-backend\input_methods\yime\yimecore\indexfile.go',
    'go-backend\input_methods\yime\yimecore\sentence.go',
    'go-backend\input_methods\yime\yimecore\testdata\e4_reviewed_alias_probes.json',
    'go-backend\cmd\yimecore-bundle-experiment\main.go',
	'go-backend\cmd\yimecore-rime-compare\main_windows.go',
    'tools\yimecore\run-e4-connected-speech-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $absolutePath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) { throw "Missing experiment source: $absolutePath" }
    [ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = Get-LowerSHA256 $absolutePath }
}
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $outputDir 'source-hashes.json') -Encoding utf8

Write-Host "YimeCore E4-B evidence: $outputDir"
if (-not $summary.all_locked_hashes_verified -or -not $summary.all_import_closures_verified -or
    -not $summary.all_bundle_checks_passed -or -not $summary.all_full_coverage_checks_passed -or -not $summary.all_rime_checks_passed -or
    -not $summary.all_latency_gates_passed -or -not $summary.all_memory_gates_passed) {
    throw "One or more E4-B gates failed; see $summaryPath"
}
