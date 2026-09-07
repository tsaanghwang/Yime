param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$workParent = Join-Path $repo '.tmp\dual-product'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $workParent ('dp1-actual-migration-review-test-' + [guid]::NewGuid().ToString('N'))
}
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if ((Split-Path -Parent $output) -ine $workParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-actual-migration-review-test-[A-Za-z0-9][A-Za-z0-9._-]*$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'OutputRoot must be a fresh immediate .tmp/dual-product/dp1-actual-migration-review-test-* directory.'
}

function Assert-NoReviewReparsePath([string]$Path) {
    for ($cursor = [IO.Path]::GetFullPath($Path); $cursor; $cursor = Split-Path -Parent $cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Review fixture path traverses a reparse point: $cursor"
            }
        }
        $parent = Split-Path -Parent $cursor
        if ($parent -eq $cursor) { break }
    }
}

if (-not (Test-Path -LiteralPath $workParent -PathType Container)) {
    New-Item -ItemType Directory -Path $workParent -Force | Out-Null
}
Assert-NoReviewReparsePath $workParent
New-Item -ItemType Directory -Path $output | Out-Null
Assert-NoReviewReparsePath $output

$modulePath = Join-Path $PSScriptRoot 'rime-pime-actual-migration-review.psm1'
Import-Module -Name $modulePath -Force
$module = Get-Module rime-pime-actual-migration-review
$checks = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[object]]::new()

function Assert-ReviewTrue([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Check([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true;detail=''})
    } catch {
        $record = [pscustomobject][ordered]@{name=$Name;passed=$false;detail=[string]$_.Exception.Message}
        $checks.Add($record)
        $failures.Add($record)
    }
}

function Copy-ReviewObject {
    param($Value, [string]$Omit = '', [hashtable]$Overrides = @{})
    $copy = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
        if ([string]$property.Name -cne $Omit) { $copy[[string]$property.Name] = $property.Value }
    }
    foreach ($name in $Overrides.Keys) { $copy[[string]$name] = $Overrides[$name] }
    return [pscustomobject]$copy
}

function New-CompleteReviewInput {
    $oldReceipt = 'a' * 64
    $oldSidecar = 'b' * 64
    $oldInstaller = 'c' * 64
    $actualSnapshot = 'd' * 64
    $newReceipt = 'e' * 64
    $newInstaller = 'f' * 64
    $archiveManifest = '1' * 64
    $adapterDigest = '2' * 64
    $adapterSourceSet = '3' * 64
    $migrationPlan = '4' * 64
    $faultMatrix = '5' * 64
    $authorizationRecord = '6' * 64
    $sourceHead = '7' * 40
    $sourceTree = '8' * 40
    $runnerBlob = '9' * 40

    $identity = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-version-identity-admission-v1'
        identity_transition_admitted=$true
        reasons=@()
        old_product_version='1.4.0-dev'
        successor_product_version='1.4.0-dev.1'
        expected_successor_product_version='1.4.0-dev.1'
        old_installer_path='installer/YIME-1.4.0-dev-setup.exe'
        successor_installer_path='installer/YIME-1.4.0-dev.1-setup.exe'
        paths_compared_case_insensitively_for_windows=$true
        actual_canonical_migration_admitted=$false
        actual_canonical_migrated=$false
        installer_or_uninstaller_executed=$false
        registry_or_product_process_touched=$false
    }
    $old = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-actual-migration-old-canonical-v1'
        product='rime-pime'
        repo_root='C:\dev\Yime'
        product_version='1.4.0-dev'
        receipt_path='installer/package-build-receipt.json'
        receipt_sha256=$oldReceipt
        receipt_sidecar_sha256=$oldSidecar
        receipt_sidecar_binds_receipt=$true
        strict_receipt_ps5=$true
        strict_receipt_ps7=$true
        installer_path='installer/YIME-1.4.0-dev-setup.exe'
        installer_sha256=$oldInstaller
        installer_bytes=[long]41456428
        physical_installer_matches_receipt=$true
        canonical_pair_file_identity_bound=$true
        normal_leaf_guards_passed=$true
        pending_transaction_absent=$true
        successor_installer_absent=$true
        protected_snapshot_sha256=$actualSnapshot
        actual_snapshot_bound=$true
    }
    $successor = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-actual-migration-successor-v1'
        product='rime-pime'
        product_version='1.4.0-dev.1'
        package_profile='x86-x64-v1'
        receipt_sha256=$newReceipt
        strict_receipt_ps5=$true
        strict_receipt_ps7=$true
        evidence_artifacts_durable=$true
        current_build_evidence=$true
        installer_path='installer/YIME-1.4.0-dev.1-setup.exe'
        installer_sha256=$newInstaller
        installer_bytes=[long]41455231
        physical_installer_matches_receipt=$true
        exact_source_head=$sourceHead
        exact_source_tree=$sourceTree
        runner_head_blob=$runnerBlob
        runner_worktree_blob=$runnerBlob
        runner_matches_exact_head=$true
        version_contract_matches=$true
        detached_clean_head=$true
        unsigned_disabled=$true
        installer_executed=$false
        signing_complete=$false
        delivery_admitted=$false
    }
    $archive = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-off-repository-archive-evidence-v1'
        archive_root='C:\Yime Rime-PIME Evidence Archives\dp1q-fixture'
        archive_manifest_sha256=$archiveManifest
        archive_manifest_bytes=[long]8192
        archive_manifest_sidecar_valid=$true
        outside_repository=$true
        outside_outer_tmp=$true
        outside_all_git_worktrees=$true
        system_visible_from_unpacked_process=$true
        archive_root_not_reparse=$true
        archive_files_not_hardlinked=$true
        archive_files_have_no_ads=$true
        object_set_exact=$true
        archived_object_count=[long]24
        all_objects_hash_and_bytes_match=$true
        all_object_sidecars_valid=$true
        receipt_evidence_set_complete=$true
        successor_installer_archived=$true
        successor_receipt_archived=$true
        historical_v1_archived=$true
        runner_result_archived=$true
        identity_admission_archived=$true
        old_canonical_snapshot_archived=$true
        ps5_verification_archived=$true
        ps7_verification_archived=$true
        source_head_tree_bound=$true
        source_head=$sourceHead
        source_tree=$sourceTree
        successor_receipt_sha256=$newReceipt
        successor_installer_sha256=$newInstaller
        temporary_source_unavailable_during_reverification=$true
        fresh_process_reopen_ps5=$true
        fresh_process_reopen_ps7=$true
        strict_receipt_read_ps5_without_source=$true
        strict_receipt_read_ps7_without_source=$true
        candidate_hash_verified_without_source=$true
    }
    $adapter = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-actual-canonical-adapter-evidence-v1'
        adapter_kind='actual-checkout-dedicated'
        actual_repo_root='C:\dev\Yime'
        adapter_path='tools/dual-product/invoke-rime-pime-actual-canonical-migration.ps1'
        adapter_sha256=$adapterDigest
        adapter_source_set_sha256=$adapterSourceSet
        migration_plan_sha256=$migrationPlan
        fault_matrix_sha256=$faultMatrix
        actual_checkout_dedicated=$true
        dp1n_fixture_gate_preserved=$true
        fixture_api_rejects_actual_checkout=$true
        dry_run_supported=$true
        dry_run_exact_write_set_verified=$true
        write_set_roles=@(
            'unique-staging-leaves','retained-evidence-objects','retained-evidence-sidecars',
            'successor-installer-stage','successor-installer','pending-intent','canonical-receipt',
            'canonical-sidecar','completed-intent'
        )
        write_set_limited_to_canonical_artifacts=$true
        expected_old_receipt_sha256=$oldReceipt
        expected_successor_receipt_sha256=$newReceipt
        expected_successor_installer_sha256=$newInstaller
        expected_actual_snapshot_sha256=$actualSnapshot
        archive_manifest_sha256=$archiveManifest
        old_receipt_cas_enforced=$true
        successor_archive_cas_enforced=$true
        protected_snapshot_preflight_bound=$true
        shared_publication_lock=$true
        pre_intent_retriable_without_canonical_change=$true
        post_intent_roll_forward_only=$true
        four_state_recovery_verified=$true
        fresh_process_recovery_ps5=$true
        fresh_process_recovery_ps7=$true
        fault_matrix_ps5=$true
        fault_matrix_ps7=$true
        stale_cas_rejected=$true
        no_replace_races_verified=$true
        foreign_state_fails_closed=$true
        old_installer_preserved=$true
        unrelated_installer_leaves_preserved=$true
        yimecore_unchanged=$true
        registry_unchanged=$true
        product_processes_unchanged=$true
        default_input_method_unchanged=$true
        production_user_data_untouched=$true
        hardware_power_loss_recovery_verified=$true
        directory_metadata_durability_verified=$true
        hostile_same_sid_replacement_prevented=$true
    }
    $authorization = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-actual-canonical-authorization-v1'
        authorization_kind='one-time-actual-canonical-artifact-migration'
        authorization_id='synthetic-fixture-authorization'
        authorization_record_sha256=$authorizationRecord
        explicit_user_authorization=$true
        one_time_authorization=$true
        repo_root='C:\dev\Yime'
        scope='actual-canonical-artifacts-only'
        migration_plan_sha256=$migrationPlan
        old_receipt_sha256=$oldReceipt
        successor_receipt_sha256=$newReceipt
        successor_installer_sha256=$newInstaller
        actual_snapshot_sha256=$actualSnapshot
        archive_manifest_sha256=$archiveManifest
        adapter_sha256=$adapterDigest
    }
    $boundaries = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-actual-canonical-downstream-boundaries-v1'
        installer_execution_in_scope=$false
        uninstaller_execution_in_scope=$false
        signing_in_scope=$false
        delivery_in_scope=$false
        installed_or_registered_host_in_scope=$false
        arm64_native_claim_in_scope=$false
        product_registry_mutation_in_scope=$false
        product_process_action_in_scope=$false
        default_input_method_change_in_scope=$false
        production_user_data_access_in_scope=$false
        installed_yimecore_mutation_in_scope=$false
        generated_uninstaller_trust_claimed=$false
        final_payload_closure_claimed=$false
        full_nsis_toolchain_closure_claimed=$false
        dp1_or_release_completion_claimed=$false
    }
    return [pscustomobject]@{
        IdentityAdmission=$identity;OldCanonical=$old;Successor=$successor
        ArchiveEvidence=$archive;AdapterEvidence=$adapter
        AuthorizationEvidence=$authorization;DownstreamBoundaries=$boundaries
    }
}

function Invoke-ReviewCase($Case) {
    return Get-RimePimeActualMigrationReview -IdentityAdmission $Case.IdentityAdmission `
        -OldCanonical $Case.OldCanonical -Successor $Case.Successor `
        -ArchiveEvidence $Case.ArchiveEvidence -AdapterEvidence $Case.AdapterEvidence `
        -AuthorizationEvidence $Case.AuthorizationEvidence -DownstreamBoundaries $Case.DownstreamBoundaries
}

Check 'module-exports-only-one-pure-review-function' {
    $exports = @($module.ExportedCommands.Keys)
    Assert-ReviewTrue ($exports.Count -eq 1 -and $exports[0] -ceq 'Get-RimePimeActualMigrationReview') 'Module export surface is not exact.'
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($modulePath,[ref]$tokens,[ref]$parseErrors)
    Assert-ReviewTrue ($parseErrors.Count -eq 0) (($parseErrors | ForEach-Object Message) -join '; ')
    $forbidden = @(
        'Get-Content','Set-Content','Get-Item','Set-Item','Test-Path','New-Item','Remove-Item','Copy-Item','Move-Item',
        'Start-Process','Stop-Process','Invoke-Expression','Import-Module','Read-RimePimePackageBuildReceiptV2',
        'Publish-RimePimeInstallerReceiptTransaction','Resume-RimePimeInstallerReceiptTransaction'
    )
    foreach ($commandAst in @($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true))) {
        $commandName = $commandAst.GetCommandName()
        Assert-ReviewTrue ($null -eq $commandName -or $forbidden -cnotcontains $commandName) "Pure review module contains forbidden command: $commandName"
    }
    $source = [IO.File]::ReadAllText($modulePath)
    foreach ($pattern in @('\[IO\.File','\[Microsoft\.Win32\.Registry','\[Diagnostics\.Process','Registry::','installer\\package-build-receipt\.json')) {
        Assert-ReviewTrue ($source -notmatch $pattern) "Pure review module contains forbidden source pattern: $pattern"
    }
}

Check 'complete-synthetic-evidence-is-review-ready-but-never-admitted' {
    $result = Invoke-ReviewCase (New-CompleteReviewInput)
    Assert-ReviewTrue $result.review_ready 'Complete synthetic evidence was not review-ready.'
    Assert-ReviewTrue ($result.reasons.Count -eq 0) 'Complete synthetic evidence has rejection reasons.'
    Assert-ReviewTrue ($result.source_admission_ready -and $result.off_repository_archive_ready -and
        $result.actual_adapter_ready -and $result.explicit_authorization_ready -and
        $result.downstream_boundaries_preserved) 'A review section did not pass.'
    Assert-ReviewTrue (-not $result.actual_canonical_migration_admitted -and -not $result.actual_canonical_migrated -and
        $result.separate_execution_gate_required) 'Review readiness was promoted into migration admission.'
}

Check 'every-required-field-has-a-stable-missing-reason' {
    $mapping = @(
        @('IdentityAdmission','identity-admission'),@('OldCanonical','old-canonical'),
        @('Successor','successor'),@('ArchiveEvidence','archive'),@('AdapterEvidence','adapter'),
        @('AuthorizationEvidence','authorization'),@('DownstreamBoundaries','downstream-boundaries')
    )
    foreach ($entry in $mapping) {
        $baseline = New-CompleteReviewInput
        $object = $baseline.($entry[0])
        foreach ($property in @($object.PSObject.Properties)) {
            $case = New-CompleteReviewInput
            $case.($entry[0]) = Copy-ReviewObject $case.($entry[0]) ([string]$property.Name)
            $result = Invoke-ReviewCase $case
            $expected = [string]$entry[1] + '-missing-' + ([string]$property.Name).Replace('_','-')
            Assert-ReviewTrue (-not $result.review_ready) "Missing field was admitted: $($entry[0]).$($property.Name)"
            Assert-ReviewTrue (@($result.reasons) -ccontains $expected) "Stable missing-field reason absent: $expected"
        }
    }
}

Check 'unexpected-fields-fail-closed' {
    $case = New-CompleteReviewInput
    $case.AdapterEvidence = Copy-ReviewObject $case.AdapterEvidence '' @{unreviewed_switch=$true}
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.review_ready) 'Unexpected adapter field was admitted.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'adapter-unexpected-unreviewed-switch') 'Unexpected-field reason is missing.'
}

Check 'script-property-getters-are-rejected-without-execution' {
    $case = New-CompleteReviewInput
    $script:reviewGetterExecutions = 0
    $case.IdentityAdmission.PSObject.Properties.Remove('schema_version')
    $case.IdentityAdmission | Add-Member -MemberType ScriptProperty -Name schema_version -Value {
        $script:reviewGetterExecutions++
        return 'yime-rime-pime-version-identity-admission-v1'
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue ($script:reviewGetterExecutions -eq 0) 'Review executed an input ScriptProperty getter.'
    Assert-ReviewTrue (-not $result.review_ready) 'Non-note input property was admitted.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'identity-admission-non-note-property-schema-version') `
        'Non-note input property reason is missing.'
}

Check 'identity-binding-fields-must-be-nonempty-strings' {
    $case = New-CompleteReviewInput
    $case.IdentityAdmission = Copy-ReviewObject $case.IdentityAdmission '' @{
        old_product_version=$null;successor_product_version=$null
        expected_successor_product_version=$null;old_installer_path=$null;successor_installer_path=$null
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.review_ready -and -not $result.source_admission_ready) `
        'Null identity bindings were admitted.'
    foreach ($name in @(
        'old-product-version','successor-product-version','expected-successor-product-version',
        'old-installer-path','successor-installer-path')) {
        Assert-ReviewTrue (@($result.reasons) -ccontains ('identity-admission-'+$name+'-not-nonempty-string')) `
            "Null identity binding reason is missing: $name"
    }

    $case = New-CompleteReviewInput
    $case.IdentityAdmission = Copy-ReviewObject $case.IdentityAdmission '' @{
        old_product_version=[pscustomobject]@{text='1.4.0-dev'}
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.review_ready -and
        @($result.reasons) -ccontains 'identity-admission-old-product-version-not-nonempty-string') `
        'Non-string identity binding was admitted through string coercion.'
}

Check 'identity-admission-cannot-overclaim-actual-migration' {
    $case = New-CompleteReviewInput
    $case.IdentityAdmission = Copy-ReviewObject $case.IdentityAdmission '' @{actual_canonical_migration_admitted=$true}
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.review_ready -and -not $result.actual_canonical_migration_admitted) 'Overclaiming identity admission escaped the review boundary.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'identity-admission-actual-canonical-migration-admitted-not-false') 'Identity overclaim reason is missing.'
}

Check 'semver-downgrade-and-windows-case-only-leaf-are-rejected' {
    $case = New-CompleteReviewInput
    $case.Successor = Copy-ReviewObject $case.Successor '' @{
        product_version='1.3.9';installer_path='INSTALLER/YIME-1.4.0-DEV-SETUP.EXE'
    }
    $case.IdentityAdmission = Copy-ReviewObject $case.IdentityAdmission '' @{
        successor_product_version='1.3.9';expected_successor_product_version='1.3.9';
        successor_installer_path='INSTALLER/YIME-1.4.0-DEV-SETUP.EXE'
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (@($result.reasons) -ccontains 'successor-version-not-strictly-greater-by-semver') 'SemVer downgrade reason is missing.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'old-and-successor-installer-path-not-distinct-on-windows') 'Case-insensitive Windows leaf reason is missing.'
}

Check 'archive-must-survive-source-unavailability-in-fresh-ps5-and-ps7-processes' {
    $case = New-CompleteReviewInput
    $case.ArchiveEvidence = Copy-ReviewObject $case.ArchiveEvidence '' @{
        temporary_source_unavailable_during_reverification=$false;fresh_process_reopen_ps5=$false;
        strict_receipt_read_ps7_without_source=$false
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.off_repository_archive_ready) 'Source-dependent archive was admitted.'
    foreach ($reason in @(
        'archive-temporary-source-unavailable-during-reverification-not-true',
        'archive-fresh-process-reopen-ps5-not-true',
        'archive-strict-receipt-read-ps7-without-source-not-true')) {
        Assert-ReviewTrue (@($result.reasons) -ccontains $reason) "Archive rejection reason is missing: $reason"
    }
}

Check 'archive-root-inside-authorized-repository-is-rejected' {
    $case = New-CompleteReviewInput
    $case.ArchiveEvidence = Copy-ReviewObject $case.ArchiveEvidence '' @{archive_root='C:\dev\Yime\archive'}
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.off_repository_archive_ready) 'In-repository archive root left the archive section ready.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'archive-root-is-inside-actual-repository') 'In-repository archive root was admitted.'
}

Check 'archive-and-repository-paths-must-be-canonical-and-cross-bound' {
    $case = New-CompleteReviewInput
    $case.ArchiveEvidence = Copy-ReviewObject $case.ArchiveEvidence '' @{
        archive_root='C:\dev\Yime2\..\Yime\archive'
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.review_ready -and -not $result.off_repository_archive_ready) `
        'Dot-segment archive path bypassed the repository boundary.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'archive-archive-root-not-canonical-windows-path') `
        'Non-canonical archive path reason is missing.'

    $case = New-CompleteReviewInput
    $case.AuthorizationEvidence = Copy-ReviewObject $case.AuthorizationEvidence '' @{repo_root='C:\not-yime'}
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.review_ready -and -not $result.explicit_authorization_ready) `
        'Authorization for a different repository was admitted.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'authorization-repo-root-binding-mismatch') `
        'Authorization repository binding reason is missing.'
}

Check 'canonical-windows-paths-and-adapter-path-fail-closed' {
    $case = New-CompleteReviewInput
    $case.ArchiveEvidence = Copy-ReviewObject $case.ArchiveEvidence '' @{
        archive_root='C:\Yime Rime-PIME Evidence Archives\bad*archive'
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.review_ready -and -not $result.off_repository_archive_ready) `
        'Archive path containing an invalid Windows character was admitted.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'archive-archive-root-not-canonical-windows-path') `
        'Invalid-character archive path reason is missing.'

    $case = New-CompleteReviewInput
    $case.AdapterEvidence = Copy-ReviewObject $case.AdapterEvidence '' @{
        adapter_path='..\..\outside.ps1'
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.review_ready -and -not $result.actual_adapter_ready) `
        'Non-canonical adapter path was admitted.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'adapter-adapter-path-unexpected-value') `
        'Non-canonical adapter path reason is missing.'
}

Check 'archive-source-and-successor-digests-are-bound' {
    $case = New-CompleteReviewInput
    $case.ArchiveEvidence = Copy-ReviewObject $case.ArchiveEvidence '' @{
        source_head=('0'*40);successor_receipt_sha256=('0'*64);successor_installer_sha256=('9'*64)
    }
    $result = Invoke-ReviewCase $case
    foreach ($reason in @('archive-source-head-binding-mismatch','archive-successor-receipt-binding-mismatch','archive-successor-installer-binding-mismatch')) {
        Assert-ReviewTrue (@($result.reasons) -ccontains $reason) "Archive binding reason is missing: $reason"
    }
}

Check 'downstream-readiness-depends-on-valid-upstream-bindings' {
    $case = New-CompleteReviewInput
    $case.Successor = Copy-ReviewObject $case.Successor '' @{exact_source_head='bad'}
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.source_admission_ready) 'Invalid source identity left source admission ready.'
    Assert-ReviewTrue (-not $result.off_repository_archive_ready -and -not $result.actual_adapter_ready -and
        -not $result.explicit_authorization_ready) `
        'A downstream readiness flag survived an invalid upstream binding.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'successor-exact-source-head-invalid-git-object') `
        'Invalid upstream source reason is missing.'
}

Check 'actual-adapter-must-preserve-dp1n-fixture-gate-and-exact-write-set' {
    $case = New-CompleteReviewInput
    $case.AdapterEvidence = Copy-ReviewObject $case.AdapterEvidence '' @{
        dp1n_fixture_gate_preserved=$false;fixture_api_rejects_actual_checkout=$false;
        write_set_roles=@('canonical-receipt')
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.actual_adapter_ready) 'Adapter that weakens the fixture gate was admitted.'
    foreach ($reason in @(
        'adapter-dp1n-fixture-gate-preserved-not-true','adapter-fixture-api-rejects-actual-checkout-not-true',
        'adapter-write-set-roles-unexpected-ordered-set')) {
        Assert-ReviewTrue (@($result.reasons) -ccontains $reason) "Adapter boundary reason is missing: $reason"
    }
}

Check 'actual-adapter-requires-durability-and-hostile-same-sid-closure' {
    $case = New-CompleteReviewInput
    $case.AdapterEvidence = Copy-ReviewObject $case.AdapterEvidence '' @{
        hardware_power_loss_recovery_verified=$false;directory_metadata_durability_verified=$false;
        hostile_same_sid_replacement_prevented=$false
    }
    $result = Invoke-ReviewCase $case
    foreach ($reason in @(
        'adapter-hardware-power-loss-recovery-verified-not-true',
        'adapter-directory-metadata-durability-verified-not-true',
        'adapter-hostile-same-sid-replacement-prevented-not-true')) {
        Assert-ReviewTrue (@($result.reasons) -ccontains $reason) "Durability reason is missing: $reason"
    }
}

Check 'actual-adapter-requires-both-shell-fault-and-recovery-matrices' {
    $case = New-CompleteReviewInput
    $case.AdapterEvidence = Copy-ReviewObject $case.AdapterEvidence '' @{
        fresh_process_recovery_ps5=$false;fresh_process_recovery_ps7=$false;
        fault_matrix_ps5=$false;fault_matrix_ps7=$false;four_state_recovery_verified=$false
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.actual_adapter_ready) 'Incomplete cross-shell fault matrix was admitted.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'adapter-fault-matrix-ps5-not-true') 'PS5 fault-matrix reason is missing.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'adapter-fault-matrix-ps7-not-true') 'PS7 fault-matrix reason is missing.'
}

Check 'adapter-and-authorization-digests-must-bind-the-reviewed-identities' {
    $case = New-CompleteReviewInput
    $case.AdapterEvidence = Copy-ReviewObject $case.AdapterEvidence '' @{expected_old_receipt_sha256=('0'*64)}
    $case.AuthorizationEvidence = Copy-ReviewObject $case.AuthorizationEvidence '' @{
        successor_receipt_sha256=('1'*64);adapter_sha256=('3'*64)
    }
    $result = Invoke-ReviewCase $case
    foreach ($reason in @(
        'adapter-old-receipt-binding-mismatch','authorization-successor-receipt-binding-mismatch',
        'authorization-adapter-binding-mismatch')) {
        Assert-ReviewTrue (@($result.reasons) -ccontains $reason) "Digest binding reason is missing: $reason"
    }
}

Check 'explicit-one-time-user-authorization-is-required' {
    $case = New-CompleteReviewInput
    $case.AuthorizationEvidence = Copy-ReviewObject $case.AuthorizationEvidence '' @{
        explicit_user_authorization=$false;one_time_authorization=$false;scope='install-and-migrate'
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.explicit_authorization_ready) 'Missing or broad authorization was admitted.'
    foreach ($reason in @(
        'authorization-explicit-user-authorization-not-true','authorization-one-time-authorization-not-true',
        'authorization-scope-unexpected-value')) {
        Assert-ReviewTrue (@($result.reasons) -ccontains $reason) "Authorization reason is missing: $reason"
    }
}

Check 'install-sign-delivery-host-and-arm64-remain-independent-negative-boundaries' {
    $case = New-CompleteReviewInput
    $case.DownstreamBoundaries = Copy-ReviewObject $case.DownstreamBoundaries '' @{
        installer_execution_in_scope=$true;signing_in_scope=$true;delivery_in_scope=$true;
        installed_or_registered_host_in_scope=$true;arm64_native_claim_in_scope=$true;
        dp1_or_release_completion_claimed=$true
    }
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (-not $result.downstream_boundaries_preserved) 'Expanded downstream scope was admitted.'
    Assert-ReviewTrue (-not $result.signing_admitted -and -not $result.delivery_admitted -and
        -not $result.installed_or_registered_host_action_admitted -and -not $result.arm64_native_claim_admitted) `
        'Output promoted a downstream action.'
}

Check 'malformed-types-fail-closed-with-stable-reasons' {
    $case = New-CompleteReviewInput
    $case.OldCanonical = Copy-ReviewObject $case.OldCanonical '' @{installer_bytes='41456428'}
    $case.ArchiveEvidence = Copy-ReviewObject $case.ArchiveEvidence '' @{outside_repository='true'}
    $result = Invoke-ReviewCase $case
    Assert-ReviewTrue (@($result.reasons) -ccontains 'old-canonical-installer-bytes-not-positive-integer') 'Integer type reason is missing.'
    Assert-ReviewTrue (@($result.reasons) -ccontains 'archive-outside-repository-not-boolean') 'Boolean type reason is missing.'
}

Check 'reason-order-is-deterministic' {
    $first = New-CompleteReviewInput
    $first.ArchiveEvidence = Copy-ReviewObject $first.ArchiveEvidence 'runner_result_archived' @{outside_outer_tmp=$false}
    $first.AdapterEvidence = Copy-ReviewObject $first.AdapterEvidence '' @{stale_cas_rejected=$false}
    $left = Invoke-ReviewCase $first
    $second = New-CompleteReviewInput
    $second.ArchiveEvidence = Copy-ReviewObject $second.ArchiveEvidence 'runner_result_archived' @{outside_outer_tmp=$false}
    $second.AdapterEvidence = Copy-ReviewObject $second.AdapterEvidence '' @{stale_cas_rejected=$false}
    $right = Invoke-ReviewCase $second
    Assert-ReviewTrue ((@($left.reasons) -join "`n") -ceq (@($right.reasons) -join "`n")) 'Reason order changed across identical reviews.'
}

Check 'review-result-field-set-is-exact-and-action-flags-stay-negative' {
    $result = Invoke-ReviewCase (New-CompleteReviewInput)
    $expected = @(
        'schema_version','review_scope','review_ready','source_admission_ready','off_repository_archive_ready',
        'actual_adapter_ready','explicit_authorization_ready','downstream_boundaries_preserved','reasons',
        'actual_canonical_migration_admitted','actual_canonical_migrated','separate_execution_gate_required',
        'installer_or_uninstaller_execution_admitted','signing_admitted','delivery_admitted',
        'installed_or_registered_host_action_admitted','arm64_native_claim_admitted',
        'registry_process_default_ime_or_user_data_action_admitted','installed_yimecore_action_admitted',
        'dp1_or_release_completion_admitted'
    )
    $actual = @($result.PSObject.Properties.Name)
    Assert-ReviewTrue (($actual -join "`n") -ceq ($expected -join "`n")) 'Review result field set or order is not exact.'
    Assert-ReviewTrue ([string]$result.schema_version -ceq 'yime-rime-pime-actual-migration-review-v1') 'Review schema is wrong.'
}

$failed = @($checks | Where-Object {-not $_.passed})
$result = [ordered]@{
    schema_version = 'yime-rime-pime-actual-migration-review-test-v1'
    total = $checks.Count
    passed = $checks.Count - $failed.Count
    failed = $failed.Count
    checks = @($checks)
    verified = [ordered]@{
        single_pure_export = $failed.Count -eq 0
        every_required_field_has_stable_missing_reason = $failed.Count -eq 0
        complete_evidence_is_review_ready_only = $failed.Count -eq 0
        actual_migration_admission_constant_false = $failed.Count -eq 0
        off_repository_source_independent_archive_required = $failed.Count -eq 0
        actual_adapter_and_cross_shell_fault_matrix_required = $failed.Count -eq 0
        explicit_bound_authorization_required = $failed.Count -eq 0
        install_sign_delivery_host_and_arm64_independent = $failed.Count -eq 0
    }
    scope_declarations = [ordered]@{
        fixture_only = $true
        privacy_safe = $true
        actual_canonical_read_or_written = $false
        installer_or_uninstaller_executed = $false
        signing_or_delivery_action_executed = $false
        registry_process_default_ime_or_user_data_touched = $false
        installed_yimecore_touched = $false
        arm64_native_action_executed = $false
    }
}
$resultPath = Join-Path $output 'result.json'
$json = ($result | ConvertTo-Json -Depth 12 -Compress) + "`n"
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
$stream = [IO.File]::Open($resultPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try { $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true) } finally { $stream.Dispose() }
$digest = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sidecarBytes = [Text.Encoding]::ASCII.GetBytes("$digest  result.json`n")
$sidecar = [IO.File]::Open($resultPath + '.sha256',[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try { $sidecar.Write($sidecarBytes,0,$sidecarBytes.Length);$sidecar.Flush($true) } finally { $sidecar.Dispose() }

if ($failed.Count) {
    $failed | Format-Table -AutoSize | Out-String | Write-Host
    throw "Actual migration review fixture failed: $($failed.Count) checks. Evidence: $resultPath ($digest)"
}
Write-Host "PASS: $($checks.Count) pure-data actual migration review checks; actual canonical migration remains unadmitted. Evidence: $resultPath ($digest)"
