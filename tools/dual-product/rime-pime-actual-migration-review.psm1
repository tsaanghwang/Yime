# Pure-data DP1-Q review gate for an eventual actual canonical Rime/PIME
# installer-plus-receipt migration. Importing and calling this module performs
# no filesystem, registry, process, build, installer, signing, or product
# action. A positive review is deliberately not an execution authorization.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:RimePimeActualMigrationReviewSchema = 'yime-rime-pime-actual-migration-review-v1'
$script:RimePimeSha256Pattern = '^[0-9a-f]{64}$'
$script:RimePimeGitObjectPattern = '^[0-9a-f]{40}(?:[0-9a-f]{24})?$'
$script:RimePimeVersionPattern = '^(?<major>0|[1-9][0-9]*)\.(?<minor>0|[1-9][0-9]*)\.(?<patch>0|[1-9][0-9]*)(?:-(?<suffix>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$'

function Add-RimePimeMigrationReviewReason {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Reasons,
        [Parameter(Mandatory)][string]$Reason
    )
    if (-not $Reasons.Contains($Reason)) { $Reasons.Add($Reason) }
}

function Test-RimePimeMigrationReviewObjectShape {
    param(
        $Value,
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Reasons
    )
    if ($null -eq $Value -or $null -eq $Value.PSObject) {
        Add-RimePimeMigrationReviewReason $Reasons ($Context + '-not-an-object')
        return $false
    }
    $names = @()
    foreach ($property in $Value.PSObject.Properties) {
        $name = [string]$property.Name
        $names += $name
        if ($property.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty) {
            Add-RimePimeMigrationReviewReason $Reasons ($Context + '-non-note-property-' + $name.Replace('_', '-'))
        }
    }
    foreach ($name in $Expected) {
        if ($names -cnotcontains $name) {
            Add-RimePimeMigrationReviewReason $Reasons ($Context + '-missing-' + $name.Replace('_', '-'))
        }
    }
    foreach ($name in $names) {
        if ($Expected -cnotcontains $name) {
            Add-RimePimeMigrationReviewReason $Reasons ($Context + '-unexpected-' + $name.Replace('_', '-'))
        }
    }
    return $true
}

function Get-RimePimeMigrationReviewProperty {
    param($Value, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Value -or $null -eq $Value.PSObject -or
        $null -eq $Value.PSObject.Properties[$Name]) { return $null }
    $property = $Value.PSObject.Properties[$Name]
    if ($property.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty) { return $null }
    return $property.Value
}

function Test-RimePimeMigrationReviewBoolean {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Expected,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Reasons
    )
    if ($null -eq $Value -or $null -eq $Value.PSObject -or $null -eq $Value.PSObject.Properties[$Name]) { return }
    $property = $Value.PSObject.Properties[$Name]
    if ($property.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty) { return }
    $actual = $property.Value
    if ($actual -isnot [bool]) {
        Add-RimePimeMigrationReviewReason $Reasons ($Context + '-' + $Name.Replace('_', '-') + '-not-boolean')
    } elseif ([bool]$actual -ne $Expected) {
        Add-RimePimeMigrationReviewReason $Reasons ($Context + '-' + $Name.Replace('_', '-') + '-not-' + $Expected.ToString().ToLowerInvariant())
    }
}

function Test-RimePimeMigrationReviewString {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Reasons
    )
    if ($null -eq $Value -or $null -eq $Value.PSObject -or $null -eq $Value.PSObject.Properties[$Name]) { return $null }
    $property = $Value.PSObject.Properties[$Name]
    if ($property.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty) { return $null }
    $actual = $property.Value
    if ($actual -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$actual)) {
        Add-RimePimeMigrationReviewReason $Reasons ($Context + '-' + $Name.Replace('_', '-') + '-not-nonempty-string')
        return $null
    }
    return [string]$actual
}

function Test-RimePimeMigrationReviewExactString {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Reasons
    )
    $actual = Test-RimePimeMigrationReviewString $Value $Name $Context $Reasons
    if ($null -ne $actual -and $actual -cne $Expected) {
        Add-RimePimeMigrationReviewReason $Reasons ($Context + '-' + $Name.Replace('_', '-') + '-unexpected-value')
    }
    return $actual
}

function Test-RimePimeMigrationReviewSha256 {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Reasons
    )
    $actual = Test-RimePimeMigrationReviewString $Value $Name $Context $Reasons
    if ($null -ne $actual -and $actual -cnotmatch $script:RimePimeSha256Pattern) {
        Add-RimePimeMigrationReviewReason $Reasons ($Context + '-' + $Name.Replace('_', '-') + '-invalid-sha256')
        return $null
    }
    return $actual
}

function Test-RimePimeMigrationReviewGitObject {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Reasons
    )
    $actual = Test-RimePimeMigrationReviewString $Value $Name $Context $Reasons
    if ($null -ne $actual -and $actual -cnotmatch $script:RimePimeGitObjectPattern) {
        Add-RimePimeMigrationReviewReason $Reasons ($Context + '-' + $Name.Replace('_', '-') + '-invalid-git-object')
        return $null
    }
    return $actual
}

function Test-RimePimeMigrationReviewPositiveInteger {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Reasons
    )
    if ($null -eq $Value -or $null -eq $Value.PSObject -or $null -eq $Value.PSObject.Properties[$Name]) { return $null }
    $property = $Value.PSObject.Properties[$Name]
    if ($property.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty) { return $null }
    $actual = $property.Value
    $integer = $actual -is [byte] -or $actual -is [sbyte] -or
        $actual -is [int16] -or $actual -is [uint16] -or
        $actual -is [int32] -or $actual -is [uint32] -or
        $actual -is [int64] -or $actual -is [uint64]
    if (-not $integer -or [decimal]$actual -lt 1) {
        Add-RimePimeMigrationReviewReason $Reasons ($Context + '-' + $Name.Replace('_', '-') + '-not-positive-integer')
        return $null
    }
    return [decimal]$actual
}

function Test-RimePimeMigrationReviewVersion {
    param($Value)
    if ($Value -isnot [string] -or $Value.Length -gt 64) { return $false }
    $match = [regex]::Match($Value, $script:RimePimeVersionPattern)
    if (-not $match.Success) { return $false }
    foreach ($name in @('major', 'minor', 'patch')) {
        [uint64]$part = 0
        if (-not [uint64]::TryParse($match.Groups[$name].Value, [ref]$part) -or $part -gt 65535) { return $false }
    }
    if ($match.Groups['suffix'].Success) {
        foreach ($identifier in $match.Groups['suffix'].Value.Split('.')) {
            if ($identifier -match '^[0-9]+$' -and $identifier.Length -gt 1 -and $identifier[0] -eq '0') { return $false }
        }
    }
    return $true
}

function Compare-RimePimeMigrationReviewVersion {
    param([Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)
    $leftMatch = [regex]::Match($Left, $script:RimePimeVersionPattern)
    $rightMatch = [regex]::Match($Right, $script:RimePimeVersionPattern)
    foreach ($name in @('major', 'minor', 'patch')) {
        $leftPart = [uint32]::Parse($leftMatch.Groups[$name].Value)
        $rightPart = [uint32]::Parse($rightMatch.Groups[$name].Value)
        if ($leftPart -lt $rightPart) { return -1 }
        if ($leftPart -gt $rightPart) { return 1 }
    }
    $leftSuffix = $leftMatch.Groups['suffix'].Success
    $rightSuffix = $rightMatch.Groups['suffix'].Success
    if (-not $leftSuffix -and -not $rightSuffix) { return 0 }
    if (-not $leftSuffix) { return 1 }
    if (-not $rightSuffix) { return -1 }
    $leftIds = $leftMatch.Groups['suffix'].Value.Split('.')
    $rightIds = $rightMatch.Groups['suffix'].Value.Split('.')
    $shared = [Math]::Min($leftIds.Count, $rightIds.Count)
    for ($index = 0; $index -lt $shared; $index++) {
        $leftId = $leftIds[$index]
        $rightId = $rightIds[$index]
        $leftNumeric = $leftId -cmatch '^[0-9]+$'
        $rightNumeric = $rightId -cmatch '^[0-9]+$'
        if ($leftNumeric -and $rightNumeric) {
            if ($leftId.Length -lt $rightId.Length) { return -1 }
            if ($leftId.Length -gt $rightId.Length) { return 1 }
        } elseif ($leftNumeric) { return -1 }
        elseif ($rightNumeric) { return 1 }
        $ordinal = [string]::CompareOrdinal($leftId, $rightId)
        if ($ordinal -lt 0) { return -1 }
        if ($ordinal -gt 0) { return 1 }
    }
    if ($leftIds.Count -lt $rightIds.Count) { return -1 }
    if ($leftIds.Count -gt $rightIds.Count) { return 1 }
    return 0
}

function Test-RimePimeMigrationReviewOrderedStrings {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Reasons
    )
    if ($null -eq $Value -or $null -eq $Value.PSObject -or $null -eq $Value.PSObject.Properties[$Name]) { return }
    $property = $Value.PSObject.Properties[$Name]
    if ($property.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty) { return }
    $actual = @($property.Value)
    $matches = $actual.Count -eq $Expected.Count
    if ($matches) {
        for ($index = 0; $index -lt $Expected.Count; $index++) {
            if ($actual[$index] -isnot [string] -or [string]$actual[$index] -cne $Expected[$index]) { $matches = $false; break }
        }
    }
    if (-not $matches) {
        Add-RimePimeMigrationReviewReason $Reasons ($Context + '-' + $Name.Replace('_', '-') + '-unexpected-ordered-set')
    }
}

function Test-RimePimeMigrationReviewCanonicalWindowsPath {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Reasons
    )
    $text = Test-RimePimeMigrationReviewString $Value $Name $Context $Reasons
    if ($null -eq $text) { return $null }
    $reason = $Context + '-' + $Name.Replace('_', '-') + '-not-canonical-windows-path'
    if ($text.Length -gt 1024 -or $text.Length -le 3 -or $text -cnotmatch '^[A-Za-z]:\\' -or
        $text.Contains('/') -or -not $text.IsNormalized([Text.NormalizationForm]::FormC)) {
        Add-RimePimeMigrationReviewReason $Reasons $reason
        return $null
    }
    foreach ($segment in $text.Substring(3).Split('\')) {
        if (-not $segment -or $segment -in @('.','..') -or $segment.EndsWith('.') -or
            $segment.EndsWith(' ') -or $segment -match '[\x00-\x1f<>:"|?*]' -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            Add-RimePimeMigrationReviewReason $Reasons $reason
            return $null
        }
    }
    try { $canonical = [IO.Path]::GetFullPath($text).TrimEnd('\') }
    catch {
        Add-RimePimeMigrationReviewReason $Reasons $reason
        return $null
    }
    if ($canonical -cne $text) {
        Add-RimePimeMigrationReviewReason $Reasons $reason
        return $null
    }
    return $canonical
}

function Get-RimePimeActualMigrationReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$IdentityAdmission,
        [Parameter(Mandatory)]$OldCanonical,
        [Parameter(Mandatory)]$Successor,
        [Parameter(Mandatory)]$ArchiveEvidence,
        [Parameter(Mandatory)]$AdapterEvidence,
        [Parameter(Mandatory)]$AuthorizationEvidence,
        [Parameter(Mandatory)]$DownstreamBoundaries
    )

    $reasons = [Collections.Generic.List[string]]::new()

    $identityFields = @(
        'schema_version','identity_transition_admitted','reasons','old_product_version',
        'successor_product_version','expected_successor_product_version','old_installer_path',
        'successor_installer_path','paths_compared_case_insensitively_for_windows',
        'actual_canonical_migration_admitted','actual_canonical_migrated',
        'installer_or_uninstaller_executed','registry_or_product_process_touched'
    )
    $oldFields = @(
        'schema_version','product','repo_root','product_version','receipt_path','receipt_sha256',
        'receipt_sidecar_sha256','receipt_sidecar_binds_receipt','strict_receipt_ps5','strict_receipt_ps7',
        'installer_path','installer_sha256','installer_bytes','physical_installer_matches_receipt',
        'canonical_pair_file_identity_bound','normal_leaf_guards_passed','pending_transaction_absent',
        'successor_installer_absent','protected_snapshot_sha256','actual_snapshot_bound'
    )
    $successorFields = @(
        'schema_version','product','product_version','package_profile','receipt_sha256','strict_receipt_ps5',
        'strict_receipt_ps7','evidence_artifacts_durable','current_build_evidence','installer_path',
        'installer_sha256','installer_bytes','physical_installer_matches_receipt','exact_source_head',
        'exact_source_tree','runner_head_blob','runner_worktree_blob','runner_matches_exact_head',
        'version_contract_matches','detached_clean_head','unsigned_disabled','installer_executed',
        'signing_complete','delivery_admitted'
    )
    $archiveFields = @(
        'schema_version','archive_root','archive_manifest_sha256','archive_manifest_bytes',
        'archive_manifest_sidecar_valid','outside_repository','outside_outer_tmp','outside_all_git_worktrees',
        'system_visible_from_unpacked_process','archive_root_not_reparse','archive_files_not_hardlinked',
        'archive_files_have_no_ads','object_set_exact','archived_object_count','all_objects_hash_and_bytes_match',
        'all_object_sidecars_valid','receipt_evidence_set_complete','successor_installer_archived',
        'successor_receipt_archived','historical_v1_archived','runner_result_archived',
        'identity_admission_archived','old_canonical_snapshot_archived','ps5_verification_archived',
        'ps7_verification_archived','source_head_tree_bound','source_head','source_tree',
        'successor_receipt_sha256','successor_installer_sha256',
        'temporary_source_unavailable_during_reverification','fresh_process_reopen_ps5',
        'fresh_process_reopen_ps7','strict_receipt_read_ps5_without_source',
        'strict_receipt_read_ps7_without_source','candidate_hash_verified_without_source'
    )
    $adapterFields = @(
        'schema_version','adapter_kind','actual_repo_root','adapter_path','adapter_sha256','adapter_source_set_sha256',
        'migration_plan_sha256','fault_matrix_sha256','actual_checkout_dedicated','dp1n_fixture_gate_preserved',
        'fixture_api_rejects_actual_checkout','dry_run_supported','dry_run_exact_write_set_verified',
        'write_set_roles','write_set_limited_to_canonical_artifacts','expected_old_receipt_sha256',
        'expected_successor_receipt_sha256','expected_successor_installer_sha256',
        'expected_actual_snapshot_sha256','archive_manifest_sha256','old_receipt_cas_enforced',
        'successor_archive_cas_enforced','protected_snapshot_preflight_bound','shared_publication_lock',
        'pre_intent_retriable_without_canonical_change','post_intent_roll_forward_only',
        'four_state_recovery_verified','fresh_process_recovery_ps5','fresh_process_recovery_ps7',
        'fault_matrix_ps5','fault_matrix_ps7','stale_cas_rejected','no_replace_races_verified',
        'foreign_state_fails_closed','old_installer_preserved','unrelated_installer_leaves_preserved',
        'yimecore_unchanged','registry_unchanged','product_processes_unchanged',
        'default_input_method_unchanged','production_user_data_untouched',
        'hardware_power_loss_recovery_verified','directory_metadata_durability_verified',
        'hostile_same_sid_replacement_prevented'
    )
    $authorizationFields = @(
        'schema_version','authorization_kind','authorization_id','authorization_record_sha256',
        'explicit_user_authorization','one_time_authorization','repo_root','scope','migration_plan_sha256',
        'old_receipt_sha256','successor_receipt_sha256','successor_installer_sha256',
        'actual_snapshot_sha256','archive_manifest_sha256','adapter_sha256'
    )
    $boundaryFields = @(
        'schema_version','installer_execution_in_scope','uninstaller_execution_in_scope','signing_in_scope',
        'delivery_in_scope','installed_or_registered_host_in_scope','arm64_native_claim_in_scope',
        'product_registry_mutation_in_scope','product_process_action_in_scope',
        'default_input_method_change_in_scope','production_user_data_access_in_scope',
        'installed_yimecore_mutation_in_scope','generated_uninstaller_trust_claimed',
        'final_payload_closure_claimed','full_nsis_toolchain_closure_claimed',
        'dp1_or_release_completion_claimed'
    )

    $sourceStart = $reasons.Count
    $null = Test-RimePimeMigrationReviewObjectShape $IdentityAdmission $identityFields 'identity-admission' $reasons
    $null = Test-RimePimeMigrationReviewObjectShape $OldCanonical $oldFields 'old-canonical' $reasons
    $null = Test-RimePimeMigrationReviewObjectShape $Successor $successorFields 'successor' $reasons

    $null = Test-RimePimeMigrationReviewExactString $IdentityAdmission 'schema_version' 'yime-rime-pime-version-identity-admission-v1' 'identity-admission' $reasons
    Test-RimePimeMigrationReviewBoolean $IdentityAdmission 'identity_transition_admitted' $true 'identity-admission' $reasons
    Test-RimePimeMigrationReviewBoolean $IdentityAdmission 'paths_compared_case_insensitively_for_windows' $true 'identity-admission' $reasons
    Test-RimePimeMigrationReviewBoolean $IdentityAdmission 'actual_canonical_migration_admitted' $false 'identity-admission' $reasons
    Test-RimePimeMigrationReviewBoolean $IdentityAdmission 'actual_canonical_migrated' $false 'identity-admission' $reasons
    Test-RimePimeMigrationReviewBoolean $IdentityAdmission 'installer_or_uninstaller_executed' $false 'identity-admission' $reasons
    Test-RimePimeMigrationReviewBoolean $IdentityAdmission 'registry_or_product_process_touched' $false 'identity-admission' $reasons
    $identityOldVersion = Test-RimePimeMigrationReviewString $IdentityAdmission 'old_product_version' 'identity-admission' $reasons
    $identityNewVersion = Test-RimePimeMigrationReviewString $IdentityAdmission 'successor_product_version' 'identity-admission' $reasons
    $identityExpectedVersion = Test-RimePimeMigrationReviewString $IdentityAdmission 'expected_successor_product_version' 'identity-admission' $reasons
    $identityOldPath = Test-RimePimeMigrationReviewString $IdentityAdmission 'old_installer_path' 'identity-admission' $reasons
    $identityNewPath = Test-RimePimeMigrationReviewString $IdentityAdmission 'successor_installer_path' 'identity-admission' $reasons
    if ($null -ne $IdentityAdmission -and $null -ne $IdentityAdmission.PSObject -and
        $null -ne $IdentityAdmission.PSObject.Properties['reasons'] -and
        $IdentityAdmission.PSObject.Properties['reasons'].MemberType -eq
            [Management.Automation.PSMemberTypes]::NoteProperty) {
        $identityReasons = $IdentityAdmission.PSObject.Properties['reasons'].Value
        if ($identityReasons -isnot [System.Array] -or @($identityReasons).Count -ne 0) {
            Add-RimePimeMigrationReviewReason $reasons 'identity-admission-reasons-not-empty-array'
        }
    }

    $null = Test-RimePimeMigrationReviewExactString $OldCanonical 'schema_version' 'yime-rime-pime-actual-migration-old-canonical-v1' 'old-canonical' $reasons
    $null = Test-RimePimeMigrationReviewExactString $OldCanonical 'product' 'rime-pime' 'old-canonical' $reasons
    $oldRepoRoot = Test-RimePimeMigrationReviewCanonicalWindowsPath $OldCanonical 'repo_root' 'old-canonical' $reasons
    $oldVersion = Test-RimePimeMigrationReviewString $OldCanonical 'product_version' 'old-canonical' $reasons
    $null = Test-RimePimeMigrationReviewExactString $OldCanonical 'receipt_path' 'installer/package-build-receipt.json' 'old-canonical' $reasons
    $oldReceipt = Test-RimePimeMigrationReviewSha256 $OldCanonical 'receipt_sha256' 'old-canonical' $reasons
    $null = Test-RimePimeMigrationReviewSha256 $OldCanonical 'receipt_sidecar_sha256' 'old-canonical' $reasons
    $oldPath = Test-RimePimeMigrationReviewString $OldCanonical 'installer_path' 'old-canonical' $reasons
    $oldInstaller = Test-RimePimeMigrationReviewSha256 $OldCanonical 'installer_sha256' 'old-canonical' $reasons
    $null = Test-RimePimeMigrationReviewPositiveInteger $OldCanonical 'installer_bytes' 'old-canonical' $reasons
    foreach ($name in @('receipt_sidecar_binds_receipt','strict_receipt_ps5','strict_receipt_ps7',
        'physical_installer_matches_receipt','canonical_pair_file_identity_bound','normal_leaf_guards_passed',
        'pending_transaction_absent','successor_installer_absent','actual_snapshot_bound')) {
        Test-RimePimeMigrationReviewBoolean $OldCanonical $name $true 'old-canonical' $reasons
    }
    $oldSnapshot = Test-RimePimeMigrationReviewSha256 $OldCanonical 'protected_snapshot_sha256' 'old-canonical' $reasons

    $null = Test-RimePimeMigrationReviewExactString $Successor 'schema_version' 'yime-rime-pime-actual-migration-successor-v1' 'successor' $reasons
    $null = Test-RimePimeMigrationReviewExactString $Successor 'product' 'rime-pime' 'successor' $reasons
    $newVersion = Test-RimePimeMigrationReviewString $Successor 'product_version' 'successor' $reasons
    $null = Test-RimePimeMigrationReviewExactString $Successor 'package_profile' 'x86-x64-v1' 'successor' $reasons
    $newReceipt = Test-RimePimeMigrationReviewSha256 $Successor 'receipt_sha256' 'successor' $reasons
    $newPath = Test-RimePimeMigrationReviewString $Successor 'installer_path' 'successor' $reasons
    $newInstaller = Test-RimePimeMigrationReviewSha256 $Successor 'installer_sha256' 'successor' $reasons
    $null = Test-RimePimeMigrationReviewPositiveInteger $Successor 'installer_bytes' 'successor' $reasons
    $sourceHead = Test-RimePimeMigrationReviewGitObject $Successor 'exact_source_head' 'successor' $reasons
    $sourceTree = Test-RimePimeMigrationReviewGitObject $Successor 'exact_source_tree' 'successor' $reasons
    $runnerHead = Test-RimePimeMigrationReviewGitObject $Successor 'runner_head_blob' 'successor' $reasons
    $runnerWorktree = Test-RimePimeMigrationReviewGitObject $Successor 'runner_worktree_blob' 'successor' $reasons
    foreach ($name in @('strict_receipt_ps5','strict_receipt_ps7','evidence_artifacts_durable',
        'current_build_evidence','physical_installer_matches_receipt','runner_matches_exact_head',
        'version_contract_matches','detached_clean_head','unsigned_disabled')) {
        Test-RimePimeMigrationReviewBoolean $Successor $name $true 'successor' $reasons
    }
    foreach ($name in @('installer_executed','signing_complete','delivery_admitted')) {
        Test-RimePimeMigrationReviewBoolean $Successor $name $false 'successor' $reasons
    }
    if ($null -ne $runnerHead -and $null -ne $runnerWorktree -and $runnerHead -cne $runnerWorktree) {
        Add-RimePimeMigrationReviewReason $reasons 'successor-runner-worktree-does-not-match-head'
    }
    if (-not (Test-RimePimeMigrationReviewVersion $oldVersion)) {
        Add-RimePimeMigrationReviewReason $reasons 'old-canonical-invalid-product-version'
    }
    if (-not (Test-RimePimeMigrationReviewVersion $newVersion)) {
        Add-RimePimeMigrationReviewReason $reasons 'successor-invalid-product-version'
    }
    if ((Test-RimePimeMigrationReviewVersion $oldVersion) -and (Test-RimePimeMigrationReviewVersion $newVersion) -and
        (Compare-RimePimeMigrationReviewVersion $oldVersion $newVersion) -ge 0) {
        Add-RimePimeMigrationReviewReason $reasons 'successor-version-not-strictly-greater-by-semver'
    }
    if ($null -ne $oldVersion -and $null -ne $oldPath -and $oldPath -cne ('installer/YIME-' + $oldVersion + '-setup.exe')) {
        Add-RimePimeMigrationReviewReason $reasons 'old-canonical-installer-path-not-canonical-versioned-leaf'
    }
    if ($null -ne $newVersion -and $null -ne $newPath -and $newPath -cne ('installer/YIME-' + $newVersion + '-setup.exe')) {
        Add-RimePimeMigrationReviewReason $reasons 'successor-installer-path-not-canonical-versioned-leaf'
    }
    if ($null -ne $oldPath -and $null -ne $newPath -and $oldPath -ieq $newPath) {
        Add-RimePimeMigrationReviewReason $reasons 'old-and-successor-installer-path-not-distinct-on-windows'
    }
    if ($null -ne $oldInstaller -and $null -ne $newInstaller -and $oldInstaller -ceq $newInstaller) {
        Add-RimePimeMigrationReviewReason $reasons 'old-and-successor-installer-sha256-not-distinct'
    }
    foreach ($binding in @(
        @($identityOldVersion,$oldVersion,'old-product-version'),
        @($identityNewVersion,$newVersion,'successor-product-version'),
        @($identityExpectedVersion,$newVersion,'expected-successor-product-version'),
        @($identityOldPath,$oldPath,'old-installer-path'),
        @($identityNewPath,$newPath,'successor-installer-path')
    )) {
        if ($null -ne $binding[0] -and $null -ne $binding[1] -and [string]$binding[0] -cne [string]$binding[1]) {
            Add-RimePimeMigrationReviewReason $reasons ('identity-admission-' + $binding[2] + '-binding-mismatch')
        }
    }
    $sourceReady = $reasons.Count -eq $sourceStart

    $archiveStart = $reasons.Count
    $null = Test-RimePimeMigrationReviewObjectShape $ArchiveEvidence $archiveFields 'archive' $reasons
    $null = Test-RimePimeMigrationReviewExactString $ArchiveEvidence 'schema_version' 'yime-rime-pime-off-repository-archive-evidence-v1' 'archive' $reasons
    $archiveRoot = Test-RimePimeMigrationReviewCanonicalWindowsPath $ArchiveEvidence 'archive_root' 'archive' $reasons
    $archiveManifest = Test-RimePimeMigrationReviewSha256 $ArchiveEvidence 'archive_manifest_sha256' 'archive' $reasons
    $null = Test-RimePimeMigrationReviewPositiveInteger $ArchiveEvidence 'archive_manifest_bytes' 'archive' $reasons
    $null = Test-RimePimeMigrationReviewPositiveInteger $ArchiveEvidence 'archived_object_count' 'archive' $reasons
    foreach ($name in @(
        'archive_manifest_sidecar_valid','outside_repository','outside_outer_tmp','outside_all_git_worktrees',
        'system_visible_from_unpacked_process','archive_root_not_reparse','archive_files_not_hardlinked',
        'archive_files_have_no_ads','object_set_exact','all_objects_hash_and_bytes_match',
        'all_object_sidecars_valid','receipt_evidence_set_complete','successor_installer_archived',
        'successor_receipt_archived','historical_v1_archived','runner_result_archived',
        'identity_admission_archived','old_canonical_snapshot_archived','ps5_verification_archived',
        'ps7_verification_archived','source_head_tree_bound','temporary_source_unavailable_during_reverification',
        'fresh_process_reopen_ps5','fresh_process_reopen_ps7','strict_receipt_read_ps5_without_source',
        'strict_receipt_read_ps7_without_source','candidate_hash_verified_without_source'
    )) { Test-RimePimeMigrationReviewBoolean $ArchiveEvidence $name $true 'archive' $reasons }
    $archiveSourceHead = Test-RimePimeMigrationReviewGitObject $ArchiveEvidence 'source_head' 'archive' $reasons
    $archiveSourceTree = Test-RimePimeMigrationReviewGitObject $ArchiveEvidence 'source_tree' 'archive' $reasons
    $archiveReceipt = Test-RimePimeMigrationReviewSha256 $ArchiveEvidence 'successor_receipt_sha256' 'archive' $reasons
    $archiveInstaller = Test-RimePimeMigrationReviewSha256 $ArchiveEvidence 'successor_installer_sha256' 'archive' $reasons
    if ($null -ne $sourceHead -and $null -ne $archiveSourceHead -and $sourceHead -cne $archiveSourceHead) {
        Add-RimePimeMigrationReviewReason $reasons 'archive-source-head-binding-mismatch'
    }
    if ($null -ne $sourceTree -and $null -ne $archiveSourceTree -and $sourceTree -cne $archiveSourceTree) {
        Add-RimePimeMigrationReviewReason $reasons 'archive-source-tree-binding-mismatch'
    }
    if ($null -ne $newReceipt -and $null -ne $archiveReceipt -and $newReceipt -cne $archiveReceipt) {
        Add-RimePimeMigrationReviewReason $reasons 'archive-successor-receipt-binding-mismatch'
    }
    if ($null -ne $newInstaller -and $null -ne $archiveInstaller -and $newInstaller -cne $archiveInstaller) {
        Add-RimePimeMigrationReviewReason $reasons 'archive-successor-installer-binding-mismatch'
    }
    if ($null -ne $archiveRoot -and $null -ne $oldRepoRoot -and
        ($archiveRoot -ieq $oldRepoRoot -or
         $archiveRoot.StartsWith($oldRepoRoot + '\',[StringComparison]::OrdinalIgnoreCase))) {
        Add-RimePimeMigrationReviewReason $reasons 'archive-root-is-inside-actual-repository'
    }
    $archiveReady = [bool]($sourceReady -and $reasons.Count -eq $archiveStart)

    $adapterStart = $reasons.Count
    $null = Test-RimePimeMigrationReviewObjectShape $AdapterEvidence $adapterFields 'adapter' $reasons
    $null = Test-RimePimeMigrationReviewExactString $AdapterEvidence 'schema_version' 'yime-rime-pime-actual-canonical-adapter-evidence-v1' 'adapter' $reasons
    $null = Test-RimePimeMigrationReviewExactString $AdapterEvidence 'adapter_kind' 'actual-checkout-dedicated' 'adapter' $reasons
    $adapterRepoRoot = Test-RimePimeMigrationReviewCanonicalWindowsPath $AdapterEvidence 'actual_repo_root' 'adapter' $reasons
    $null = Test-RimePimeMigrationReviewExactString $AdapterEvidence 'adapter_path' `
        'tools/dual-product/invoke-rime-pime-actual-canonical-migration.ps1' 'adapter' $reasons
    $adapterDigest = Test-RimePimeMigrationReviewSha256 $AdapterEvidence 'adapter_sha256' 'adapter' $reasons
    $null = Test-RimePimeMigrationReviewSha256 $AdapterEvidence 'adapter_source_set_sha256' 'adapter' $reasons
    $migrationPlan = Test-RimePimeMigrationReviewSha256 $AdapterEvidence 'migration_plan_sha256' 'adapter' $reasons
    $null = Test-RimePimeMigrationReviewSha256 $AdapterEvidence 'fault_matrix_sha256' 'adapter' $reasons
    $writeRoles = @(
        'unique-staging-leaves','retained-evidence-objects','retained-evidence-sidecars',
        'successor-installer-stage','successor-installer','pending-intent','canonical-receipt',
        'canonical-sidecar','completed-intent'
    )
    Test-RimePimeMigrationReviewOrderedStrings $AdapterEvidence 'write_set_roles' $writeRoles 'adapter' $reasons
    foreach ($name in @(
        'actual_checkout_dedicated','dp1n_fixture_gate_preserved','fixture_api_rejects_actual_checkout',
        'dry_run_supported','dry_run_exact_write_set_verified','write_set_limited_to_canonical_artifacts',
        'old_receipt_cas_enforced','successor_archive_cas_enforced','protected_snapshot_preflight_bound',
        'shared_publication_lock','pre_intent_retriable_without_canonical_change','post_intent_roll_forward_only',
        'four_state_recovery_verified','fresh_process_recovery_ps5','fresh_process_recovery_ps7',
        'fault_matrix_ps5','fault_matrix_ps7','stale_cas_rejected','no_replace_races_verified',
        'foreign_state_fails_closed','old_installer_preserved','unrelated_installer_leaves_preserved',
        'yimecore_unchanged','registry_unchanged','product_processes_unchanged',
        'default_input_method_unchanged','production_user_data_untouched'
    )) { Test-RimePimeMigrationReviewBoolean $AdapterEvidence $name $true 'adapter' $reasons }
    foreach ($name in @(
        'hardware_power_loss_recovery_verified','directory_metadata_durability_verified',
        'hostile_same_sid_replacement_prevented'
    )) { Test-RimePimeMigrationReviewBoolean $AdapterEvidence $name $false 'adapter' $reasons }
    foreach ($binding in @(
        @('expected_old_receipt_sha256',$oldReceipt,'old-receipt'),
        @('expected_successor_receipt_sha256',$newReceipt,'successor-receipt'),
        @('expected_successor_installer_sha256',$newInstaller,'successor-installer'),
        @('expected_actual_snapshot_sha256',$oldSnapshot,'actual-snapshot'),
        @('archive_manifest_sha256',$archiveManifest,'archive-manifest')
    )) {
        $value = Test-RimePimeMigrationReviewSha256 $AdapterEvidence $binding[0] 'adapter' $reasons
        if ($null -ne $value -and $null -ne $binding[1] -and $value -cne [string]$binding[1]) {
            Add-RimePimeMigrationReviewReason $reasons ('adapter-' + $binding[2] + '-binding-mismatch')
        }
    }
    if ($null -ne $adapterRepoRoot -and $null -ne $oldRepoRoot -and $adapterRepoRoot -ine $oldRepoRoot) {
        Add-RimePimeMigrationReviewReason $reasons 'adapter-actual-repo-root-binding-mismatch'
    }
    $adapterReady = [bool]($sourceReady -and $archiveReady -and $reasons.Count -eq $adapterStart)

    $authorizationStart = $reasons.Count
    $null = Test-RimePimeMigrationReviewObjectShape $AuthorizationEvidence $authorizationFields 'authorization' $reasons
    $null = Test-RimePimeMigrationReviewExactString $AuthorizationEvidence 'schema_version' 'yime-rime-pime-actual-canonical-authorization-v1' 'authorization' $reasons
    $null = Test-RimePimeMigrationReviewExactString $AuthorizationEvidence 'authorization_kind' 'one-time-actual-canonical-artifact-migration' 'authorization' $reasons
    $null = Test-RimePimeMigrationReviewString $AuthorizationEvidence 'authorization_id' 'authorization' $reasons
    $null = Test-RimePimeMigrationReviewSha256 $AuthorizationEvidence 'authorization_record_sha256' 'authorization' $reasons
    Test-RimePimeMigrationReviewBoolean $AuthorizationEvidence 'explicit_user_authorization' $true 'authorization' $reasons
    Test-RimePimeMigrationReviewBoolean $AuthorizationEvidence 'one_time_authorization' $true 'authorization' $reasons
    $repoRoot = Test-RimePimeMigrationReviewCanonicalWindowsPath $AuthorizationEvidence 'repo_root' 'authorization' $reasons
    $null = Test-RimePimeMigrationReviewExactString $AuthorizationEvidence 'scope' 'actual-canonical-artifacts-only' 'authorization' $reasons
    foreach ($binding in @(
        @('migration_plan_sha256',$migrationPlan,'migration-plan'),
        @('old_receipt_sha256',$oldReceipt,'old-receipt'),
        @('successor_receipt_sha256',$newReceipt,'successor-receipt'),
        @('successor_installer_sha256',$newInstaller,'successor-installer'),
        @('actual_snapshot_sha256',$oldSnapshot,'actual-snapshot'),
        @('archive_manifest_sha256',$archiveManifest,'archive-manifest'),
        @('adapter_sha256',$adapterDigest,'adapter')
    )) {
        $value = Test-RimePimeMigrationReviewSha256 $AuthorizationEvidence $binding[0] 'authorization' $reasons
        if ($null -ne $value -and $null -ne $binding[1] -and $value -cne [string]$binding[1]) {
            Add-RimePimeMigrationReviewReason $reasons ('authorization-' + $binding[2] + '-binding-mismatch')
        }
    }
    if ($null -ne $repoRoot -and $null -ne $oldRepoRoot -and $repoRoot -ine $oldRepoRoot) {
        Add-RimePimeMigrationReviewReason $reasons 'authorization-repo-root-binding-mismatch'
    }
    if ($null -ne $repoRoot -and $null -ne $adapterRepoRoot -and $repoRoot -ine $adapterRepoRoot) {
        Add-RimePimeMigrationReviewReason $reasons 'authorization-adapter-repo-root-binding-mismatch'
    }
    $authorizationReady = [bool]($sourceReady -and $archiveReady -and $adapterReady -and
        $reasons.Count -eq $authorizationStart)

    $boundaryStart = $reasons.Count
    $null = Test-RimePimeMigrationReviewObjectShape $DownstreamBoundaries $boundaryFields 'downstream-boundaries' $reasons
    $null = Test-RimePimeMigrationReviewExactString $DownstreamBoundaries 'schema_version' 'yime-rime-pime-actual-canonical-downstream-boundaries-v1' 'downstream-boundaries' $reasons
    foreach ($name in $boundaryFields[1..($boundaryFields.Count - 1)]) {
        Test-RimePimeMigrationReviewBoolean $DownstreamBoundaries $name $false 'downstream-boundaries' $reasons
    }
    $boundariesReady = $reasons.Count -eq $boundaryStart

    return [pscustomobject][ordered]@{
        schema_version = $script:RimePimeActualMigrationReviewSchema
        review_scope = 'actual-canonical-artifacts-only'
        review_ready = $reasons.Count -eq 0
        source_admission_ready = [bool]$sourceReady
        off_repository_archive_ready = [bool]$archiveReady
        actual_adapter_ready = [bool]$adapterReady
        explicit_authorization_ready = [bool]$authorizationReady
        downstream_boundaries_preserved = [bool]$boundariesReady
        reasons = @($reasons)
        actual_canonical_migration_admitted = $false
        actual_canonical_migrated = $false
        separate_execution_gate_required = $true
        installer_or_uninstaller_execution_admitted = $false
        signing_admitted = $false
        delivery_admitted = $false
        installed_or_registered_host_action_admitted = $false
        arm64_native_claim_admitted = $false
        registry_process_default_ime_or_user_data_action_admitted = $false
        installed_yimecore_action_admitted = $false
        hardware_power_loss_recovery_verified = $false
        directory_metadata_durability_verified = $false
        hostile_same_sid_replacement_prevented = $false
        dp1_or_release_completion_admitted = $false
    }
}

Export-ModuleMember -Function 'Get-RimePimeActualMigrationReview'
