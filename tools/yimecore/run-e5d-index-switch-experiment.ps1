[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e5d\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E5-D evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$testLog = Join-Path $outputDir 'go-test.txt'
$binDir = Join-Path $outputDir 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$indexTool = Join-Path $binDir 'yimecore-index.exe'
$broker = Join-Path $binDir 'YimeBroker.exe'
$switchTool = Join-Path $binDir 'yimebroker-index-switch-experiment.exe'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimebroker ./cmd/yimebroker ./cmd/yimebroker-index-switch-experiment -count=1 2>&1 | Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E5-D tests failed; see $testLog" }
    & go test ./input_methods/yime -run '^TestNativeBackendKeepsRimeOwnedCandidatePaging$' -count=1 2>&1 | Tee-Object -FilePath $testLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Native paging ownership guard failed; see $testLog" }
    & go build -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -o $broker ./cmd/yimebroker
    if ($LASTEXITCODE -ne 0) { throw 'Could not build YimeBroker.' }
    & go build -o $switchTool ./cmd/yimebroker-index-switch-experiment
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimebroker-index-switch-experiment.' }
}
finally {
    Pop-Location
}

$probePath = Join-Path $goBackend 'input_methods\yime\yimecore\testdata\e4_reviewed_alias_probes.json'
$probes = Get-Content -LiteralPath $probePath -Raw | ConvertFrom-Json
$definitions = @(
    [ordered]@{ mode = 'full'; initial = 'yime_full.dict.yaml'; candidate = 'yime_third_tone_stage5c_full.dict.yaml' },
    [ordered]@{ mode = 'variable'; initial = 'yime_variable.dict.yaml'; candidate = 'yime_third_tone_stage5c_variable.dict.yaml' },
    [ordered]@{ mode = 'shorthand'; initial = 'yime_shorthand.dict.yaml'; candidate = 'yime_third_tone_stage5c_shorthand.dict.yaml' }
)
$modeResults = @()
foreach ($definition in $definitions) {
    $mode = $definition.mode
    $modeDir = Join-Path $outputDir $mode
    New-Item -ItemType Directory -Force -Path $modeDir | Out-Null
    $initialIndex = Join-Path $modeDir 'initial.yidx'
    $candidateIndex = Join-Path $modeDir 'candidate.yidx'
    $initialBuildPath = Join-Path $modeDir 'initial-build.json'
    $candidateBuildPath = Join-Path $modeDir 'candidate-build.json'
    & $indexTool -mode $mode -source (Join-Path $dataRoot $definition.initial) -output $initialIndex -manifest $initialBuildPath `
        -allowed-source-root $dataRoot -allowed-output-root $outputDir
    if ($LASTEXITCODE -ne 0) { throw "Initial index build failed for $mode" }
    & $indexTool -mode $mode -source (Join-Path $dataRoot $definition.candidate) -output $candidateIndex -manifest $candidateBuildPath `
        -allowed-source-root $dataRoot -allowed-output-root $outputDir
    if ($LASTEXITCODE -ne 0) { throw "Candidate index build failed for $mode" }
    $initialBuild = Get-Content -LiteralPath $initialBuildPath -Raw | ConvertFrom-Json
    $candidateBuild = Get-Content -LiteralPath $candidateBuildPath -Raw | ConvertFrom-Json
    if ($initialBuild.build.index_sha256 -eq $candidateBuild.build.index_sha256) { throw "E5-D requires distinct index generations for $mode" }
    $probe = @($probes.modes.$mode | Where-Object { $_.module -eq 'third-tone-stage5c' })[0]
    if ($null -eq $probe) { throw "Missing reviewed third-tone candidate probe for $mode" }

    $manifest = Join-Path $modeDir 'control.json'
    $status = Join-Path $modeDir 'status.json'
    $evidencePath = Join-Path $modeDir 'switch.json'
    & $switchTool -broker $broker -initial-index $initialIndex -candidate-index $candidateIndex `
        -initial-sha256 $initialBuild.build.index_sha256 -candidate-sha256 $candidateBuild.build.index_sha256 `
        -probe-code $probe.code -probe-text $probe.text -mode $mode -manifest $manifest -status $status -output $evidencePath
    if ($LASTEXITCODE -ne 0) { throw "Index switch experiment failed for $mode; see $evidencePath" }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $modeResults += [ordered]@{
        mode = $mode
        initial_source_sha256 = $initialBuild.build.source_sha256
        initial_index_sha256 = $initialBuild.build.index_sha256
        candidate_source_sha256 = $candidateBuild.build.source_sha256
        candidate_index_sha256 = $candidateBuild.build.index_sha256
        initial_index_verified = [bool]$initialBuild.verified
        candidate_index_verified = [bool]$candidateBuild.verified
        candidate_probe_code = $evidence.candidate_probe_code
        candidate_probe_text = $evidence.candidate_probe_text
        rejected_switch = $evidence.rejected_switch
        valid_switch = $evidence.valid_switch
        rollback = $evidence.rollback
        old_session_survived_switch = [bool]$evidence.old_session_survived_switch
        new_session_used_candidate = [bool]$evidence.new_session_used_candidate
        candidate_probe_passed = [bool]$evidence.candidate_probe_passed
        candidate_session_survived_rollback = [bool]$evidence.candidate_session_survived_rollback
        post_rollback_session_used_initial = [bool]$evidence.post_rollback_session_used_initial
        clean_shutdown_passed = [bool]$evidence.clean_shutdown_passed
        passed = [bool]$evidence.passed
        evidence_path = $evidencePath
    }
}

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\input_methods\yime\yimebroker\protocol.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher.go',
    'go-backend\input_methods\yime\yimebroker\index_manager.go',
    'go-backend\input_methods\yime\yimebroker\index_manager_test.go',
    'go-backend\input_methods\yime\yimebroker\index_control.go',
    'go-backend\cmd\yimebroker\main.go',
    'go-backend\cmd\yimebroker-index-switch-experiment\main.go',
    'go-backend\cmd\yimebroker-index-switch-experiment\process_windows.go',
    'go-backend\input_methods\yime\yimecore\testdata\e4_reviewed_alias_probes.json',
    'tools\yimecore\run-e5d-index-switch-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $absolutePath = Join-Path $repoRoot $relativePath
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath
    [ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashesPath = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sourceHashesPath -Encoding utf8

$summary = [ordered]@{
    tool_version = 'yimebroker-e5d-index-switch-acceptance-v1'
    stage = 'e5d'
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
    modes = $modeResults
    all_initial_indices_verified = -not ($modeResults.initial_index_verified -contains $false)
    all_candidate_indices_verified = -not ($modeResults.candidate_index_verified -contains $false)
    all_invalid_switches_rejected = -not (($modeResults | Where-Object { $_.rejected_switch.status.accepted -ne $false -or $_.rejected_switch.status.manager.active_version -ne 'v1' }).Count)
    all_valid_switches_passed = -not ($modeResults.valid_switch.passed -contains $false)
    all_candidate_probes_passed = -not ($modeResults.candidate_probe_passed -contains $false)
    all_rollbacks_passed = -not ($modeResults.rollback.passed -contains $false)
    all_old_sessions_survived = -not ($modeResults.old_session_survived_switch -contains $false)
    all_candidate_sessions_survived_rollback = -not ($modeResults.candidate_session_survived_rollback -contains $false)
    all_clean_shutdowns_passed = -not ($modeResults.clean_shutdown_passed -contains $false)
    native_rime_paging_ownership_preserved = $true
    limitations = @(
        'the candidate generation is a reviewed third-tone overlay index used to prove a distinct hash and behavior; it is not proposed as a standalone production lexicon',
        'control uses a watched manifest and status file in the experiment directory; production authorization and lifecycle integration remain outside this stage',
        'user-model namespace compatibility across genuinely different full-index releases requires an explicit stable namespace at deployment',
        'production PIME, TSF and installed runtime remain unchanged'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host "YimeBroker E5-D evidence: $outputDir"
if (-not $summary.all_initial_indices_verified -or -not $summary.all_candidate_indices_verified -or
    -not $summary.all_invalid_switches_rejected -or -not $summary.all_valid_switches_passed -or
    -not $summary.all_candidate_probes_passed -or -not $summary.all_rollbacks_passed -or
    -not $summary.all_old_sessions_survived -or -not $summary.all_candidate_sessions_survived_rollback -or
    -not $summary.all_clean_shutdowns_passed -or -not $summary.native_rime_paging_ownership_preserved) {
    throw "One or more E5-D gates failed; see $summaryPath"
}
