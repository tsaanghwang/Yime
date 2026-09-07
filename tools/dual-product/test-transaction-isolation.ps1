[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'transaction-isolation.ps1')

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$parent = Join-Path $repo '.tmp\dual-product'
if ((Split-Path -Parent $output) -ine $parent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-transaction-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a new immediate .tmp/dual-product/dp1-transaction-* fixture root.'
}
for ($cursor = $parent; $cursor; $cursor = Split-Path -Parent $cursor) {
    if ((Test-Path -LiteralPath $cursor) -and
        ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Transaction evidence path traverses a reparse point.'
    }
    if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
}
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
New-Item -ItemType Directory -Path $output | Out-Null

$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Body) {
    try { & $Body; $checks.Add([ordered]@{name=$Name;passed=$true}) }
    catch { $checks.Add([ordered]@{name=$Name;passed=$false;reason=$_.Exception.Message}) }
}
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Must-Reject([scriptblock]$Body) {
    $rejected = $false
    try { & $Body | Out-Null } catch { $rejected = $true }
    Assert-True $rejected 'Expected fail-closed rejection.'
}
function Copy-Fixture($Fixture) {
    return ($Fixture | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
}
function New-Event([string]$Id, [string]$Kind, [string]$Owner, $Fields) {
    $record = [ordered]@{id=$Id;kind=$Kind;owner=$Owner}
    if ($Fields) { foreach ($key in $Fields.Keys) { $record[$key]=$Fields[$key] } }
    return [pscustomobject]$record
}
function Set-EventSequence([object[]]$Events) {
    for ($index=0; $index -lt $Events.Count; $index++) {
        $Events[$index] | Add-Member -NotePropertyName sequence -NotePropertyValue ($index+1) -Force
    }
    return $Events
}
function New-UpgradeFixture([string]$Target, [ValidateSet('success','rolled-back')][string]$Outcome) {
    $policy=Get-DualProductTransactionFixturePolicy
    $item=$policy.products[$Target];$peer=[string]$item.peer
    $sid='S-1-5-21-100-200-300-1001'
    $architectures=@('x64','x86')
    $events=[Collections.Generic.List[object]]::new()
    $events.Add((New-Event 'stage' 'stage-package' $Target @{path=([string]$item.staging_root+'\package')}))
    $events.Add((New-Event 'target-before' 'snapshot-target' $Target $null))
    $events.Add((New-Event 'peer-before' 'snapshot-peer' $peer $null))
    $events.Add((New-Event 'stop' 'stop-owned-process' $Target @{path=(Join-Path ([string]$item.install_root) ([string]$item.process_paths[0]));sid=$sid}))
    $events.Add((New-Event 'quiescent' 'quiescence-verified' $Target $null))
    $events.Add((New-Event 'unregister-com' 'unregister-com' $Target @{clsid=$item.clsid;architectures=$architectures}))
    $events.Add((New-Event 'unregister-tip' 'unregister-tip' $Target @{clsid=$item.clsid;profile=$item.profile;sid=$sid}))
    if ($Outcome -eq 'success') {
        $events.Add((New-Event 'register-com' 'register-com' $Target @{clsid=$item.clsid;architectures=$architectures}))
        $events.Add((New-Event 'register-tip' 'register-tip' $Target @{clsid=$item.clsid;profile=$item.profile;sid=$sid}))
        $events.Add((New-Event 'run' 'write-run' $Target @{name=$item.run_name;sid=$sid}))
        $events.Add((New-Event 'uninstall' 'write-uninstall' $Target @{name=$item.uninstall_name;sid=$sid}))
        $events.Add((New-Event 'state' 'write-state' $Target @{path=([string]$item.state_root+'\settings.json');sid=$sid}))
        $events.Add((New-Event 'registered' 'verify-registration' $Target @{install_root=$item.install_root;architectures=$architectures}))
        $events.Add((New-Event 'start' 'start-runtime' $Target @{path=(Join-Path ([string]$item.install_root) ([string]$item.process_paths[0]));sid=$sid}))
        $events.Add((New-Event 'running' 'verify-runtime' $Target $null))
        $events.Add((New-Event 'commit' 'commit' $Target $null))
        $events.Add((New-Event 'old-root' 'delete-old-root' $Target @{path=$item.old_install_root}))
    } else {
        $events.Add((New-Event 'failure' 'failure-marker' $Target $null))
        $events.Add((New-Event 'rollback-begin' 'rollback-begin' $Target $null))
        $events.Add((New-Event 'restore-registration' 'restore-registration' $Target @{clsid=$item.clsid;architectures=$architectures}))
        $events.Add((New-Event 'restore-run' 'restore-run' $Target @{name=$item.run_name;sid=$sid}))
        $events.Add((New-Event 'restore-uninstall' 'restore-uninstall' $Target @{name=$item.uninstall_name;sid=$sid}))
        $events.Add((New-Event 'restore-tip' 'restore-user-tip' $Target @{clsid=$item.clsid;profile=$item.profile;sid=$sid}))
        $events.Add((New-Event 'restore-config' 'restore-config' $Target @{path=([string]$item.state_root+'\runtime-config.json');sid=$sid}))
        $events.Add((New-Event 'restore-runtime' 'restore-runtime-state' $Target @{path=([string]$item.state_root+'\runtime-status.json');sid=$sid}))
        $events.Add((New-Event 'verify-rollback' 'verify-rollback' $Target $null))
        $events.Add((New-Event 'rollback-complete' 'rollback-complete' $Target $null))
    }
    $targetAfter=if($Outcome -eq 'success'){'c'*64}else{'b'*64}
    return [pscustomobject][ordered]@{
        schema_version='yime-dual-product-transaction-fixture-v1'
        target_product=$Target
        peer_product=$peer
        action='upgrade'
        outcome=$Outcome
        architectures=$architectures
        sid_chain=[pscustomobject][ordered]@{
            initiating_sid=$sid;elevated_sid=$sid;target_user_sid=$sid;maintenance_worker_sid=$sid
            standard_user_runtime_sid=$sid;initiating_token_elevated=$false;worker_token_elevated=$true
            standard_user_runtime_elevated=$false
        }
        events=@(Set-EventSequence $events.ToArray())
        state_fingerprints=[pscustomobject][ordered]@{
            target_before='b'*64;target_after=$targetAfter
            target_registry_kinds_before='d'*64;target_registry_kinds_after='d'*64
            peer_before='a'*64;peer_after='a'*64
            default_input_before='e'*64;default_input_after='e'*64
        }
    }
}
function New-InstallFixture([string]$Target) {
    $fixture=Copy-Fixture (New-UpgradeFixture $Target 'success')
    $fixture.action='install'
    $fixture.events=@(Set-EventSequence @($fixture.events|Where-Object{
        $_.kind -notin @('stop-owned-process','unregister-com','unregister-tip','delete-old-root')
    }))
    return $fixture
}
function New-UninstallFixture([string]$Target) {
    $policy=Get-DualProductTransactionFixturePolicy
    $item=$policy.products[$Target];$peer=[string]$item.peer
    $sid='S-1-5-21-100-200-300-1001'
    $architectures=@('x64','x86')
    $events=@(
        (New-Event 'target-before' 'snapshot-target' $Target $null),
        (New-Event 'peer-before' 'snapshot-peer' $peer $null),
        (New-Event 'stop' 'stop-owned-process' $Target @{path=(Join-Path ([string]$item.install_root) ([string]$item.process_paths[0]));sid=$sid}),
        (New-Event 'quiescent' 'quiescence-verified' $Target $null),
        (New-Event 'unregister-com' 'unregister-com' $Target @{clsid=$item.clsid;architectures=$architectures}),
        (New-Event 'unregister-tip' 'unregister-tip' $Target @{clsid=$item.clsid;profile=$item.profile;sid=$sid}),
        (New-Event 'remove' 'remove-owned-resource' $Target @{path=([string]$item.install_root+'\payload.bin')}),
        (New-Event 'absent' 'verify-target-absent' $Target $null),
        (New-Event 'commit' 'commit' $Target $null)
    )
    return [pscustomobject][ordered]@{
        schema_version='yime-dual-product-transaction-fixture-v1';target_product=$Target;peer_product=$peer
        action='uninstall';outcome='success'
        architectures=$architectures
        sid_chain=[pscustomobject][ordered]@{
            initiating_sid=$sid;elevated_sid=$sid;target_user_sid=$sid;maintenance_worker_sid=$sid
            standard_user_runtime_sid=$sid;initiating_token_elevated=$false;worker_token_elevated=$true
            standard_user_runtime_elevated=$false
        }
        events=@(Set-EventSequence $events)
        state_fingerprints=[pscustomobject][ordered]@{
            target_before='b'*64;target_after='c'*64
            target_registry_kinds_before='d'*64;target_registry_kinds_after='f'*64
            peer_before='a'*64;peer_after='a'*64
            default_input_before='e'*64;default_input_after='e'*64
        }
    }
}

$sourceFiles=@(
    'installer/installer.nsi',
    'libIME2/src/ImeModule.cpp',
    'PIMETextService/CMakeLists.txt',
    'PIMETextService/RegistrationStatus.cpp',
    'PIMELauncher/src/main.rs',
    'PIMELauncher/src/backend_manager.rs',
    'PIMELauncher/src/lib.rs',
    'PIMELauncher/src/maintenance.rs',
    'PIMELauncher/src/bin/mock_backend.rs',
    'PIMELauncher/tests/integration_test.rs',
    'tools/dual-product/rime-pime-target-user.ps1',
    'tools/dual-product/invoke-rime-pime-target-user.ps1',
    'tools/dual-product/test-rime-pime-target-user.ps1',
    'tools/dual-product/rime-pime-ownership.ps1',
    'tools/dual-product/invoke-rime-pime-maintenance.ps1',
    'tools/dual-product/test-rime-maintenance.ps1',
    'tools/dual-product/test-rime-pime-native-user-cleanup.ps1',
    'tools/dual-product/test-rime-pime-registration-ownership.ps1',
    'tools/dual-product/test-rime-pime-registration-completeness.ps1',
    'tools/dual-product/rime-pime-transaction-engine.ps1',
    'tools/dual-product/test-rime-pime-transaction-faults.ps1',
    'tools/pime-registry-cleanup.ps1',
    'tools/dev-install.ps1',
    'tools/dev-uninstall.ps1',
    'tools/dual-product/rime-pime-directed-stop-contract.ps1',
    'tools/dual-product/test-rime-pime-directed-stop.ps1',
    'tools/yimecore/manage-e6c-trial-install.ps1',
    'tools/yimecore/invoke-local-product-native-install.ps1',
    'tools/yimecore/invoke-local-rollback-rehearsal.ps1',
    'tools/yimecore/test-e6c-user-tip-rollback.ps1',
    'tools/yimecore/test-local-product-maintenance.ps1',
    'tools/dual-product/transaction-isolation.ps1',
    'tools/dual-product/test-transaction-isolation.ps1'
)
$source=@{};$sourceHashes=[ordered]@{}
foreach($relative in $sourceFiles){
    $path=Join-Path $repo $relative
    $source[$relative]=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $sourceHashes[$relative]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$core=$source['tools/yimecore/manage-e6c-trial-install.ps1']
$coreAcceptance=$source['tools/yimecore/invoke-local-product-native-install.ps1']
$coreRollback=$source['tools/yimecore/invoke-local-rollback-rehearsal.ps1']
$nsis=$source['installer/installer.nsi']
$nativeImeModule=$source['libIME2/src/ImeModule.cpp']
$registrationProbe=$source['PIMETextService/RegistrationStatus.cpp']
$pimeCleanup=$source['tools/pime-registry-cleanup.ps1']
$pimeOwnership=$source['tools/dual-product/rime-pime-ownership.ps1']
$pimeMaintenanceEntry=$source['tools/dual-product/invoke-rime-pime-maintenance.ps1']
$sourceAudit=[ordered]@{
    level='read-only-source-anchors-not-live-transaction-evidence'
    yimecore_same_sid_elevation_anchors_present=[bool](
        $core.Contains("'-TargetUserSid', (Quote-Argument `$TargetUserSid)") -and
        $core.Contains('must be elevated with the same Windows account that started the operation') -and
        $core.Contains("'-StateRoot', (Quote-Argument `$stateRootPath)"))
    yimecore_stage_before_preinstall_anchor_present=[bool](
        $core.IndexOf('New-Item -ItemType Directory -Path $stagingRoot') -ge 0 -and
        $core.IndexOf('New-Item -ItemType Directory -Path $stagingRoot') -lt $core.IndexOf('$preinstall = Invoke-UninstallCore'))
    yimecore_rollback_restore_anchors_present=[bool](
        $core.Contains('Restore-PreviousInstallation $previousRoot $previousConfigText') -and
        $core.Contains('Restore-RegistryValueSnapshot $runKey $productKeyName $runSnapshot') -and
        $core.Contains('Restore-RegistryKeySnapshot $uninstallKey $uninstallSnapshot') -and
        $core.Contains('Restore-RegistryKeySnapshot $userTipKey $userTipSnapshot'))
    yimecore_other_product_protection_acceptance_present=[bool](
        $coreAcceptance.Contains("`$production='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'") -and
        $coreAcceptance.Contains('$Before.protected|ConvertTo-Json') -and
        $coreAcceptance.Contains('$After.protected|ConvertTo-Json'))
    yimecore_native_failed_rollback_comparison_present=[bool](
        $coreRollback.Contains('system_visible_registry_restored') -and
        $coreRollback.Contains('user_registration_and_value_kinds_restored'))
    rime_pime_initiating_sid_chain_wired=[bool](
        $nsis.Contains('RequestExecutionLevel user') -and
        $nsis.Contains('Function bootstrapTargetUser') -and
        $nsis.Contains('Function un.bootstrapTargetUser') -and
        $nsis.Contains('CaptureInitiator') -and $nsis.Contains('ValidateWorker') -and
        $nsis.Contains('/InitiatingSid=') -and $nsis.Contains('/TargetUserSid=') -and
        $nsis.Contains('/EnvelopePath=') -and $nsis.Contains('/CorrelationId=') -and
        $nsis.Contains('Call acceptTargetUserWorker') -and
        $nsis.Contains('Call un.acceptTargetUserWorker') -and
        $nsis.Contains('InstallLayoutOrTipForUser') -and
        $nsis.Contains('-TargetUserSid "$TargetUserSid"'))
    rime_pime_user_registry_cleanup_target_sid_only=[bool](
        $pimeCleanup.Contains('Assert-PIMERegistryTargetUserSid') -and
        $pimeCleanup.Contains('Get-YimePimeTargetUserRegistryPath -TargetUserSid $TargetUserSid') -and
        $pimeCleanup.Contains('Remove-PIMEUserLanguageProfileValues -TargetUserSid $TargetUserSid') -and
        -not $pimeCleanup.Contains('Get-ChildItem -LiteralPath "Registry::HKEY_USERS"') -and
        -not $pimeCleanup.Contains('HKCU:') -and
        -not ([regex]::Match($nativeImeModule,'(?ms)^HRESULT\s+ImeModule::unregisterServer\([^)]*\)\s*\{.*?(?=^[A-Za-z_][^\r\n]*\s+ImeModule::|\z)').Value -match 'HKEY_USERS|loadDefaultUserRegistry|RegUnLoadKeyW') -and
        -not ([regex]::Match($nativeImeModule,'(?ms)^HRESULT\s+ImeModule::registerLangProfiles\([^\r\n]*\)\s*\{.*?(?=^HRESULT\s+ImeModule::|\z)').Value -match 'HKEY_USERS|loadDefaultUserRegistry|RegLoadKeyW|RegUnLoadKeyW'))
    rime_pime_native_uac_and_registered_profile_acceptance_passed=$false
    rime_pime_full_transaction_engine_wired_into_installer=[bool](
        $nsis.Contains('package.staging') -and $nsis.Contains('RestoreTransactionSnapshot') -and
        $nsis.Contains('VerifyRollback'))
    rime_pime_registration_exit_and_state_source_anchors_present=[bool](
        $nsis.Contains('Call verifyRegistrationOwnership') -and $nsis.Contains('regsvr32') -and
        $nsis.Contains('registrationExitCode') -and
        $nsis.Contains('$WINDIR\Sysnative\regsvr32.exe') -and
        $nsis.Contains('$WINDIR\SysWOW64\regsvr32.exe') -and
        $nsis.Contains('PIMERegistrationStatus_x86.exe') -and
        $nsis.Contains('PIMERegistrationStatus_x64.exe') -and
        $nsis.Contains('PIMERegistrationStatus_arm64.exe') -and
        $nsis.Contains('!macro RunCheckedRegistrationCommand') -and
        $nsis.Contains('verify-present') -and $nsis.Contains('verify-absent') -and
        $registrationProbe.Contains('ITfInputProcessorProfileMgr') -and
        $registrationProbe.Contains('EnumProfiles') -and
        $registrationProbe.Contains('EnumCategoriesInItem') -and
        $pimeOwnership.Contains('function Get-YimePimeRegistrationSnapshot') -and
        $pimeOwnership.Contains('function Assert-YimePimeRegistrationSnapshot') -and
        $pimeOwnership.Contains("'target-user-profile-enable'") -and
        $pimeOwnership.Contains('function Assert-YimePimeNativeRegistrationAbsent') -and
        $pimeMaintenanceEntry.Contains("'ValidateRegistration'"))
    rime_pime_legacy_registration_selected_root_only=$false
    rime_pime_unowned_legacy_registration_deletion_absent=[bool](
        $nsis -notmatch 'DeleteRegKey\s+HKLM\s+"\$\{LEGACY_PRODUCT_(?:UNINST|INSTALL)_KEY\}"')
}
Check 'source-audit-distinguishes-yimecore-anchors-from-live-proof' {
    Assert-True $sourceAudit.yimecore_same_sid_elevation_anchors_present 'YimeCore same-SID source chain drifted.'
    Assert-True $sourceAudit.yimecore_stage_before_preinstall_anchor_present 'YimeCore stage/preinstall order drifted.'
    Assert-True $sourceAudit.yimecore_rollback_restore_anchors_present 'YimeCore rollback wiring drifted.'
    Assert-True $sourceAudit.yimecore_other_product_protection_acceptance_present 'YimeCore peer-product snapshot guard drifted.'
    Assert-True $sourceAudit.yimecore_native_failed_rollback_comparison_present 'YimeCore native rollback comparison drifted.'
    Assert-True ($sourceAudit.level -like 'read-only-*') 'Source anchors were promoted to live evidence.'
}
Check 'rime-target-sid-source-wiring-is-present-with-native-gate-explicit' {
    Assert-True $sourceAudit.rime_pime_initiating_sid_chain_wired 'Rime/PIME initiating SID source chain is incomplete.'
    Assert-True $sourceAudit.rime_pime_user_registry_cleanup_target_sid_only 'Rime/PIME user cleanup is not restricted to TargetUserSid.'
    Assert-True (-not $sourceAudit.rime_pime_native_uac_and_registered_profile_acceptance_passed) 'Source checks were promoted to native UAC/profile evidence.'
    Assert-True ($nsis.Contains('InstallLayoutOrTip(w "${YIME_TIP}"') -and
        -not $pimeCleanup.Contains('Get-ChildItem -LiteralPath "Registry::HKEY_USERS"')) 'Concrete target-SID source evidence changed.'
}
Check 'registration-source-gate-is-wired-while-full-transaction-remains-explicit' {
    Assert-True (-not $sourceAudit.rime_pime_full_transaction_engine_wired_into_installer) 'Rime/PIME transaction status changed; perform a dedicated review.'
    Assert-True $sourceAudit.rime_pime_registration_exit_and_state_source_anchors_present 'Rime/PIME registration exit/readback source gate is incomplete.'
    Assert-True (-not $sourceAudit.rime_pime_legacy_registration_selected_root_only) 'Legacy-only migration was promoted without its own owner snapshot.'
    Assert-True $sourceAudit.rime_pime_unowned_legacy_registration_deletion_absent 'Unowned legacy registration can still be deleted.'
    $upgrade=[regex]::Match($nsis,'(?s)Function uninstallOldVersion\s+(.*?)FunctionEnd').Groups[1].Value
    Assert-True ($upgrade.Contains('In-place upgrade is not enabled') -and
        $upgrade.Contains('existing installation was not stopped, unregistered, overwritten or deleted') -and
        $upgrade -notmatch '(?:/u /s|Call stopRunningBackend|RMDir|DeleteReg|\bFile\b)') `
        'Current-family upgrade is not frozen before every product mutation.'
    $installInit=[regex]::Match($nsis,'(?s)Function \.onInit\s+(.*?)FunctionEnd').Groups[1].Value
    $main=[regex]::Match($nsis,'(?s)Section \$\(SECTION_MAIN\) SecMain\s+(.*?)SectionEnd').Groups[1].Value
    Assert-True ($installInit -notmatch 'Call (?:uninstallOldVersion|stopRunningBackend)' -and
        $main.IndexOf('Call uninstallOldVersion') -ge 0 -and
        $upgrade.Contains('Call verifyStagedRegistrationAbsent') -and
        [regex]::Matches($main,'Call verifyStagedRegistrationAbsent').Count -ge 1 -and
        $main.LastIndexOf('Call verifyStagedRegistrationAbsent') -lt $main.IndexOf('SetOverwrite on')) `
        'Post-license fresh-install admission or final vacancy readback is missing.'
    Assert-True ($nsis.Contains('A historical PIME installation needs an explicit migration workflow') -and
        $nsis -notmatch 'DeleteRegKey\s+HKLM\s+"\$\{LEGACY_PRODUCT_(?:UNINST|INSTALL)_KEY\}"') `
        'Legacy-only or partial marker families are not fail-closed.'
}
Check 'existing-yimecore-tests-are-reusable-but-not-peer-product-matrix-proof' {
    Assert-True ($source['tools/yimecore/test-e6c-user-tip-rollback.ps1'].Contains('Registry types or values changed.')) 'TIP value-kind rollback regression is unavailable.'
    Assert-True ($source['tools/yimecore/test-local-product-maintenance.ps1'].Contains('reject launch token')) 'Token negative matrix is unavailable.'
    Assert-True ($sourceAudit.level -eq 'read-only-source-anchors-not-live-transaction-evidence') 'Reuse level was overstated.'
}
foreach($relative in $sourceFiles | Where-Object {$_ -like '*.ps1'}) {
    Check ('powershell-parse-'+$relative) {
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseInput($source[$relative],[ref]$tokens,[ref]$errors)
        Assert-True ($errors.Count -eq 0) 'PowerShell parse failed.'
    }
}

foreach($target in @('rime-pime','yimecore')) {
    foreach($outcome in @('success','rolled-back')) {
        Check ("pure-upgrade-$target-$outcome") {
            $result=Assert-DualProductTransactionFixture (New-UpgradeFixture $target $outcome)
            Assert-True ($result.passed -and -not $result.actual_registry_or_install_mutation_executed -and
                -not $result.dp1_full_implementation_passed) 'Synthetic result was promoted beyond its evidence.'
        }
    }
    Check ("pure-install-$target-success") {
        $result=Assert-DualProductTransactionFixture (New-InstallFixture $target)
        Assert-True ($result.passed -and $result.action -eq 'install') 'Synthetic install contract failed.'
    }
    Check ("pure-uninstall-$target-success") {
        $result=Assert-DualProductTransactionFixture (New-UninstallFixture $target)
        Assert-True ($result.passed -and $result.action -eq 'uninstall') 'Synthetic uninstall contract failed.'
    }
}
Check 'same-sid-chain-negative-matrix' {
    foreach($field in @('elevated_sid','target_user_sid','maintenance_worker_sid','standard_user_runtime_sid')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'yimecore' 'success')
        $fixture.sid_chain.$field='S-1-5-21-100-200-300-2002'
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
    $fixture=Copy-Fixture (New-UpgradeFixture 'rime-pime' 'success');$fixture.sid_chain.initiating_token_elevated=$true
    Must-Reject {Assert-DualProductTransactionFixture $fixture}
    $fixture=Copy-Fixture (New-UpgradeFixture 'rime-pime' 'success');$fixture.sid_chain.standard_user_runtime_elevated=$true
    Must-Reject {Assert-DualProductTransactionFixture $fixture}
    foreach($field in @('standard_user_runtime_sid','standard_user_runtime_elevated')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'rime-pime' 'success')
        $fixture.sid_chain.PSObject.Properties.Remove($field)
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'per-user-and-process-events-require-explicit-sid' {
    foreach($kind in @('stop-owned-process','register-tip','write-run','write-uninstall',
            'write-state','start-runtime')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'rime-pime' 'success')
        @($fixture.events|Where-Object kind -eq $kind)[0].PSObject.Properties.Remove('sid')
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'cross-product-mutation-and-dependency-rejected' {
    foreach($mode in @('owner','dependency')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'yimecore' 'success')
        $event=@($fixture.events|Where-Object kind -eq 'write-state')[0]
        if($mode -eq 'owner'){$event.owner='rime-pime'}else{
            $event|Add-Member -NotePropertyName dependency_product -NotePropertyValue 'rime-pime'
        }
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'peer-and-default-fingerprints-must-remain-exact' {
    foreach($field in @('peer_after','default_input_after')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'rime-pime' 'success');$fixture.state_fingerprints.$field='f'*64
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'rollback-restores-target-and-registry-kinds-exactly' {
    foreach($field in @('target_after','target_registry_kinds_after')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'yimecore' 'rolled-back');$fixture.state_fingerprints.$field='f'*64
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'snapshot-and-staging-must-precede-active-mutation' {
    foreach($kind in @('snapshot-target','stage-package')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'rime-pime' 'success')
        $selected=@($fixture.events|Where-Object kind -eq $kind)[0]
        $selected.sequence=99
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'canonical-stage-snapshot-stop-quiescence-order-is-enforced' {
    foreach($pair in @(@('stage-package','snapshot-target'),@('stop-owned-process','quiescence-verified'))) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'rime-pime' 'success')
        $events=@($fixture.events)
        $left=[array]::FindIndex($events,[Predicate[object]]{param($item) [string]$item.kind -ceq $pair[0]})
        $right=[array]::FindIndex($events,[Predicate[object]]{param($item) [string]$item.kind -ceq $pair[1]})
        $temporary=$events[$left];$events[$left]=$events[$right];$events[$right]=$temporary
        $fixture.events=@(Set-EventSequence $events)
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'registration-run-and-uninstall-identities-are-product-specific' {
    foreach($kind in @('register-com','register-tip','write-run','write-uninstall')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'yimecore' 'success')
        $event=@($fixture.events|Where-Object kind -eq $kind)[0]
        if($event.PSObject.Properties['clsid']){$event.clsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'}
        elseif($event.PSObject.Properties['name']){$event.name='PIMELauncher'}
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'registration-covers-exact-declared-architecture-set' {
    foreach($scenario in @('missing-x86','undeclared-arm64','duplicate-declaration')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'yimecore' 'success')
        $event=@($fixture.events|Where-Object kind -eq 'register-com')[0]
        switch($scenario){
            'missing-x86' {$event.architectures=@('x64')}
            'undeclared-arm64' {$event.architectures=@('x64','x86','arm64')}
            'duplicate-declaration' {$fixture.architectures=@('x64','x64')}
        }
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'registration-verification-root-and-order-are-exact' {
    foreach($mode in @('root','architectures','after-start')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'rime-pime' 'success')
        $verified=@($fixture.events|Where-Object kind -eq 'verify-registration')[0]
        if($mode -eq 'root'){$verified.install_root='C:\DP1-Fixture\YimeCore\current'}
        elseif($mode -eq 'architectures'){$verified.architectures=@('x64')}
        else {
            $start=@($fixture.events|Where-Object kind -eq 'start-runtime')[0]
            $temporary=$verified.sequence;$verified.sequence=$start.sequence;$start.sequence=$temporary
        }
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'old-root-delete-waits-for-new-registration-runtime-and-commit' {
    $fixture=Copy-Fixture (New-UpgradeFixture 'yimecore' 'success')
    $old=@($fixture.events|Where-Object kind -eq 'delete-old-root')[0]
    $commit=@($fixture.events|Where-Object kind -eq 'commit')[0]
    $temporary=$old.sequence;$old.sequence=$commit.sequence;$commit.sequence=$temporary
    Must-Reject {Assert-DualProductTransactionFixture $fixture}
}
Check 'failed-upgrade-cannot-commit-or-delete-predecessor' {
    foreach($kind in @('commit','delete-old-root')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'rime-pime' 'rolled-back')
        $item=(Get-DualProductTransactionFixturePolicy).products['rime-pime']
        $extra=if($kind -eq 'commit'){New-Event 'bad-commit' $kind 'rime-pime' $null}else{New-Event 'bad-delete' $kind 'rime-pime' @{path=$item.old_install_root}}
        $events=[Collections.Generic.List[object]]::new();foreach($event in @($fixture.events)[0..($fixture.events.Count-2)]){$events.Add($event)};$events.Add($extra);$events.Add($fixture.events[-1])
        $fixture.events=@(Set-EventSequence $events.ToArray())
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'missing-rollback-dimension-rejected' {
    foreach($kind in @('restore-registration','restore-run','restore-uninstall','restore-user-tip','restore-config','restore-runtime-state')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'yimecore' 'rolled-back')
        $fixture.events=@(Set-EventSequence @($fixture.events|Where-Object kind -ne $kind))
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}
Check 'path-escape-and-foreign-process-rejected' {
    $fixture=Copy-Fixture (New-UpgradeFixture 'yimecore' 'success')
    @($fixture.events|Where-Object kind -eq 'write-state')[0].path='C:\DP1-Fixture\RimePimeState\foreign.json'
    Must-Reject {Assert-DualProductTransactionFixture $fixture}
    $fixture=Copy-Fixture (New-UpgradeFixture 'yimecore' 'success')
    @($fixture.events|Where-Object kind -eq 'start-runtime')[0].path='C:\DP1-Fixture\YimeCore\current\bin\Other.exe'
    Must-Reject {Assert-DualProductTransactionFixture $fixture}
}
Check 'explicit-default-input-operation-rejected' {
    $fixture=Copy-Fixture (New-UpgradeFixture 'rime-pime' 'success')
    @($fixture.events|Where-Object kind -eq 'write-state')[0].kind='default-input-write'
    Must-Reject {Assert-DualProductTransactionFixture $fixture}
}
Check 'ambiguous-sequence-and-event-id-rejected' {
    foreach($field in @('sequence','id')) {
        $fixture=Copy-Fixture (New-UpgradeFixture 'yimecore' 'success')
        if($field -eq 'sequence'){$fixture.events[1].sequence=1}else{$fixture.events[1].id=$fixture.events[0].id}
        Must-Reject {Assert-DualProductTransactionFixture $fixture}
    }
}

Check 'source-snapshot-unchanged-during-run' {
    foreach($relative in $sourceFiles) {
        $actual=(Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-True ($actual -ceq [string]$sourceHashes[$relative]) "Source changed during run: $relative"
    }
}

$failed=@($checks|Where-Object{-not $_.passed})
$remaining=@(
    [ordered]@{id='DP1-PIME-REGISTRY-05';requires_authorization=$true;next_level='unpackaged native UAC and registered-profile acceptance';reason='Source and synthetic PS5/PS7 contracts pass. Verify same-account consent succeeds, alternate administrator credentials fail before mutation, and profile cleanup affects only the initiating SID.'},
    [ordered]@{id='DP1-PIME-TRANSACTION-06';requires_authorization=$false;next_level='wire the isolated transaction engine into the installer';reason='The pure 24-stage fault model exists, but the installer still must stage the complete package before active mutation and durably restore exact package, registration value kinds, startup and prior running state on failure.'},
    [ordered]@{id='DP2-SINGLE-AND-COEXISTENCE';requires_authorization=$true;next_level='unpackaged native installation matrix';reason='Only after source gates: separately run single-product, both install orders, upgrade, failed rollback, uninstall, restore and reboot evidence without changing the user default input method.'},
    [ordered]@{id='DP2-PHYSICAL-HOSTS';requires_authorization=$true;next_level='registered/live-host and physical architecture acceptance';reason='Installed x64/x86 hosts and an identified ARM64 target require their own evidence; synthetic contracts and cross-compilation cannot satisfy this gate.'}
)
$receipt=[ordered]@{
    schema_version='yime-dual-product-transaction-isolated-v1'
    passed=($failed.Count -eq 0)
    test_level='read-only-source-audit-and-pure-synthetic-transaction-contract'
    checks=@($checks)
    source_audit=$sourceAudit
    source_manifest=$sourceHashes
    source_unchanged=($failed.Count -eq 0)
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    powershell_edition=$PSVersionTable.PSEdition
    powershell_version=$PSVersionTable.PSVersion.ToString()
    known_pending=@('DP1-PIME-REGISTRY-05','DP1-PIME-TRANSACTION-06')
    reusable_existing_yimecore_tests=@(
        'tools/yimecore/test-e6c-user-tip-rollback.ps1',
        'tools/yimecore/test-local-product-maintenance.ps1',
        'tools/yimecore/invoke-local-product-native-install.ps1',
        'tools/yimecore/invoke-local-rollback-rehearsal.ps1'
    )
    remaining_real_gates=$remaining
    actual_elevation_executed=$false
    actual_native_registration_probe_executed=$false
    actual_installer_or_uninstaller_executed=$false
    actual_registry_or_install_mutation_executed=$false
    actual_restore_or_process_stop_executed=$false
    installed_runtime_examined=$false
    user_text_or_learning_read=$false
    default_input_method_changed=$false
    dp1_full_implementation_passed=$false
    dp2_physical_acceptance_passed=$false
}
$receiptPath=Join-Path $output 'result.json'
[IO.File]::WriteAllText($receiptPath,(($receipt|ConvertTo-Json -Depth 30)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
if($failed.Count){throw ('Transaction isolation checks failed: '+(($failed|ForEach-Object{$_.name+': '+$_.reason})-join '; '))}
Write-Output "PASS: $($checks.Count) read-only/source and pure transaction checks. Evidence: $output"
