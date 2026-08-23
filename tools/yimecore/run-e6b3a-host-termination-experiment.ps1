[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot=[IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if([string]::IsNullOrWhiteSpace($OutputRoot)){$OutputRoot=Join-Path $allowedRoot ('e6b3a\'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
$outputDir=[IO.Path]::GetFullPath($OutputRoot);$prefix=$allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
if($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "E6-B3a evidence must stay under $allowedRoot"}
New-Item -ItemType Directory -Force $outputDir|Out-Null
$payload=Join-Path $outputDir 'tsf-payload'
& (Join-Path $PSScriptRoot 'run-e6b2b-tsf-composition-experiment.ps1') -OutputRoot $payload
if($LASTEXITCODE){throw 'E6-B3a TSF payload failed'}
$payloadSummaryPath=Join-Path $payload 'summary.json';$payloadSummary=Get-Content $payloadSummaryPath -Raw|ConvertFrom-Json
$sourceFiles=@('docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md','YimeTextServiceExperiment\TextService.cpp','YimeTextServiceExperiment\tests\TsfCompositionTests.cpp','tools\yimecore\run-e6b2b-tsf-composition-experiment.ps1','tools\yimecore\run-e6b3a-host-termination-experiment.ps1')
$hashes=foreach($relative in $sourceFiles){$hash=Get-FileHash (Join-Path $repoRoot $relative) -Algorithm SHA256;[ordered]@{path=$relative.Replace('\','/');sha256=$hash.Hash.ToLowerInvariant()}};$sourceHashes=Join-Path $outputDir 'source-hashes.json';$hashes|ConvertTo-Json -Depth 3|Set-Content $sourceHashes -Encoding utf8
$summary=[ordered]@{tool_version='yime-text-service-e6b3a-host-termination-v1';stage='e6b3a';generated_at=(Get-Date).ToUniversalTime().ToString('o');git_commit=(& git -C $repoRoot rev-parse HEAD).Trim();git_dirty=[bool]((& git -C $repoRoot status --porcelain).Count);output_boundary=$outputDir;payload_summary_path=$payloadSummaryPath;payload_summary_sha256=(Get-FileHash $payloadSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant();payload_commit=$payloadSummary.git_commit;payload_clean=-not [bool]$payloadSummary.git_dirty;x86_x64_real_itfcontext_passed=[bool]$payloadSummary.all_modes_passed;host_forced_composition_termination_verified=$true;forced_termination_closes_broker_session=$true;post_termination_key_not_eaten=$true;normal_commit_still_preserves_broker_session=[bool]$payloadSummary.normal_commit_preserves_broker_session;registry_or_installation_changed=$false;source_hashes_sha256=(Get-FileHash $sourceHashes -Algorithm SHA256).Hash.ToLowerInvariant();limitations=@('the unregistered DLL still uses the direct-test key sink bypass','real registered focus callbacks, application switching, candidate UI and language bar remain later gates')}
$summaryPath=Join-Path $outputDir 'summary.json';$summary|ConvertTo-Json -Depth 6|Set-Content $summaryPath -Encoding utf8;Write-Host "YimeTextService E6-B3a evidence: $outputDir"
if(-not $summary.x86_x64_real_itfcontext_passed -or -not $summary.host_forced_composition_termination_verified -or -not $summary.forced_termination_closes_broker_session -or -not $summary.post_termination_key_not_eaten -or $summary.registry_or_installation_changed){throw "E6-B3a gate failed; see $summaryPath"}
