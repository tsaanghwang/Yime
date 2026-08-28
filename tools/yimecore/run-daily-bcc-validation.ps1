[CmdletBinding()]
param(
    [string]$Python,
    [string]$Go = 'go',
    [string]$SourceDatabase,
    [string]$InputModelDatabase,
    [string]$IndexRoot,
    [string]$OutputRoot,
    [string]$Seed,
    [int]$SampleLimit = 20,
    [int]$ScanLimit = 5000,
    [int]$MinimumTargetLength = 3,
    [int]$MaximumTargetLength = 12,
    [int]$MaximumStructuralAlternatives = 128,
    [int]$MaximumPathsPerTarget = 256,
    [switch]$FailOnMismatch
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$utf8NoBom = New-Object Text.UTF8Encoding($false)

if ([string]::IsNullOrWhiteSpace($Python)) {
    $Python = Join-Path $repoRoot '.venv\Scripts\python.exe'
}
if ([string]::IsNullOrWhiteSpace($SourceDatabase)) {
    $SourceDatabase = Join-Path $repoRoot '.generated\lexicon_source_bundle\source_lexicon.sqlite3'
}
if ([string]::IsNullOrWhiteSpace($InputModelDatabase)) {
    $InputModelDatabase = Join-Path $repoRoot '.generated\input_candidate_model\input_model.sqlite3'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot '.generated\bcc_daily_validation'
}
if ([string]::IsNullOrWhiteSpace($Seed)) {
    $Seed = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
}

function Test-IndexRoot([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }
    foreach ($mode in @('full', 'variable', 'shorthand')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path ($mode + '.yidx')) -PathType Leaf)) {
            return $false
        }
    }
    return $true
}

if ([string]::IsNullOrWhiteSpace($IndexRoot) -and -not [string]::IsNullOrWhiteSpace($env:YIMECORE_INDEX_ROOT)) {
    $IndexRoot = $env:YIMECORE_INDEX_ROOT
}
if ([string]::IsNullOrWhiteSpace($IndexRoot)) {
    $productRoot = Join-Path $env:ProgramFiles 'YimeCore Experimental Trial'
    if (Test-Path -LiteralPath $productRoot -PathType Container) {
        $IndexRoot = Get-ChildItem -LiteralPath $productRoot -Directory -Force |
            Sort-Object LastWriteTimeUtc -Descending |
            ForEach-Object { Join-Path $_.FullName 'indexes' } |
            Where-Object { Test-IndexRoot $_ } |
            Select-Object -First 1
    }
}

if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
    throw "Python executable not found: $Python"
}
foreach ($database in @($SourceDatabase, $InputModelDatabase)) {
    if (-not (Test-Path -LiteralPath $database -PathType Leaf)) {
        throw "required database not found: $database"
    }
}
if (-not (Test-IndexRoot $IndexRoot)) {
    throw 'A directory containing full.yidx, variable.yidx, and shorthand.yidx is required via -IndexRoot or YIMECORE_INDEX_ROOT.'
}

$seedBytes = [Text.Encoding]::UTF8.GetBytes($Seed)
$hasher = [Security.Cryptography.SHA256]::Create()
try {
    $seedHash = ([BitConverter]::ToString($hasher.ComputeHash($seedBytes))).Replace('-', '').ToLowerInvariant().Substring(0, 12)
} finally {
    $hasher.Dispose()
}
$runDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
$runRoot = Join-Path (Join-Path $OutputRoot $runDate) ('seed-' + $seedHash)
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$validator = Join-Path $repoRoot 'tools\validate_bcc_composition_paths.py'
$validatorArguments = @(
    $validator,
    '--source-database', [IO.Path]::GetFullPath($SourceDatabase),
    '--input-model-database', [IO.Path]::GetFullPath($InputModelDatabase),
    '--output-dir', $runRoot,
    '--seed', $Seed,
    '--sample-limit', $SampleLimit,
    '--scan-limit', $ScanLimit,
    '--minimum-target-length', $MinimumTargetLength,
    '--maximum-target-length', $MaximumTargetLength,
    '--maximum-structural-alternatives', $MaximumStructuralAlternatives,
    '--maximum-paths-per-target', $MaximumPathsPerTarget
)
& $Python @validatorArguments
if ($LASTEXITCODE -ne 0) {
    throw "offline BCC path validation failed with exit code $LASTEXITCODE"
}

$pathsPath = Join-Path $runRoot 'composition_input_paths.json'
$replayPath = Join-Path $runRoot 'yimecore_replay.json'
$goBackend = Join-Path $repoRoot 'go-backend'
Push-Location $goBackend
try {
    & $Go run ./cmd/yimecore-bcc-replay -index-root ([IO.Path]::GetFullPath($IndexRoot)) -paths $pathsPath -output $replayPath
    if ($LASTEXITCODE -ne 0) {
        throw "YimeCore BCC replay failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$offline = Get-Content -LiteralPath $pathsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$offlineManifestPath = Join-Path $runRoot 'manifest.json'
$offlineManifest = Get-Content -LiteralPath $offlineManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$replay = Get-Content -LiteralPath $replayPath -Raw -Encoding UTF8 | ConvertFrom-Json
$failureRows = New-Object Collections.Generic.List[object]
foreach ($skipped in $offline.skipped) {
    $failureRows.Add([pscustomobject]@{
        phase = 'offline'
        text = [string]$skipped.text
        mode = ''
        blocking = $true
        reason = [string]$skipped.reason
        numeric_component_input = ''
        input = ''
        actual_sentence = ''
        error = [string]$skipped.error
    })
}
foreach ($target in $replay.targets) {
    foreach ($mode in $target.modes) {
        foreach ($attempt in $mode.attempts) {
            if ([string]::IsNullOrWhiteSpace([string]$attempt.failure)) { continue }
            $failureRows.Add([pscustomobject]@{
                phase = 'runtime'
                text = [string]$target.text
                mode = [string]$mode.mode
                blocking = -not [bool]$mode.runtime_direct_output_success
                reason = [string]$attempt.failure
                diagnosis = [string]$attempt.diagnosis
                numeric_component_input = [string]$attempt.numeric_component_input
                input = [string]$attempt.input
                actual_sentence = [string]$attempt.actual_sentence
                error = [string]$attempt.error
            })
        }
    }
}

function ConvertTo-TsvField([object]$Value) {
    return ([string]$Value).Replace("`t", ' ').Replace("`r", ' ').Replace("`n", ' ')
}

$failurePath = Join-Path $runRoot 'failures.tsv'
$failureLines = New-Object Collections.Generic.List[string]
$failureLines.Add("phase`ttext`tmode`tblocking`treason`tdiagnosis`tnumeric_component_input`tinput`tactual_sentence`terror")
foreach ($row in $failureRows) {
    $failureLines.Add((@(
        $row.phase,
        $row.text,
        $row.mode,
        $row.blocking,
        $row.reason,
        $row.diagnosis,
        $row.numeric_component_input,
        $row.input,
        $row.actual_sentence,
        $row.error
    ) | ForEach-Object { ConvertTo-TsvField $_ }) -join "`t")
}
[IO.File]::WriteAllText($failurePath, (($failureLines -join "`n") + "`n"), $utf8NoBom)

$failedTargets = @($replay.targets | Where-Object { -not $_.all_modes_direct_output_success }).Count
$diagnosisCounts = [ordered]@{}
foreach ($row in $failureRows) {
    if ($row.phase -ne 'runtime') { continue }
    $diagnosis = [string]$row.diagnosis
    if ([string]::IsNullOrWhiteSpace($diagnosis)) { $diagnosis = 'runtime_failure_unclassified' }
    if (-not $diagnosisCounts.Contains($diagnosis)) { $diagnosisCounts[$diagnosis] = 0 }
    $diagnosisCounts[$diagnosis] = [int]$diagnosisCounts[$diagnosis] + 1
}

$segmentLimitPressure = [ordered]@{
    attempts = 0
    spans = 0
    modes = [ordered]@{
        full = 0
        variable = 0
        shorthand = 0
    }
}
foreach ($target in $replay.targets) {
    foreach ($mode in $target.modes) {
        foreach ($attempt in $mode.attempts) {
            $pressures = @($attempt.segment_limit_pressure)
            if ($pressures.Count -eq 0) { continue }
            $segmentLimitPressure.attempts++
            $segmentLimitPressure.spans += $pressures.Count
            $modeName = [string]$mode.mode
            if ($segmentLimitPressure.modes.Contains($modeName)) {
                $segmentLimitPressure.modes[$modeName] += $pressures.Count
            }
        }
    }
}

$modeResults = [ordered]@{}
foreach ($modeName in @('full', 'variable', 'shorthand')) {
    $passed = 0
    $estimatedCorrectable = 0
    foreach ($target in $replay.targets) {
        $mode = @($target.modes | Where-Object { $_.mode -eq $modeName } | Select-Object -First 1)
        if ($mode.Count -gt 0) {
            if ([bool]$mode[0].runtime_direct_output_success) { $passed++ }
            if ([bool]$mode[0].estimated_correctable_within_top_n) { $estimatedCorrectable++ }
        }
    }
    $total = @($replay.targets).Count
    $failed = $total - $passed
    $modeResults[$modeName] = [ordered]@{
        total = $total
        passed = $passed
        failed = $failed
        failure_rate = if ($total -eq 0) { 0.0 } else { [Math]::Round($failed / [double]$total, 4) }
        estimated_correctable_within_top_n = $estimatedCorrectable
        estimated_correctable_rate = if ($total -eq 0) { 0.0 } else { [Math]::Round($estimatedCorrectable / [double]$total, 4) }
    }
}

$developerAlerts = New-Object Collections.Generic.List[object]
function Add-DeveloperAlert([string]$Severity, [string]$Code, [int]$Count, [string]$Message, [string]$Action) {
    $developerAlerts.Add([pscustomobject][ordered]@{
        severity = $Severity
        code = $Code
        count = $Count
        message = $Message
        suggested_action = $Action
    })
}
if ([int]$offlineManifest.counts.skipped -gt 0) {
    Add-DeveloperAlert 'critical' 'offline_path_generation_failed' ([int]$offlineManifest.counts.skipped) `
        'Sampled targets could not be converted into reviewed formal composition paths.' `
        'Inspect failures.tsv and repair source readings or formal decomposition rules; never handwrite an encoding.'
}
$diagnosisGuidance = [ordered]@{
    runtime_index_graph_missing_target_path = @('warning', 'Runtime indexes do not contain a complete target path.', 'Inspect index coverage and reviewed lexicon generation; do not import the BCC target as a candidate.')
    runtime_beam_pruned_target_path = @('warning', 'A complete target path exists but was pruned by the production beam.', 'Inspect competing retained paths and beam pressure before changing any beam limit.')
    runtime_ranking_preferred_other_sentence = @('warning', 'The target path survived the beam but lost final ranking.', 'Review static frequency evidence and explicit correction learning; evaluate the optional reranker only on held-out data.')
    input_path_invalid = @('critical', 'A generated composition input was rejected by the runtime.', 'Compare the offline path artifact with runtime alphabet and mode projection validation.')
    runtime_failure_unclassified = @('warning', 'A runtime failure has no structured diagnosis.', 'Inspect yimecore_replay.json and add a diagnostic classification before changing ranking logic.')
}
foreach ($diagnosis in $diagnosisCounts.Keys) {
    if ($diagnosis -eq 'direct_output_success') { continue }
    $guidance = $diagnosisGuidance[$diagnosis]
    if ($null -eq $guidance) { $guidance = $diagnosisGuidance.runtime_failure_unclassified }
    Add-DeveloperAlert $guidance[0] $diagnosis ([int]$diagnosisCounts[$diagnosis]) $guidance[1] $guidance[2]
}
if ($segmentLimitPressure.spans -gt 0) {
    Add-DeveloperAlert 'warning' 'runtime_segment_candidate_limit_pressure' ([int]$segmentLimitPressure.spans) `
        ("The runtime omitted one or more exact records on {0} input spans across {1} replay attempts because the per-segment candidate limit is 64." -f $segmentLimitPressure.spans, $segmentLimitPressure.attempts) `
        'Inspect the reported attempt spans and target-path reachability before changing the limit; do not infer that every mismatch was caused by truncation.'
}
foreach ($modeName in $modeResults.Keys) {
    $modeResult = $modeResults[$modeName]
    if ($modeResult.failed -eq 0) { continue }
    $severity = if ($modeResult.failure_rate -ge 0.5) { 'critical' } else { 'warning' }
    Add-DeveloperAlert $severity ("mode_failure_rate_" + $modeName) ([int]$modeResult.failed) `
        ("Mode '{0}' failed direct output for {1:P1} of sampled targets." -f $modeName, $modeResult.failure_rate) `
        'Use diagnosis counts to choose index, beam, or ranking investigation; keep this sample evaluation-only.'
}
$alertStatus = if (@($developerAlerts | Where-Object { $_.severity -eq 'critical' }).Count -gt 0) {
    'critical'
} elseif ($developerAlerts.Count -gt 0) {
    'warning'
} else {
    'ok'
}
$alertsPath = Join-Path $runRoot 'developer_alerts.json'
$alertReport = [ordered]@{
    schema_version = 'yime-bcc-developer-alerts-v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    status = $alertStatus
    evaluation_only = $true
    diagnosis_counts = $diagnosisCounts
    segment_candidate_limit_pressure = $segmentLimitPressure
    modes = $modeResults
    alerts = $developerAlerts
}
[IO.File]::WriteAllText($alertsPath, (($alertReport | ConvertTo-Json -Depth 8) + "`n"), $utf8NoBom)

$summary = [ordered]@{
    schema_version = 'yime-bcc-daily-validation-summary-v2'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    run_date_utc = $runDate
    seed = $Seed
    seed_sha256_prefix = $seedHash
    run_root = $runRoot
    source_database = [IO.Path]::GetFullPath($SourceDatabase)
    input_model_database = [IO.Path]::GetFullPath($InputModelDatabase)
    index_root = [IO.Path]::GetFullPath($IndexRoot)
    input_databases_unchanged = [bool]$offlineManifest.input_databases_unchanged
    offline = [ordered]@{
        samples = [int]$offlineManifest.counts.samples
        paths = [int]$offlineManifest.counts.paths
        skipped = [int]$offlineManifest.counts.skipped
    }
    runtime = [ordered]@{
        targets = @($replay.targets).Count
        passed_targets = @($replay.targets).Count - $failedTargets
        failed_targets = $failedTargets
        all_targets_passed = [bool]$replay.passed
        diagnosis_counts = $diagnosisCounts
        segment_candidate_limit_pressure = $segmentLimitPressure
        modes = $modeResults
    }
    developer_alert_status = $alertStatus
    developer_alert_count = $developerAlerts.Count
    failure_rows = $failureRows.Count
    blocking_failure_rows = @($failureRows | Where-Object { $_.blocking }).Count
    alternate_path_failure_rows = @($failureRows | Where-Object { -not $_.blocking }).Count
    artifacts = [ordered]@{
        offline_manifest = $offlineManifestPath
        component_paths = $pathsPath
        runtime_replay = $replayPath
        failures_tsv = $failurePath
        developer_alerts = $alertsPath
    }
    semantics = [ordered]@{
        bcc_is_frequency_evidence_only = $true
        offline_path_reachability_is_not_runtime_success = $true
        runtime_or_user_candidate_imported = $false
        user_model_attached = $false
        evaluation_targets_used_for_training = $false
    }
}
$summaryPath = Join-Path $runRoot 'daily_summary.json'
[IO.File]::WriteAllText($summaryPath, (($summary | ConvertTo-Json -Depth 8) + "`n"), $utf8NoBom)
Write-Host "Daily BCC validation: samples=$($summary.offline.samples) paths=$($summary.offline.paths) failed_targets=$failedTargets"
Write-Host "Summary: $summaryPath"
Write-Host "Failures: $failurePath"
Write-Host "Developer alerts: status=$alertStatus count=$($developerAlerts.Count) path=$alertsPath"

if ($FailOnMismatch -and -not $replay.passed) {
    exit 1
}
