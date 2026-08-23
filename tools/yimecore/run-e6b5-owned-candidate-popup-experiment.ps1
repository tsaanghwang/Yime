[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e6b5\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$prefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-B5 evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force $outputDir | Out-Null
$payload = Join-Path $outputDir 'p'
& (Join-Path $PSScriptRoot 'run-e6b2b-tsf-composition-experiment.ps1') -OutputRoot $payload
if ($LASTEXITCODE) { throw 'E6-B5 TSF payload failed' }

$payloadSummaryPath = Join-Path $payload 'summary.json'
$payloadSummary = Get-Content $payloadSummaryPath -Raw | ConvertFrom-Json
$observations = foreach ($mode in @('full', 'variable', 'shorthand')) {
    foreach ($architecture in @('x64', 'x86')) {
        $logPath = Join-Path $payload ("$mode\$architecture.txt")
        $text = Get-Content $logPath -Raw
        function Read-BooleanObservation([string]$name) {
            $match = [regex]::Match($text, "(?m)^$([regex]::Escape($name))=(true|false)\r?$")
            if (-not $match.Success) { throw "missing $name observation in $logPath" }
            return [bool]::Parse($match.Groups[1].Value)
        }
        [ordered]@{
            mode = $mode
            architecture = $architecture
            owned_popup_visible = Read-BooleanObservation 'owned_candidate_popup_visible'
            mouse_selection_verified = Read-BooleanObservation 'mouse_candidate_selection_verified'
            text_extent_anchor = Read-BooleanObservation 'text_extent_anchor'
        }
    }
}
$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'YimeTextServiceExperiment\CMakeLists.txt',
    'YimeTextServiceExperiment\CandidateListUIElement.h',
    'YimeTextServiceExperiment\CandidatePopup.h',
    'YimeTextServiceExperiment\CandidatePopup.cpp',
    'YimeTextServiceExperiment\ExperimentSettings.h',
    'YimeTextServiceExperiment\ExperimentSettings.cpp',
    'YimeTextServiceExperiment\CompositionEditSession.h',
    'YimeTextServiceExperiment\CompositionEditSession.cpp',
    'YimeTextServiceExperiment\TextService.h',
    'YimeTextServiceExperiment\TextService.cpp',
    'YimeTextServiceExperiment\tests\ContractTests.cpp',
    'YimeTextServiceExperiment\tests\TsfCompositionTests.cpp',
    'tools\yimecore\run-e6b5-owned-candidate-popup-experiment.ps1'
)
$hashes = foreach ($relative in $sourceFiles) {
    $hash = Get-FileHash (Join-Path $repoRoot $relative) -Algorithm SHA256
    [ordered]@{ path = $relative.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashes = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content $sourceHashes -Encoding utf8
$summary = [ordered]@{
    tool_version = 'yime-text-service-e6b5-owned-candidate-popup-v1'
    stage = 'e6b5'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    output_boundary = $outputDir
    payload_summary_path = $payloadSummaryPath
    payload_summary_sha256 = (Get-FileHash $payloadSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    payload_clean = -not [bool]$payloadSummary.git_dirty
    payload_all_modes_passed = [bool]$payloadSummary.all_modes_passed
    observations = $observations
    all_x86_x64_three_mode_owned_popup_paths_passed = -not ($observations.owned_popup_visible -contains $false)
    all_x86_x64_three_mode_mouse_paths_passed = -not ($observations.mouse_selection_verified -contains $false)
    text_extent_anchor_paths_observed = @($observations | Where-Object { $_.text_extent_anchor }).Count
    popup_contract = [ordered]@{
        maximum_candidates = 9
        selection_labels = 'Shift+1 through Shift+9'
        no_activate = $true
        tool_window = $true
        monitor_work_area_clamped = $true
        no_icon_or_skin_dependency = $true
    }
    registry_or_installation_changed = $false
    source_hashes_sha256 = (Get-FileHash $sourceHashes -Algorithm SHA256).Hash.ToLowerInvariant()
    limitations = @(
        'the synthetic ITfContext has no context owner window and returns no usable GetTextExt rectangle, so all six direct-test paths intentionally report text_extent_anchor=false and exercise the documented fallback anchor',
        'automatic GetTextExt positioning, AdviseKeyEventSink delivery and application focus callbacks require the elevated registered-host gate'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content $summaryPath -Encoding utf8
Write-Host "YimeTextService E6-B5 evidence: $outputDir"
if (-not $summary.payload_all_modes_passed -or
    -not $summary.all_x86_x64_three_mode_owned_popup_paths_passed -or
    -not $summary.all_x86_x64_three_mode_mouse_paths_passed -or
    $summary.registry_or_installation_changed) {
    throw "E6-B5 gate failed; see $summaryPath"
}
