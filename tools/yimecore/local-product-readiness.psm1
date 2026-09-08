Set-StrictMode -Version Latest

function Assert-L6($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-L6True($Value) { Assert-L6 ($Value -is [bool] -and $Value) 'Expected JSON true, not a coerced value.' }
function Assert-L6False($Value) { Assert-L6 ($Value -is [bool] -and -not $Value) 'Expected JSON false, not a coerced value.' }
function Assert-L6Hash([string]$Value) { Assert-L6 ($Value -cmatch '^[0-9a-fA-F]{64}$') 'Invalid SHA256.' }

# Check every existing ancestor before reading or enumerating. References from JSON
# never authorize a new filesystem root, ADS, device path, or reparse traversal.
function Get-L6SafePath([string]$Path, [string]$Root, [switch]$AllowMissing) {
    Assert-L6 (-not [string]::IsNullOrWhiteSpace($Path)) 'Empty evidence path.'
    Assert-L6 ($Path -notmatch '^\\\\|^//|(^|[\\/])\.{1,2}([\\/]|$)|:[^\\/]') 'Noncanonical evidence path.'
    $full = [IO.Path]::GetFullPath($Path)
    if ($Root) {
        $base = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
        Assert-L6 ($full.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) 'Evidence path escapes its allowed root.'
    }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            Assert-L6 (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'Reparse evidence path is forbidden.'
        } elseif ($cursor -eq $full -and -not $AllowMissing) { throw 'Evidence path is missing.' }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    $full
}
function Get-L6Hash([string]$Path) {
    $safe = Get-L6SafePath $Path ''
    (Get-FileHash -LiteralPath $safe -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-L6Json([string]$Path, [string]$Schema = '') {
    $safe = Get-L6SafePath $Path ''
    Assert-L6 ([IO.Path]::GetExtension($safe) -eq '.json') 'Only explicit JSON evidence is read.'
    $value = Get-Content -LiteralPath $safe -Raw | ConvertFrom-Json
    if ($Schema) { Assert-L6 ($value.schema_version -ceq $Schema) 'Unexpected evidence schema.' }
    $value
}
function Get-L6Member([string]$Root, [string]$Relative) {
    Assert-L6 ($Relative -and -not [IO.Path]::IsPathRooted($Relative) -and $Relative -notmatch '[:*?]|(^|[\\/])\.{1,2}([\\/]|$)|[ .]([\\/]|$)') 'Invalid relative member path.'
    Get-L6SafePath (Join-Path $Root $Relative) $Root
}
function Assert-L6ExactHash([string]$Path, [string]$Hash) {
    Assert-L6Hash $Hash
    Assert-L6 ((Get-L6Hash $Path) -eq $Hash) 'Evidence hash mismatch.'
}
function Assert-L6MapEqual($Before, $After, [int]$Count) {
    Assert-L6 (@($Before.PSObject.Properties).Count -eq $Count -and @($After.PSObject.Properties).Count -eq $Count) 'Protected key inventory mismatch.'
    foreach ($entry in $Before.PSObject.Properties) { Assert-L6Hash $entry.Value; Assert-L6 ($After.($entry.Name) -ceq $entry.Value) 'Protected registry hashes changed.' }
}
function Assert-L6Snapshot($Value, [string]$Version, [string]$Hash, [int]$Count, [string]$Computer) {
    Assert-L6 ($Value.schema_version -ceq 'yimecore-l5-metadata-v1' -and $Value.computer -ceq $Computer -and $Value.package_version -ceq $Version -and $Value.manifest_sha256 -eq $Hash) 'Snapshot candidate or target mismatch.'
    Assert-L6 ($Value.package_file_count -is [ValueType] -and $Value.package_file_count -eq $Count -and @($Value.package_mismatches).Count -eq 0) 'Snapshot package inventory mismatch.'
    Assert-L6True $Value.package_integrity_passed; Assert-L6True $Value.runtime_identity_passed; Assert-L6True $Value.registered_x64_matches
    Assert-L6 ($Value.protected_registry_provider -ceq 'out-of-process StdRegProv; no process-view fallback') 'Independent registry provider missing.'
    Assert-L6 (@($Value.registered_x64_dll).Count -eq 1 -and $Value.registered_x64_dll[0] -ieq (Join-Path $Value.install_root 'x64\YimeTextServiceExperiment.dll')) 'Snapshot registered DLL mismatch.'
    Assert-L6 (@($Value.processes).Count -eq 2) 'Runtime process inventory mismatch.'
    foreach ($name in @('YimeCoreTrialRuntime.exe','YimeBroker.exe')) {
        $p = @($Value.processes | Where-Object { $_.name -ceq $name }); Assert-L6 ($p.Count -eq 1) 'Missing or duplicate runtime process.'
        Assert-L6True $p[0].current_package; Assert-L6True $p[0].after_boot
        Assert-L6 ($p[0].image -ieq (Join-Path $Value.install_root ('bin\' + $name)) -and [datetimeoffset]$p[0].started_at -gt [datetimeoffset]$Value.boot_at) 'Runtime path or boot binding mismatch.'
    }
    foreach ($key in @('user_text_read','learning_data_read','frozen_targets_executed','writes_to_product')) { Assert-L6False $Value.$key }
}
function Test-L6Package([string]$Root, [string]$Version, [string]$Hash, [string]$Computer) {
    $manifestPath = Get-L6Member $Root 'package-manifest.json'; Assert-L6ExactHash $manifestPath $Hash
    $m = Read-L6Json $manifestPath
    Assert-L6 ($m.package_contract -ceq 'yimecore-local-product-package-v1' -and $m.product_version -ceq $Version -and $m.development_scope.computer_name -ceq $Computer) 'Package identity or target mismatch.'
    $seen = @{}
    foreach ($entry in @($m.files)) {
        $key = ([string]$entry.path).Replace('\','/')
        Assert-L6 (-not $seen.ContainsKey($key)) 'Duplicate manifest member.'; $seen[$key] = $true
        $path = Get-L6Member $Root $key
        Assert-L6 ($entry.bytes -is [ValueType] -and $entry.bytes -isnot [bool] -and $entry.bytes -ge 0 -and (Get-Item -LiteralPath $path).Length -eq $entry.bytes) 'Package size mismatch.'
        Assert-L6ExactHash $path $entry.sha256
    }
    foreach ($key in @('Install-YimeCore-Local.cmd','Maintain-YimeCore-Local.cmd','LOCAL-PRODUCT.md','local-product.json','help/README.html','help/settings-and-data.html','help/diagnostics.html','maintenance/Manage-YimeCoreTrial.ps1','maintenance/backup-local-trial-state.ps1','maintenance/restore-local-trial-state.ps1','x64/YimeTextServiceExperiment.dll','x86/YimeTextServiceExperiment.dll','bin/YimeCoreTrialRuntime.exe','bin/YimeBroker.exe','build/source-manifest.json')) { Assert-L6 ($seen.ContainsKey($key)) 'Required package member missing.' }
    Assert-L6ExactHash (Get-L6Member $Root 'build/source-manifest.json') $m.source_manifest_sha256
    $descriptor = Read-L6Json (Get-L6Member $Root 'local-product.json') 'yimecore-local-product-v1'
    Assert-L6 ($descriptor.version -ceq $Version -and $descriptor.scope.computer_name -ceq $Computer -and $descriptor.identity.clsid -ceq '{E40FA752-BB96-461D-A51D-F40EB437EC65}' -and $descriptor.identity.profile -ceq '{126F54C6-E9B1-4E22-8652-03224CBD49F9}') 'Descriptor candidate identity mismatch.'
    # Enumeration does not enter reparse directories or read installation metadata.
    $queue = New-Object 'System.Collections.Generic.Queue[string]'; $queue.Enqueue($Root)
    while ($queue.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force) {
            $safe = Get-L6SafePath $item.FullName $Root
            if ($item.PSIsContainer) { $queue.Enqueue($safe) } else {
                $relative = $safe.Substring($Root.TrimEnd('\','/').Length + 1).Replace('\','/')
                Assert-L6 ($seen.ContainsKey($relative) -or $relative -in @('package-manifest.json','install-metadata.json')) 'Unlisted public package member.'
            }
        }
    }
    $m
}
function Assert-L6ModeResults($Results) {
    Assert-L6 (@($Results).Count -eq 6) 'Expected six registered architecture/mode outcomes.'
    foreach ($arch in @('x64','x86')) { foreach ($mode in @('full','variable','shorthand')) {
        $r = @($Results | Where-Object { $_.architecture -ceq $arch -and $_.mode -ceq $mode })
        Assert-L6 ($r.Count -eq 1 -and $r[0].exit_code -is [ValueType] -and $r[0].exit_code -isnot [bool] -and $r[0].exit_code -eq 0) 'Registered result missing, duplicate, or failed.'
        Assert-L6True $r[0].passed
    } }
}

function Get-YimeCoreLocalProductReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$DailyUseEvidence,
        [Parameter(Mandatory)][string]$RegisteredHostEvidence,
        [Parameter(Mandatory)][string]$RebootEvidence,
        [Parameter(Mandatory)][string]$X86AcceptanceRecord,
        [Parameter(Mandatory)][string]$Local12ManualEvidence,
        [Parameter(Mandatory)][string]$PreviousPackageBackupEvidence,
        [string]$CurrentCandidateRecoveryEvidence,
        [string]$RepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))),
        [string]$ExpectedVersion = '0.1.0-local.12',
        [string]$ExpectedManifestSha256 = '9b3366b350ef2b23fd285fc9d97d876bf1ae6e2fc0f8613c647640f01184502e',
        [string]$EvidenceIndex = (Join-Path $PSScriptRoot 'local12-readiness-evidence.json'),
        [string]$RecoveryArchiveRoot = (Join-Path $env:USERPROFILE 'YimeCore Recovery Archives')
    )
    $ErrorActionPreference = 'Stop'
    $index = Read-L6Json (Get-L6SafePath $EvidenceIndex $RepositoryRoot) 'yimecore-local12-readiness-evidence-index-v1'
    Assert-L6 ($index.package_version -ceq $ExpectedVersion -and $index.manifest_sha256 -eq $ExpectedManifestSha256 -and $index.computer -ceq 'MYCOMPUTER') 'Evidence index candidate mismatch.'
    $checks = [ordered]@{}; $errors = [ordered]@{}; $evidence = [ordered]@{}
    function Read-Indexed([string]$Id, [string]$SuppliedPath = '') {
        $entry = $index.records.$Id
        $path = Get-L6Member $RepositoryRoot $entry.path
        if ($SuppliedPath) { Assert-L6 ([IO.Path]::GetFullPath($SuppliedPath) -ieq $path) 'Evidence input differs from the reviewed index.' }
        Assert-L6ExactHash $path $entry.sha256
        $evidence[$Id] = [ordered]@{path=$path;sha256=Get-L6Hash $path}
        Read-L6Json $path $entry.schema
    }
    function Check([string]$Name, [scriptblock]$Body) {
        try { & $Body | Out-Null; $checks[$Name]=$true } catch { $checks[$Name]=$false; $errors[$Name]=$_.Exception.Message }
    }
    $package = [ordered]@{passed=$false;root=[IO.Path]::GetFullPath($PackageRoot);version=$ExpectedVersion;manifest_sha256=$ExpectedManifestSha256;file_count=0}
    Check 'sealed_package_integrity' {
        $safe = Get-L6SafePath $PackageRoot $RecoveryArchiveRoot
        $m = Test-L6Package $safe $ExpectedVersion $ExpectedManifestSha256 $index.computer
        $package.passed=$true; $package.file_count=@($m.files).Count
        $package.source_manifest_sha256=$m.source_manifest_sha256
    }
    Check 'sealed_package_outside_repository' {
        Assert-L6 (-not ([IO.Path]::GetFullPath($PackageRoot).StartsWith([IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\','/') + '\', [StringComparison]::OrdinalIgnoreCase))) 'Sealed package remains in the repository.'
    }
    Check 'sealed_source_and_build_archive_integrity' {
        Assert-L6True $package.passed
        $root = Split-Path -Parent $PackageRoot
        $sealPath = Get-L6Member $root 'seal.json'; Assert-L6ExactHash $sealPath $index.seal_sha256
        $seal = Read-L6Json $sealPath 'yimecore-local12-l6-seal-v1'
        Assert-L6 ($seal.package_version -ceq $ExpectedVersion -and $seal.package_manifest_sha256 -eq $ExpectedManifestSha256) 'Seal candidate mismatch.'
        foreach ($pair in @(@('source-snapshot.zip','source_snapshot_sha256'),@('working-tree.patch','working_tree_patch_sha256'),@('summary.json','build_summary_sha256'))) { Assert-L6ExactHash (Get-L6Member $root $pair[0]) $seal.($pair[1]) }
        $build = Read-L6Json (Get-L6Member $root 'summary.json') 'yimecore-local-build-result-v1'
        Assert-L6True $build.passed; Assert-L6True $build.registration_and_default_preserved
        $source = Read-L6Json (Get-L6Member $PackageRoot 'build/source-manifest.json') 'yimecore-local-source-v1'
        $m = Read-L6Json (Get-L6Member $PackageRoot 'package-manifest.json')
        Assert-L6 ($source.git_commit -ceq $m.git_commit) 'Source commit differs from the package.'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead((Get-L6Member $root 'source-snapshot.zip'))
        try {
            $zipEntries=@{}
            foreach ($entry in $zip.Entries) {
                $name = $entry.FullName.Replace('\','/')
                if ($name.EndsWith('/')) { continue }
                Assert-L6 ($name -notmatch '^/|[:*?]|(^|/)\.{1,2}(/|$)' -and -not $zipEntries.ContainsKey($name)) 'Unsafe or duplicate source ZIP entry.'
                $zipEntries[$name]=$entry
            }
            Assert-L6 ($zipEntries.Count -eq @($source.files).Count) 'Source ZIP inventory differs from source manifest.'
            foreach ($file in $source.files) {
                $entry=$zipEntries[[string]$file.path]; Assert-L6 ($null -ne $entry -and $entry.Length -eq $file.bytes) 'Source ZIP member missing or wrong size.'
                $stream=$entry.Open(); $sha=[Security.Cryptography.SHA256]::Create()
                try { $hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant(); Assert-L6 ($hash -eq $file.sha256) 'Source ZIP member hash mismatch.' } finally { $sha.Dispose(); $stream.Dispose() }
            }
        } finally { $zip.Dispose() }
        $evidence.seal=@{path=$sealPath;sha256=Get-L6Hash $sealPath}
    }
    Check 'l5_final_user_confirmation' {
        $daily=Read-Indexed 'daily_use' $DailyUseEvidence
        Assert-L6 ($daily.affected_product -ceq 'YimeCore' -and $daily.scope -ceq ('MYCOMPUTER installed ' + $ExpectedVersion + ' only')) 'Daily-use target mismatch.'
        Assert-L6True $daily.gates.L5_final_user_confirmation; Assert-L6True $daily.user_report.accepted_for_daily_use; Assert-L6True $daily.guided_scenario.user_executed
        foreach ($field in @('L6_sealed','local_product_ready','public_release_ready')) { Assert-L6False $daily.gates.$field }
    }
    Check 'l5_post_use_identity_and_protection' {
        Assert-L6True $package.passed
        $daily=Read-Indexed 'daily_use' $DailyUseEvidence; $post=Read-Indexed 'post_use'; $reboot=Read-Indexed 'reboot' $RebootEvidence
        Assert-L6 ($daily.mechanical_post_use.snapshot_path -ceq $index.records.post_use.path -and $daily.mechanical_post_use.snapshot_sha256 -eq $index.records.post_use.sha256 -and $daily.mechanical_post_use.reference_path -ceq $index.records.reboot.path -and $daily.mechanical_post_use.reference_sha256 -eq $index.records.reboot.sha256) 'Daily-use raw reference mismatch.'
        Assert-L6Snapshot $post $ExpectedVersion $ExpectedManifestSha256 $package.file_count $index.computer
        Assert-L6MapEqual $post.protected_registry_sha256 $reboot.current_installed.protected_registry_sha256 12
        Assert-L6True $daily.mechanical_post_use.passed
        foreach ($field in $daily.mechanical_post_use.checks.PSObject.Properties) { Assert-L6True $field.Value }
        foreach ($field in $daily.privacy.PSObject.Properties) { Assert-L6False $field.Value }
    }
    Check 'installed_x64_x86_registered_hosts' {
        $registered=Read-Indexed 'registered_hosts' $RegisteredHostEvidence
        Assert-L6 ($registered.manifest_sha256 -eq $ExpectedManifestSha256) 'Registered candidate mismatch.'
        Assert-L6ModeResults $registered.results
        foreach ($key in @('passed','registered_host_acceptance','protected_registry_unchanged','runtime_unchanged','environment_restored','children_stopped','package_recheck_passed')) { Assert-L6True $registered.gates.$key }
        Assert-L6MapEqual $registered.baseline_before.sha256 $registered.baseline_after.sha256 23
        Assert-L6 (@($registered.artifacts).Count -eq 7) 'Registered raw artifact inventory mismatch.'
        $rawSeen=@{}; $rawSummaryCount=0
        $requiredOutcomes=@('candidate_popup_ownership_guard_verified','registered_key_sink_verified','registered_text_extent_anchor','registered_candidate_commit','registered_default_candidate_keys_verified','registered_invalid_code_backspace_recovery_verified','registered_direction_and_page_keys_verified','registered_english_shift_passthrough_verified','physical_mouse_candidate_selection_verified','delayed_async_edit_completion_verified','failed_async_edit_recovery_verified','punctuation_text_extent_anchor_verified','retained_language_bar_after_deactivation_verified','registered_focus_callbacks_verified','registered_focus_cancellation_preserves_committed_text_verified','registered_delayed_focus_cancellation_verified','registered_failed_focus_cancellation_text_preservation_verified','registered_language_bar_accepted','architecture_verified')
        foreach ($artifact in $registered.artifacts) {
            $mapped=@($index.registered_artifacts | Where-Object { $_.original_path -ieq $artifact.path -and $_.sha256 -eq $artifact.sha256 })
            Assert-L6 ($mapped.Count -eq 1) 'Unreviewed registered raw artifact reference.'
            $p=Get-L6Member $RepositoryRoot $mapped[0].path; Assert-L6ExactHash $p $artifact.sha256
            if ([IO.Path]::GetFileName($artifact.path) -eq 'summary.json') {
                $rawSummaryCount++
                $raw=Read-L6Json $p 'yimecore-local12-private-host-v1'
                Assert-L6 ($raw.manifest_sha256 -eq $ExpectedManifestSha256 -and $raw.install_root -ieq $registered.install_root) 'Registered raw candidate mismatch.'
                Assert-L6ModeResults $raw.results; Assert-L6True $raw.passed
            } else {
                $raw=Read-L6Json $p
                $rawKey=([string]$raw.architecture)+'/'+([string]$raw.mode)
                Assert-L6 (-not $rawSeen.ContainsKey($rawKey)) 'Duplicate raw registered outcome.'; $rawSeen[$rawKey]=$true
                $match=@($registered.results | Where-Object { $_.architecture -ceq $raw.architecture -and $_.mode -ceq $raw.mode })
                Assert-L6 ($match.Count -eq 1) 'Registered raw mode mismatch.'
                Assert-L6True $raw.passed; Assert-L6False $raw.timed_out
                Assert-L6 ($raw.exit_code -is [ValueType] -and $raw.exit_code -isnot [bool] -and $raw.exit_code -eq 0) 'Raw registered exit code failed.'
                Assert-L6 ($raw.outcomes.registered_focus_outcome -ceq 'unconfirmed_input_cancelled') 'Raw registered focus outcome failed.'
                foreach ($outcome in $requiredOutcomes) {
                    Assert-L6True $raw.outcomes.$outcome
                    Assert-L6True $match[0].outcomes.$outcome
                }
            }
        }
        Assert-L6 ($rawSummaryCount -eq 1 -and $rawSeen.Count -eq 6) 'Registered raw summary/mode inventory mismatch.'
    }
    Check 'local12_reboot_and_logon_autostart' {
        Assert-L6True $package.passed
        $r=Read-Indexed 'reboot' $RebootEvidence; $manual=Read-Indexed 'manual' $Local12ManualEvidence
        Assert-L6Snapshot $r.current_installed $ExpectedVersion $ExpectedManifestSha256 $package.file_count $index.computer
        Assert-L6 ($r.pre_reboot_reference.path -ceq $index.records.manual.path -and $r.pre_reboot_reference.sha256 -eq $index.records.manual.sha256) 'Reboot pre-reference hash mismatch.'
        Assert-L6True $r.local12_reboot_autostart_gate_passed
        foreach ($field in $r.checks.PSObject.Properties) { Assert-L6True $field.Value }
        Assert-L6 ([datetimeoffset]$r.current_installed.boot_at -gt [datetimeoffset]$manual.recorded_at) 'Reboot predates the manual record.'
        Assert-L6True $r.startup_metadata.autostart_run.exact_value_matches
        Assert-L6 ($r.startup_metadata.autostart_run.registry_reader -ceq 'StdRegProv/HKEY_USERS') 'Autostart lacks independent registry evidence.'
        Assert-L6True $r.event_command_rendering.exact_known_event_rendering_matches
        $runtime=@($r.current_installed.processes | Where-Object name -eq 'YimeCoreTrialRuntime.exe')[0]
        $events=@($r.startup_metadata.shell_core.events | Where-Object { $_.record_id -eq $r.event_command_rendering.record_id -and $_.runtime_pid -eq $runtime.pid -and $_.user_sid -ceq $r.startup_metadata.target_user_sid -and $_.event_id -eq 9708 })
        Assert-L6 ($events.Count -eq 1) 'Shell-Core event does not bind the accepted Runtime PID/SID.'
        Assert-L6True $events[0].same_user; Assert-L6True $events[0].after_boot
    }
    Check 'previous_working_package_backup_preserved' {
        $b=Read-Indexed 'backup' $PreviousPackageBackupEvidence
        Assert-L6 ($b.candidate_manifest_sha256 -eq $ExpectedManifestSha256 -and $b.current_installed.computer -ceq $index.computer -and $b.current_installed.package_version -ceq '0.1.0-local.11') 'Previous package target or version mismatch.'
        Assert-L6True $b.native_context_verified; Assert-L6True $b.native_backup_manifest_passed
        $archive=Get-L6SafePath $b.archive_root $RecoveryArchiveRoot
        # Only hash the explicitly named backup manifest; never read state entries or state contents.
        $metadata=Get-L6Member $archive 'backup-manifest.json'; Assert-L6ExactHash $metadata $b.manifest.sha256
        $previous=Test-L6Package (Get-L6Member $archive 'previous-package') $b.current_installed.package_version $b.current_installed.manifest_sha256 $index.computer
        Assert-L6 ($previous.product_version -ceq $b.archived_public_package_verification.product_version -and @($previous.files).Count -eq $b.archived_public_package_verification.package_manifest_files_verified) 'Previous package inventory mismatch.'
        $evidence.previous_package=@{root=(Join-Path $archive 'previous-package');manifest_sha256=$b.current_installed.manifest_sha256;file_count=@($previous.files).Count}
    }
    Check 'x86_live_host_evidence_chain' {
        Assert-L6True $package.passed
        $x=Read-Indexed 'x86_live_hosts' $X86AcceptanceRecord; $manual=Read-Indexed 'manual' $Local12ManualEvidence; $old=Read-Indexed 'x86_registered'
        Assert-L6 ($x.computer_name -ceq $index.computer -and $x.package_version -ceq '0.1.0-local.11' -and $x.package_manifest_sha256 -eq $old.manifest_sha256 -and $x.registered_host_summary_sha256 -eq $index.records.x86_registered.sha256 -and $x.registered_host_summary -ieq $index.records.x86_registered.original_path) 'Historical x86 evidence binding mismatch.'
        Assert-L6ModeResults $old.results; Assert-L6True $old.passed; Assert-L6True $x.passed; Assert-L6True $x.protected_state_unchanged
        $protection=Read-Indexed 'x86_protection'
        Assert-L6 ($x.protected_state_comparison -ieq $index.records.x86_protection.original_path -and @($protection.checked_keys).Count -eq 12 -and @($protection.changed_keys).Count -eq 0) 'Historical x86 protection reference mismatch.'
        Assert-L6True $protection.all_protected_unchanged
        Assert-L6False $x.default_input_method.changed_by_acceptance
        $backup=Read-Indexed 'backup' $PreviousPackageBackupEvidence
        Assert-L6 ($x.package_manifest_sha256 -eq $backup.current_installed.manifest_sha256 -and $old.development_scope.computer_name -ceq $index.computer) 'Historical x86 package/target mismatch.'
        Assert-L6 ($old.registered_dlls.x86.sha256 -eq $x.x86_text_service_sha256) 'Historical registered x86 hash mismatch.'
        Assert-L6 (@($x.hosts).Count -eq 2) 'Expected the two reported physical hosts.'
        foreach ($name in @('Firefox','Notepad++')) {
            $hostRecord=@($x.hosts | Where-Object { $_.name -ceq $name }); Assert-L6 ($hostRecord.Count -eq 1) 'Missing or duplicate physical host.'
            $h=$hostRecord[0]
            Assert-L6 ($h.architecture -ceq 'x86' -and $h.pe_machine -ceq '0x014C' -and $h.loaded_text_service_sha256 -eq $x.x86_text_service_sha256 -and $h.loaded_text_service -ieq (Join-Path $x.package_root 'x86\YimeTextServiceExperiment.dll')) 'Historical live DLL mismatch.'
            Assert-L6True $h.exact_installed_x86_module_verified; Assert-L6True $h.all_input_observations_passed
            foreach ($key in @('composition_and_commit','bare_digits_remain_composition','shift_1_selects_first_candidate')) { Assert-L6True $h.input_observations.$key }
        }
        Assert-L6Snapshot $manual.current_installed $ExpectedVersion $ExpectedManifestSha256 $package.file_count $index.computer
        Assert-L6True $manual.user_report.uncommitted_focus_switch.tested; Assert-L6False $manual.user_report.uncommitted_focus_switch.unexpected_anomaly_reported
        Assert-L6 ($manual.regression_status.'D2-F-01' -ceq 'manual_retest_passed_user_report_for_reported_Word_Notepadpp_switching') 'Missing current affected x86 manual confirmation.'
        $m=Read-L6Json (Get-L6Member $PackageRoot 'package-manifest.json')
        $hash=@($m.files | Where-Object path -eq 'x86/YimeTextServiceExperiment.dll')[0].sha256
        $modules=@($manual.host_modules.hosts | Where-Object name -eq 'notepad++.exe' | ForEach-Object yime_modules)
        Assert-L6 ($modules.Count -eq 1 -and $modules[0].sha256 -eq $hash -and $modules[0].path -ieq (Join-Path $manual.current_installed.install_root 'x86\YimeTextServiceExperiment.dll')) 'Current affected x86 loaded DLL mismatch.'
    }
    # No accepted native recovery producer exists yet. A hand-written report, even
    # with true booleans, cannot upgrade the closure decision to a verified pass.
    $checks.current_candidate_actual_restore_and_failed_upgrade_rollback=$false
    $errors.current_candidate_actual_restore_and_failed_upgrade_rollback='No reviewed native recovery producer is integrated; determine inherited evidence and minimal maintenance coverage before execution.'
    if ($CurrentCandidateRecoveryEvidence) {
        $p=Get-L6SafePath $CurrentCandidateRecoveryEvidence $RepositoryRoot
        $evidence.unverified_recovery_submission=@{path=$p;sha256=Get-L6Hash $p;accepted_for_closure=$false}
    }
    $pending=@($checks.Keys | Where-Object { -not $checks[$_] })
    [ordered]@{
        schema_version='yimecore-local-product-readiness-v2';generated_at=(Get-Date).ToUniversalTime().ToString('o')
        affected_product='YimeCore';scope='MYCOMPUTER local.12 historical acceptance and currently sealed public artifacts; no fresh live-host acceptance'
        package=$package;checks=$checks;check_failures=$errors;local_product_ready=$false;L6_sealed=$false;public_release_ready=$false;pending=$pending
        evidence_index=@{path=[IO.Path]::GetFullPath($EvidenceIndex);sha256=Get-L6Hash $EvidenceIndex};evidence=$evidence
        privacy=@{installer_executed=$false;product_or_registry_mutated=$false;default_input_method_changed=$false;user_text_read=$false;user_settings_or_learning_files_read=$false;raw_logs_or_events_read=$false;recovery_state_contents_read=$false;installed_product_read=$false}
        limitations=@('Historical reports retain their original scope and dates; this is a public-artifact and evidence validation, not current installed acceptance.','Hashes bind reviewed evidence; they do not authenticate a forged new recovery report. Recovery needs a reviewed producer and a decision on inherited coverage.','The x86 chain inherits local.11 physical hosts and local.12 affected-path manual confirmation; a full physical rerun is not claimed.','Signing, ARM64 native acceptance and other physical PC acceptance remain separate.')
    }
}

function Write-YimeCoreReadinessResult {
    param([Parameter(Mandatory)]$Result,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][string]$RepositoryRoot)
    $path=Get-L6SafePath $OutputPath $RepositoryRoot -AllowMissing
    $relative=$path.Substring([IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\','/').Length+1).Replace('\','/')
    Assert-L6 ($relative -match '^(docs/testing/l6|\.tmp/yimecore-readiness)/[A-Za-z0-9][A-Za-z0-9._-]*\.json$') 'Output must be a new JSON directly in docs/testing/l6 or .tmp/yimecore-readiness.'
    $parent=Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $null=Get-L6SafePath $parent $RepositoryRoot
    # CreateNew also rejects pre-existing hard links and prevents overwriting raw evidence.
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(($Result | ConvertTo-Json -Depth 20)); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
}
Export-ModuleMember -Function Get-YimeCoreLocalProductReadiness,Write-YimeCoreReadinessResult
