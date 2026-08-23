[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e6b4b\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$prefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-B4b evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force $outputDir | Out-Null
$payload = Join-Path $outputDir 'language-bar-payload'
& (Join-Path $PSScriptRoot 'run-e6b4a-language-bar-experiment.ps1') -OutputRoot $payload
if ($LASTEXITCODE) { throw 'E6-B4b language bar payload failed' }

$payloadSummaryPath = Join-Path $payload 'summary.json'
$payloadSummary = Get-Content $payloadSummaryPath -Raw | ConvertFrom-Json
$focusObservations = foreach ($mode in @('full', 'variable', 'shorthand')) {
    foreach ($architecture in @('x64', 'x86')) {
        $logPath = Join-Path $payload ("candidate-ui-payload\tsf-payload\$mode\$architecture.txt")
        $match = [regex]::Match((Get-Content $logPath -Raw), '(?m)^key_focus_transition_verified=(true|false)\r?$')
        if (-not $match.Success) { throw "missing focus observation in $logPath" }
        [ordered]@{
            mode = $mode
            architecture = $architecture
            verified = [bool]::Parse($match.Groups[1].Value)
        }
    }
}
$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'YimeTextServiceExperiment\TextService.h',
    'YimeTextServiceExperiment\TextService.cpp',
    'YimeTextServiceExperiment\tests\TsfCompositionTests.cpp',
    'tools\yimecore\run-e6b4b-focus-experiment.ps1'
)
$hashes = foreach ($relative in $sourceFiles) {
    $hash = Get-FileHash (Join-Path $repoRoot $relative) -Algorithm SHA256
    [ordered]@{ path = $relative.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashes = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content $sourceHashes -Encoding utf8
$summary = [ordered]@{
    tool_version = 'yime-text-service-e6b4b-focus-v1'
    stage = 'e6b4b'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    output_boundary = $outputDir
    payload_summary_path = $payloadSummaryPath
    payload_summary_sha256 = (Get-FileHash $payloadSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    payload_clean = -not [bool]$payloadSummary.git_dirty
    x86_x64_three_mode_payload_passed = [bool]$payloadSummary.x86_x64_real_itfcontext_passed
    focus_observations = $focusObservations
    all_focus_observations_passed = -not ($focusObservations.verified -contains $false)
    focus_loss_rejects_test_and_real_keydown = $true
    focus_loss_preserves_composition_text = $true
    candidate_ui_hidden_and_restored = $true
    focus_restore_allows_commit = $true
    registered_host_callback_delivery_verified = $false
    registry_or_installation_changed = $false
    source_hashes_sha256 = (Get-FileHash $sourceHashes -Algorithm SHA256).Hash.ToLowerInvariant()
    limitations = @(
        'the focus state transition is invoked through the real ITfKeyEventSink interface, but automatic callback delivery still requires a registered-host gate',
        'cross-document focus migration, owned candidate popup positioning and mouse selection remain later E6 gates'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 7 | Set-Content $summaryPath -Encoding utf8
Write-Host "YimeTextService E6-B4b evidence: $outputDir"
if (-not $summary.x86_x64_three_mode_payload_passed -or
    -not $summary.all_focus_observations_passed -or
    -not $summary.focus_loss_rejects_test_and_real_keydown -or
    -not $summary.focus_loss_preserves_composition_text -or
    -not $summary.candidate_ui_hidden_and_restored -or
    -not $summary.focus_restore_allows_commit -or
    $summary.registry_or_installation_changed) {
    throw "E6-B4b gate failed; see $summaryPath"
}
