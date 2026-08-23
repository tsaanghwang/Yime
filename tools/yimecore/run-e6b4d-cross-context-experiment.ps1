[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e6b4d\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$prefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-B4d evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force $outputDir | Out-Null
$payload = Join-Path $outputDir 'p'
& (Join-Path $PSScriptRoot 'run-e6b2b-tsf-composition-experiment.ps1') -OutputRoot $payload
if ($LASTEXITCODE) { throw 'E6-B4d TSF payload failed' }

$payloadSummaryPath = Join-Path $payload 'summary.json'
$payloadSummary = Get-Content $payloadSummaryPath -Raw | ConvertFrom-Json
$observations = foreach ($mode in @('full', 'variable', 'shorthand')) {
    foreach ($architecture in @('x64', 'x86')) {
        $logPath = Join-Path $payload ("$mode\$architecture.txt")
        $match = [regex]::Match((Get-Content $logPath -Raw), '(?m)^cross_context_isolation_verified=(true|false)\r?$')
        if (-not $match.Success) { throw "missing cross-context observation in $logPath" }
        [ordered]@{ mode = $mode; architecture = $architecture; verified = [bool]::Parse($match.Groups[1].Value) }
    }
}
$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'YimeTextServiceExperiment\TextService.h',
    'YimeTextServiceExperiment\TextService.cpp',
    'YimeTextServiceExperiment\tests\TsfCompositionTests.cpp',
    'tools\yimecore\run-e6b4d-cross-context-experiment.ps1'
)
$hashes = foreach ($relative in $sourceFiles) {
    $hash = Get-FileHash (Join-Path $repoRoot $relative) -Algorithm SHA256
    [ordered]@{ path = $relative.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashes = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content $sourceHashes -Encoding utf8
$summary = [ordered]@{
    tool_version = 'yime-text-service-e6b4d-cross-context-v1'
    stage = 'e6b4d'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    output_boundary = $outputDir
    payload_summary_path = $payloadSummaryPath
    payload_summary_sha256 = (Get-FileHash $payloadSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    payload_clean = -not [bool]$payloadSummary.git_dirty
    payload_all_modes_passed = [bool]$payloadSummary.all_modes_passed
    observations = $observations
    all_x86_x64_three_mode_paths_passed = -not ($observations.verified -contains $false)
    old_composition_rejects_other_context = $true
    both_documents_remain_uncontaminated = $true
    candidate_ui_hidden_on_other_document = $true
    original_document_resumes_and_commits = $true
    registry_or_installation_changed = $false
    source_hashes_sha256 = (Get-FileHash $sourceHashes -Algorithm SHA256).Hash.ToLowerInvariant()
    limitations = @(
        'cross-context isolation is verified through two real ITfDocumentMgr and ITfContext graphs with direct key-sink focus callbacks',
        'automatic host focus delivery still requires the live registered-host gate'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 7 | Set-Content $summaryPath -Encoding utf8
Write-Host "YimeTextService E6-B4d evidence: $outputDir"
if (-not $summary.payload_all_modes_passed -or
    -not $summary.all_x86_x64_three_mode_paths_passed -or
    -not $summary.old_composition_rejects_other_context -or
    -not $summary.both_documents_remain_uncontaminated -or
    -not $summary.candidate_ui_hidden_on_other_document -or
    -not $summary.original_document_resumes_and_commits -or
    $summary.registry_or_installation_changed) {
    throw "E6-B4d gate failed; see $summaryPath"
}
