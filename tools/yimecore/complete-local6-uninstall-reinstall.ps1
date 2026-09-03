[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
$evidence='C:\Users\tsaan\YimeCore Recovery Archives\local6-uninstall-reinstall-20260903-121508-ef668e62'
$expectedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'
$expectedValidator='8f560a009bfead4a3bd8ca736d8b4008e0e0da32a350aeaf0a7fa0f1ad0addb4'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$legacyClsid='{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$trialClsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}'
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$backup=Join-Path $evidence 'preuninstall-backup'
$archivedPackage=Join-Path $backup 'previous-package'
$reinstallPackage=Join-Path $backup 'reinstall-package'
$manifestPath=Join-Path $reinstallPackage 'package-manifest.json'
if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
    (Get-FileHash -LiteralPath $manifestPath).Hash -ine $expectedManifest){throw 'Pinned completion package is missing or changed.'}
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')){
    . (Join-Path $reinstallPackage "maintenance\$name")
}
$package=Assert-LocalProductPackage $reinstallPackage
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
function Restore-RegistryTreeFromSystemSnapshot([string]$Path,$Snapshot){
    if($null -eq $Snapshot -or -not $Snapshot.exists){
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        return
    }
    if(-not (Test-Path -LiteralPath $Path)){New-Item -Path $Path -ErrorAction Stop|Out-Null}
    $key=Get-Item -LiteralPath $Path
    try{$currentValues=@($key.GetValueNames());$currentChildren=@($key.GetSubKeyNames())}finally{$key.Dispose()}
    $expectedValues=@($Snapshot.values|ForEach-Object{[string]$_.name})
    $expectedChildren=@($Snapshot.children.PSObject.Properties|ForEach-Object{$_.Name})
    foreach($name in $currentValues){if($expectedValues -notcontains $name){Remove-ItemProperty -LiteralPath $Path -Name $name -ErrorAction Stop}}
    foreach($value in @($Snapshot.values)){
        New-ItemProperty -LiteralPath $Path -Name ([string]$value.name) -Value $value.value `
            -PropertyType ([Microsoft.Win32.RegistryValueKind]([int]$value.kind)) -Force|Out-Null
    }
    foreach($name in $currentChildren){if($expectedChildren -notcontains $name){Remove-Item -LiteralPath ($Path+'\'+$name) -Recurse -Force -ErrorAction Stop}}
    foreach($child in @($Snapshot.children.PSObject.Properties)){
        Restore-RegistryTreeFromSystemSnapshot ($Path+'\'+$child.Name) $child.Value
    }
}
if(-not $Execute){
    [ordered]@{action='complete-local6-uninstall-reinstall';evidence=$evidence;manifest_sha256=$expectedManifest;
        resume_from='verified partial uninstall';restore_frozen_user_tip=$true;reinstall_from_preserved_package=$true;
        production_components_changed=$false;default_input_method_changed=$false;reboot_requested=$false}|ConvertTo-Json -Depth 6
    exit 0
}
Assert-YimeCoreUnpackagedDataMaintenance
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($identity.User.Value -cne $expectedSid){throw 'Use the Windows account that owns local.6.'}
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use normal File Explorer double-click, not Run as administrator.'}
if(Get-Process WINWORD,Notepad,YimeCoreInputToolbar,YimeCoreSettingsTool,YimeCoreToolCenter -ErrorAction SilentlyContinue){throw 'Close Word, Notepad and YimeCore tools before completion.'}
$originalSummary=Get-Content -LiteralPath (Join-Path $evidence 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($originalSummary.stage -cne 'uninstall-preserve-data' -or $originalSummary.uninstalled -or $originalSummary.reinstalled -or
    [string]$originalSummary.candidate_manifest_sha256 -ine $expectedManifest){throw 'Evidence is not the reviewed partial-uninstall failure.'}
$oldRoot=[IO.Path]::GetFullPath([string]$originalSummary.old_install_root).TrimEnd('\')
$beforeRegistry=Get-Content -LiteralPath (Join-Path $evidence 'system-before.json') -Raw -Encoding UTF8|ConvertFrom-Json
$beforeData=Get-Content -LiteralPath (Join-Path $evidence 'data-before.json') -Raw -Encoding UTF8|ConvertFrom-Json
$backupManifest=Get-Content -LiteralPath (Join-Path $backup 'backup-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$backupManifestHash=(Get-FileHash -LiteralPath (Join-Path $backup 'backup-manifest.json')).Hash.ToLowerInvariant()
$stage='verify-partial-uninstall';$passed=$false;$failure=$null;$newRoot=$null;$tipRestored=$false;$reinstalled=$false
Start-Transcript -LiteralPath (Join-Path $evidence 'completion-transcript.txt') -Append|Out-Null
try{
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'state') $backupManifest.state_files
    Assert-YimeCoreArchiveRecords $archivedPackage $backupManifest.package_files
    $currentData=@(Get-YimeCoreDataRecords $state)
    Assert-YimeCoreUnchangedData $beforeData $currentData
    if((Test-Path -LiteralPath $oldRoot) -or
        (Test-Path -LiteralPath (Join-Path $state 'runtime-config.json')) -or
        (Test-Path -LiteralPath (Join-Path $state 'runtime-status.json')) -or
        (Get-Process YimeCoreTrialRuntime,YimeBroker -ErrorAction SilentlyContinue)){throw 'Partial uninstall no longer has the reviewed stopped and root-absent state.'}
    $absenceOutput=(& (Join-Path $reinstallPackage 'x64\YimeTextServiceRegistration.exe') verify-absent 2>&1)-join "`n"
    $absenceExit=$LASTEXITCODE
    $absenceOutput|Set-Content -LiteralPath (Join-Path $evidence 'registration-absence-before-completion.txt') -Encoding UTF8
    if($absenceExit -ne 0){throw 'Native registration is not semantically absent after partial uninstall.'}
    $legacyUserPath="Software\Microsoft\CTF\TIP\$legacyClsid"
    $legacyUserSnapshot=$beforeRegistry.protected.PSObject.Properties[$legacyUserPath].Value
    if($null -eq $legacyUserSnapshot -or -not $legacyUserSnapshot.exists){throw 'Original frozen user TIP snapshot is unavailable.'}
    Restore-RegistryTreeFromSystemSnapshot "Registry::HKEY_USERS\$expectedSid\$legacyUserPath" $legacyUserSnapshot
    $midRegistry=Get-CutoverRegistrySnapshot
    if(-not (Same $beforeRegistry.protected $midRegistry.protected)){throw 'Protected registry did not return to the pre-uninstall snapshot.'}
    $tipRestored=$true
    Write-Evidence $midRegistry (Join-Path $evidence 'system-after-tip-restore-before-reinstall.json')
    if($midRegistry.native_com.exists -or
        -not (Test-TipSnapshotSemanticallyAbsent $midRegistry.native_tip $trialClsid) -or
        -not (Test-TipSnapshotSemanticallyAbsent $midRegistry.mirrored_tip $trialClsid) -or
        @($midRegistry.trial_run).Count -ne 0 -or $midRegistry.uninstall.exists){throw 'Local.6 registration is not fully absent before reinstall.'}
    Write-Evidence $midRegistry (Join-Path $evidence 'system-uninstalled.json')
    Write-Evidence $currentData (Join-Path $evidence 'data-uninstalled.json')

    $stage='reinstall-same-package'
    if((Get-FileHash -LiteralPath $manifestPath).Hash -ine $expectedManifest -or
        (Get-FileHash -LiteralPath (Join-Path $backup 'backup-manifest.json')).Hash -ine $backupManifestHash){throw 'Recovery media changed before completion install.'}
    & (Join-Path $reinstallPackage 'Install-YimeCore-Local.cmd')
    $installExit=$LASTEXITCODE
    @('command=Install',"exit_code=$installExit")|Set-Content -LiteralPath (Join-Path $evidence 'completion-install-output.txt') -Encoding ASCII
    if($installExit -ne 0){throw "Local.6 completion install failed with exit $installExit."}
    $reinstalled=$true
    $newConfig=Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $newRoot=[IO.Path]::GetFullPath([string]$newConfig.install_root).TrimEnd('\')
    if((Get-FileHash -LiteralPath (Join-Path $newRoot 'package-manifest.json')).Hash -ine $expectedManifest){throw 'Completed install package identity mismatch.'}
    $newContext=Assert-LocalProductInstalledContext $newRoot $state
    $newLive=Assert-LocalProductLiveRuntime $newContext
    & (Join-Path $newRoot 'Maintain-YimeCore-Local.cmd') -Action Verify
    $verifyExit=$LASTEXITCODE
    @('command=Verify',"exit_code=$verifyExit")|Set-Content -LiteralPath (Join-Path $evidence 'completion-verify-output.txt') -Encoding ASCII
    if($verifyExit -ne 0){throw "Completed local.6 verification failed with exit $verifyExit."}
    $afterData=@(Get-YimeCoreDataRecords $state)
    $afterRegistry=Get-CutoverRegistrySnapshot
    Assert-YimeCoreUnchangedData $beforeData $afterData
    if(-not (Same (Normalize-RootInSnapshot $beforeRegistry $oldRoot) (Normalize-RootInSnapshot $afterRegistry $newRoot))){throw 'Registry after completion differs beyond the allowed install-root replacement.'}
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'state') $backupManifest.state_files
    Assert-YimeCoreArchiveRecords $archivedPackage $backupManifest.package_files
    & (Join-Path $newRoot 'bin\YimeCoreIndependenceAudit.exe') -package $newRoot -output (Join-Path $evidence 'installed-audit-after.json')
    if($LASTEXITCODE -ne 0){throw 'Completed installed package audit failed.'}
    Write-Evidence $afterData (Join-Path $evidence 'data-after.json')
    Write-Evidence $afterRegistry (Join-Path $evidence 'system-after.json')
    Write-Evidence $newLive (Join-Path $evidence 'live-after.json')
    $passed=$true;$stage='accepted'
}catch{
    $failure=[ordered]@{stage=$stage;message=$_.Exception.Message;type=$_.Exception.GetType().FullName;stack=$_.ScriptStackTrace}
    Write-Evidence $failure (Join-Path $evidence 'completion-failure.json')
}finally{
    $completion=[ordered]@{schema_version='yimecore-local6-uninstall-reinstall-completion-v1';passed=$passed;stage=$stage;
        resumed_from_failure='failure.json';uninstalled=$true;reinstalled=$reinstalled;frozen_user_tip_restored=$tipRestored;
        candidate_manifest_sha256=$expectedManifest;old_install_root=$oldRoot;new_install_root=$newRoot;fresh_backup=$backup;
        user_data_preserved=$passed;production_components_changed=$false;default_input_method_changed=$false;
        frozen_targets_executed=$false;reboot_requested=$false;failure=$failure;local_product_ready=$false;public_release_ready=$false}
    Write-Evidence $completion (Join-Path $evidence 'completion-summary.json')
    if($passed){Write-Evidence $completion (Join-Path $evidence 'summary.json')}
    Stop-Transcript|Out-Null
}
if(-not $passed){Write-Host "BLOCKED: $stage; $($failure.message) Evidence: $evidence";exit 1}
Write-Host "PASS: local.6 uninstall gap verified, frozen user TIP restored, user data preserved, and pinned complete package reinstalled. Evidence: $evidence"
