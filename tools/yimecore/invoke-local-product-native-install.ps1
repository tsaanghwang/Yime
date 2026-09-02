[CmdletBinding(DefaultParameterSetName='Plan')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Install')]
    [switch]$Execute,
    [Parameter(Mandatory=$true,ParameterSetName='Probe')]
    [switch]$LaunchProbeOnly,
    [string]$PackageRoot='C:\dev\Yime\.tmp\yimecore-local-product\20260903-local3-standard-primary\package',
    [Parameter(ParameterSetName='Probe')][string]$StandardUserInitiator,
    [Parameter(ParameterSetName='Probe')][string]$EvidenceRoot,
    [Parameter(ParameterSetName='Probe')][string]$ExpectedSourcesHash
)
$ErrorActionPreference='Stop'
$expectedManifest='6964099f48e0b6f534b763728d4a1806e4d4edfb1e7d7053b42c6d78d9fee74a'
$expectedLauncher='36ccdd6cb08e05819ab994bd8fcfe032c4654d379bd612b69e0812c48650f12c'
$expectedPreviousManifest='8d48953ac0b5017b725272ee6300d0b988e99a0d25b9e035216f6c90b774fb64'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')
$manifestPath=Join-Path $package 'package-manifest.json'
if((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ine $expectedManifest){throw 'Candidate manifest changed; do not install an unreviewed or superseded package.'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
# Verify every library we load against the pinned candidate before dot-sourcing.
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')) {
    $records=@($manifest.files|Where-Object{$_.path -eq "maintenance/$name"})
    $path=Join-Path $package "maintenance\$name"
    if($records.Count -ne 1 -or (Get-FileHash -LiteralPath $path).Hash -ine $records[0].sha256){throw "Unverified candidate helper: $name"}
    . $path
}
$null=Get-YimeCoreDevelopmentScope
if($Execute -or $LaunchProbeOnly){
    Assert-YimeCoreUnpackagedDataMaintenance
    if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $expectedSid){throw 'Use the initiating Windows account, not another administrator account.'}
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $administrator=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if(-not $StandardUserInitiator -and $administrator) {
        throw 'Use normal double-click from File Explorer, NOT Run as administrator. This entry requests UAC itself and retains the original standard-user process.'
    }
    if($PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1 for this acceptance window.'}
}
$validated=Assert-LocalProductPackage $package
if((Get-FileHash -LiteralPath (Join-Path $package 'maintenance\local-runtime-launcher.cs')).Hash -ine $expectedLauncher){throw 'Candidate does not contain the natively verified standard-primary launcher.'}
$planText=(& (Join-Path $package 'Maintain-YimeCore-Local.cmd') -Action Plan) -join "`n"
if($LASTEXITCODE -ne 0){throw "Candidate Plan failed: $planText"}
$plan=$planText|ConvertFrom-Json
if(-not $Execute -and -not $LaunchProbeOnly){
    [ordered]@{action='prepare-only';candidate_manifest_sha256=$expectedManifest;expected_previous_manifest_sha256=$expectedPreviousManifest;
        target_sid=$expectedSid;plan=$plan;writes_requested=$false;native_execute_required=$true;
        native_install_paused=$false;next_action='normal Explorer double-click Install-YimeCore-Local-Dev.cmd';
        steps=@('native ordinary initiator and actual UAC launch preflight','fresh quiesced backup in ordinary context','package Install entry with its own same-user UAC','live standard-user and three-mode verification','data and independent system-registry comparison');
        reboot_requested=$false;host_acceptance_included=$false}|ConvertTo-Json -Depth 8
    exit 0
}

function Write-AcceptanceJson($Value,[string]$Path){$Value|ConvertTo-Json -Depth 35|Set-Content -LiteralPath $Path -Encoding UTF8}
. (Join-Path $PSScriptRoot 'local-token-diagnostics.ps1')
$sourceFiles=@($PSCommandPath,(Join-Path $PSScriptRoot 'local-token-diagnostics.ps1'))
$sources=@($sourceFiles|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})
$digest=[Security.Cryptography.SHA256]::Create()
try {$sourceHash=([BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes(($sources|ConvertTo-Json -Compress))))).Replace('-','').ToLowerInvariant()}
finally {$digest.Dispose()}
function Assert-AcceptanceOriginRecord($Origin,[string]$Reference,[string]$Hash,[string]$Sid,[string]$ManifestHash) {
    if($Reference -notmatch '^[1-9][0-9]*:[1-9][0-9]*$' -or $Hash -notmatch '^[a-f0-9]{64}$' -or
        $Origin.initiator -cne $Reference -or $Origin.sid -cne $Sid -or
        $Origin.source_set_sha256 -cne $Hash -or $Origin.candidate_manifest_sha256 -cne $ManifestHash){throw 'Native acceptance initiator record mismatch.'}
}
function Assert-AcceptanceWorkerOrigin([string]$Root,[string]$Reference,[string]$Hash,[string]$CurrentHash) {
    if(-not $Hash -or $Hash -cne $CurrentHash){throw 'Acceptance sources changed across UAC; restart from the normal entry.'}
    $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $base=Join-Path $env:USERPROFILE 'YimeCore Recovery Archives'
    if((Split-Path -Parent $rootPath) -ine $base -or (Split-Path -Leaf $rootPath) -notmatch '^local-product-install-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$'){throw 'Unexpected native acceptance archive.'}
    Assert-YimeCorePlainPath $rootPath
    $origin=Get-Content -LiteralPath (Join-Path $rootPath 'initiator.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-AcceptanceOriginRecord $origin $Reference $Hash $expectedSid $expectedManifest
    foreach($name in @('launch-worker.json','summary.json','standard-user-launch-probe.json')) {
        if(Test-Path -LiteralPath (Join-Path $rootPath $name)){throw 'Do not reuse an acceptance worker archive.'}
    }
    return $rootPath
}
function Invoke-AcceptanceAudit([string]$Root) {
    $probeOutput=Join-Path $Root 'standard-user-launch-probe.json'
    $probe=$null
    try {
        $probe=[YimeCore.LocalMaintenance.StandardUserLauncher]::Start(
            (Join-Path $package 'bin\YimeCoreIndependenceAudit.exe'),
            ('-package "'+$package+'" -output "'+$probeOutput+'"'),$package,$expectedSid)
        $attempt=[YimeCore.LocalMaintenance.StandardUserLauncher]::LastLaunchAttempt
        if(-not [YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardPrimaryToken($attempt.ChildToken,$expectedSid,(Get-Process -Id $PID).SessionId)){throw 'Actual probe child is not the same-user ordinary primary token.'}
        if(-not $probe.WaitForExit(20000) -or $probe.ExitCode -ne 0){throw 'Standard-user read-only launch probe failed; old runtime has not been stopped.'}
        $probeResult=Get-Content -LiteralPath $probeOutput -Raw -Encoding UTF8|ConvertFrom-Json
        if(-not $probeResult.passed -or $probeResult.manifest_sha256 -ine $expectedManifest){throw 'Standard-user launch probe did not verify the candidate.'}
        $null=Assert-YimeCoreNativeFile $probeOutput
        return $attempt
    } finally {
        if($probe){try{if(-not $probe.HasExited){$probe.Kill()}}finally{$probe.Dispose()}}
    }
}
# This elevated worker is READ ONLY. Backup stays in the ordinary parent so
# the legacy Trial runtime is never restarted with an administrator token.
if($StandardUserInitiator) {
    if(-not $LaunchProbeOnly -or -not $administrator){throw 'Internal worker requires read-only probe mode and same-account UAC.'}
    $workerRoot=Assert-AcceptanceWorkerOrigin $EvidenceRoot $StandardUserInitiator $ExpectedSourcesHash $sourceHash
    $workerPassed=$false;$workerFailure=$null;$attempt=$null
    try {
        $env:YIMECORE_MAINTENANCE_INITIATOR=$StandardUserInitiator
        Assert-YimeCoreMaintenanceInitiator
        Add-Type -Path (Join-Path $package 'maintenance\local-runtime-launcher.cs')
        $null=[YimeCore.LocalMaintenance.StandardUserLauncher]::ValidateLaunchToken($expectedSid)
        $attempt=Invoke-AcceptanceAudit $workerRoot
        $workerPassed=$true
    } catch {$workerFailure=@(Get-YimeCoreExceptionEvidence $_.Exception)}
    Write-AcceptanceJson ([ordered]@{passed=$workerPassed;source_set_sha256=$sourceHash;candidate_manifest_sha256=$expectedManifest;
        initiator=$StandardUserInitiator;launch_attempt=$attempt;failure=$workerFailure;actual_install_executed=$false;old_runtime_stopped=$false}) (Join-Path $workerRoot 'launch-worker.json')
    if(-not $workerPassed){exit 1}
    exit 0
}
if($EvidenceRoot -or $ExpectedSourcesHash){throw 'Internal worker arguments require a retained ordinary initiator.'}
function Get-CutoverRegistrySnapshot {
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $trial='{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
    $production='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
    $protected=[ordered]@{}
    foreach($path in @("SOFTWARE\Classes\CLSID\$production","SOFTWARE\Classes\WOW6432Node\CLSID\$production",
        "SOFTWARE\Microsoft\CTF\TIP\$production","SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$production",
        "SOFTWARE\Classes\WOW6432Node\CLSID\$trial","SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$trial")) {
        $protected[$path]=Read-YimeCoreSystemKey 2147483650 $path
    }
    foreach($path in @("Software\Microsoft\CTF\TIP\$trial","Software\Microsoft\CTF\TIP\$production",
        "Software\Classes\WOW6432Node\CLSID\$trial",'Control Panel\International\User Profile','Keyboard Layout\Preload')) {
        $protected[$path]=Read-YimeCoreSystemKey 2147483651 "$sid\$path"
    }
    $run=Read-YimeCoreSystemKey 2147483651 "$sid\Software\Microsoft\Windows\CurrentVersion\Run"
    $protected['other_autostart_values']=@($run.values|Where-Object{$_.name -ne 'YimeCoreExperimentalTrial'})
    $default=Get-WinDefaultInputMethodOverride
    $protected['default_override']=if($default){[string]$default.InputMethodTip}else{''}
    [ordered]@{protected=$protected;
        native_com=Read-YimeCoreSystemKey 2147483650 "SOFTWARE\Classes\CLSID\$trial\InprocServer32";
        native_tip=Read-YimeCoreSystemKey 2147483650 "SOFTWARE\Microsoft\CTF\TIP\$trial";
        trial_run=@($run.values|Where-Object{$_.name -eq 'YimeCoreExperimentalTrial'});
        uninstall=Read-YimeCoreSystemKey 2147483651 "$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial"}
}
function Require-CutoverValue($Values,[string]$Name,[int]$Kind,[string]$Expected) {
    $found=@($Values|Where-Object{$_.name -ceq $Name})
    if($found.Count -ne 1 -or [int]$found[0].kind -ne $Kind -or [string]$found[0].value -cne $Expected){throw "Independent system registry value mismatch: $Name"}
}
function Assert-CutoverRegistry($Before,$After,[string]$Root,[string]$DisplayName,[string]$Sid,[string]$StateRoot) {
    if(($Before.protected|ConvertTo-Json -Depth 35 -Compress) -cne ($After.protected|ConvertTo-Json -Depth 35 -Compress)) {
        throw 'Production, frozen registration, user TIP, default input method or unrelated autostart changed.'
    }
    Require-CutoverValue $After.native_com.values '' 1 (Join-Path $Root 'x64\YimeTextServiceExperiment.dll')
    Require-CutoverValue $After.trial_run 'YimeCoreExperimentalTrial' 1 ('"'+(Join-Path $Root 'bin\YimeCoreTrialRuntime.exe')+'" -no-toolbar')
    Require-CutoverValue $After.uninstall.values 'InstallLocation' 1 $Root
    Require-CutoverValue $After.uninstall.values 'DisplayName' 1 $DisplayName
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $uninstall='"'+$ps+'" -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $Root 'maintenance\Manage-YimeCoreTrial.ps1')+'" -Action Uninstall -StateRoot "'+$StateRoot+'" -TargetUserSid "'+$Sid+'" -NativeX64Only'
    Require-CutoverValue $After.uninstall.values 'UninstallString' 1 $uninstall
}

$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
Assert-YimeCorePlainPath $state
$config=Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
$previous=[IO.Path]::GetFullPath([string]$config.install_root)
Assert-YimeCorePlainPath $previous
if((Get-FileHash -LiteralPath (Join-Path $previous 'package-manifest.json')).Hash -ine $expectedPreviousManifest){throw 'Previous install is no longer the reviewed Trial baseline. Stop and re-plan; do not repeat this first-migration acceptance.'}
if(Test-Path -LiteralPath $plan.install_root){throw 'Planned target is occupied; preserve it and re-plan before installing.'}
if(Get-Process WINWORD -ErrorAction SilentlyContinue){throw 'Close Word and all input-method tools before starting this acceptance.'}
$others=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -and
    $_.ExecutablePath.StartsWith($previous+'\',[StringComparison]::OrdinalIgnoreCase) -and
    $_.Name -notin @('YimeCoreTrialRuntime.exe','YimeBroker.exe')})
if($others.Count){throw 'Close all running tools from the previous input-method package before acceptance.'}
$liveBefore=Get-YimeCoreLiveRuntimeEvidence $state
if(-not $liveBefore.passed){throw 'Cannot verify previous runtime/Broker identity; no backup or install was started.'}
Add-Type -Path (Join-Path $package 'maintenance\local-runtime-launcher.cs')
[Environment]::SetEnvironmentVariable('YIMECORE_MAINTENANCE_INITIATOR',$null,'Process')
$standardInitiator=[YimeCore.LocalMaintenance.StandardUserLauncher]::ValidateLaunchToken($expectedSid)
$reference=[YimeCore.LocalMaintenance.StandardUserLauncher]::CaptureInitiatorReference($expectedSid)
foreach($processId in @([int]$liveBefore.status.runtime_pid,[int]$liveBefore.status.broker_pid)) {
    $token=[YimeCore.LocalMaintenance.StandardUserLauncher]::InspectProcess($processId)
    if(-not [YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardPrimaryToken($token,$expectedSid,(Get-Process -Id $PID).SessionId)){throw 'Previous runtime must already be ordinary same-user; stop and re-plan without mutation.'}
}

$archive=Join-Path $env:USERPROFILE ('YimeCore Recovery Archives\local-product-install-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
Assert-YimeCorePlainPath $archive
if(Test-Path -LiteralPath $archive){throw 'Acceptance archive must be new.'}
New-Item -ItemType Directory -Path $archive|Out-Null
Write-AcceptanceJson ([ordered]@{initiator=$reference;sid=$expectedSid;source_set_sha256=$sourceHash;sources=$sources;candidate_manifest_sha256=$expectedManifest}) (Join-Path $archive 'initiator.json')
$backup=Join-Path $archive 'preinstall-backup'
$stage='capture-before';$installed=$false;$passed=$false;$failure=$null
Start-Transcript -LiteralPath (Join-Path $archive 'transcript.txt')|Out-Null
try {
    $before=Get-CutoverRegistrySnapshot
    Write-AcceptanceJson $before (Join-Path $archive 'system-before.json')
    # Capture actual ordinary origin; the pinned package is never edited in place.
    $tokenDiagnostics=$null;$tokenDiagnosticError=@()
    try {$tokenDiagnostics=Get-YimeCoreLaunchTokenDiagnostics}
    catch {$tokenDiagnosticError=@(Get-YimeCoreExceptionEvidence $_.Exception)}
    Write-AcceptanceJson ([ordered]@{plan=$plan;previous_install=$previous;previous_live=$liveBefore;standard_primary_initiator=$standardInitiator;
        token_diagnostics=$tokenDiagnostics;token_diagnostic_errors=$tokenDiagnosticError;
        launch_probe_only=[bool]$LaunchProbeOnly;diagnostic_helper_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'local-token-diagnostics.ps1')).Hash;
        candidate_manifest_sha256=$expectedManifest;acceptance_script_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash}) (Join-Path $archive 'preflight.json')
    & (Join-Path $package 'bin\YimeCoreIndependenceAudit.exe') -package $previous -output (Join-Path $archive 'previous-package-audit.json')
    if($LASTEXITCODE -ne 0){throw 'Previous package integrity audit failed.'}
    $stage='standard-user-launch-preflight'
    # Preserve this ordinary process across the read-only UAC probe. The package
    # installer later retains its own ordinary initiator across installation UAC.
    $worker=$null
    try {
        $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $argsLine='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -LaunchProbeOnly -PackageRoot "'+$package+'" -StandardUserInitiator "'+$reference+'" -EvidenceRoot "'+$archive+'" -ExpectedSourcesHash "'+$sourceHash+'"'
        $worker=Start-Process -FilePath $ps -ArgumentList $argsLine -Verb RunAs -WindowStyle Hidden -PassThru
        $worker.WaitForExit()
        $workerResultPath=Join-Path $archive 'launch-worker.json'
        if(-not (Test-Path -LiteralPath $workerResultPath)){throw "Read-only UAC worker exited $($worker.ExitCode) without launch evidence; no backup or install was started."}
        $workerResult=Get-Content -LiteralPath $workerResultPath -Raw -Encoding UTF8|ConvertFrom-Json
        if($worker.ExitCode -ne 0 -or -not $workerResult.passed){throw ('Read-only UAC launch failed: '+($workerResult.failure|ConvertTo-Json -Depth 8 -Compress))}
        if($workerResult.source_set_sha256 -cne $sourceHash -or $workerResult.candidate_manifest_sha256 -cne $expectedManifest -or $workerResult.initiator -cne $reference){throw 'UAC launch evidence identity mismatch.'}
        $null=Assert-YimeCoreNativeFile $workerResultPath
    } finally {if($worker){$worker.Dispose()}}
    if($LaunchProbeOnly){
        $passed=$true;$stage='standard-user-launch-probe-passed'
        Write-Host "PASS: read-only standard-user launch probe only; no backup, stop, install or reboot. Evidence: $archive"
        return
    }
    $stage='fresh-backup'
    # This is still the ordinary parent: the legacy adapter restarts the old
    # runtime normally, without accidentally elevating it after the backup.
    & (Join-Path $package 'maintenance\backup-local-trial-state.ps1') -BackupRoot $backup
    $saved=Get-Content -LiteralPath (Join-Path $backup 'backup-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $saved.passed -or -not $saved.native_context_verified -or $saved.source_install_root -ine $previous){throw 'Fresh backup identity mismatch.'}
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'state') $saved.state_files
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'previous-package') $saved.package_files
    $null=Assert-YimeCoreNativeFile (Join-Path $backup 'backup-manifest.json')
    Assert-YimeCoreUnchangedData $saved.data_files @(Get-YimeCoreDataRecords $state)
    $stage='install'
    & (Join-Path $package 'Install-YimeCore-Local.cmd')
    if($LASTEXITCODE -ne 0){
        $installExit=$LASTEXITCODE
        $errorPath=Join-Path $state 'maintenance-last-error.txt'
        $detail=''
        if(Test-Path -LiteralPath $errorPath){
            Copy-Item -LiteralPath $errorPath -Destination (Join-Path $archive 'installer-maintenance-last-error.txt')
            $detail=Get-Content -LiteralPath $errorPath -Raw -Encoding UTF8
        }
        throw "Package installer failed (exit $installExit). It owns transactional rollback; preserve this archive. $detail"
    }
    $installed=$true
    $stage='verify-installed'
    $context=Assert-LocalProductInstalledContext ([string]$plan.install_root) $state
    if($context.package.manifest_sha256 -ine $expectedManifest){throw 'Installed manifest is not the reviewed candidate.'}
    $standard=Assert-LocalProductLiveRuntime $context
    Write-AcceptanceJson $standard (Join-Path $archive 'standard-user-runtime.json')
    & (Join-Path $context.package.root 'Maintain-YimeCore-Local.cmd') -Action Verify
    if($LASTEXITCODE -ne 0){throw 'Installed package three-mode verification failed.'}
    Copy-Item -LiteralPath (Join-Path $state 'evidence\live-runtime-verification.json') -Destination (Join-Path $archive 'live-runtime-verification.json')
    $stage='compare-data-and-system-registry'
    $after=Get-CutoverRegistrySnapshot
    Write-AcceptanceJson $after (Join-Path $archive 'system-after.json')
    Assert-CutoverRegistry $before $after $context.package.root $validated.descriptor.display_name $expectedSid $state
    $dataAfter=@(Get-YimeCoreDataRecords $state)
    Assert-YimeCoreUnchangedData $saved.data_files $dataAfter
    Write-AcceptanceJson $dataAfter (Join-Path $archive 'data-after.json')
    # Frozen x86 references require retaining the entire old install, byte-for-byte.
    Assert-YimeCoreArchiveRecords $previous $saved.package_files
    $null=Assert-YimeCoreNativeFile (Join-Path $archive 'standard-user-runtime.json')
    $passed=$true;$stage='native-install-accepted'
} catch {
    $chain=@(Get-YimeCoreExceptionEvidence $_.Exception)
    $win32=@($chain|Where-Object{$null -ne $_.native_error_code}|Select-Object -First 1)
    $failure=[ordered]@{stage=$stage;message=$_.Exception.Message;type=$_.Exception.GetType().FullName;stack=$_.ScriptStackTrace;
        exception_chain=$chain;native_error_code=if($win32.Count){$win32[0].native_error_code}else{$null};
        native_error_message=if($win32.Count){$win32[0].native_error_message}else{$null}}
    Write-AcceptanceJson $failure (Join-Path $archive 'failure.json')
    if($win32.Count){Write-Host "BLOCKED: $stage; Win32=$($failure.native_error_code): $($failure.native_error_message). Evidence: $archive"}
    else {Write-Host "BLOCKED: $stage; $($failure.message). Evidence: $archive"}
    # Never automatically repeat installation or overwrite data after a failed
    # post-check. The installer's own rollback covers failed installation only.
    throw
} finally {
    try {
        Write-AcceptanceJson ([ordered]@{schema_version='yimecore-local-native-install-acceptance-v1';passed=$passed;stage=$stage;
            launch_probe_only=[bool]$LaunchProbeOnly;install_acceptance_passed=($passed -and -not $LaunchProbeOnly);
            install_command_succeeded=$installed;archive_root=$archive;backup_root=$backup;failure=$failure;
            candidate_manifest_sha256=$expectedManifest;source_install_root=$previous;planned_install_root=$plan.install_root;
            source_set_sha256=$sourceHash;initiator_reference=$reference;
            actual_backup_restore_tested=$false;actual_failed_upgrade_rollback_tested=$false;live_host_acceptance=$false;
            reboot_requested=$false;local_product_ready=$false;public_release_ready=$false}) (Join-Path $archive 'summary.json')
    } finally {Stop-Transcript|Out-Null}
}
Write-Host "PASS: native candidate install, standard-user runtime, preserved data and system registration. Evidence: $archive"
Write-Host 'Do not reboot yet. Return the PASS line for installed-host and rollback acceptance.'
