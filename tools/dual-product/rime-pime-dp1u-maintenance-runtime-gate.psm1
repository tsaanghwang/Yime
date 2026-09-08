# Pure DP1-U admission logic. Importing this module performs no registry,
# process, filesystem-maintenance, installer, uninstaller or product action.
Set-StrictMode -Version 2.0
$script:Dp1USchema='yime-rime-pime-dp1u-maintenance-runtime-evidence-v1'
$script:Dp1UFields=@(
    'schema_version','affected_product','canonical_artifact_migrated',
    'canonical_receipt_strict_ps5','canonical_receipt_strict_ps7',
    'source_registration_ps5','source_registration_ps7','source_rollback_ps5','source_rollback_ps7',
    'source_removal_ps5','source_removal_ps7','source_runtime_ps5','source_runtime_ps7',
    'product_independence_contract',
    'actual_registration_probe_executed','actual_registration_converged_x86','actual_registration_converged_x64',
    'actual_registration_target_sid_verified','actual_peer_registration_unchanged',
    'actual_rollback_executed','actual_rollback_all_dimensions_restored',
    'actual_rollback_persistent_journal_replayed','actual_rollback_process_crash_recovered',
    'actual_rollback_peer_unchanged','actual_rollback_default_unchanged',
    'actual_uninstaller_executed','actual_removal_manifest_exact',
    'actual_removal_concurrent_replacement_excluded','actual_removal_foreign_content_preserved',
    'actual_registration_absent_after_removal',
    'actual_runtime_executed','actual_runtime_non_elevated','actual_runtime_target_sid_verified',
    'actual_runtime_current_images_verified','actual_runtime_launcher_ready','actual_runtime_backend_ready',
    'actual_runtime_peer_not_required',
    'installed_yimecore_local12_touched','production_user_data_accessed','default_input_method_changed',
    'hardware_power_loss_verified','directory_metadata_durability_verified'
)

function Add-Dp1UReason([Collections.Generic.List[string]]$Reasons,[string]$Reason){
    if(-not $Reasons.Contains($Reason)){$Reasons.Add($Reason)}
}

function Test-Dp1UBool($Evidence,[string]$Name,[bool]$Expected,[Collections.Generic.List[string]]$Reasons){
    $property=$Evidence.PSObject.Properties[$Name]
    if($null -eq $property -or $property.Value -isnot [bool] -or [bool]$property.Value -ne $Expected){
        Add-Dp1UReason $Reasons ($Name+'-not-'+$Expected.ToString().ToLowerInvariant())
        return $false
    }
    return $true
}

function Test-RimePimeDp1UMaintenanceRuntimeGate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][AllowEmptyString()]$Evidence)
    $reasons=[Collections.Generic.List[string]]::new()
    if($null -eq $Evidence -or $Evidence -isnot [pscustomobject]){
        $reasons.Add('evidence-not-object')
        return [pscustomobject][ordered]@{
            schema_version='yime-rime-pime-dp1u-maintenance-runtime-gate-result-v1'
            source_contract_ready=$false;registration_gate_passed=$false;rollback_gate_passed=$false
            removal_gate_passed=$false;runtime_gate_passed=$false;dp1_u_acceptance_passed=$false
            reasons=@($reasons);installed_yimecore_local12_touched=$false
            hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
        }
    }
    $actual=@($Evidence.PSObject.Properties|ForEach-Object{[string]$_.Name})
    if(($actual-join "`n") -cne ($script:Dp1UFields-join "`n")){Add-Dp1UReason $reasons 'field-set-or-order-not-exact'}
    $schemaProperty=$Evidence.PSObject.Properties['schema_version']
    $productProperty=$Evidence.PSObject.Properties['affected_product']
    if($null -eq $schemaProperty -or $schemaProperty.Value -isnot [string] -or
        $schemaProperty.Value -cne $script:Dp1USchema){Add-Dp1UReason $reasons 'schema-not-supported'}
    if($null -eq $productProperty -or $productProperty.Value -isnot [string] -or
        $productProperty.Value -cne 'rime-pime'){Add-Dp1UReason $reasons 'affected-product-not-rime-pime'}

    $sourceReady=($reasons.Count -eq 0)
    foreach($name in @(
        'canonical_artifact_migrated','canonical_receipt_strict_ps5','canonical_receipt_strict_ps7',
        'source_registration_ps5','source_registration_ps7','source_rollback_ps5','source_rollback_ps7',
        'source_removal_ps5','source_removal_ps7','source_runtime_ps5','source_runtime_ps7',
        'product_independence_contract')){
        if(-not(Test-Dp1UBool $Evidence $name $true $reasons)){$sourceReady=$false}
    }
    foreach($name in @('installed_yimecore_local12_touched','production_user_data_accessed','default_input_method_changed')){
        if(-not(Test-Dp1UBool $Evidence $name $false $reasons)){$sourceReady=$false}
    }

    $registration=$sourceReady
    foreach($name in @('actual_registration_probe_executed','actual_registration_converged_x86',
        'actual_registration_converged_x64','actual_registration_target_sid_verified','actual_peer_registration_unchanged')){
        if(-not(Test-Dp1UBool $Evidence $name $true $reasons)){$registration=$false}
    }
    $rollback=$sourceReady
    foreach($name in @('actual_rollback_executed','actual_rollback_all_dimensions_restored',
        'actual_rollback_persistent_journal_replayed','actual_rollback_process_crash_recovered',
        'actual_rollback_peer_unchanged','actual_rollback_default_unchanged')){
        if(-not(Test-Dp1UBool $Evidence $name $true $reasons)){$rollback=$false}
    }
    $removal=$sourceReady
    foreach($name in @('actual_uninstaller_executed','actual_removal_manifest_exact',
        'actual_removal_concurrent_replacement_excluded','actual_removal_foreign_content_preserved',
        'actual_registration_absent_after_removal')){
        if(-not(Test-Dp1UBool $Evidence $name $true $reasons)){$removal=$false}
    }
    $runtime=$sourceReady
    foreach($name in @('actual_runtime_executed','actual_runtime_non_elevated','actual_runtime_target_sid_verified',
        'actual_runtime_current_images_verified','actual_runtime_launcher_ready','actual_runtime_backend_ready',
        'actual_runtime_peer_not_required')){
        if(-not(Test-Dp1UBool $Evidence $name $true $reasons)){$runtime=$false}
    }

    $hardware=Test-Dp1UBool $Evidence 'hardware_power_loss_verified' $false $reasons
    $directory=Test-Dp1UBool $Evidence 'directory_metadata_durability_verified' $false $reasons
    $local12Property=$Evidence.PSObject.Properties['installed_yimecore_local12_touched']
    return [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-dp1u-maintenance-runtime-gate-result-v1'
        source_contract_ready=[bool]$sourceReady
        registration_gate_passed=[bool]$registration
        rollback_gate_passed=[bool]$rollback
        removal_gate_passed=[bool]$removal
        runtime_gate_passed=[bool]$runtime
        dp1_u_acceptance_passed=[bool]($registration -and $rollback -and $removal -and $runtime -and $hardware -and $directory)
        reasons=@($reasons)
        installed_yimecore_local12_touched=[bool]($null -ne $local12Property -and $local12Property.Value -is [bool] -and $local12Property.Value)
        hardware_power_loss_verified=[bool]($hardware -and $false)
        directory_metadata_durability_verified=[bool]($directory -and $false)
    }
}

Export-ModuleMember -Function Test-RimePimeDp1UMaintenanceRuntimeGate
