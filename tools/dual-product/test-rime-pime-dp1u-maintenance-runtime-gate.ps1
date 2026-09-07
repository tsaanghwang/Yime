[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$outer=[IO.Path]::GetFullPath((Join-Path $repo '.tmp\dual-product')).TrimEnd('\')
$out=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if((Split-Path -Parent $out) -ine $outer -or (Split-Path -Leaf $out) -cnotmatch '^dp1-u-gate-test-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $out)){throw 'Use a fresh immediate .tmp/dual-product/dp1-u-gate-test-* output.'}
New-Item -ItemType Directory -Path $out|Out-Null
$modulePath=Join-Path $PSScriptRoot 'rime-pime-dp1u-maintenance-runtime-gate.psm1'
$m=Import-Module $modulePath -Force -PassThru
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){try{&$Body;$checks.Add([ordered]@{name=$Name;passed=$true;error=''})}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function New-Evidence([bool]$Actual=$true){
    return [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-dp1u-maintenance-runtime-evidence-v1';affected_product='rime-pime'
        canonical_artifact_migrated=$true;canonical_receipt_strict_ps5=$true;canonical_receipt_strict_ps7=$true
        source_registration_ps5=$true;source_registration_ps7=$true;source_rollback_ps5=$true;source_rollback_ps7=$true
        source_removal_ps5=$true;source_removal_ps7=$true;source_runtime_ps5=$true;source_runtime_ps7=$true
        product_independence_contract=$true
        actual_registration_probe_executed=$Actual;actual_registration_converged_x86=$Actual
        actual_registration_converged_x64=$Actual;actual_registration_target_sid_verified=$Actual
        actual_peer_registration_unchanged=$Actual;actual_rollback_executed=$Actual
        actual_rollback_all_dimensions_restored=$Actual;actual_rollback_persistent_journal_replayed=$Actual
        actual_rollback_process_crash_recovered=$Actual;actual_rollback_peer_unchanged=$Actual
        actual_rollback_default_unchanged=$Actual;actual_uninstaller_executed=$Actual
        actual_removal_manifest_exact=$Actual;actual_removal_concurrent_replacement_excluded=$Actual
        actual_removal_foreign_content_preserved=$Actual;actual_registration_absent_after_removal=$Actual
        actual_runtime_executed=$Actual;actual_runtime_non_elevated=$Actual
        actual_runtime_target_sid_verified=$Actual;actual_runtime_current_images_verified=$Actual
        actual_runtime_launcher_ready=$Actual;actual_runtime_backend_ready=$Actual;actual_runtime_peer_not_required=$Actual
        installed_yimecore_local12_touched=$false;production_user_data_accessed=$false;default_input_method_changed=$false
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
    }
}
function Copy-Evidence($Value){return $Value|ConvertTo-Json -Depth 10|ConvertFrom-Json}
function Assert-Reason($Result,[string]$Reason){Assert-True (@($Result.reasons)-ccontains $Reason) "Missing reason: $Reason"}

Check 'module-exports-one-pure-gate' {
    Assert-True ((@($m.ExportedCommands.Keys)-join ',') -ceq 'Test-RimePimeDp1UMaintenanceRuntimeGate') 'Unexpected export surface.'
}
Check 'complete-actual-evidence-admits-all-four-gates' {
    $r=Test-RimePimeDp1UMaintenanceRuntimeGate (New-Evidence)
    Assert-True ($r.source_contract_ready -and $r.registration_gate_passed -and $r.rollback_gate_passed -and
        $r.removal_gate_passed -and $r.runtime_gate_passed -and $r.dp1_u_acceptance_passed -and
        @($r.reasons).Count -eq 0) 'Complete evidence did not pass.'
}
Check 'current-no-execution-evidence-keeps-four-acceptance-gates-closed' {
    $r=Test-RimePimeDp1UMaintenanceRuntimeGate (New-Evidence $false)
    Assert-True ($r.source_contract_ready -and -not $r.registration_gate_passed -and -not $r.rollback_gate_passed -and
        -not $r.removal_gate_passed -and -not $r.runtime_gate_passed -and -not $r.dp1_u_acceptance_passed) 'Unexecuted evidence was promoted.'
}
Check 'every-source-proof-is-required' {
    foreach($name in @('canonical_artifact_migrated','canonical_receipt_strict_ps5','canonical_receipt_strict_ps7',
        'source_registration_ps5','source_registration_ps7','source_rollback_ps5','source_rollback_ps7',
        'source_removal_ps5','source_removal_ps7','source_runtime_ps5','source_runtime_ps7','product_independence_contract')){
        $e=Copy-Evidence (New-Evidence);$e.$name=$false;$r=Test-RimePimeDp1UMaintenanceRuntimeGate $e
        Assert-True (-not $r.source_contract_ready -and -not $r.dp1_u_acceptance_passed) "Source omission passed: $name"
        Assert-Reason $r ($name+'-not-true')
    }
}
Check 'every-registration-observation-is-required' {
    foreach($name in @('actual_registration_probe_executed','actual_registration_converged_x86','actual_registration_converged_x64',
        'actual_registration_target_sid_verified','actual_peer_registration_unchanged')){
        $e=Copy-Evidence (New-Evidence);$e.$name=$false;$r=Test-RimePimeDp1UMaintenanceRuntimeGate $e
        Assert-True (-not $r.registration_gate_passed -and -not $r.dp1_u_acceptance_passed) "Registration omission passed: $name"
    }
}
Check 'every-rollback-observation-is-required' {
    foreach($name in @('actual_rollback_executed','actual_rollback_all_dimensions_restored',
        'actual_rollback_persistent_journal_replayed','actual_rollback_process_crash_recovered',
        'actual_rollback_peer_unchanged','actual_rollback_default_unchanged')){
        $e=Copy-Evidence (New-Evidence);$e.$name=$false;$r=Test-RimePimeDp1UMaintenanceRuntimeGate $e
        Assert-True (-not $r.rollback_gate_passed -and -not $r.dp1_u_acceptance_passed) "Rollback omission passed: $name"
    }
}
Check 'every-removal-observation-is-required' {
    foreach($name in @('actual_uninstaller_executed','actual_removal_manifest_exact','actual_removal_concurrent_replacement_excluded',
        'actual_removal_foreign_content_preserved','actual_registration_absent_after_removal')){
        $e=Copy-Evidence (New-Evidence);$e.$name=$false;$r=Test-RimePimeDp1UMaintenanceRuntimeGate $e
        Assert-True (-not $r.removal_gate_passed -and -not $r.dp1_u_acceptance_passed) "Removal omission passed: $name"
    }
}
Check 'every-runtime-observation-is-required' {
    foreach($name in @('actual_runtime_executed','actual_runtime_non_elevated','actual_runtime_target_sid_verified',
        'actual_runtime_current_images_verified','actual_runtime_launcher_ready','actual_runtime_backend_ready','actual_runtime_peer_not_required')){
        $e=Copy-Evidence (New-Evidence);$e.$name=$false;$r=Test-RimePimeDp1UMaintenanceRuntimeGate $e
        Assert-True (-not $r.runtime_gate_passed -and -not $r.dp1_u_acceptance_passed) "Runtime omission passed: $name"
    }
}
Check 'cross-product-user-data-and-default-mutations-fail-closed' {
    foreach($name in @('installed_yimecore_local12_touched','production_user_data_accessed','default_input_method_changed')){
        $e=Copy-Evidence (New-Evidence);$e.$name=$true;$r=Test-RimePimeDp1UMaintenanceRuntimeGate $e
        Assert-True (-not $r.source_contract_ready -and -not $r.dp1_u_acceptance_passed) "Prohibited mutation passed: $name"
        Assert-Reason $r ($name+'-not-false')
    }
}
Check 'physical-nonclaims-must-remain-false' {
    foreach($name in @('hardware_power_loss_verified','directory_metadata_durability_verified')){
        $e=Copy-Evidence (New-Evidence);$e.$name=$true;$r=Test-RimePimeDp1UMaintenanceRuntimeGate $e
        Assert-Reason $r ($name+'-not-false')
        Assert-True (-not $r.$name -and -not $r.dp1_u_acceptance_passed) "Physical nonclaim was promoted: $name"
    }
}
Check 'schema-product-field-set-order-and-types-fail-closed' {
    $cases=[Collections.Generic.List[object]]::new()
    $e=Copy-Evidence (New-Evidence);$e.schema_version='future';$cases.Add($e)
    $e=Copy-Evidence (New-Evidence);$e.affected_product='yimecore';$cases.Add($e)
    $e=Copy-Evidence (New-Evidence);$e|Add-Member extra $true;$cases.Add($e)
    $e=Copy-Evidence (New-Evidence);$e.actual_runtime_executed='true';$cases.Add($e)
    foreach($case in $cases){$r=Test-RimePimeDp1UMaintenanceRuntimeGate $case;Assert-True (-not $r.dp1_u_acceptance_passed) 'Malformed evidence passed.'}
}

$failed=@($checks|Where-Object{-not $_.passed})
$result=[ordered]@{
    schema_version='yime-rime-pime-dp1u-maintenance-runtime-gate-test-v1'
    powershell_edition=$PSVersionTable.PSEdition;powershell_version=$PSVersionTable.PSVersion.ToString()
    module_sha256=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    passed=$failed.Count -eq 0;check_count=$checks.Count;passed_count=$checks.Count-$failed.Count;failed_count=$failed.Count
    checks=@($checks);actual_installer_or_uninstaller_executed=$false;actual_registry_or_product_process_touched=$false
    installed_yimecore_local12_touched=$false;production_user_data_accessed=$false;default_input_method_changed=$false
    hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
}
$json=ConvertTo-Json $result -Depth 20 -Compress;$path=Join-Path $out 'result.json'
[IO.File]::WriteAllText($path,$json+"`n",[Text.UTF8Encoding]::new($false));$sha=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($path+'.sha256',$sha+'  result.json'+"`n",[Text.UTF8Encoding]::new($false))
Remove-Module $m -Force
if($failed.Count){throw "DP1-U gate tests failed: $($failed.Count). Evidence: $path ($sha)"}
Write-Host "PASS: DP1-U gate $($checks.Count)/$($checks.Count). Evidence: $path ($sha)"
