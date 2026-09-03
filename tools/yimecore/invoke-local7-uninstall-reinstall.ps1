[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
$candidate='C:\dev\Yime\.tmp\yimecore-local-product\local7-build-20260903-1645\package'
$expectedManifest='0346bbe83eb3dab721e3bd75b14031a604dbdb7fbed041f9021834b7822690bb'
$expectedValidator='8f560a009bfead4a3bd8ca736d8b4008e0e0da32a350aeaf0a7fa0f1ad0addb4'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$trialClsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}'
$trialProfile='{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
$manifestPath=Join-Path $candidate 'package-manifest.json'
if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or (Get-FileHash -LiteralPath $manifestPath).Hash -ine $expectedManifest){throw 'Pinned local.7 candidate is missing or changed.'}
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')){
    $path=Join-Path $candidate "maintenance\$name"
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Candidate helper is missing: $name"}
    . $path
}
$package=Assert-LocalProductPackage $candidate
$validator=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
if((Get-FileHash -LiteralPath $validator).Hash -ine $expectedValidator){throw 'Pinned read-only registry validator changed.'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($validator,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-CutoverRegistrySnapshot'},$true)
if(-not $fn){throw 'Missing read-only registry snapshot helper.'}
. ([scriptblock]::Create($fn.Extent.Text))
function Same($Left,$Right){return (($Left|ConvertTo-Json -Depth 40 -Compress) -ceq ($Right|ConvertTo-Json -Depth 40 -Compress))}
function Write-Evidence($Value,[string]$Path){$Value|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $Path -Encoding UTF8}
function Normalize-RootInSnapshot($Snapshot,[string]$Root){
    $json=$Snapshot|ConvertTo-Json -Depth 40 -Compress
    $escaped=([string]$Root|ConvertTo-Json -Compress).Trim('"')
    return ($json.Replace($escaped,'<INSTALL_ROOT>')|ConvertFrom-Json)
}
function New-InstallablePackageCopy([string]$SourceRoot,[string]$DestinationRoot,$Manifest){
    if(Test-Path -LiteralPath $DestinationRoot){throw 'Installable recovery package destination must be new.'}
    New-Item -ItemType Directory -Path $DestinationRoot|Out-Null
    foreach($relative in @($Manifest.files.path)+@('package-manifest.json')){
        $nativeRelative=([string]$relative).Replace('/','\')
        $source=Join-Path $SourceRoot $nativeRelative
        $destination=Join-Path $DestinationRoot $nativeRelative
        $parent=Split-Path -Parent $destination
        if(-not (Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
        Copy-Item -LiteralPath $source -Destination $destination
    }
    return $DestinationRoot
}
function Write-CommandResult([string]$CommandName,[int]$ExitCode,[string]$Path){
    @("command=$CommandName","exit_code=$ExitCode")|Set-Content -LiteralPath $Path -Encoding ASCII
}
function Get-ChildNames($Node){
    if($null -eq $Node -or $null -eq $Node.children){return @()}
    if($Node.children -is [Collections.IDictionary]){
        return @($Node.children.Keys|ForEach-Object{[string]$_})
    }
    return @($Node.children.PSObject.Properties|ForEach-Object{$_.Name})
}
function Get-ChildNode($Node,[string]$Name){
    if($null -eq $Node -or $null -eq $Node.children){return $null}
    if($Node.children -is [Collections.IDictionary]){return $Node.children[$Name]}
    $property=$Node.children.PSObject.Properties[$Name]
    if($null -eq $property){return $null}
    return $property.Value
}
function Get-EnableRecord($Snapshot,[string]$ProfileGuid){
    if($null -eq $Snapshot -or -not $Snapshot.exists){return $null}
    $leaf=Get-ChildNode (Get-ChildNode (Get-ChildNode $Snapshot 'LanguageProfile') '0x00000804') $ProfileGuid
    if($null -eq $leaf -or -not $leaf.exists){return $null}
    $values=@($leaf.values|Where-Object{$_.name -ceq 'Enable'})
    if($values.Count -ne 1){return $null}
    return $values[0]
}
function Assert-ActiveUserTipEnabled($Snapshot){
    $enable=Get-EnableRecord $Snapshot $trialProfile
    if($null -eq $enable -or [int]$enable.kind -ne 4 -or [int]$enable.value -ne 1){throw 'Active per-user local product TIP is not DWORD Enable=1.'}
}
function Read-ActiveUserTip {
    Read-YimeCoreSystemKey ([uint32]2147483651) "$expectedSid\Software\Microsoft\CTF\TIP\$trialClsid"
}
function Test-TipSnapshotSemanticallyAbsent($Snapshot,[string]$Clsid){
    if($null -eq $Snapshot -or -not $Snapshot.exists){return $true}
    $language=Get-ChildNode (Get-ChildNode $Snapshot 'LanguageProfile') '0x00000804'
    if(@(Get-ChildNames $language).Count -ne 0){return $false}
    $category=Get-ChildNode $Snapshot 'Category'
    $categories=Get-ChildNode $category 'Category'
    foreach($categoryName in @(Get-ChildNames $categories)){
        if(@(Get-ChildNames (Get-ChildNode $categories $categoryName)) -contains $Clsid){return $false}
    }
    $item=Get-ChildNode (Get-ChildNode $category 'Item') $Clsid
    if(@(Get-ChildNames $item).Count -ne 0){return $false}
    return $true
}
if(-not $Execute){
    [ordered]@{action='local7-uninstall-preserve-data-and-reinstall';candidate=$candidate;manifest_sha256=$expectedManifest;
        fresh_backup_required=$true;uninstall_gap_verified=$true;active_user_tip_enable_verified=$true;reinstall_same_package=$true;
        user_data_purged=$false;production_components_changed=$false;default_input_method_changed=$false;reboot_requested=$false}|ConvertTo-Json -Depth 5
    exit 0
}
Assert-YimeCoreUnpackagedDataMaintenance
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($identity.User.Value -cne $expectedSid){throw 'Use the Windows account that owns the local.7 installation.'}
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use normal File Explorer double-click, not Run as administrator.'}
if(Get-Process WINWORD -ErrorAction SilentlyContinue){throw 'Close Word before uninstall/reinstall acceptance.'}
$configPath=Join-Path $state 'runtime-config.json'
$config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json
$oldRoot=[IO.Path]::GetFullPath([string]$config.install_root).TrimEnd('\')
if((Get-FileHash -LiteralPath (Join-Path $oldRoot 'package-manifest.json')).Hash -ine $expectedManifest){throw 'Current installation is not the pinned local.7 package.'}
$oldContext=Assert-LocalProductInstalledContext $oldRoot $state
$oldLive=Assert-LocalProductLiveRuntime $oldContext
$evidence=Join-Path $env:USERPROFILE ('YimeCore Recovery Archives\local7-uninstall-reinstall-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
if(Test-Path -LiteralPath $evidence){throw 'Evidence directory must be new.'}
New-Item -ItemType Directory -Path $evidence|Out-Null
$backup=Join-Path $evidence 'preuninstall-backup'
$stage='fresh-backup';$passed=$false;$uninstalled=$false;$reinstalled=$false;$failure=$null;$newRoot=$null
Start-Transcript -LiteralPath (Join-Path $evidence 'transcript.txt')|Out-Null
try{
    Write-Evidence ([ordered]@{candidate=$candidate;candidate_manifest_sha256=$expectedManifest;old_install_root=$oldRoot;
        initiator_sid=$expectedSid;old_live=$oldLive;reboot_requested=$false}) (Join-Path $evidence 'preflight.json')
    & (Join-Path $candidate 'bin\YimeCoreIndependenceAudit.exe') -package $candidate -output (Join-Path $evidence 'candidate-audit-before.json')
    if($LASTEXITCODE -ne 0){throw 'Pinned local.7 candidate audit failed.'}
    # Keep maintenance commands attached to the console. Capturing native
    # output creates a pipe that the restarted Runtime can inherit and hold
    # open indefinitely, even after the maintenance command itself exits.
    & (Join-Path $oldRoot 'Maintain-YimeCore-Local.cmd') -Action Backup -BackupRoot $backup
    $backupExit=$LASTEXITCODE
    Write-CommandResult 'Backup' $backupExit (Join-Path $evidence 'backup-output.txt')
    if($backupExit -ne 0){throw "Fresh pre-uninstall backup failed with exit $backupExit."}
    $backupManifest=Get-Content -LiteralPath (Join-Path $backup 'backup-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $backupManifest.passed -or -not $backupManifest.native_context_verified -or $backupManifest.source_install_root -ine $oldRoot){throw 'Fresh backup identity is invalid.'}
    $backupManifestHash=(Get-FileHash -LiteralPath (Join-Path $backup 'backup-manifest.json')).Hash.ToLowerInvariant()
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'state') $backupManifest.state_files
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'previous-package') $backupManifest.package_files
    Assert-YimeCoreUnchangedData $backupManifest.data_files @(Get-YimeCoreDataRecords $state)
    $archivedPackage=Join-Path $backup 'previous-package'
    if((Get-FileHash -LiteralPath (Join-Path $archivedPackage 'package-manifest.json')).Hash -ine $expectedManifest){throw 'Fresh recovery package identity mismatch.'}
    # previous-package is exact recovery material and intentionally retains the
    # old root-bound install-metadata.json. Build a separate installable copy
    # from only the pinned manifest payload, leaving the exact archive intact.
    $reinstallPackage=Join-Path $backup 'reinstall-package'
    $null=New-InstallablePackageCopy $archivedPackage $reinstallPackage $package.manifest
    $null=Assert-LocalProductPackage $reinstallPackage
    & (Join-Path $reinstallPackage 'bin\YimeCoreIndependenceAudit.exe') -package $reinstallPackage -output (Join-Path $evidence 'reinstall-package-audit-before.json')
    if($LASTEXITCODE -ne 0){throw 'Fresh recovery package audit failed.'}
    # Backup stops and restarts the service. Capture the new PIDs that uninstall
    # must terminate instead of checking the stale pre-backup processes.
    $oldContext=Assert-LocalProductInstalledContext $oldRoot $state
    $oldLive=Assert-LocalProductLiveRuntime $oldContext
    Write-Evidence $oldLive (Join-Path $evidence 'live-before-uninstall.json')
    $beforeData=@(Get-YimeCoreDataRecords $state)
    $beforeRegistry=Get-CutoverRegistrySnapshot
    Write-Evidence $beforeData (Join-Path $evidence 'data-before.json')
    Write-Evidence $beforeRegistry (Join-Path $evidence 'system-before.json')
    $beforeActiveUserTip=Read-ActiveUserTip
    Assert-ActiveUserTipEnabled $beforeActiveUserTip
    Write-Evidence $beforeActiveUserTip (Join-Path $evidence 'active-user-tip-before.json')

    $stage='uninstall-preserve-data'
    # Run uninstall from the preserved external package. The installed CMD is
    # deleted by a successful uninstall before cmd.exe can read its final line,
    # which turns successful removal into a misleading exit code 1.
    & (Join-Path $reinstallPackage 'Maintain-YimeCore-Local.cmd') -Action Uninstall
    $uninstallExit=$LASTEXITCODE
    Write-CommandResult 'Uninstall' $uninstallExit (Join-Path $evidence 'uninstall-output.txt')
    if($uninstallExit -ne 0){throw "Local.7 uninstall failed with exit $uninstallExit."}
    $uninstalled=$true
    $midRegistry=Get-CutoverRegistrySnapshot
    $midData=@(Get-YimeCoreDataRecords $state)
    Write-Evidence $midRegistry (Join-Path $evidence 'system-uninstalled.json')
    Write-Evidence $midData (Join-Path $evidence 'data-uninstalled.json')
    $midActiveUserTip=Read-ActiveUserTip
    Write-Evidence $midActiveUserTip (Join-Path $evidence 'active-user-tip-uninstalled.json')
    if(-not (Test-TipSnapshotSemanticallyAbsent $midActiveUserTip $trialClsid)){throw 'Active per-user local product TIP was not removed during uninstall.'}
    Assert-YimeCoreUnchangedData $beforeData $midData
    if(-not (Same $beforeRegistry.protected $midRegistry.protected)){throw 'Production, frozen, default-input or unrelated autostart registry changed during uninstall.'}
    if($midRegistry.native_com.exists -or
        -not (Test-TipSnapshotSemanticallyAbsent $midRegistry.native_tip $trialClsid) -or
        -not (Test-TipSnapshotSemanticallyAbsent $midRegistry.mirrored_tip $trialClsid) -or
        @($midRegistry.trial_run).Count -ne 0 -or $midRegistry.uninstall.exists){throw 'Active local.7 registration was not completely removed.'}
    foreach($relative in @('runtime-config.json','runtime-status.json')){if(Test-Path -LiteralPath (Join-Path $state $relative)){throw "Uninstall left active state: $relative"}}
    foreach($pidValue in @([int]$oldLive.live.status.runtime_pid,[int]$oldLive.live.status.broker_pid)){
        if(Get-Process -Id $pidValue -ErrorAction SilentlyContinue){throw "Uninstall left runtime process alive: $pidValue"}
    }

    $stage='reinstall-same-package'
    if((Get-FileHash -LiteralPath (Join-Path $archivedPackage 'package-manifest.json')).Hash -ine $expectedManifest -or
        (Get-FileHash -LiteralPath (Join-Path $reinstallPackage 'package-manifest.json')).Hash -ine $expectedManifest -or
        (Get-FileHash -LiteralPath (Join-Path $backup 'backup-manifest.json')).Hash -ine $backupManifestHash){throw 'Fresh recovery media changed during uninstall.'}
    & (Join-Path $reinstallPackage 'Install-YimeCore-Local.cmd')
    $installExit=$LASTEXITCODE
    Write-CommandResult 'Install' $installExit (Join-Path $evidence 'reinstall-output.txt')
    if($installExit -ne 0){throw "Local.7 reinstall failed with exit $installExit; preserve evidence and recovery archive."}
    $reinstalled=$true
    $newConfig=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json
    $newRoot=[IO.Path]::GetFullPath([string]$newConfig.install_root).TrimEnd('\')
    if((Get-FileHash -LiteralPath (Join-Path $newRoot 'package-manifest.json')).Hash -ine $expectedManifest){throw 'Reinstalled package identity mismatch.'}
    $newContext=Assert-LocalProductInstalledContext $newRoot $state
    $newLive=Assert-LocalProductLiveRuntime $newContext
    & (Join-Path $newRoot 'Maintain-YimeCore-Local.cmd') -Action Verify
    $verifyExit=$LASTEXITCODE
    Write-CommandResult 'Verify' $verifyExit (Join-Path $evidence 'verify-output.txt')
    if($verifyExit -ne 0){throw "Reinstalled three-mode verification failed with exit $verifyExit."}
    $afterData=@(Get-YimeCoreDataRecords $state)
    $afterRegistry=Get-CutoverRegistrySnapshot
    Assert-YimeCoreUnchangedData $beforeData $afterData
    $afterActiveUserTip=Read-ActiveUserTip
    Assert-ActiveUserTipEnabled $afterActiveUserTip
    Write-Evidence $afterActiveUserTip (Join-Path $evidence 'active-user-tip-after.json')
    if(-not (Same $beforeActiveUserTip $afterActiveUserTip)){throw 'Active per-user TIP after reinstall differs from the enabled pre-uninstall state.'}
    if(-not (Same (Normalize-RootInSnapshot $beforeRegistry $oldRoot) (Normalize-RootInSnapshot $afterRegistry $newRoot))){throw 'Registry after reinstall differs beyond the allowed install-root replacement.'}
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'state') $backupManifest.state_files
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'previous-package') $backupManifest.package_files
    & (Join-Path $newRoot 'bin\YimeCoreIndependenceAudit.exe') -package $newRoot -output (Join-Path $evidence 'installed-audit-after.json')
    if($LASTEXITCODE -ne 0){throw 'Reinstalled package audit failed.'}
    Write-Evidence $afterData (Join-Path $evidence 'data-after.json')
    Write-Evidence $afterRegistry (Join-Path $evidence 'system-after.json')
    Write-Evidence $newLive (Join-Path $evidence 'live-after.json')
    $passed=$true;$stage='accepted'
    Write-Host "PASS: local.7 uninstalled with data preserved and reinstalled from the pinned complete package. Evidence: $evidence"
}catch{
    $failure=[ordered]@{stage=$stage;message=$_.Exception.Message;type=$_.Exception.GetType().FullName;stack=$_.ScriptStackTrace}
    Write-Evidence $failure (Join-Path $evidence 'failure.json')
    Write-Host "BLOCKED: $stage; $($failure.message) Evidence: $evidence"
    throw
}finally{
    try{
        Write-Evidence ([ordered]@{schema_version='yimecore-local7-uninstall-reinstall-acceptance-v1';passed=$passed;stage=$stage;
            uninstalled=$uninstalled;reinstalled=$reinstalled;candidate_manifest_sha256=$expectedManifest;old_install_root=$oldRoot;new_install_root=$newRoot;
            fresh_backup=$backup;archived_package=(Join-Path $backup 'previous-package');reinstall_package=$reinstallPackage;
            user_data_preserved=$passed;production_components_changed=$false;default_input_method_changed=$false;
            frozen_targets_executed=$false;active_user_tip_enable_after=if($passed){1}else{$null};taskbar_visibility_user_confirmation_required=$passed;reboot_requested=$false;failure=$failure;local_product_ready=$false;public_release_ready=$false}) (Join-Path $evidence 'summary.json')
    }finally{Stop-Transcript|Out-Null}
}
