[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd([char]92)
$parent = Join-Path $repo '.tmp\dual-product'
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd([char]92)
if ((Split-Path -Parent $output) -ine $parent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-r-trust-admission-test-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a fresh immediate .tmp/dual-product/dp1-r-trust-admission-test-* root.'
}
$null = New-Item -ItemType Directory -Path $output
$modulePath = Join-Path $PSScriptRoot 'rime-pime-dp1r-trust-admission.psm1'
$module = Import-Module $modulePath -Force -PassThru
$hex = @{
    plan=('1'*64); manifest=('2'*64); tree=('3'*64); payload=('4'*64); nsis=('5'*64)
    installer=('6'*64); uninstaller=('7'*64); source=('8'*64)
}

function New-BuildFixture {
    [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-staged-nsis-build-result-membership-interval-v1'
        product='rime-pime';product_version='1.4.0-dev.1';package_plan_sha256=$hex.plan
        content_manifest_sha256=$hex.manifest;content_tree_sha256=$hex.tree;payload_nsh_sha256=$hex.payload
        nsis_compiler_input_tree_sha256=$hex.nsis;candidate_installer_sha256=$hex.installer
        candidate_installer_bytes=[long]41455231
        staged_pe_architecture_verified_under_read_leases=$true;repository_local_compiler_inputs_leased=$true
        repository_local_bare_include_shadowing_closed=$true;makensis_no_current_directory_change=$true
        makensis_user_config_disabled=$true;nsis_distribution_tree_exact_at_open_and_test=$true
        nsis_known_input_file_replacement_closure=$true;nsis_compiler_input_pre_snapshot_exact=$true
        nsis_compiler_input_post_snapshot_exact=$true;nsis_compiler_input_leases_held_during_makensis=$true
        makensis_path_lease_verified=$true;unsigned_disabled_build=$true;candidate_leased=$true;makensis_executed=$true
        active_same_sid_transient_tree_membership_interference_excluded=$false
        nsis_non_os_compiler_input_closure=$false;full_nsis_toolchain_input_closure=$false
        generated_uninstaller_verified=$false;final_payload_closure=$false;installer_executed=$false
        uninstaller_executed=$false;signing_hook_processes_executed=$false
        installed_product_processes_touched=$false;product_registry_mutated=$false;default_input_method_changed=$false
        production_user_data_read_or_written=$false;installed_yimecore_local12_touched=$false
        nsis_compiler_membership_interval=[pscustomobject][ordered]@{
            schema_version='yime-rime-pime-nsis-compiler-membership-interval-v1'
            armed_before_baseline=$true;completion_barrier_after_compiler_exit=$true
            unexpected_membership_event_count=0;notification_batch_count=1
            physical_membership_prevention_claimed=$false
            active_same_sid_transient_tree_membership_interference_excluded=$false
            nsis_non_os_compiler_input_closure=$false;full_nsis_toolchain_input_closure=$false
        }
    }
}

function New-ImageFixture([string]$Hash,[long]$Bytes) {
    [pscustomobject][ordered]@{
        path='C:\fixture\image.exe';bytes=$Bytes;sha256=$Hash;machine='x86'
        file_version='1.4.0-dev.1';product_version='1.4.0-dev.1';company_name='YIME Project'
        signature_status='NotSigned';package_plan_raw_byte_binding=$true
        content_manifest_raw_byte_binding=$true;content_tree_raw_byte_binding=$true
        payload_nsh_raw_byte_binding=$true;trusted=$false
    }
}

function New-PostbuildFixture {
    [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-postbuild-extraction-v1';product='rime-pime';product_version='1.4.0-dev.1'
        package_plan_sha256=$hex.plan;content_manifest_sha256=$hex.manifest;content_tree_sha256=$hex.tree
        payload_nsh_sha256=$hex.payload;nsis_compiler_input_tree_sha256=$hex.nsis
        nsis_distribution_inputs_exact_and_read_leased_during_postbuild=$true
        nsis_known_input_file_replacement_closure=$true;installer_archive_listing_exact=$true
        nested_uninstaller_archive_listing_exact=$true;stable_extracted_snapshot_matches_expected_sources=$true
        stable_extracted_stage_owned_files_match_sealed_manifest=$true
        installer_archive_per_entry_raw_stdout_verified=$true;nested_uninstaller_archive_per_entry_raw_stdout_verified=$true
        archive_content_origin_proven=$true;archive_content_provenance_closed_against_active_same_sid_replacement=$true
        active_same_sid_extracted_path_interference_excluded_from_archive_byte_provenance=$true
        package_plan_stage_bindings_verified=$true;payload_nsh_raw_byte_binding_verified=$true
        execution_logic_read_leases_held_through_seal=$true
        extraction_root_and_expected_directory_identity_leases_held_through_seal=$true
        extracted_file_read_leases_held_through_seal=$true;raw_generated_uninstaller_capture_read_lease_held_through_seal=$true
        result_json_and_sidecar_create_new_digest_bound_leases_held_through_runner_pass=$true
        text_logs_create_new_memory_digest_bound_and_leased_through_result_seal=$true
        installer_read_lease_held_for_all_reads=$true;uninstaller_read_lease_held_for_all_reads=$true
        seven_zip_read_lease_held_for_all_calls=$true;seven_zip_parser_library_read_lease_held_for_all_calls=$true
        generated_uninstaller_present=$true;generated_uninstaller_static_archive_member_verified=$true
        active_same_sid_transient_tree_membership_interference_excluded=$false
        nsis_compiler_input_leases_held_during_makensis=$false;nsis_non_os_compiler_input_closure=$false
        full_nsis_toolchain_input_closure=$false;generated_uninstaller_verified=$false
        generated_uninstaller_trusted=$false;final_payload_closure=$false;delivery_admitted=$false
        actual_installer_or_uninstaller_executed=$false;product_process_started_or_stopped=$false
        registry_touched=$false;default_input_method_changed=$false;production_user_data_read_or_written=$false
        installed_yimecore_local12_touched=$false
        installer=(New-ImageFixture $hex.installer 41455231)
        generated_uninstaller=(New-ImageFixture $hex.uninstaller 585292)
        installer_archive=[pscustomobject][ordered]@{entry_count=181}
        uninstaller_archive=[pscustomobject][ordered]@{entry_count=11}
    }
}

function New-SourceAuditFixture {
    [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-dp1r-source-audit-v1';installer_source_sha256=$hex.source
        payload_nsh_sha256=$hex.payload;actual_source_bytes_examined=$true
        dynamic_compiler_directives_absent=$true;environment_macro_reads_absent=$true
        wildcard_payload_reads_absent=$true;include_roots_closed=$true
        executed_build_logic_source_set_hash_bound=$true;installer_or_uninstaller_executed=$false
        registry_or_product_process_touched=$false;installed_yimecore_local12_touched=$false
        production_user_data_read_or_written=$false
    }
}

function New-Case {
    [pscustomobject]@{Build=(New-BuildFixture);Ps5=(New-PostbuildFixture);Ps7=(New-PostbuildFixture);Audit=(New-SourceAuditFixture)}
}

function Invoke-Case($Case) {
    Get-RimePimeDp1RTrustAdmission -Build $Case.Build -PostbuildPs5 $Case.Ps5 -PostbuildPs7 $Case.Ps7 -SourceAudit $Case.Audit
}

$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action) {
    try { & $Action; $checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true}) }
    catch { $checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;error=$_.Exception.Message}) }
}
function Assert-True([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message } }
function Assert-Rejected($Case,[string]$ExpectedReason) {
    $result=Invoke-Case $Case
    Assert-True (-not $result.review_ready) 'Unsafe evidence was admitted.'
    Assert-True (@($result.reasons) -ccontains $ExpectedReason) "Expected rejection reason missing: $ExpectedReason"
    Assert-True (-not $result.full_payload_static_closure -and -not $result.nsis_non_os_compiler_input_closure -and
        -not $result.generated_uninstaller_verified -and -not $result.generated_uninstaller_trusted_for_unsigned_disabled_static_scope) `
        'A failed review promoted a trust field.'
}

Check 'complete-converged-evidence-is-admitted-in-static-scope' {
    $result=Invoke-Case (New-Case)
    Assert-True ($result.review_ready -and $result.full_payload_static_closure -and
        $result.nsis_non_os_compiler_input_closure -and $result.generated_uninstaller_verified -and
        $result.generated_uninstaller_trusted_for_unsigned_disabled_static_scope -and
        $result.independent_ps5_ps7_postbuild_convergence) 'Complete evidence was not admitted.'
    Assert-True ($result.historical_build_and_postbuild_non_claims_preserved -and
        -not $result.active_same_sid_physical_replacement_prevented -and
        -not $result.full_nsis_toolchain_input_closure -and -not $result.generated_uninstaller_signature_trusted -and
        -not $result.signing_complete -and -not $result.delivery_admitted -and -not $result.dp1_complete) `
        'Static admission overclaimed a downstream or physical boundary.'
}
Check 'membership-event-is-rejected' {$c=New-Case;$c.Build.nsis_compiler_membership_interval.unexpected_membership_event_count=1;Assert-Rejected $c 'interval-unexpected-membership-events'}
Check 'missing-completion-barrier-is-rejected' {$c=New-Case;$c.Build.nsis_compiler_membership_interval.completion_barrier_after_compiler_exit=$false;Assert-Rejected $c 'interval-invalid-completion_barrier_after_compiler_exit'}
Check 'compiler-input-lease-gap-is-rejected' {$c=New-Case;$c.Build.nsis_compiler_input_leases_held_during_makensis=$false;Assert-Rejected $c 'build-invalid-nsis_compiler_input_leases_held_during_makensis'}
Check 'ps5-installer-mismatch-is-rejected' {$c=New-Case;$c.Ps5.installer.sha256=('a'*64);Assert-Rejected $c 'cross-binding-mismatch-installer-sha256'}
Check 'ps7-uninstaller-mismatch-is-rejected' {$c=New-Case;$c.Ps7.generated_uninstaller.sha256=('a'*64);Assert-Rejected $c 'cross-binding-mismatch-uninstaller-sha256'}
Check 'outer-archive-extra-member-count-is-rejected' {$c=New-Case;$c.Ps7.installer_archive.entry_count=182;Assert-Rejected $c 'postbuild-ps7-invalid-installer-entry-count'}
Check 'nested-uninstaller-extra-member-count-is-rejected' {$c=New-Case;$c.Ps5.uninstaller_archive.entry_count=12;Assert-Rejected $c 'postbuild-ps5-invalid-uninstaller-entry-count'}
Check 'uninstaller-raw-binding-gap-is-rejected' {$c=New-Case;$c.Ps7.generated_uninstaller.payload_nsh_raw_byte_binding=$false;Assert-Rejected $c 'postbuild-ps7-uninstaller-invalid-payload_nsh_raw_byte_binding'}
Check 'source-dynamic-directive-gap-is-rejected' {$c=New-Case;$c.Audit.dynamic_compiler_directives_absent=$false;Assert-Rejected $c 'source-audit-invalid-dynamic_compiler_directives_absent'}
Check 'source-payload-binding-mismatch-is-rejected' {$c=New-Case;$c.Audit.payload_nsh_sha256=('a'*64);Assert-Rejected $c 'cross-binding-mismatch-source-audit-payload-nsh'}
Check 'historical-field-promotion-is-rejected' {$c=New-Case;$c.Build.nsis_non_os_compiler_input_closure=$true;Assert-Rejected $c 'build-invalid-nsis_non_os_compiler_input_closure'}
Check 'script-property-is-not-executed' {
    $c=New-Case;$global:dp1rGetterRan=$false
    $c.Ps5.PSObject.Properties.Remove('product')
    $c.Ps5|Add-Member -MemberType ScriptProperty -Name product -Value {$global:dp1rGetterRan=$true;'rime-pime'}
    Assert-Rejected $c 'postbuild-ps5-missing-product'
    Assert-True (-not $global:dp1rGetterRan) 'A ScriptProperty getter executed.'
}
Check 'module-exports-only-review-api' {
    $actual=@($module.ExportedFunctions.Keys|Sort-Object)
    Assert-True (($actual -join '|') -ceq 'Get-RimePimeDp1RTrustAdmission') 'Module export surface drifted.'
}
Check 'module-has-no-mutation-or-execution-surface' {
    $source=[IO.File]::ReadAllText($modulePath)
    foreach($forbidden in @('Start-Process','Invoke-Expression','Invoke-Command','Remove-Item','Move-Item','Copy-Item',
        'Set-Content','Add-Content','WriteAll','Registry::','HKLM','HKCU','Get-Process','Stop-Process','makensis.exe','7z.exe')) {
        Assert-True (-not $source.Contains($forbidden)) "Pure review module contains forbidden surface: $forbidden"
    }
}

$failed=@($checks|Where-Object{-not $_.passed})
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-dp1r-trust-admission-test-v1'
    powershell=$PSVersionTable.PSVersion.ToString();passed=$failed.Count -eq 0
    check_count=$checks.Count;passed_count=@($checks|Where-Object{$_.passed}).Count;failed_count=$failed.Count
    checks=@($checks);fixture_only=$true;actual_candidate_review_executed=$false
    actual_installer_or_uninstaller_executed=$false;registry_or_product_process_touched=$false
    installed_yimecore_local12_touched=$false;production_user_data_read_or_written=$false
    full_nsis_toolchain_input_closure=$false;signing_complete=$false;delivery_admitted=$false;dp1_complete=$false
    module_sha256=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
$resultPath=Join-Path $output 'result.json'
$json=($result|ConvertTo-Json -Depth 8 -Compress)+"`n"
[IO.File]::WriteAllText($resultPath,$json,[Text.UTF8Encoding]::new($false))
$digest=(Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($resultPath+'.sha256',$digest+"`n",[Text.UTF8Encoding]::new($false))
if($failed.Count){$failed|Format-Table -AutoSize|Out-String|Write-Host;throw "$($failed.Count) of $($checks.Count) DP1-R trust admission checks failed."}
Write-Host "PASS: $($checks.Count) DP1-R trust-admission checks passed. Evidence: $resultPath ($digest)"
