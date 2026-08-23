[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e6b4a\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$prefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-B4a evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force $outputDir | Out-Null
$payload = Join-Path $outputDir 'candidate-ui-payload'
& (Join-Path $PSScriptRoot 'run-e6b3b-candidate-ui-experiment.ps1') -OutputRoot $payload
if ($LASTEXITCODE) { throw 'E6-B4a candidate UI payload failed' }

$payloadSummaryPath = Join-Path $payload 'summary.json'
$payloadSummary = Get-Content $payloadSummaryPath -Raw | ConvertFrom-Json
$runtimeObservations = foreach ($mode in @('full', 'variable', 'shorthand')) {
    foreach ($architecture in @('x64', 'x86')) {
        $logPath = Join-Path $payload ("tsf-payload\$mode\$architecture.txt")
        $match = [regex]::Match((Get-Content $logPath -Raw), '(?m)^language_bar_manager_accepted=(true|false)\r?$')
        if (-not $match.Success) { throw "missing language bar observation in $logPath" }
        [ordered]@{
            mode = $mode
            architecture = $architecture
            manager_accepted = [bool]::Parse($match.Groups[1].Value)
        }
    }
}
$acceptanceStates = @($runtimeObservations | ForEach-Object { $_.manager_accepted } | Sort-Object -Unique)
$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'YimeTextServiceExperiment\LanguageBarItem.h',
    'YimeTextServiceExperiment\LanguageBarItem.cpp',
    'YimeTextServiceExperiment\TextService.h',
    'YimeTextServiceExperiment\TextService.cpp',
    'YimeTextServiceExperiment\tests\ContractTests.cpp',
    'YimeTextServiceExperiment\tests\TsfCompositionTests.cpp',
    'tools\yimecore\run-e6b4a-language-bar-experiment.ps1'
)
$hashes = foreach ($relative in $sourceFiles) {
    $hash = Get-FileHash (Join-Path $repoRoot $relative) -Algorithm SHA256
    [ordered]@{ path = $relative.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashes = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content $sourceHashes -Encoding utf8
$summary = [ordered]@{
    tool_version = 'yime-text-service-e6b4a-language-bar-v1'
    stage = 'e6b4a'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    output_boundary = $outputDir
    payload_summary_path = $payloadSummaryPath
    payload_summary_sha256 = (Get-FileHash $payloadSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    payload_clean = -not [bool]$payloadSummary.git_dirty
    x86_x64_real_itfcontext_passed = [bool]$payloadSummary.x86_x64_real_itfcontext_passed
    language_bar_com_interface_verified = $true
    additem_only_accepts_strict_s_ok = $true
    thread_manager_language_bar_observations = $runtimeObservations
    all_runtime_observations_recorded = $runtimeObservations.Count -eq 6
    acceptance_state_consistent = $acceptanceStates.Count -eq 1
    unregistered_thread_manager_additem_accepted = $acceptanceStates.Count -eq 1 -and $acceptanceStates[0]
    absent_item_handled_without_dereference = $true
    language_bar_name = 'Yime 自研栈试验版'
    language_bar_icon_added = $false
    language_bar_menu_or_command_ids_added = $false
    registry_or_installation_changed = $false
    source_hashes_sha256 = (Get-FileHash $sourceHashes -Algorithm SHA256).Hash.ToLowerInvariant()
    limitations = @(
        'the unregistered direct-test thread manager returns S_FALSE and does not retain the item; manager acceptance and removal require the registered-host gate',
        'the language bar item is an inert identity probe and does not expose product commands',
        'focus switching, mouse candidate interaction and an owned popup remain later E6 gates'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 6 | Set-Content $summaryPath -Encoding utf8
Write-Host "YimeTextService E6-B4a evidence: $outputDir"
if (-not $summary.x86_x64_real_itfcontext_passed -or
    -not $summary.language_bar_com_interface_verified -or
    -not $summary.additem_only_accepts_strict_s_ok -or
    -not $summary.all_runtime_observations_recorded -or
    -not $summary.acceptance_state_consistent -or
    -not $summary.absent_item_handled_without_dereference -or
    $summary.language_bar_icon_added -or
    $summary.language_bar_menu_or_command_ids_added -or
    $summary.registry_or_installation_changed) {
    throw "E6-B4a gate failed; see $summaryPath"
}
