[CmdletBinding()]
param([switch]$Execute,[switch]$Worker,[string]$EvidenceRoot,[string]$ExpectedSourceHash)
$ErrorActionPreference='Stop'
$installed='C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-4bfa828009d1-2631aeb3'
$archive='C:\Users\tsaan\YimeCore Recovery Archives\local-product-install-20260903-094523-3cadc5b7'
$manifestHash='2631aeb3634f6bc103771e12e3a8d6748bd87123f890afb2ae874b1d06706c7a'
$beforeHash='f30f66b791fe7aed9397575752a8c6683e7d4bc0d440a3083154ea9c255ded45'
$afterHash='443eeb4c52edcc17f6921fd7150d669dbe75873a903dd0285311e944a726fdf8'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$newClsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}'
$legacyClsid='{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$newWow="SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$newClsid"
$legacyUser="Software\Microsoft\CTF\TIP\$legacyClsid"
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$manifestPath=Join-Path $installed 'package-manifest.json'
if((Get-FileHash -LiteralPath $manifestPath).Hash -ine $manifestHash){throw 'Installed local.5 package is not the pinned migration result.'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')){
    $path=Join-Path $installed "maintenance\$name"
    $record=@($manifest.files|Where-Object{$_.path -ceq "maintenance/$name"})
    if($record.Count -ne 1 -or (Get-FileHash -LiteralPath $path).Hash -ine $record[0].sha256){throw "Installed helper mismatch: $name"}
    . $path
}
$null=Assert-LocalProductPackage $installed
$null=Get-YimeCoreDevelopmentScope
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $expectedSid){throw 'Use the Windows account that initiated the migration.'}
$administrator=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($Execute){Assert-YimeCoreUnpackagedDataMaintenance}
if($Execute -and $PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
if($Execute -and $administrator -and -not $Worker){throw 'Use normal File Explorer double-click, not Run as administrator.'}
if(($Worker -or $EvidenceRoot -or $ExpectedSourceHash) -and -not ($Execute -and $Worker -and $administrator -and $EvidenceRoot -and $ExpectedSourceHash)){throw 'Incomplete internal repair arguments.'}

$acceptance=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
$sources=@($PSCommandPath,$acceptance|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})
$digest=[Security.Cryptography.SHA256]::Create()
try{$sourceHash=([BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes(($sources|ConvertTo-Json -Compress))))).Replace('-','').ToLowerInvariant()}
finally{$digest.Dispose()}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($acceptance,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Get-CutoverRegistrySnapshot','Require-CutoverValue','Assert-CutoverRegistry')){
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $fn){throw "Missing validator: $name"}
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Read-Pinned([string]$Name,[string]$Hash){
    $path=Join-Path $archive $Name
    $null=Assert-YimeCoreNativeFile $path
    if((Get-FileHash -LiteralPath $path).Hash -ine $Hash){throw "Migration evidence changed: $Name"}
    Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
}
function Convert-BeforeShape($Value){
    $copy=$Value|ConvertTo-Json -Depth 40|ConvertFrom-Json
    $language=$copy.protected.'Control Panel\International\User Profile'
    $mirrored=$copy.protected.$newWow
    $copy.protected.PSObject.Properties.Remove('Control Panel\International\User Profile')
    $copy.protected.PSObject.Properties.Remove($newWow)
    $copy|Add-Member -NotePropertyName language_profile -NotePropertyValue $language
    $copy|Add-Member -NotePropertyName mirrored_tip -NotePropertyValue $mirrored
    return $copy
}
function Same($Left,$Right){return (($Left|ConvertTo-Json -Depth 40 -Compress) -ceq ($Right|ConvertTo-Json -Depth 40 -Compress))}
function Write-Json($Value,[string]$Name){$Value|ConvertTo-Json -Depth 40|Set-Content -LiteralPath (Join-Path $EvidenceRoot $Name) -Encoding UTF8}
function Restore-Tree([Microsoft.Win32.RegistryKey]$Base,[string]$Path,$Snapshot){
    $cut=$Path.LastIndexOf('\')
    if($cut -lt 1){throw "Unsafe registry repair path: $Path"}
    $parentPath=$Path.Substring(0,$cut);$leaf=$Path.Substring($cut+1)
    $parent=$Base.OpenSubKey($parentPath,$true)
    if(-not $parent){throw "Registry repair parent missing: $parentPath"}
    try{$parent.DeleteSubKeyTree($leaf,$false)}finally{$parent.Dispose()}
    if(-not $Snapshot.exists){return}
    $key=$Base.CreateSubKey($Path,$true)
    try{
        foreach($value in @($Snapshot.values)){$key.SetValue([string]$value.name,$value.value,[Microsoft.Win32.RegistryValueKind]([int]$value.kind))}
    }finally{$key.Dispose()}
    foreach($child in $Snapshot.children.PSObject.Properties){Restore-Tree $Base ($Path+'\'+$child.Name) $child.Value}
}
$beforeRaw=Read-Pinned 'system-before.json' $beforeHash
$afterRaw=Read-Pinned 'system-after.json' $afterHash
$before=Convert-BeforeShape $beforeRaw
$expectedNewWow=$afterRaw.protected.$newWow
$expectedLegacyUser=$afterRaw.protected.$legacyUser
$current=Get-CutoverRegistrySnapshot
if(-not (Same $current.mirrored_tip $expectedNewWow)){throw 'Shared TSF profile mirror changed since migration evidence; refuse repair.'}
if(-not (Same $current.protected.$legacyUser $expectedLegacyUser)){throw 'Legacy per-user TIP changed since migration evidence; refuse repair.'}
$projected=$current|ConvertTo-Json -Depth 40|ConvertFrom-Json
$projected.protected.$legacyUser=$before.protected.$legacyUser
$descriptor=Get-Content -LiteralPath (Join-Path $installed 'local-product.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert-CutoverRegistry $before $projected $installed ([string]$descriptor.display_name) $expectedSid $state
$operations=@([ordered]@{operation='restore-tree';hive='HKEY_USERS';path="$expectedSid\$legacyUser";from='pinned pre-migration snapshot'})
if(-not $Execute){[ordered]@{action='local5-identity-repair-plan';operations=$operations;writes_requested=$false;reinstall=$false;reboot=$false}|ConvertTo-Json -Depth 8;exit 0}
$archiveBase=Join-Path $env:USERPROFILE 'YimeCore Recovery Archives'
if(-not $Worker){
    $EvidenceRoot=Join-Path $archiveBase ('local5-identity-repair-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    Assert-YimeCorePlainPath $EvidenceRoot
    if(Test-Path -LiteralPath $EvidenceRoot){throw 'Repair evidence root must be new.'}
    New-Item -ItemType Directory -Path $EvidenceRoot|Out-Null
    Write-Json ([ordered]@{sid=$expectedSid;source_set_sha256=$sourceHash;sources=$sources;installed_manifest_sha256=$manifestHash;migration_archive=$archive}) 'initiator.json'
    Write-Json $current 'system-before.json';Write-Json $operations 'operations.json'
    $process=$null;$result=$null;$parentFailure=$null
    try{
        $preflightContext=Assert-LocalProductInstalledContext $installed $state
        $preflightLive=Assert-LocalProductLiveRuntime $preflightContext
        Write-Json $preflightLive 'live-runtime-before.json'
        $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $args='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Execute -Worker -EvidenceRoot "'+$EvidenceRoot+'" -ExpectedSourceHash "'+$sourceHash+'"'
        $process=Start-Process -FilePath $ps -ArgumentList $args -Verb RunAs -WindowStyle Hidden -PassThru
        $process.WaitForExit()
        $workerSummary=Join-Path $EvidenceRoot 'worker-summary.json'
        if(-not (Test-Path -LiteralPath $workerSummary)){throw "Repair worker exited $($process.ExitCode) without evidence."}
        $result=Get-Content -LiteralPath $workerSummary -Raw -Encoding UTF8|ConvertFrom-Json
        if($process.ExitCode -ne 0 -or -not $result.passed){throw "Repair failed: $($result.failure)"}
        $verified=Get-CutoverRegistrySnapshot
        Assert-CutoverRegistry $before $verified $installed ([string]$descriptor.display_name) $expectedSid $state
        Write-Json $verified 'system-after-parent.json'
        $context=Assert-LocalProductInstalledContext $installed $state
        $live=Assert-LocalProductLiveRuntime $context
        Write-Json $live 'live-runtime-after.json'
        Write-Json ([ordered]@{passed=$true;failure=$null;rolled_back=$false;worker_passed=$true;parent_runtime_verified=$true;
            installed_manifest_sha256=$manifestHash;active_x64_identity='{E40FA752-BB96-461D-A51D-F40EB437EC65}/{126F54C6-E9B1-4E22-8652-03224CBD49F9}';
            frozen_legacy_identity_preserved=$true;shared_tsf_profile_mirror_verified=$true;new_wow64_com_server_absent=$true;default_input_method_changed=$false;
            production_rime_pime_changed=$false;reinstall_performed=$false;reboot_requested=$false;local_product_ready=$true}) 'summary.json'
        Write-Host "PASS: local.5 identity migration repaired and verified. Evidence: $EvidenceRoot"
    }catch{
        $parentFailure=$_.Exception.Message
        Write-Json ([ordered]@{passed=$false;failure=$parentFailure;rolled_back=if($result){[bool]$result.rolled_back}else{$false};
            worker_passed=if($result){[bool]$result.passed}else{$false};parent_runtime_verified=$false;registry_repair_applied=if($result){[bool]$result.passed}else{$false};
            installed_manifest_sha256=$manifestHash;default_input_method_changed=$false;production_rime_pime_changed=$false;reinstall_performed=$false;reboot_requested=$false;local_product_ready=$false}) 'summary.json'
        Write-Host "BLOCKED: local.5 identity repair failed: $parentFailure Evidence: $EvidenceRoot"
    }finally{if($process){$process.Dispose()}}
    if($parentFailure){exit 1}
    exit 0
}
$EvidenceRoot=[IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\')
if((Split-Path -Parent $EvidenceRoot) -ine $archiveBase -or (Split-Path -Leaf $EvidenceRoot) -notmatch '^local5-identity-repair-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$'){throw 'Unexpected repair evidence root.'}
Assert-YimeCorePlainPath $EvidenceRoot
$origin=Get-Content -LiteralPath (Join-Path $EvidenceRoot 'initiator.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($sourceHash -cne $ExpectedSourceHash -or $origin.source_set_sha256 -cne $sourceHash -or $origin.sid -cne $expectedSid){throw 'Repair source or user changed across UAC.'}
if(Test-Path -LiteralPath (Join-Path $EvidenceRoot 'worker-summary.json')){throw 'Do not reuse repair evidence.'}
$users=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::Users,[Microsoft.Win32.RegistryView]::Registry64)
$passed=$false;$failure=$null;$rolledBack=$false
try{
    Restore-Tree $users "$expectedSid\$legacyUser" $before.protected.$legacyUser
    $verified=Get-CutoverRegistrySnapshot
    Assert-CutoverRegistry $before $verified $installed ([string]$descriptor.display_name) $expectedSid $state
    Write-Json $verified 'system-after.json'
    $passed=$true
}catch{
    $failure=$_.Exception.Message
    try{
        Restore-Tree $users "$expectedSid\$legacyUser" $expectedLegacyUser
        $rolledBack=$true
    }catch{$failure+='; rollback failed: '+$_.Exception.Message}
}finally{
    $users.Dispose()
    Write-Json ([ordered]@{passed=$passed;failure=$failure;rolled_back=$rolledBack;installed_manifest_sha256=$manifestHash;
        active_x64_identity='{E40FA752-BB96-461D-A51D-F40EB437EC65}/{126F54C6-E9B1-4E22-8652-03224CBD49F9}';
        frozen_legacy_identity_preserved=$passed;shared_tsf_profile_mirror_verified=$passed;new_wow64_com_server_absent=$passed;default_input_method_changed=$false;
        production_rime_pime_changed=$false;reinstall_performed=$false;reboot_requested=$false;local_product_ready=$false}) 'worker-summary.json'
}
if(-not $passed){exit 1}
