Set-StrictMode -Version Latest

$script:Dp1RSchema = 'yime-rime-pime-dp1r-trust-admission-v1'

function Add-Dp1RReason {
    param([Collections.Generic.List[string]]$Reasons,[string]$Reason)
    if (-not $Reasons.Contains($Reason)) { $Reasons.Add($Reason) }
}

function Get-Dp1RNoteProperty {
    param($Object,[string]$Name,[string]$Context,[Collections.Generic.List[string]]$Reasons)
    if ($null -eq $Object -or $null -eq $Object.PSObject) {
        Add-Dp1RReason $Reasons "$Context-not-an-object"
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $property.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty) {
        Add-Dp1RReason $Reasons "$Context-missing-$Name"
        return $null
    }
    return $property.Value
}

function Test-Dp1RExactString {
    param($Object,[string]$Name,[string]$Expected,[string]$Context,[Collections.Generic.List[string]]$Reasons)
    $value = Get-Dp1RNoteProperty $Object $Name $Context $Reasons
    if ($value -isnot [string] -or [string]$value -cne $Expected) {
        Add-Dp1RReason $Reasons "$Context-invalid-$Name"
        return $null
    }
    return [string]$value
}

function Test-Dp1RString {
    param($Object,[string]$Name,[string]$Context,[Collections.Generic.List[string]]$Reasons)
    $value = Get-Dp1RNoteProperty $Object $Name $Context $Reasons
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$value) -or [string]$value -match '[\r\n]') {
        Add-Dp1RReason $Reasons "$Context-invalid-$Name"
        return $null
    }
    return [string]$value
}

function Test-Dp1RSha256 {
    param($Object,[string]$Name,[string]$Context,[Collections.Generic.List[string]]$Reasons)
    $value = Get-Dp1RNoteProperty $Object $Name $Context $Reasons
    if ($value -isnot [string] -or [string]$value -cnotmatch '^[0-9a-f]{64}$') {
        Add-Dp1RReason $Reasons "$Context-invalid-$Name"
        return $null
    }
    return [string]$value
}

function Test-Dp1RBoolean {
    param($Object,[string]$Name,[bool]$Expected,[string]$Context,[Collections.Generic.List[string]]$Reasons)
    $value = Get-Dp1RNoteProperty $Object $Name $Context $Reasons
    if ($value -isnot [bool] -or [bool]$value -ne $Expected) {
        Add-Dp1RReason $Reasons "$Context-invalid-$Name"
        return $false
    }
    return $true
}

function Test-Dp1RPositiveInteger {
    param($Object,[string]$Name,[string]$Context,[Collections.Generic.List[string]]$Reasons)
    $value = Get-Dp1RNoteProperty $Object $Name $Context $Reasons
    if ($value -isnot [byte] -and $value -isnot [int16] -and $value -isnot [int32] -and $value -isnot [int64] -and
        $value -isnot [uint16] -and $value -isnot [uint32] -and $value -isnot [uint64]) {
        Add-Dp1RReason $Reasons "$Context-invalid-$Name"
        return $null
    }
    if ([uint64]$value -eq 0) {
        Add-Dp1RReason $Reasons "$Context-invalid-$Name"
        return $null
    }
    return [uint64]$value
}

function Test-Dp1RPostbuild {
    param($Postbuild,[string]$Context,[Collections.Generic.List[string]]$Reasons)
    $start = $Reasons.Count
    $null = Test-Dp1RExactString $Postbuild 'schema_version' 'yime-rime-pime-postbuild-extraction-v1' $Context $Reasons
    $null = Test-Dp1RExactString $Postbuild 'product' 'rime-pime' $Context $Reasons
    $version = Test-Dp1RString $Postbuild 'product_version' $Context $Reasons
    $plan = Test-Dp1RSha256 $Postbuild 'package_plan_sha256' $Context $Reasons
    $manifest = Test-Dp1RSha256 $Postbuild 'content_manifest_sha256' $Context $Reasons
    $tree = Test-Dp1RSha256 $Postbuild 'content_tree_sha256' $Context $Reasons
    $payload = Test-Dp1RSha256 $Postbuild 'payload_nsh_sha256' $Context $Reasons
    $nsisTree = Test-Dp1RSha256 $Postbuild 'nsis_compiler_input_tree_sha256' $Context $Reasons
    foreach ($name in @(
        'nsis_distribution_inputs_exact_and_read_leased_during_postbuild',
        'nsis_known_input_file_replacement_closure','installer_archive_listing_exact',
        'nested_uninstaller_archive_listing_exact','stable_extracted_snapshot_matches_expected_sources',
        'stable_extracted_stage_owned_files_match_sealed_manifest',
        'installer_archive_per_entry_raw_stdout_verified','nested_uninstaller_archive_per_entry_raw_stdout_verified',
        'archive_content_origin_proven','archive_content_provenance_closed_against_active_same_sid_replacement',
        'active_same_sid_extracted_path_interference_excluded_from_archive_byte_provenance',
        'package_plan_stage_bindings_verified','payload_nsh_raw_byte_binding_verified',
        'execution_logic_read_leases_held_through_seal',
        'extraction_root_and_expected_directory_identity_leases_held_through_seal',
        'extracted_file_read_leases_held_through_seal','raw_generated_uninstaller_capture_read_lease_held_through_seal',
        'result_json_and_sidecar_create_new_digest_bound_leases_held_through_runner_pass',
        'text_logs_create_new_memory_digest_bound_and_leased_through_result_seal',
        'installer_read_lease_held_for_all_reads','uninstaller_read_lease_held_for_all_reads',
        'seven_zip_read_lease_held_for_all_calls','seven_zip_parser_library_read_lease_held_for_all_calls',
        'generated_uninstaller_present','generated_uninstaller_static_archive_member_verified'
    )) { $null = Test-Dp1RBoolean $Postbuild $name $true $Context $Reasons }
    foreach ($name in @(
        'active_same_sid_transient_tree_membership_interference_excluded',
        'nsis_compiler_input_leases_held_during_makensis','nsis_non_os_compiler_input_closure',
        'full_nsis_toolchain_input_closure','generated_uninstaller_verified','generated_uninstaller_trusted',
        'final_payload_closure','delivery_admitted','actual_installer_or_uninstaller_executed',
        'product_process_started_or_stopped','registry_touched','default_input_method_changed',
        'production_user_data_read_or_written','installed_yimecore_local12_touched'
    )) { $null = Test-Dp1RBoolean $Postbuild $name $false $Context $Reasons }
    $installer = Get-Dp1RNoteProperty $Postbuild 'installer' $Context $Reasons
    $uninstaller = Get-Dp1RNoteProperty $Postbuild 'generated_uninstaller' $Context $Reasons
    $installerHash = Test-Dp1RSha256 $installer 'sha256' "$Context-installer" $Reasons
    $installerBytes = Test-Dp1RPositiveInteger $installer 'bytes' "$Context-installer" $Reasons
    $uninstallerHash = Test-Dp1RSha256 $uninstaller 'sha256' "$Context-uninstaller" $Reasons
    $uninstallerBytes = Test-Dp1RPositiveInteger $uninstaller 'bytes' "$Context-uninstaller" $Reasons
    foreach ($image in @(@($installer,"$Context-installer"),@($uninstaller,"$Context-uninstaller"))) {
        $null = Test-Dp1RExactString $image[0] 'machine' 'x86' $image[1] $Reasons
        $null = Test-Dp1RExactString $image[0] 'signature_status' 'NotSigned' $image[1] $Reasons
        foreach ($name in @('package_plan_raw_byte_binding','content_manifest_raw_byte_binding',
            'content_tree_raw_byte_binding','payload_nsh_raw_byte_binding')) {
            $null = Test-Dp1RBoolean $image[0] $name $true $image[1] $Reasons
        }
        $null = Test-Dp1RBoolean $image[0] 'trusted' $false $image[1] $Reasons
    }
    $installerArchive = Get-Dp1RNoteProperty $Postbuild 'installer_archive' $Context $Reasons
    $uninstallerArchive = Get-Dp1RNoteProperty $Postbuild 'uninstaller_archive' $Context $Reasons
    $outerCount = Test-Dp1RPositiveInteger $installerArchive 'entry_count' "$Context-installer-archive" $Reasons
    $nestedCount = Test-Dp1RPositiveInteger $uninstallerArchive 'entry_count' "$Context-uninstaller-archive" $Reasons
    if ($null -ne $outerCount -and $outerCount -ne 181) { Add-Dp1RReason $Reasons "$Context-invalid-installer-entry-count" }
    if ($null -ne $nestedCount -and $nestedCount -ne 11) { Add-Dp1RReason $Reasons "$Context-invalid-uninstaller-entry-count" }
    return [pscustomobject][ordered]@{
        ready = $Reasons.Count -eq $start; version = $version; package_plan_sha256 = $plan
        content_manifest_sha256 = $manifest; content_tree_sha256 = $tree; payload_nsh_sha256 = $payload
        nsis_tree_sha256 = $nsisTree; installer_sha256 = $installerHash; installer_bytes = $installerBytes
        uninstaller_sha256 = $uninstallerHash; uninstaller_bytes = $uninstallerBytes
    }
}

function Get-RimePimeDp1RTrustAdmission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Build,
        [Parameter(Mandatory)]$PostbuildPs5,
        [Parameter(Mandatory)]$PostbuildPs7,
        [Parameter(Mandatory)]$SourceAudit
    )
    $reasons = [Collections.Generic.List[string]]::new()
    $null = Test-Dp1RExactString $Build 'schema_version' 'yime-rime-pime-staged-nsis-build-result-membership-interval-v1' 'build' $reasons
    $null = Test-Dp1RExactString $Build 'product' 'rime-pime' 'build' $reasons
    $buildVersion = Test-Dp1RString $Build 'product_version' 'build' $reasons
    $buildPlan = Test-Dp1RSha256 $Build 'package_plan_sha256' 'build' $reasons
    $buildManifest = Test-Dp1RSha256 $Build 'content_manifest_sha256' 'build' $reasons
    $buildTree = Test-Dp1RSha256 $Build 'content_tree_sha256' 'build' $reasons
    $buildPayload = Test-Dp1RSha256 $Build 'payload_nsh_sha256' 'build' $reasons
    $buildNsisTree = Test-Dp1RSha256 $Build 'nsis_compiler_input_tree_sha256' 'build' $reasons
    $buildInstaller = Test-Dp1RSha256 $Build 'candidate_installer_sha256' 'build' $reasons
    $buildInstallerBytes = Test-Dp1RPositiveInteger $Build 'candidate_installer_bytes' 'build' $reasons
    foreach ($name in @(
        'staged_pe_architecture_verified_under_read_leases','repository_local_compiler_inputs_leased',
        'repository_local_bare_include_shadowing_closed','makensis_no_current_directory_change',
        'makensis_user_config_disabled','nsis_distribution_tree_exact_at_open_and_test',
        'nsis_known_input_file_replacement_closure','nsis_compiler_input_pre_snapshot_exact',
        'nsis_compiler_input_post_snapshot_exact','nsis_compiler_input_leases_held_during_makensis',
        'makensis_path_lease_verified','unsigned_disabled_build','candidate_leased','makensis_executed'
    )) { $null = Test-Dp1RBoolean $Build $name $true 'build' $reasons }
    foreach ($name in @(
        'active_same_sid_transient_tree_membership_interference_excluded','nsis_non_os_compiler_input_closure',
        'full_nsis_toolchain_input_closure','generated_uninstaller_verified','final_payload_closure',
        'installer_executed','uninstaller_executed','signing_hook_processes_executed',
        'installed_product_processes_touched','product_registry_mutated','default_input_method_changed',
        'production_user_data_read_or_written','installed_yimecore_local12_touched'
    )) { $null = Test-Dp1RBoolean $Build $name $false 'build' $reasons }
    $interval = Get-Dp1RNoteProperty $Build 'nsis_compiler_membership_interval' 'build' $reasons
    $null = Test-Dp1RExactString $interval 'schema_version' 'yime-rime-pime-nsis-compiler-membership-interval-v1' 'interval' $reasons
    $null = Test-Dp1RBoolean $interval 'armed_before_baseline' $true 'interval' $reasons
    $null = Test-Dp1RBoolean $interval 'completion_barrier_after_compiler_exit' $true 'interval' $reasons
    $eventCount = Get-Dp1RNoteProperty $interval 'unexpected_membership_event_count' 'interval' $reasons
    if (($eventCount -isnot [byte] -and $eventCount -isnot [int16] -and $eventCount -isnot [int32] -and
        $eventCount -isnot [int64] -and $eventCount -isnot [uint16] -and $eventCount -isnot [uint32] -and
        $eventCount -isnot [uint64]) -or [int64]$eventCount -ne 0) {
        Add-Dp1RReason $reasons 'interval-unexpected-membership-events'
    }

    $ps5 = Test-Dp1RPostbuild $PostbuildPs5 'postbuild-ps5' $reasons
    $ps7 = Test-Dp1RPostbuild $PostbuildPs7 'postbuild-ps7' $reasons
    $null = Test-Dp1RExactString $SourceAudit 'schema_version' 'yime-rime-pime-dp1r-source-audit-v1' 'source-audit' $reasons
    $auditInstaller = Test-Dp1RSha256 $SourceAudit 'installer_source_sha256' 'source-audit' $reasons
    $auditPayload = Test-Dp1RSha256 $SourceAudit 'payload_nsh_sha256' 'source-audit' $reasons
    foreach ($name in @('actual_source_bytes_examined','dynamic_compiler_directives_absent',
        'environment_macro_reads_absent','wildcard_payload_reads_absent','include_roots_closed',
        'executed_build_logic_source_set_hash_bound')) {
        $null = Test-Dp1RBoolean $SourceAudit $name $true 'source-audit' $reasons
    }
    foreach ($name in @('installer_or_uninstaller_executed','registry_or_product_process_touched',
        'installed_yimecore_local12_touched','production_user_data_read_or_written')) {
        $null = Test-Dp1RBoolean $SourceAudit $name $false 'source-audit' $reasons
    }
    # The existing build-result schema binds installer.nsi through its sealed
    # interim/final receipt. The filesystem runner creates SourceAudit from
    # that receipt and the actual source bytes; this pure function does not
    # invent a new property on the historical build result.
    foreach ($binding in @(
        @($buildVersion,$ps5.version,$ps7.version,'product-version'),
        @($buildPlan,$ps5.package_plan_sha256,$ps7.package_plan_sha256,'package-plan'),
        @($buildManifest,$ps5.content_manifest_sha256,$ps7.content_manifest_sha256,'content-manifest'),
        @($buildTree,$ps5.content_tree_sha256,$ps7.content_tree_sha256,'content-tree'),
        @($buildPayload,$ps5.payload_nsh_sha256,$ps7.payload_nsh_sha256,'payload-nsh'),
        @($buildNsisTree,$ps5.nsis_tree_sha256,$ps7.nsis_tree_sha256,'nsis-tree'),
        @($buildInstaller,$ps5.installer_sha256,$ps7.installer_sha256,'installer-sha256'),
        @($buildInstallerBytes,$ps5.installer_bytes,$ps7.installer_bytes,'installer-bytes'),
        @($ps5.uninstaller_sha256,$ps7.uninstaller_sha256,$ps7.uninstaller_sha256,'uninstaller-sha256'),
        @($ps5.uninstaller_bytes,$ps7.uninstaller_bytes,$ps7.uninstaller_bytes,'uninstaller-bytes'),
        @($buildPayload,$auditPayload,$auditPayload,'source-audit-payload-nsh')
    )) {
        if ($null -eq $binding[0] -or $null -eq $binding[1] -or $null -eq $binding[2] -or
            [string]$binding[0] -cne [string]$binding[1] -or [string]$binding[0] -cne [string]$binding[2]) {
            Add-Dp1RReason $reasons ("cross-binding-mismatch-" + $binding[3])
        }
    }
    $ready = $reasons.Count -eq 0
    return [pscustomobject][ordered]@{
        schema_version = $script:Dp1RSchema
        review_ready = $ready
        reasons = @($reasons)
        full_payload_static_closure = [bool]$ready
        nsis_non_os_compiler_input_closure = [bool]$ready
        generated_uninstaller_verified = [bool]$ready
        generated_uninstaller_trusted_for_unsigned_disabled_static_scope = [bool]$ready
        independent_ps5_ps7_postbuild_convergence = [bool]$ready
        historical_build_and_postbuild_non_claims_preserved = $true
        active_same_sid_physical_replacement_prevented = $false
        full_nsis_toolchain_input_closure = $false
        generated_uninstaller_signature_trusted = $false
        signing_complete = $false
        delivery_admitted = $false
        installer_or_uninstaller_execution_admitted = $false
        installed_or_registered_host_action_admitted = $false
        installed_yimecore_action_admitted = $false
        dp1_complete = $false
    }
}

Export-ModuleMember -Function 'Get-RimePimeDp1RTrustAdmission'
