$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'local-product-readiness.psm1') -Force
$root = Join-Path ([IO.Path]::GetTempPath()) ('yimecore-readiness-' + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $root 'repo'
$recoveryRoot = Join-Path $root 'archives'
$checksRun = 0
function Write-Json($Path,$Value) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 25),(New-Object Text.UTF8Encoding($false)))
}
function Hash($Path) { (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant() }
function Assert-Test($Condition,$Name) { if (-not $Condition) { throw "FAIL: $Name" }; $script:checksRun++; Write-Host "PASS: $Name" }
function New-Package($Path,$Version) {
    $members=@('Install-YimeCore-Local.cmd','Maintain-YimeCore-Local.cmd','LOCAL-PRODUCT.md','local-product.json','help/README.html','help/settings-and-data.html','help/diagnostics.html','maintenance/Manage-YimeCoreTrial.ps1','maintenance/backup-local-trial-state.ps1','maintenance/restore-local-trial-state.ps1','x64/YimeTextServiceExperiment.dll','x86/YimeTextServiceExperiment.dll','bin/YimeCoreTrialRuntime.exe','bin/YimeBroker.exe','build/source-manifest.json')
    foreach($name in $members) { $p=Join-Path $Path $name; [IO.Directory]::CreateDirectory((Split-Path -Parent $p))|Out-Null; [IO.File]::WriteAllText($p,$name) }
    Write-Json (Join-Path $Path 'local-product.json') @{schema_version='yimecore-local-product-v1';version=$Version;scope=@{computer_name='MYCOMPUTER'};identity=@{clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}';profile='{126F54C6-E9B1-4E22-8652-03224CBD49F9}'}}
    $sourceDir=Join-Path $root 'fixture-source'; [IO.Directory]::CreateDirectory($sourceDir)|Out-Null; [IO.File]::WriteAllText((Join-Path $sourceDir 'hello.txt'),'public source')
    Write-Json (Join-Path $Path 'build/source-manifest.json') @{schema_version='yimecore-local-source-v1';git_commit=('a'*40);files=@(@{path='hello.txt';bytes=13;sha256=Hash (Join-Path $sourceDir 'hello.txt')})}
    $entries=@($members|ForEach-Object { $p=Join-Path $Path $_; @{path=$_;bytes=(Get-Item $p).Length;sha256=Hash $p} })
    Write-Json (Join-Path $Path 'package-manifest.json') @{package_contract='yimecore-local-product-package-v1';product_version=$Version;git_commit=('a'*40);development_scope=@{computer_name='MYCOMPUTER'};source_manifest_sha256=Hash (Join-Path $Path 'build/source-manifest.json');files=$entries}
}
function Snapshot($Version,$Manifest,$Install) {
    $protected=@{}; 1..12|ForEach-Object { $protected["key$_"]='a'*64 }
    @{schema_version='yimecore-l5-metadata-v1';computer='MYCOMPUTER';package_version=$Version;manifest_sha256=$Manifest;install_root=$Install;package_file_count=15;package_mismatches=@();package_integrity_passed=$true;runtime_identity_passed=$true;registered_x64_matches=$true;registered_x64_dll=@((Join-Path $Install 'x64/YimeTextServiceExperiment.dll'));boot_at='2026-09-08T01:00:00Z';protected_registry_provider='out-of-process StdRegProv; no process-view fallback';protected_registry_sha256=$protected;processes=@(@{name='YimeCoreTrialRuntime.exe';pid=12;image=(Join-Path $Install 'bin/YimeCoreTrialRuntime.exe');started_at='2026-09-08T01:01:00Z';current_package=$true;after_boot=$true},@{name='YimeBroker.exe';pid=13;image=(Join-Path $Install 'bin/YimeBroker.exe');started_at='2026-09-08T01:01:01Z';current_package=$true;after_boot=$true});user_text_read=$false;learning_data_read=$false;frozen_targets_executed=$false;writes_to_product=$false}
}
function Save-Record($Id,$Value) { $path=Join-Path $repo ($Id+'.json'); Write-Json $path $Value; $script:index.records[$Id]=@{path=($Id+'.json');sha256=Hash $path;schema=$Value.schema_version}; $path }
function Refresh-Record($Id) { $script:index.records[$Id].sha256=Hash (Join-Path $repo $script:index.records[$Id].path); Write-Json $indexPath $script:index }
function Run-Readiness { Write-Json $indexPath $script:index; Get-YimeCoreLocalProductReadiness @arguments }
function Bad-Record($Id,$Gate,[scriptblock]$Mutation,$Name) {
    $path=Join-Path $repo $script:index.records[$Id].path; $original=[IO.File]::ReadAllText($path)
    try { $value=$original|ConvertFrom-Json; & $Mutation $value; Write-Json $path $value; Refresh-Record $Id; $result=Run-Readiness; Assert-Test (-not $result.checks[$Gate] -and -not $result.local_product_ready) $Name }
    finally { [IO.File]::WriteAllText($path,$original); Refresh-Record $Id }
}
function Expect-Throw([scriptblock]$Action,$Name) { $rejected=$false; try { & $Action |Out-Null } catch { $rejected=$true }; Assert-Test $rejected $Name }
try {
    [IO.Directory]::CreateDirectory($repo)|Out-Null
    $sealRoot=Join-Path $recoveryRoot 'sealed'; $package=Join-Path $sealRoot 'package'; New-Package $package '0.1.0-local.12'
    $archive=Join-Path $recoveryRoot 'previous'; $previous=Join-Path $archive 'previous-package'; New-Package $previous '0.1.0-local.11'
    $manifestHash=Hash (Join-Path $package 'package-manifest.json'); $oldHash=Hash (Join-Path $previous 'package-manifest.json')
    $x86Hash=Hash (Join-Path $package 'x86/YimeTextServiceExperiment.dll')
    $install=Join-Path $root 'never-created-install'; $oldInstall=Join-Path $root 'never-created-old-install'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $root 'fixture-source'),(Join-Path $sealRoot 'source-snapshot.zip'))
    [IO.File]::WriteAllText((Join-Path $sealRoot 'working-tree.patch'),'public patch')
    Write-Json (Join-Path $sealRoot 'summary.json') @{schema_version='yimecore-local-build-result-v1';passed=$true;registration_and_default_preserved=$true}
    Write-Json (Join-Path $sealRoot 'seal.json') @{schema_version='yimecore-local12-l6-seal-v1';package_version='0.1.0-local.12';package_manifest_sha256=$manifestHash;source_snapshot_sha256=Hash (Join-Path $sealRoot 'source-snapshot.zip');working_tree_patch_sha256=Hash (Join-Path $sealRoot 'working-tree.patch');build_summary_sha256=Hash (Join-Path $sealRoot 'summary.json')}
    $script:index=@{schema_version='yimecore-local12-readiness-evidence-index-v1';computer='MYCOMPUTER';package_version='0.1.0-local.12';manifest_sha256=$manifestHash;seal_sha256=Hash (Join-Path $sealRoot 'seal.json');records=@{};registered_artifacts=@()}
    $indexPath=Join-Path $repo 'index.json'
    $snapshot=Snapshot '0.1.0-local.12' $manifestHash $install
    $post=Save-Record 'post_use' $snapshot
    $manual=Save-Record 'manual' @{schema_version='yimecore-l5-local12-manual-pre-reboot-v1';recorded_at='2026-09-07T10:00:00Z';current_installed=$snapshot;user_report=@{uncommitted_focus_switch=@{tested=$true;unexpected_anomaly_reported=$false}};regression_status=@{'D2-F-01'='manual_retest_passed_user_report_for_reported_Word_Notepadpp_switching'};host_modules=@{hosts=@(@{name='notepad++.exe';yime_modules=@(@{path=(Join-Path $install 'x86/YimeTextServiceExperiment.dll');sha256=$x86Hash})})}}
    $reboot=Save-Record 'reboot' @{schema_version='yimecore-l5-local12-reboot-outcomes-v1';current_installed=$snapshot;pre_reboot_reference=@{path='manual.json';sha256=Hash $manual};local12_reboot_autostart_gate_passed=$true;checks=@{package=$true};startup_metadata=@{target_user_sid='S-1-5-21-1-2-3-1001';autostart_run=@{exact_value_matches=$true;registry_reader='StdRegProv/HKEY_USERS'};shell_core=@{events=@(@{record_id=1;runtime_pid=12;user_sid='S-1-5-21-1-2-3-1001';event_id=9708;same_user=$true;after_boot=$true})}};event_command_rendering=@{record_id=1;exact_known_event_rendering_matches=$true}}
    $daily=Save-Record 'daily_use' @{schema_version='yimecore-local12-l5-final-daily-use-v1';affected_product='YimeCore';scope='MYCOMPUTER installed 0.1.0-local.12 only';user_report=@{accepted_for_daily_use=$true};guided_scenario=@{user_executed=$true};gates=@{L5_final_user_confirmation=$true;L6_sealed=$false;local_product_ready=$false;public_release_ready=$false};mechanical_post_use=@{passed=$true;checks=@{package=$true};snapshot_path='post_use.json';snapshot_sha256=Hash $post;reference_path='reboot.json';reference_sha256=Hash $reboot};privacy=@{user_text_read=$false}}
    $outcomes=@{registered_focus_outcome='unconfirmed_input_cancelled'}
    foreach($key in @('candidate_popup_ownership_guard_verified','registered_key_sink_verified','registered_text_extent_anchor','registered_candidate_commit','registered_default_candidate_keys_verified','registered_invalid_code_backspace_recovery_verified','registered_direction_and_page_keys_verified','registered_english_shift_passthrough_verified','physical_mouse_candidate_selection_verified','delayed_async_edit_completion_verified','failed_async_edit_recovery_verified','punctuation_text_extent_anchor_verified','retained_language_bar_after_deactivation_verified','registered_focus_callbacks_verified','registered_focus_cancellation_preserves_committed_text_verified','registered_delayed_focus_cancellation_verified','registered_failed_focus_cancellation_text_preservation_verified','registered_language_bar_accepted','architecture_verified')) { $outcomes[$key]=$true }
    $results=@(); foreach($arch in @('x64','x86')) { foreach($mode in @('full','variable','shorthand')) { $results+=@{architecture=$arch;mode=$mode;passed=$true;exit_code=0;timed_out=$false;outcomes=$outcomes} } }
    $protected=@{}; 1..23|ForEach-Object { $protected["key$_"]='a'*64 }
    $rawSummary=Join-Path $repo 'raw-summary.json'; Write-Json $rawSummary @{schema_version='yimecore-local12-private-host-v1';manifest_sha256=$manifestHash;install_root=$install;results=$results;passed=$true}
    $artifacts=@(@{path=(Join-Path $repo 'summary.json');sha256=Hash $rawSummary})
    $script:index.registered_artifacts+=@{original_path=$artifacts[0].path;path='raw-summary.json';sha256=Hash $rawSummary}
    $number=0; foreach($r in $results) { $p=Join-Path $repo ("outcome-$number.json"); Write-Json $p $r; $artifacts+=@{path=$p;sha256=Hash $p}; $script:index.registered_artifacts+=@{original_path=$p;path=("outcome-$number.json");sha256=Hash $p}; $number++ }
    $registered=Save-Record 'registered_hosts' @{schema_version='yimecore-l5-local12-registered-acceptance-v1';manifest_sha256=$manifestHash;install_root=$install;results=$results;artifacts=$artifacts;baseline_before=@{sha256=$protected};baseline_after=@{sha256=$protected};gates=@{passed=$true;registered_host_acceptance=$true;protected_registry_unchanged=$true;runtime_unchanged=$true;environment_restored=$true;children_stopped=$true;package_recheck_passed=$true}}
    $xreg=Save-Record 'x86_registered' @{schema_version='yimecore-installed-local-host-v1';manifest_sha256=$oldHash;development_scope=@{computer_name='MYCOMPUTER'};registered_dlls=@{x86=@{sha256=$x86Hash}};results=$results;passed=$true}
    $script:index.records.x86_registered.original_path=$xreg
    $hosts=@(); foreach($name in @('Firefox','Notepad++')) { $hosts+=@{name=$name;architecture='x86';pe_machine='0x014C';loaded_text_service_sha256=$x86Hash;loaded_text_service=(Join-Path $oldInstall 'x86/YimeTextServiceExperiment.dll');exact_installed_x86_module_verified=$true;all_input_observations_passed=$true;input_observations=@{composition_and_commit=$true;bare_digits_remain_composition=$true;shift_1_selects_first_candidate=$true}} }
    $xp=Save-Record 'x86_protection' @{schema_version='';checked_keys=@(1..12);changed_keys=@();all_protected_unchanged=$true}
    $script:index.records.x86_protection.original_path=$xp
    $x86=Save-Record 'x86_live_hosts' @{schema_version='yimecore-x86-live-host-acceptance-v1';computer_name='MYCOMPUTER';package_version='0.1.0-local.11';package_manifest_sha256=$oldHash;package_root=$oldInstall;registered_host_summary=$xreg;registered_host_summary_sha256=Hash $xreg;x86_text_service_sha256=$x86Hash;hosts=$hosts;passed=$true;protected_state_unchanged=$true;protected_state_comparison=$xp;default_input_method=@{changed_by_acceptance=$false}}
    Write-Json (Join-Path $archive 'backup-manifest.json') @{public_metadata_only=$true}
    $backup=Save-Record 'backup' @{schema_version='yimecore-l5-local12-native-backup-evidence-v1';candidate_manifest_sha256=$manifestHash;current_installed=@{computer='MYCOMPUTER';package_version='0.1.0-local.11';manifest_sha256=$oldHash};archive_root=$archive;manifest=@{sha256=Hash (Join-Path $archive 'backup-manifest.json')};native_context_verified=$true;native_backup_manifest_passed=$true;archived_public_package_verification=@{product_version='0.1.0-local.11';package_manifest_files_verified=15}}
    $arguments=@{PackageRoot=$package;DailyUseEvidence=$daily;RegisteredHostEvidence=$registered;RebootEvidence=$reboot;X86AcceptanceRecord=$x86;Local12ManualEvidence=$manual;PreviousPackageBackupEvidence=$backup;RepositoryRoot=$repo;ExpectedManifestSha256=$manifestHash;EvidenceIndex=$indexPath;RecoveryArchiveRoot=$recoveryRoot}
    $good=Run-Readiness
    Assert-Test ($good.pending.Count -eq 1 -and $good.checks.sealed_source_and_build_archive_integrity -and $good.checks.x86_live_host_evidence_chain) ('Complete public fixture validates nine checks: '+($good.check_failures|ConvertTo-Json -Compress))
    Assert-Test (-not $good.local_product_ready -and -not $good.L6_sealed -and -not $good.public_release_ready) 'Unverified native recovery cannot close L6'
    $submission=Join-Path $repo 'unverified-recovery.json'; Write-Json $submission @{schema_version='yimecore-local-product-current-candidate-recovery-v1';passed=$true;package_version='0.1.0-local.12';manifest_sha256=$manifestHash;actual_restore_passed=$true;actual_failed_upgrade_rollback_passed=$true;system_registry_rollback_verified=$true}
    $arguments.CurrentCandidateRecoveryEvidence=$submission; $unverified=Run-Readiness
    Assert-Test (-not $unverified.local_product_ready -and -not $unverified.checks.current_candidate_actual_restore_and_failed_upgrade_rollback) 'All-true hand-written recovery report is rejected for closure'
    $arguments.Remove('CurrentCandidateRecoveryEvidence')
    foreach($value in @('false','true',1,0,$null)) { $script:badBoolean=$value; Bad-Record 'daily_use' 'l5_final_user_confirmation' {param($v) $v.user_report.accepted_for_daily_use=$script:badBoolean} "JSON truth must be boolean: $value" }
    Bad-Record 'daily_use' 'l5_final_user_confirmation' {param($v) $v.scope='OTHERPC installed 0.1.0-local.12 only'} 'Wrong daily-use target rejected'
    Bad-Record 'daily_use' 'l5_post_use_identity_and_protection' {param($v) $v.mechanical_post_use.snapshot_sha256='b'*64} 'Stale post-use reference hash rejected'
    Bad-Record 'post_use' 'l5_post_use_identity_and_protection' {param($v) $v.package_version='0.1.0-local.13'} 'Other-version post-use evidence rejected'
    Bad-Record 'registered_hosts' 'installed_x64_x86_registered_hosts' {param($v) $v.results[0].passed='false'} 'String registered pass rejected'
    Bad-Record 'registered_hosts' 'installed_x64_x86_registered_hosts' {param($v) $v.results[5]=$v.results[0]} 'Duplicate registered architecture/mode rejected'
    Bad-Record 'registered_hosts' 'installed_x64_x86_registered_hosts' {param($v) $v.artifacts[0].sha256='b'*64} 'Raw registered hash mismatch rejected'
    Bad-Record 'registered_hosts' 'installed_x64_x86_registered_hosts' {param($v) $v.manifest_sha256='b'*64} 'Registered candidate mismatch rejected'
    Bad-Record 'registered_hosts' 'installed_x64_x86_registered_hosts' {param($v) $v.artifacts[6]=$v.artifacts[1]} 'Duplicate raw registered evidence rejected'
    Bad-Record 'registered_hosts' 'installed_x64_x86_registered_hosts' {param($v) $v.results[0].outcomes.PSObject.Properties.Remove('failed_async_edit_recovery_verified')} 'Missing required registered outcome rejected'
    Bad-Record 'registered_hosts' 'installed_x64_x86_registered_hosts' {param($v) $v.baseline_after.sha256.key1='b'*64} 'Protected registry mismatch rejected'
    Bad-Record 'reboot' 'local12_reboot_and_logon_autostart' {param($v) $v.startup_metadata.shell_core.events[0].runtime_pid=999} 'Reboot event wrong PID rejected'
    Bad-Record 'reboot' 'local12_reboot_and_logon_autostart' {param($v) $v.startup_metadata.autostart_run.registry_reader='process HKCU'} 'Process-local registry evidence rejected'
    Bad-Record 'x86_live_hosts' 'x86_live_host_evidence_chain' {param($v) $v.hosts[0].input_observations.bare_digits_remain_composition='false'} 'x86 physical report string truth rejected'
    Bad-Record 'x86_live_hosts' 'x86_live_host_evidence_chain' {param($v) $v.hosts[0].loaded_text_service_sha256='b'*64} 'Wrong historical x86 module rejected'
    Bad-Record 'x86_live_hosts' 'x86_live_host_evidence_chain' {param($v) $v.computer_name='OTHERPC'} 'Wrong historical x86 target rejected'
    Bad-Record 'manual' 'x86_live_host_evidence_chain' {param($v) $v.host_modules.hosts[0].yime_modules[0].sha256='b'*64} 'Current affected x86 DLL mismatch rejected'
    Bad-Record 'backup' 'previous_working_package_backup_preserved' {param($v) $v.archive_root=Join-Path $repo 'outside-archive'} 'Backup reference outside approved archive root rejected'
    $rawPath=Join-Path $repo 'outcome-0.json'; $rawBytes=[IO.File]::ReadAllText($rawPath); [IO.File]::AppendAllText($rawPath,' ')
    Assert-Test (-not (Run-Readiness).checks.installed_x64_x86_registered_hosts) 'Tampered raw outcome fails despite true summary'; [IO.File]::WriteAllText($rawPath,$rawBytes)
    $x86Text=[IO.File]::ReadAllText($x86); [IO.File]::WriteAllText($x86,'# PASS')
    Refresh-Record 'x86_live_hosts'; Assert-Test (-not (Run-Readiness).checks.x86_live_host_evidence_chain) 'Markdown existence cannot substitute for raw x86 JSON'; [IO.File]::WriteAllText($x86,$x86Text); Refresh-Record 'x86_live_hosts'
    foreach($name in @('source-snapshot.zip','working-tree.patch','summary.json')) { $p=Join-Path $sealRoot $name; $bytes=[IO.File]::ReadAllBytes($p); [IO.File]::AppendAllText($p,'tampered'); Assert-Test (-not (Run-Readiness).checks.sealed_source_and_build_archive_integrity) "Tampered sealed $name rejected"; [IO.File]::WriteAllBytes($p,$bytes) }
    $oldBroker=Join-Path $previous 'bin/YimeBroker.exe'; $bytes=[IO.File]::ReadAllBytes($oldBroker); [IO.File]::AppendAllText($oldBroker,'tampered'); Assert-Test (-not (Run-Readiness).checks.previous_working_package_backup_preserved) 'Previous package bytes revalidated'; [IO.File]::WriteAllBytes($oldBroker,$bytes)
    $broker=Join-Path $package 'bin/YimeBroker.exe'; $bytes=[IO.File]::ReadAllBytes($broker); [IO.File]::AppendAllText($broker,'tampered'); Assert-Test (-not (Run-Readiness).checks.sealed_package_integrity) 'Candidate package bytes revalidated'; [IO.File]::WriteAllBytes($broker,$bytes)
    $unlisted=Join-Path $package 'unlisted.exe'; [IO.File]::WriteAllText($unlisted,'extra'); Assert-Test (-not (Run-Readiness).checks.sealed_package_integrity) 'Unlisted sealed member rejected'; [IO.File]::Delete($unlisted)
    $module=Get-Module local-product-readiness
    Expect-Throw { & $module {param($p,$r) Get-L6Member $r '../escape'} $root $package } 'Manifest parent traversal rejected'
    Expect-Throw { & $module {param($r) Get-L6Member $r 'bin/YimeBroker.exe:secret'} $package } 'Manifest ADS rejected'
    $junction=Join-Path $package 'linked'; New-Item -ItemType Junction -Path $junction -Target $repo | Out-Null
    try { Assert-Test (-not (Run-Readiness).checks.sealed_package_integrity) 'Reparse directory rejected before traversal' } finally { [IO.Directory]::Delete($junction) }
    $output=Join-Path $repo 'docs/testing/l6/result.json'; Write-YimeCoreReadinessResult $good $output $repo
    $outputHash=Hash $output
    Expect-Throw { Write-YimeCoreReadinessResult $good $output $repo } 'Existing evidence cannot be overwritten'
    Assert-Test ((Hash $output) -eq $outputHash) 'Rejected overwrite preserves existing bytes'
    Expect-Throw { Write-YimeCoreReadinessResult $good (Join-Path $repo 'tools/change.ps1') $repo } 'Arbitrary output extension and directory rejected'
    Expect-Throw { Write-YimeCoreReadinessResult $good (Join-Path $recoveryRoot 'outside.json') $repo } 'Output outside repository rejected'
    $hardlink=Join-Path $repo 'docs/testing/l6/hardlink.json'; New-Item -ItemType HardLink -Path $hardlink -Target $output|Out-Null
    Expect-Throw { Write-YimeCoreReadinessResult $good $hardlink $repo } 'Existing hardlink output rejected'
    Assert-Test ((Hash $output) -eq $outputHash) 'Hardlink target unchanged'
    $again=Run-Readiness; Assert-Test ($again.pending.Count -eq 1) 'All fixture mutations restored'
    Write-Host "PASS: $checksRun L6 evidence and output-boundary regressions; native acceptance remains false."
} finally {
    # Delete only the verified random fixture root under the system temp directory.
    $resolved=[IO.Path]::GetFullPath($root); $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+'\'
    if (-not $resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^yimecore-readiness-[0-9a-f]{32}$') { throw 'Unsafe fixture cleanup root.' }
    if(Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
