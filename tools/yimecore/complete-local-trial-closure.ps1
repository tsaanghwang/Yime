[CmdletBinding()]
param([string]$PlanPath,[string]$TargetUserSid,[switch]$Elevated)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
$scope=Get-YimeCoreDevelopmentScope
# MUST precede elevation, directory creation, stopping writers or live mutations.
Assert-YimeCoreUnpackagedDataMaintenance
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if(-not $PlanPath){$PlanPath=Join-Path $repo '.tmp\yimecore-experiment\native-closure-ready\plan.json'}
$plan=Get-Content -Encoding UTF8 -LiteralPath $PlanPath -Raw|ConvertFrom-Json
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(-not $TargetUserSid){$TargetUserSid=$identity.User.Value}
if($identity.User.Value -ne $TargetUserSid -or $plan.sid -ne $TargetUserSid -or
   $plan.schema_version -ne 'yimecore-native-closure-plan-v1' -or -not (Test-YimeCoreScopeEvidence $plan.development_scope $scope)){throw 'Prepared plan, initiating SID or development scope mismatch.'}
foreach($input in $plan.inputs){
    Assert-YimeCorePlainPath $input.path
    if((Get-FileHash -LiteralPath $input.path).Hash -ne $input.sha256){throw "Prepared script changed; prepare again before maintenance: $($input.path)"}
}
if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if($Elevated){throw 'Elevation did not provide an administrator token of the same user.'}
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args='-NoProfile -ExecutionPolicy Bypass -File "{0}" -PlanPath "{1}" -TargetUserSid "{2}" -Elevated' -f $PSCommandPath,([IO.Path]::GetFullPath($PlanPath)),$TargetUserSid
    $child=Start-Process -FilePath $ps -ArgumentList $args -Verb RunAs -WindowStyle Hidden -PassThru
    # Wait for this script only, not the resident runtime descendants.
    $child.WaitForExit()
    if($child.ExitCode -ne 0){throw 'Native closure did not pass. Preserve the new archive and evidence; do not rerun Upgrade.'}
    Write-Host 'Native backup, restore and rollback completed. Return to Codex for independent evidence review.'
    exit 0
}
if(Get-Process WINWORD -ErrorAction SilentlyContinue){throw 'Save and close Word before starting this rehearsal.'}
$stateRoot=[IO.Path]::GetFullPath([string]$plan.state_root)
if($stateRoot -ine [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'))){throw 'StateRoot does not belong to the initiating user.'}
$config=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $stateRoot 'runtime-config.json') -Raw|ConvertFrom-Json
if($config.install_root -ine $plan.source_install_root -or
    (Get-FileHash -LiteralPath (Join-Path $config.install_root 'package-manifest.json')).Hash -ne $plan.source_manifest_sha256){throw 'Installed package changed after preparation.'}
if((Get-FileHash -LiteralPath $plan.recovery_probe).Hash -ne $plan.recovery_probe_sha256 -or
    (Get-FileHash -LiteralPath (Join-Path $plan.failure_package 'package-manifest.json')).Hash -ne $plan.failure_manifest_sha256){throw 'Prepared recovery/fault input changed.'}
if(-not (Get-YimeCoreLiveRuntimeEvidence $stateRoot).passed){throw 'Live runtime/Broker identity preflight failed; no maintenance started.'}
$runId='native-closure-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$out=Join-Path $repo ('.tmp\yimecore-experiment\'+$runId)
$archive=Join-Path $env:USERPROFILE ('YimeCore Recovery Archives\'+$runId)
Assert-YimeCorePlainPath $out
Assert-YimeCorePlainPath $archive
New-Item -ItemType Directory -Path $out,$archive|Out-Null
Start-Transcript -LiteralPath (Join-Path $out 'transcript.txt')|Out-Null
$stage='preflight'
try {
    & (Join-Path $PSScriptRoot 'test-local-maintenance-encoding.ps1') -OutputRoot (Join-Path $out 'encoding-preflight')
    & (Join-Path $PSScriptRoot 'repair-e6c-trial-autostart.ps1') -ValidateOnly -OutputPath (Join-Path $out 'autostart-before.json')|Out-Null
    & (Join-Path $PSScriptRoot 'repair-e6c-system-uninstall.ps1') -OutputPath (Join-Path $out 'uninstall-before.json')|Out-Null
    & (Join-Path $PSScriptRoot 'capture-local-maintenance-state.ps1') -OutputPath (Join-Path $out 'before.json')
    $stage='fresh-backup'
    $restoreBackup=Join-Path $archive 'restore-backup'
    & (Join-Path $PSScriptRoot 'backup-local-trial-state.ps1') -BackupRoot $restoreBackup
    $stage='actual-restore'
    & (Join-Path $PSScriptRoot 'restore-local-trial-state.ps1') -BackupRoot $restoreBackup -RecoveryProbe $plan.recovery_probe
    $stage='fresh-rollback-backup'
    $rollbackBackup=Join-Path $archive 'rollback-backup'
    & (Join-Path $PSScriptRoot 'backup-local-trial-state.ps1') -BackupRoot $rollbackBackup
    $stage='actual-failed-upgrade-rollback'
    & (Join-Path $PSScriptRoot 'invoke-local-rollback-rehearsal.ps1') -FailurePackage $plan.failure_package -BackupRoot $rollbackBackup -OutputRoot (Join-Path $out 'rollback') -TargetUserSid $TargetUserSid
    $stage='final-verification'
    & (Join-Path $PSScriptRoot 'verify-e6c-trial-runtime.ps1')|Out-Null
    & (Join-Path $PSScriptRoot 'repair-e6c-trial-autostart.ps1') -ValidateOnly -OutputPath (Join-Path $out 'autostart-after.json')|Out-Null
    & (Join-Path $PSScriptRoot 'repair-e6c-system-uninstall.ps1') -OutputPath (Join-Path $out 'uninstall-after.json')|Out-Null
    & (Join-Path $PSScriptRoot 'capture-local-maintenance-state.ps1') -OutputPath (Join-Path $out 'after.json')
    $before=Get-Content -Encoding UTF8 (Join-Path $out 'before.json') -Raw|ConvertFrom-Json
    $after=Get-Content -Encoding UTF8 (Join-Path $out 'after.json') -Raw|ConvertFrom-Json
    Assert-YimeCoreUnchangedData $before.data_files $after.data_files
    if(-not $after.live_runtime.passed -or
        ($before.registration|ConvertTo-Json -Depth 35 -Compress) -cne ($after.registration|ConvertTo-Json -Depth 35 -Compress) -or
        ($before.user|ConvertTo-Json -Depth 35 -Compress) -cne ($after.user|ConvertTo-Json -Depth 35 -Compress) -or
        ($before.system_registry_trees|ConvertTo-Json -Depth 35 -Compress) -cne ($after.system_registry_trees|ConvertTo-Json -Depth 35 -Compress)) {throw 'Final live identity or registry preservation check failed.'}
    $restore=Get-Content -Encoding UTF8 (Join-Path $restoreBackup 'restore-evidence.json') -Raw|ConvertFrom-Json
    $rollback=Get-Content -Encoding UTF8 (Join-Path $out 'rollback\summary.json') -Raw|ConvertFrom-Json
    if(-not $restore.passed -or -not $rollback.system_registry_rollback_verified){throw 'Restore/rollback acceptance evidence missing.'}
    $nativeFiles=@()
    foreach($backup in @($restoreBackup,$rollbackBackup)) {
        $nativeFiles+=@(Assert-YimeCoreNativeFile (Join-Path $backup 'backup-manifest.json'))
        $manifest=Get-Content -Encoding UTF8 (Join-Path $backup 'backup-manifest.json') -Raw|ConvertFrom-Json
        foreach($record in $manifest.state_files){
            $file=Assert-YimeCoreNativeFile (Join-Path (Join-Path $backup 'state') $record.path)
            if($file.sha256 -ne $record.sha256){throw 'Recovery state archive changed after rehearsal.'}
            $nativeFiles+=@($file)
        }
        foreach($record in $manifest.package_files){
            $file=Assert-YimeCoreNativeFile (Join-Path (Join-Path $backup 'previous-package') $record.path)
            if($file.sha256 -ne $record.sha256){throw 'Recovery package changed after rehearsal.'}
            $nativeFiles+=@($file)
        }
    }
    $result=[ordered]@{schema_version='yimecore-native-local-closure-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');
        passed=$true;sid=$TargetUserSid;development_scope=$scope;native_context_verified=$true;
        restore=$restore;rollback=$rollback;all_user_data_unchanged=$true;all_registration_preserved=$true;
        system_visible_archive_files=$nativeFiles;archive_root=$archive;evidence_root=$out;live_runtime=$after.live_runtime;
        reboot_performed=$false;default_input_method_changed=$false;production_rime_pime_changed=$false;
        trusted_signing='Signing certificate application pending approval; related work deferred.'}
    $result|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding utf8
    Copy-Item -LiteralPath (Join-Path $out 'summary.json') -Destination (Join-Path $archive 'closure-summary.json')
    Write-Host "PASS: native backup, actual restore and failed-upgrade rollback. Evidence: $out"
} catch {
    [ordered]@{passed=$false;stage=$stage;error=$_.Exception.Message;archive_root=$archive;evidence_root=$out;
        generated_at=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $out 'failure.json') -Encoding utf8
    Write-Error "Closure stopped at $stage. Preserve $archive and $out. $($_.Exception.Message)"
    exit 1
} finally {Stop-Transcript|Out-Null}
