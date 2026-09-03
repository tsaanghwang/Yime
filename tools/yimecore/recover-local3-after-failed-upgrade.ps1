[CmdletBinding()]
param([switch]$Execute,[switch]$Worker,[switch]$Finalize,[string]$EvidenceRoot,[string]$ExpectedSourceHash,[string]$InitiatorReference)
$ErrorActionPreference='Stop'
$old='C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-75485fda5d79-6964099f'
$failed='C:\Users\tsaan\YimeCore Recovery Archives\local-product-install-20260903-082737-39936047'
$backup=Join-Path $failed 'preinstall-backup'
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$sid='S-1-5-21-2783006668-770716121-2150155084-1001'
$tip='0804:{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
$manifestHash='6964099f48e0b6f534b763728d4a1806e4d4edfb1e7d7053b42c6d78d9fee74a'
$systemBeforeHash='3e4c917b40c90a76b634097e90fa76169b0b963de9216e20f879c46361585bbe'
$backupManifestHash='854d5c2a7c659a76bd1caeb0e031681d9e350b0348f4150990457f2e51f0e8d9'
$configHash='9de5cd164e174322e501dec41f47e8e2347f6974aaa32835f7f0ce6d383149d4'
$new='C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-4bfa828009d1-02ae6ebc'
$systemBeforePath=Join-Path $failed 'system-before.json'
$backupManifestPath=Join-Path $backup 'backup-manifest.json'
$backupConfig=Join-Path $backup 'state\runtime-config.json'
$manifestPath=Join-Path $old 'package-manifest.json'
foreach($record in @(@($manifestPath,$manifestHash),@($systemBeforePath,$systemBeforeHash),@($backupManifestPath,$backupManifestHash),@($backupConfig,$configHash))){
    if(-not (Test-Path -LiteralPath $record[0] -PathType Leaf) -or (Get-FileHash -LiteralPath $record[0]).Hash -ine $record[1]){throw "Pinned recovery input changed: $($record[0])"}
}
if(Test-Path -LiteralPath $new){throw 'Failed local.4 target unexpectedly exists; preserve it and stop.'}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $sid){throw 'Recovery must use the initiating Windows account.'}
$admin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($Execute -and $PSVersionTable.PSVersion.Major -ne 5){throw 'Recovery requires native Windows PowerShell 5.1.'}
if($Execute -and $admin -and -not $Worker){throw 'Start the recovery normally; it requests its own same-user UAC.'}
if(($Worker -or $EvidenceRoot -or $ExpectedSourceHash -or $InitiatorReference) -and -not ($Execute -and $Worker -and $admin -and $EvidenceRoot -and $ExpectedSourceHash -and $InitiatorReference)){throw 'Incomplete recovery worker arguments.'}
. (Join-Path $old 'maintenance\development-scope.ps1')
. (Join-Path $old 'maintenance\local-maintenance-safety.ps1')
. (Join-Path $old 'maintenance\local-package-contract.ps1')
. (Join-Path $old 'maintenance\local-product-runtime.ps1')
$null=Get-YimeCoreDevelopmentScope
if($Execute){Assert-YimeCoreUnpackagedDataMaintenance}
$package=Assert-LocalProductPackage $old
$backupManifest=Get-Content -LiteralPath $backupManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if(-not $backupManifest.passed -or $backupManifest.source_install_root -ine $old -or $backupManifest.source_state_root -ine $state){throw 'Pinned preinstall backup identity mismatch.'}
Assert-YimeCoreArchiveRecords (Join-Path $backup 'state') $backupManifest.state_files
Assert-YimeCoreArchiveRecords $old $backupManifest.package_files
Assert-YimeCoreUnchangedData $backupManifest.data_files @(Get-YimeCoreDataRecords $state)
$before=Get-Content -LiteralPath $systemBeforePath -Raw -Encoding UTF8|ConvertFrom-Json
$acceptance=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($acceptance,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Get-CutoverRegistrySnapshot','Require-CutoverValue','Assert-CutoverRegistry')){
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $fn){throw "Missing recovery validator: $name"}; . ([scriptblock]::Create($fn.Extent.Text))
}
$sources=@($PSCommandPath,$acceptance|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})
$sha=[Security.Cryptography.SHA256]::Create()
try{$sourceHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($sources|ConvertTo-Json -Compress))))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
$tool=Join-Path $old 'x64\YimeTextServiceRegistration.exe';$dll=Join-Path $old 'x64\YimeTextServiceExperiment.dll'
function Status-Map { $map=@{}; foreach($line in ((& $tool status 2>&1) -split "`r?`n")){if($line -match '='){$i=$line.IndexOf('=');$map[$line.Substring(0,$i)]=$line.Substring($i+1)}};if($LASTEXITCODE -ne 0){throw 'Registration status failed.'};$map }
function Assert-RecoveredState([bool]$AllowMissingUserTip) {
    $s=Status-Map
    if($s.com_registered_current_view -ne 'true' -or $s.profile_registered -ne 'true' -or [int]$s.categories_registered_count -ne 5){throw 'Recovered x64 registration is incomplete.'}
    $current=Get-CutoverRegistrySnapshot
    Require-CutoverValue $current.native_com.values '' 1 $dll
    Require-CutoverValue $current.trial_run 'YimeCoreExperimentalTrial' 1 ('"'+(Join-Path $old 'bin\YimeCoreTrialRuntime.exe')+'" -no-toolbar')
    Require-CutoverValue $current.uninstall.values 'InstallLocation' 1 $old
    Require-CutoverValue $current.uninstall.values 'DisplayName' 1 ([string]$package.descriptor.display_name)
    $projected=$current.protected|ConvertTo-Json -Depth 40|ConvertFrom-Json
    $originalAutostarts=@($before.protected.other_autostart_values)
    foreach($original in $originalAutostarts){
        $actual=@($current.protected.other_autostart_values|Where-Object name -ceq $original.name)
        if($actual.Count -ne 1 -or ($actual[0]|ConvertTo-Json -Compress) -cne ($original|ConvertTo-Json -Compress)){throw "Original unrelated Run value changed: $($original.name)"}
    }
    $concurrent=@($current.protected.other_autostart_values|Where-Object{$_.name -notin @($originalAutostarts.name)})
    $projected.other_autostart_values=$originalAutostarts
    $userTipPath='Software\Microsoft\CTF\TIP\{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
    if($AllowMissingUserTip -and -not $current.protected.$userTipPath.exists){$projected.$userTipPath=$before.protected.$userTipPath}
    if(($projected|ConvertTo-Json -Depth 40 -Compress) -cne ($before.protected|ConvertTo-Json -Depth 40 -Compress)){throw 'Recovered protection state differs outside explicitly preserved concurrent Run additions.'}
    [ordered]@{snapshot=$current;concurrent_autostart_additions=$concurrent}
}
function Assert-DamagedState {
    if(Get-Process YimeCoreTrialRuntime,YimeBroker -ErrorAction SilentlyContinue){throw 'Unexpected local runtime is active.'}
    $s=Status-Map
    if($s.com_registered_current_view -ne 'false' -or $s.profile_registered -ne 'true' -or [int]$s.categories_registered_count -ne 5){throw 'Registration no longer matches the preserved-profile failure state.'}
    $current=Get-CutoverRegistrySnapshot
    if($current.native_com.exists -or $current.trial_run -or $current.uninstall.exists){throw 'Damaged cutover state changed; refuse broad overwrite.'}
    # Only the documented language-list/user-TIP removal may differ. Project
    # those two snapshots back to the pinned original and require every other
    # production, frozen, default-IME and unrelated Run observation to match.
    $projected=$current.protected|ConvertTo-Json -Depth 40|ConvertFrom-Json
    foreach($path in @('Software\Microsoft\CTF\TIP\{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}','Control Panel\International\User Profile')){
        $projected.$path=$before.protected.$path
    }
    if(($projected|ConvertTo-Json -Depth 40 -Compress) -cne ($before.protected|ConvertTo-Json -Depth 40 -Compress)){throw 'A protected registry area outside the documented failed-cutover delta changed.'}
    $current
}
$current=if($Finalize){(Assert-RecoveredState $true).snapshot}else{Assert-DamagedState}
if(-not $Execute){[ordered]@{action=$(if($Finalize){'finalize-recovery-plan'}else{'recover-plan'});writes_requested=$false;old_manifest=$manifestHash;failed_archive=$failed;source_hash=$sourceHash}|ConvertTo-Json;exit 0}
$archiveBase=Join-Path $env:USERPROFILE 'YimeCore Recovery Archives'
function Write-Evidence($value,[string]$name){$value|ConvertTo-Json -Depth 40|Set-Content -LiteralPath (Join-Path $EvidenceRoot $name) -Encoding UTF8}
if(-not $Worker){
    $EvidenceRoot=Join-Path $archiveBase ('local3-failed-upgrade-recovery-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $EvidenceRoot|Out-Null
    Write-Evidence ([ordered]@{sid=$sid;source_hash=$sourceHash;sources=$sources;failed_archive=$failed}) 'initiator.json'
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Initialize-LocalProductLauncher ([ordered]@{package=$package})
    $reference=[YimeCore.LocalMaintenance.StandardUserLauncher]::CaptureInitiatorReference($sid)
    $args='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Execute -Worker'+$(if($Finalize){' -Finalize'}else{''})+' -EvidenceRoot "'+$EvidenceRoot+'" -ExpectedSourceHash "'+$sourceHash+'" -InitiatorReference "'+$reference+'"'
    $p=Start-Process -FilePath $ps -ArgumentList $args -Verb RunAs -WindowStyle Hidden -PassThru;$p.WaitForExit();$code=$p.ExitCode;$p.Dispose()
    if($code -ne 0){throw "Elevated recovery failed (exit $code). Evidence: $EvidenceRoot"}
    if(-not $Finalize){
        if(Test-Path -LiteralPath (Join-Path $state 'runtime-config.json')){throw 'Runtime configuration appeared concurrently.'}
        Copy-Item -LiteralPath $backupConfig -Destination (Join-Path $state 'runtime-config.json')
        $languages=Get-WinUserLanguageList;$zh=$languages|Where-Object LanguageTag -eq 'zh-Hans-CN'|Select-Object -First 1
        if(-not $zh){throw 'zh-Hans-CN language entry is missing.'}
        if(@($zh.InputMethodTips) -notcontains $tip){$null=$zh.InputMethodTips.Add($tip);Set-WinUserLanguageList -LanguageList $languages -Force}
        & (Join-Path $old 'maintenance\start-e6c-trial-runtime.ps1')|Out-Null
    }
    $context=Assert-LocalProductInstalledContext $old $state;$live=Assert-LocalProductLiveRuntime $context
    $verified=Assert-RecoveredState $false;$after=$verified.snapshot
    Write-Evidence $after 'system-after.json';Write-Evidence $live 'live-runtime.json'
    Write-Evidence ([ordered]@{passed=$true;restored_manifest=$manifestHash;failed_archive=$failed;x64_com_repointed=$true;run_and_uninstall_restored=$true;language_tip_restored=$true;runtime_config_restored=$true;standard_user_runtime_restored=$true;production_and_frozen_registration_preserved=$true;default_input_method_preserved=$true;concurrent_autostart_additions=$verified.concurrent_autostart_additions;reboot_requested=$false}) 'summary.json'
    Write-Host "PASS: local.3 recovered with protected registry unchanged. Evidence: $EvidenceRoot";exit 0
}
$EvidenceRoot=[IO.Path]::GetFullPath($EvidenceRoot)
if((Split-Path -Parent $EvidenceRoot) -ine $archiveBase -or (Split-Path -Leaf $EvidenceRoot) -notmatch '^local3-failed-upgrade-recovery-'){throw 'Unexpected recovery evidence root.'}
$origin=Get-Content -Raw (Join-Path $EvidenceRoot 'initiator.json')|ConvertFrom-Json
if($sourceHash -cne $ExpectedSourceHash -or $origin.source_hash -cne $sourceHash -or $origin.sid -cne $sid){throw 'Recovery source changed across UAC.'}
$env:YIMECORE_MAINTENANCE_INITIATOR=$InitiatorReference
Assert-YimeCoreMaintenanceInitiator
$null=if($Finalize){Assert-RecoveredState $true}else{Assert-DamagedState}
$output='finalize-user-tip-only'
if(-not $Finalize){$output=(& $tool repoint $dll 2>&1)-join "`n";if($LASTEXITCODE -ne 0){throw "x64 COM repoint failed: $output"};$s=Status-Map;if($s.com_registered_current_view -ne 'true' -or $s.profile_registered -ne 'true' -or [int]$s.categories_registered_count -ne 5){throw 'x64 registration did not converge after repoint.'}}
$users=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::Users,[Microsoft.Win32.RegistryView]::Registry64)
try{
    if(-not $Finalize){
        $run=$users.CreateSubKey("$sid\Software\Microsoft\Windows\CurrentVersion\Run",$true)
        try{$run.SetValue([string]$before.trial_run.name,[string]$before.trial_run.value,[Microsoft.Win32.RegistryValueKind]::String)}finally{$run.Dispose()}
        $uninstall=$users.CreateSubKey("$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial",$true)
        try{foreach($v in $before.uninstall.values){$uninstall.SetValue([string]$v.name,$v.value,[Microsoft.Win32.RegistryValueKind]([int]$v.kind))}}finally{$uninstall.Dispose()}
    }
    $userTip=$users.CreateSubKey("$sid\Software\Microsoft\CTF\TIP\{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}\LanguageProfile\0x00000804\{607895A8-9504-4A2E-9BB1-2C159E3A1757}",$true)
    try{$userTip.SetValue('Enable',[uint32]1,[Microsoft.Win32.RegistryValueKind]::DWord)}finally{$userTip.Dispose()}
}finally{$users.Dispose()}
$workerLive=$null
if($Finalize){
    $context=Assert-LocalProductInstalledContext $old $state
    $existing=Get-YimeCoreLiveRuntimeEvidence $state
    if($existing.passed){$workerLive=Assert-LocalProductLiveRuntime $context}
    else{
        if(Get-Process YimeCoreTrialRuntime,YimeBroker -ErrorAction SilentlyContinue){throw 'Unverified local runtime process exists; refuse duplicate launch.'}
        $workerLive=Start-LocalProductRuntime $context
    }
}
Write-Evidence ([ordered]@{passed=$true;registration_output=$output;source_hash=$sourceHash;standard_user_runtime=$workerLive}) 'worker-summary.json'
