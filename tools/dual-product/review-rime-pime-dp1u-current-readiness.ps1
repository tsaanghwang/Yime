[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$Dp1TApplyPath,
    [Parameter(Mandatory)][string]$Dp1TResumePath,
    [Parameter(Mandatory)][string[]]$RegistrationOwnershipPaths,
    [Parameter(Mandatory)][string[]]$RegistrationCompletenessPaths,
    [Parameter(Mandatory)][string[]]$NativeCleanupPaths,
    [Parameter(Mandatory)][string[]]$TransactionFaultPaths,
    [Parameter(Mandatory)][string[]]$TransactionIsolationPaths,
    [Parameter(Mandatory)][string[]]$JournalPaths,
    [Parameter(Mandatory)][string[]]$MaintenancePaths
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$outer=[IO.Path]::GetFullPath((Join-Path $repo '.tmp\dual-product')).TrimEnd('\')
$out=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if(-not $out.StartsWith($outer+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $out) -cnotmatch '^dp1-u-current-readiness-[A-Za-z0-9-]+$' -or (Test-Path -LiteralPath $out)){
    throw 'Use a fresh .tmp/dual-product/dp1-u-current-readiness-* output.'
}
New-Item -ItemType Directory -Path $out|Out-Null
function Read-Evidence([string]$Path,[string]$Schema){
    $full=[IO.Path]::GetFullPath($Path)
    if(-not $full.StartsWith($outer+'\',[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path $full -PathType Leaf)){throw "Evidence path is invalid: $Path"}
    $value=Get-Content -Raw -LiteralPath $full|ConvertFrom-Json
    if([string]$value.schema_version -cne $Schema){throw "Evidence schema differs: $Path"}
    return [pscustomobject]@{Value=$value;Path=$full;Sha256=(Get-FileHash $full -Algorithm SHA256).Hash.ToLowerInvariant()}
}
function Read-ShellPair([string[]]$Paths,[string]$Schema,[scriptblock]$Pass){
    if($Paths.Count -ne 2){throw 'Every DP1-U source suite requires exactly two shell results.'}
    $rows=@($Paths|ForEach-Object{Read-Evidence $_ $Schema})
    $editions=@($rows|ForEach-Object{[string]$_.Value.powershell_edition}|Sort-Object -Unique)
    if($editions.Count -ne 2 -or $editions -cnotcontains 'Desktop' -or $editions -cnotcontains 'Core'){throw 'Evidence pair does not cover PS5 Desktop and PS7 Core.'}
    foreach($row in $rows){if(-not(& $Pass $row.Value)){throw "Evidence is not passing: $($row.Path)"}}
    return $rows
}
$apply=Read-Evidence $Dp1TApplyPath 'yime-rime-pime-actual-canonical-adapter-result-v1'
$resume=Read-Evidence $Dp1TResumePath 'yime-rime-pime-actual-canonical-adapter-result-v1'
if([string]$apply.Value.mode -cne 'Apply' -or [string]$resume.Value.mode -cne 'Resume' -or
    -not [bool]$apply.Value.actual_canonical_migrated -or -not [bool]$resume.Value.actual_canonical_migrated -or
    [string]$apply.Value.final_canonical_receipt_sha256 -cne [string]$resume.Value.final_canonical_receipt_sha256){throw 'DP1-T Apply/Resume evidence does not converge.'}
$ownership=Read-ShellPair $RegistrationOwnershipPaths 'yime-rime-registration-ownership-isolated-v1' {param($v)[bool]$v.passed -and [long]$v.failed_count -eq 0}
$completeness=Read-ShellPair $RegistrationCompletenessPaths 'yime-rime-pime-registration-completeness-test-v1' {param($v)[bool]$v.passed -and [long]$v.failed_count -eq 0}
$cleanup=Read-ShellPair $NativeCleanupPaths 'yime-rime-pime-native-user-cleanup-test-v1' {param($v)[bool]$v.passed -and [long]$v.failed_count -eq 0}
$faults=Read-ShellPair $TransactionFaultPaths 'yime-rime-pime-transaction-fault-matrix-v2' {param($v)[bool]$v.passed -and [long]$v.failed_count -eq 0}
$isolation=Read-ShellPair $TransactionIsolationPaths 'yime-dual-product-transaction-isolated-v1' {param($v)[bool]$v.passed}
$journal=Read-ShellPair $JournalPaths 'yime-rime-pime-fixture-journal-test-result-v1' {param($v)[long]$v.checks_failed -eq 0 -and [long]$v.checks_total -eq [long]$v.checks_passed}
$maintenance=Read-ShellPair $MaintenancePaths 'yime-rime-maintenance-isolated-v1' {param($v)[bool]$v.passed -and [long]$v.failed_count -eq 0}
$evidence=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-dp1u-maintenance-runtime-evidence-v1';affected_product='rime-pime'
    canonical_artifact_migrated=$true;canonical_receipt_strict_ps5=$true;canonical_receipt_strict_ps7=$true
    source_registration_ps5=$true;source_registration_ps7=$true;source_rollback_ps5=$true;source_rollback_ps7=$true
    source_removal_ps5=$true;source_removal_ps7=$true;source_runtime_ps5=$true;source_runtime_ps7=$true
    product_independence_contract=$true
    actual_registration_probe_executed=$false;actual_registration_converged_x86=$false;actual_registration_converged_x64=$false
    actual_registration_target_sid_verified=$false;actual_peer_registration_unchanged=$false
    actual_rollback_executed=$false;actual_rollback_all_dimensions_restored=$false
    actual_rollback_persistent_journal_replayed=$false;actual_rollback_process_crash_recovered=$false
    actual_rollback_peer_unchanged=$false;actual_rollback_default_unchanged=$false
    actual_uninstaller_executed=$false;actual_removal_manifest_exact=$false
    actual_removal_concurrent_replacement_excluded=$false;actual_removal_foreign_content_preserved=$false
    actual_registration_absent_after_removal=$false
    actual_runtime_executed=$false;actual_runtime_non_elevated=$false;actual_runtime_target_sid_verified=$false
    actual_runtime_current_images_verified=$false;actual_runtime_launcher_ready=$false;actual_runtime_backend_ready=$false
    actual_runtime_peer_not_required=$false
    installed_yimecore_local12_touched=$false;production_user_data_accessed=$false;default_input_method_changed=$false
    hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
}
$module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-maintenance-runtime-gate.psm1') -Force -PassThru
try{$gate=Test-RimePimeDp1UMaintenanceRuntimeGate $evidence}finally{Remove-Module $module -Force}
$inputs=[ordered]@{
    dp1_t_apply=$apply.Sha256
    dp1_t_resume=$resume.Sha256
    gate_module=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-dp1u-maintenance-runtime-gate.psm1') -Algorithm SHA256).Hash.ToLowerInvariant()
    current_readiness_script=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
foreach($pair in @(@('registration_ownership',$ownership),@('registration_completeness',$completeness),@('native_cleanup',$cleanup),
    @('transaction_faults',$faults),@('transaction_isolation',$isolation),@('fixture_journal',$journal),@('maintenance',$maintenance))){
    $inputs[$pair[0]+'_ps5']=@($pair[1]|Where-Object{[string]$_.Value.powershell_edition -ceq 'Desktop'})[0].Sha256
    $inputs[$pair[0]+'_ps7']=@($pair[1]|Where-Object{[string]$_.Value.powershell_edition -ceq 'Core'})[0].Sha256
}
$result=[ordered]@{
    schema_version='yime-rime-pime-dp1u-current-readiness-result-v1';generated_at_utc=[DateTime]::UtcNow.ToString('o')
    affected_product='rime-pime';powershell_edition=$PSVersionTable.PSEdition;powershell_version=$PSVersionTable.PSVersion.ToString()
    canonical_receipt_sha256=[string]$apply.Value.final_canonical_receipt_sha256;input_result_sha256=$inputs
    gate=$gate;dp1_u_gate_implementation_complete=[bool]$gate.source_contract_ready
    dp1_u_acceptance_passed=[bool]$gate.dp1_u_acceptance_passed
    installer_or_uninstaller_executed=$false;registry_or_product_process_touched=$false
    installed_yimecore_local12_touched=$false;production_user_data_accessed=$false;default_input_method_changed=$false
    hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
    dp1_complete=$false;dp2_complete=$false;dp3_complete=$false
}
$json=ConvertTo-Json $result -Depth 30 -Compress;$path=Join-Path $out 'result.json'
[IO.File]::WriteAllText($path,$json+"`n",[Text.UTF8Encoding]::new($false));$sha=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($path+'.sha256',$sha+'  result.json'+"`n",[Text.UTF8Encoding]::new($false))
if(-not $gate.source_contract_ready -or $gate.dp1_u_acceptance_passed){throw 'DP1-U current readiness must pass source contracts and keep unexecuted acceptance closed.'}
Write-Host "PASS: DP1-U source readiness; installed acceptance remains closed. Evidence: $path ($sha)"
