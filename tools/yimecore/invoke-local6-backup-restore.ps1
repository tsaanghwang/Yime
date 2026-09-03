[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
$expectedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'
$expectedValidator='8f560a009bfead4a3bd8ca736d8b4008e0e0da32a350aeaf0a7fa0f1ad0addb4'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$config=Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
$installed=[IO.Path]::GetFullPath([string]$config.install_root).TrimEnd('\')
$manifestPath=Join-Path $installed 'package-manifest.json'
if((Get-FileHash -LiteralPath $manifestPath).Hash -ine $expectedManifest){throw 'Current install is not the reviewed local.6 package.'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')){
    $path=Join-Path $installed "maintenance\$name"
    $record=@($manifest.files|Where-Object{$_.path -ceq "maintenance/$name"})
    if($record.Count -ne 1 -or (Get-FileHash -LiteralPath $path).Hash -ine $record[0].sha256){throw "Installed helper mismatch: $name"}
    . $path
}
$context=Assert-LocalProductInstalledContext $installed $state
$plan=[ordered]@{action='local6-fresh-backup-restore';package_root=$installed;manifest_sha256=$expectedManifest;
    target_sid=$expectedSid;restore_scope='user model and listed settings only';registry_mutation_requested=$false;
    production_components_changed=$false;default_input_method_changed=$false;reboot_requested=$false}
if(-not $Execute){$plan|ConvertTo-Json -Depth 6;exit 0}
Assert-YimeCoreUnpackagedDataMaintenance
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $expectedSid){throw 'Use the Windows account that owns local.6.'}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use normal File Explorer double-click, not Run as administrator.'}
if(Get-Process WINWORD,Notepad -ErrorAction SilentlyContinue){throw 'Save and close Word and Notepad before backup/restore acceptance.'}
$null=Assert-LocalProductLiveRuntime $context

$validator=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
if((Get-FileHash -LiteralPath $validator).Hash -ine $expectedValidator){throw 'Read-only registry validator changed; review before restore.'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($validator,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-CutoverRegistrySnapshot'},$true)
if(-not $fn){throw 'Missing read-only registry snapshot helper.'}
. ([scriptblock]::Create($fn.Extent.Text))
function Write-Evidence($Value,[string]$Path){$Value|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $Path -Encoding UTF8}
function Same($Left,$Right){return (($Left|ConvertTo-Json -Depth 40 -Compress) -ceq ($Right|ConvertTo-Json -Depth 40 -Compress))}
function Get-ExceptionEvidence([Exception]$Exception){
    $result=@();$current=$Exception
    while($current){
        $nativeCode=$null
        if($current -is [ComponentModel.Win32Exception]){$nativeCode=$current.NativeErrorCode}
        $result+=[ordered]@{type=$current.GetType().FullName;message=$current.Message;hresult=$current.HResult;native_error_code=$nativeCode}
        $current=$current.InnerException
    }
    return $result
}
$archive=Join-Path $env:USERPROFILE ('YimeCore Recovery Archives\local6-backup-restore-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
Assert-YimeCorePlainPath $archive
$stage='capture-before';$passed=$false;$backupPassed=$false;$restorePassed=$false;$failure=$null;$beforeRegistry=$null;$beforeData=$null
try{
    $beforeRegistry=Get-CutoverRegistrySnapshot
    $beforeData=@(Get-YimeCoreDataRecords $state)
    $stage='fresh-backup'
    & (Join-Path $installed 'Maintain-YimeCore-Local.cmd') -Action Backup -BackupRoot $archive
    if($LASTEXITCODE -ne 0){throw "Installed package backup failed with exit code $LASTEXITCODE."}
    $backupPassed=$true
    Write-Evidence $plan (Join-Path $archive 'acceptance-plan.json')
    Write-Evidence $beforeRegistry (Join-Path $archive 'system-before.json')
    Write-Evidence $beforeData (Join-Path $archive 'data-before.json')
    $stage='live-restore'
    & (Join-Path $installed 'Maintain-YimeCore-Local.cmd') -Action Restore -BackupRoot $archive
    if($LASTEXITCODE -ne 0){throw "Installed package restore failed with exit code $LASTEXITCODE."}
    $restorePassed=$true
    $stage='verify-after'
    $afterData=@(Get-YimeCoreDataRecords $state)
    Assert-YimeCoreUnchangedData $beforeData $afterData
    Write-Evidence $afterData (Join-Path $archive 'data-after.json')
    $afterRegistry=Get-CutoverRegistrySnapshot
    Write-Evidence $afterRegistry (Join-Path $archive 'system-after.json')
    if(-not (Same $beforeRegistry $afterRegistry)){throw 'Registry changed during data-only backup/restore.'}
    $afterContext=Assert-LocalProductInstalledContext $installed $state
    $liveAfter=Assert-LocalProductLiveRuntime $afterContext
    Write-Evidence $liveAfter (Join-Path $archive 'live-runtime-after.json')
    & (Join-Path $installed 'Maintain-YimeCore-Local.cmd') -Action Verify
    if($LASTEXITCODE -ne 0){throw 'Post-restore three-mode verification failed.'}
    $restoreEvidence=Get-Content -LiteralPath (Join-Path $archive 'restore-evidence.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $restoreEvidence.passed -or -not $restoreEvidence.live_data_restored -or -not $restoreEvidence.all_restored_hashes_match){throw 'Package restore evidence is incomplete.'}
    $passed=$true;$stage='local6-backup-restore-accepted'
}catch{
    $failure=[ordered]@{stage=$stage;message=$_.Exception.Message;type=$_.Exception.GetType().FullName;stack=$_.ScriptStackTrace;
        exception_chain=@(Get-ExceptionEvidence $_.Exception)}
    if(Test-Path -LiteralPath $archive){Write-Evidence $failure (Join-Path $archive 'acceptance-failure.json')}
}
if(Test-Path -LiteralPath $archive){
    Write-Evidence ([ordered]@{schema_version='yimecore-local6-backup-restore-acceptance-v1';passed=$passed;stage=$stage;failure=$failure;
        package_root=$installed;manifest_sha256=$expectedManifest;backup_passed=$backupPassed;restore_passed=$restorePassed;
        user_data_hashes_preserved=$passed;original_model_preserved=$passed;registry_unchanged=$passed;ordinary_runtime_verified=$passed;
        production_components_changed=$false;default_input_method_changed=$false;reboot_requested=$false;
        local_product_ready=$false;public_release_ready=$false}) (Join-Path $archive 'acceptance-summary.json')
}
if(-not $passed){Write-Host "BLOCKED: $stage; $($failure.message) Evidence: $archive";exit 1}
Write-Host "PASS: local.6 fresh backup, live restore, data hashes, registry and ordinary runtime verified. Evidence: $archive"
