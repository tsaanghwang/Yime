[CmdletBinding()]param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=[IO.Path]::GetFullPath($OutputPath)
if(-not $out.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Fresh repository .tmp test output required'}
$cursor=Split-Path -Parent $out
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect test output'};$cursor=Split-Path -Parent $cursor}
[IO.Directory]::CreateDirectory((Split-Path -Parent $out))|Out-Null
$root=Join-Path (Split-Path -Parent $out) ('backup-owned-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$modulePath=Join-Path $PSScriptRoot 'native-maintenance-backup.psm1'
$module=Import-Module $modulePath -Force -PassThru
$checks=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Passed,[string]$Name){if(-not $Passed){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Body,[string]$Name){$caught=$false;try{& $Body|Out-Null}catch{$caught=$true};Check $caught $Name}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Text([string]$Path,[string]$Value){[IO.Directory]::CreateDirectory((Split-Path -Parent $Path))|Out-Null;[IO.File]::WriteAllText($Path,$Value,[Text.UTF8Encoding]::new($false))}
function Json([string]$Path,$Value,[bool]$Bom=$false){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($Bom))}
function Rows([string]$Path){@(Get-ChildItem -LiteralPath $Path -Recurse -File|ForEach-Object {[ordered]@{path=$_.FullName.Substring($Path.Length+1).Replace('\','/');bytes=$_.Length;sha256=Hash $_.FullName}}|Sort-Object { $_.path })}
function Refresh($Fixture,[switch]$Package){
    if($Package){Json (Join-Path $Fixture.package 'package-manifest.json') $Fixture.previous;$Fixture.call.ExpectedPreviousManifestSha256=Hash (Join-Path $Fixture.package 'package-manifest.json');$Fixture.marker.package_manifest_sha256=$Fixture.call.ExpectedPreviousManifestSha256;Json (Join-Path $Fixture.package 'install-metadata.json') $Fixture.marker}
    $Fixture.manifest.state_files=Rows $Fixture.state;$Fixture.manifest.package_files=Rows $Fixture.package
    $Fixture.manifest.data_files=@($Fixture.manifest.state_files|Where-Object {$_.path.StartsWith('user-model/') -or $_.path -ceq 'speech.json'})
    Json $Fixture.manifestPath $Fixture.manifest
}
function Fixture {
    $base=Join-Path $root ([guid]::NewGuid().ToString('N'));$state=Join-Path $base 'state';$package=Join-Path $base 'previous-package'
    foreach($path in @($state,$package)){[IO.Directory]::CreateDirectory($path)|Out-Null}
    foreach($n in 1..74){Text (Join-Path $package ('payload/member-'+$n+'.txt')) "not executable; synthetic public payload $n"}
    Text (Join-Path $state 'user-model/full/user-model.journal') 'PRIVATE SYNTHETIC BODY NEVER RETURN'
    Text (Join-Path $state 'speech.json') '{"enabled":false}'
    Text (Join-Path $state 'runtime-config.json') 'config bytes only, not parsed'
    Text (Join-Path $state 'diagnostics.log') 'diagnostic bytes only, not returned'
    $previous=[ordered]@{package_contract='yimecore-local-product-package-v1';tool_version='yimecore-local-builder-v1';product_version='0.1.0-local.12';package_id='synthetic-local12';files=(Rows $package)}
    $call=@{BackupRoot=$base;ExpectedStateRoot='C:\SyntheticBackupInput\state';ExpectedInstallRoot='C:\SyntheticBackupInput\installed';ExpectedPreviousManifestSha256=('a'*64);ActualBackupExitCode=0}
    $marker=[ordered]@{schema_version='yimecore-trial-install-v1';product_key='YimeCoreExperimentalTrial';install_root=$call.ExpectedInstallRoot;package_manifest_sha256=('a'*64)}
    $scope=[ordered]@{id='mainstream-x64-arm64-resumed-2026-09-04';computer_name='MYCOMPUTER';native_architecture='AMD64';active_architectures=@('x64','x86');performance_profile='development_host_x64';frozen_targets=@('forward_physical_pcs','simulated_hardware_tiers');experiment_targets=@();policy_sha256=('b'*64)}
    $manifest=[ordered]@{schema_version='yimecore-quiesced-backup-v1';generated_at=[DateTime]::UtcNow.ToString('o');development_scope=$scope;source_state_root=$call.ExpectedStateRoot;source_install_root=$call.ExpectedInstallRoot;
        runtime_pid_before=1234;broker_pid_before=1235;writers_stopped=$true;source_stable_during_copy=$true;state_files=@();package_files=@();native_context_verified=$true;
        live_runtime_before=@{passed=$true;status=@{state='running';duration=0.25}};data_files=@();backup_root=$base;passed=$true}
    $fixture=@{root=$base;state=$state;package=$package;previous=$previous;marker=$marker;manifest=$manifest;manifestPath=(Join-Path $base 'backup-manifest.json');call=$call}
    Refresh $fixture -Package;return $fixture
}
# Hashtable splatting is deliberately explicit; no public fixture/provider API.
function Invoke-Fixture($Fixture){$args=$Fixture.call;Read-YimeCoreNativeMaintenanceBackup @args}
function Reject-Manifest($Fixture,[string]$Name){Json $Fixture.manifestPath $Fixture.manifest;Reject {Invoke-Fixture $Fixture} $Name}

$valid=Fixture
$value=Invoke-Fixture $valid
Check ($value.static_backup_verified -and $value.package_file_count -eq 76 -and $value.state_file_count -eq 4) 'complete quiesced state and local12 74+2 package accepted'
Check ($value.previous_package_manifest.files.Count -eq 74 -and $value.previous_manifest.sha256 -ceq $valid.call.ExpectedPreviousManifestSha256) 'previous manifest and full listed hashes available for process-image bindings'
Check ($value.state_reference.records.Count -eq 4 -and $value.data_reference.records.Count -eq 2) 'complete state inventory and exact user-data subset remain separate'
Check ($value.state_reference.directories.Count -eq 2 -and $value.state_reference.directories[0] -ceq 'user-model' -and $value.state_reference.directories[1] -ceq 'user-model/full') 'verified directory inventory returned separately from manifest file records'
$empty=Fixture
foreach($relative in @('speech.json','user-model/full/user-model.journal')){Remove-Item -LiteralPath (Join-Path $empty.state $relative)}
Refresh $empty
$emptyResult=Invoke-Fixture $empty
Check ($emptyResult.static_backup_verified -and $emptyResult.data_reference.records.Count -eq 0) 'empty complete data subset accepted without inventing user data'
Check (($value|ConvertTo-Json -Depth 30) -notmatch 'PRIVATE SYNTHETIC BODY NEVER RETURN|config bytes only|diagnostic bytes only') 'receipt never returns state or package file bodies'
$private=Fixture
$private.manifest.live_runtime_before.status.private='EMBEDDED STATUS BODY NEVER RETURN'
$private.previous.extra='UNVALIDATED PACKAGE BODY NEVER RETURN'
Refresh $private -Package
$projected=Invoke-Fixture $private
Check (($projected|ConvertTo-Json -Depth 30) -notmatch 'EMBEDDED STATUS BODY NEVER RETURN|UNVALIDATED PACKAGE BODY NEVER RETURN') 'embedded runtime diagnostics and unvalidated package extras never escape receipt'
Check ($projected.manifest.PSObject.Properties.Name -cnotcontains 'live_runtime_before' -and $projected.previous_package_manifest.PSObject.Properties.Name -cnotcontains 'extra' -and $projected.manifest.package_files.Count -eq 76) 'receipt uses explicit metadata projections while retaining verified package records'
foreach($flag in @('actual_backup_exit_os_authenticated','runtime_restart_verified','native_context_authenticated','independent_system_visibility_verified','loaded_helper_identity_authenticated','continuous_membership_protection','execution_authorized','ready_to_execute','L6_sealed','local_product_ready','public_release_ready')){Check ($value.$flag -is [bool] -and -not $value.$flag) ('honest false '+$flag)}
Check ($value.all_files_held_through_verification -and $value.leases_released_on_return) 'full read interval is bounded and leases released'
$probe=[IO.File]::Open($valid.manifestPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$probe.Dispose()
Check ($true) 'manifest handle released after successful read'
Json $valid.manifestPath $valid.manifest $true
Check (Invoke-Fixture $valid).static_backup_verified 'actual PS5 UTF8 BOM accepted'
Check (@($module.ExportedFunctions.Keys).Count -eq 1) 'only one read API exported'
foreach($bad in @('0',@([int]0),$null,[double]0,$false,1,20,26,-1)){$call=$valid.call.Clone();$call.ActualBackupExitCode=$bad;Reject {Read-YimeCoreNativeMaintenanceBackup @call} ('reject nonliteral or nonzero supplied exit '+$checks.Count)}
foreach($binding in @('ExpectedStateRoot','ExpectedInstallRoot','BackupRoot','ExpectedPreviousManifestSha256')){
    $call=$valid.call.Clone();$call[$binding]=if($binding.EndsWith('Sha256')){'d'*64}else{'C:\OtherSyntheticRoot'}
    Reject {Read-YimeCoreNativeMaintenanceBackup @call} ('reject changed external binding '+$binding)
    $call=$valid.call.Clone();$call[$binding]=@($call[$binding]);Reject {Read-YimeCoreNativeMaintenanceBackup @call} ('reject array external binding '+$binding)
}
foreach($field in @($valid.manifest.Keys)){$f=Fixture;$f.manifest.Remove($field);Reject-Manifest $f ('reject missing manifest '+$field)}
foreach($field in @('passed','writers_stopped','native_context_verified','source_stable_during_copy')){
    foreach($bad in @('true',@($true),$false,1,$null)){$f=Fixture;$f.manifest[$field]=$bad;Reject-Manifest $f ('reject coerced or false '+$field+' '+$checks.Count)}
}
foreach($field in @('schema_version','generated_at','source_state_root','source_install_root','backup_root','runtime_pid_before','broker_pid_before')){$f=Fixture;$f.manifest[$field]=@($f.manifest[$field]);Reject-Manifest $f ('reject array manifest binding '+$field)}
foreach($field in @('state_files','package_files','data_files')){
    $f=Fixture;$f.manifest[$field]=@($f.manifest[$field]|Select-Object -Skip 1);Reject-Manifest $f ('reject incomplete '+$field)
    $f=Fixture;$f.manifest[$field]=@($f.manifest[$field])+@($f.manifest[$field][0]);Reject-Manifest $f ('reject duplicate '+$field)
    $f=Fixture;$first=$f.manifest[$field][0];$copy=[ordered]@{path=$first.path.ToUpperInvariant();bytes=$first.bytes;sha256=$first.sha256};$f.manifest[$field]=@($f.manifest[$field])+@($copy);Reject-Manifest $f ('reject case collision '+$field)
    foreach($property in @('path','sha256','bytes')){$f=Fixture;$f.manifest[$field][0][$property]=@($f.manifest[$field][0][$property]);Reject-Manifest $f ('reject record array '+$field+'.'+$property)}
}
foreach($bad in @('../escape','user-model/../../escape','C:/escape','/escape','user-model\escape','payload/a:stream','payload/a.','payload/CON.txt','payload/a|b')){$f=Fixture;$f.manifest.state_files[0].path=$bad;Reject-Manifest $f ('reject member escape '+$bad)}
foreach($tree in @('state','package')){
    $f=Fixture;Text (Join-Path $f[$tree] 'extra.txt') 'unlisted';Reject {Invoke-Fixture $f} ('reject unlisted '+$tree+' file')
    $f=Fixture;$file=@(Get-ChildItem $f[$tree] -Recurse -File)[0].FullName;Text $file 'changed bytes';Reject {Invoke-Fixture $f} ('reject changed '+$tree+' file')
    $f=Fixture;$file=@(Get-ChildItem $f[$tree] -Recurse -File)[0].FullName;Remove-Item -LiteralPath $file;Reject {Invoke-Fixture $f} ('reject missing '+$tree+' file')
}
$f=Fixture;Text (Join-Path $f.package 'extra.txt') 'rehashed unlisted';Refresh $f;Reject {Invoke-Fixture $f} 'package_files cannot authorize extra payload even with valid hash'
$f=Fixture;$f.previous.files=@($f.previous.files|Select-Object -Skip 1);Refresh $f -Package;Reject {Invoke-Fixture $f} 'previous manifest must list exactly 74 local12 payloads'
$f=Fixture;$f.previous.product_version='0.1.0-local.13';Refresh $f -Package;Reject {Invoke-Fixture $f} 'different local version rejected even with caller supplied matching hash'
$f=Fixture;$f.previous.package_id=@('synthetic-local12');Refresh $f -Package;Reject {Invoke-Fixture $f} 'array package identity rejected'
$f=Fixture;$f.previous.files[0].sha256='d'*64;Refresh $f -Package;Reject {Invoke-Fixture $f} 'backup package rows must agree with pinned manifest rows'
$f=Fixture;$f.marker.install_root='C:\WrongInstalledRoot';Refresh $f -Package;Reject {Invoke-Fixture $f} 'installed marker binds exact previous root'
$f=Fixture;$f.marker.staging=$true;Refresh $f -Package;Reject {Invoke-Fixture $f} 'staged marker rejected'
$f=Fixture;$f.marker.product_key='YIME';Refresh $f -Package;Reject {Invoke-Fixture $f} 'other product marker rejected'
$f=Fixture;Text (Join-Path $f.root 'restore-evidence.json') '{}';Reject {Invoke-Fixture $f} 'previously used restore archive is not a fresh backup'
$f=Fixture;[IO.Directory]::CreateDirectory((Join-Path $f.package 'unlisted-empty'))|Out-Null;Reject {Invoke-Fixture $f} 'unlisted empty package directory rejected'
$f=Fixture;$f.manifest.data_files=@($f.manifest.state_files);Reject-Manifest $f 'diagnostics and runtime config cannot masquerade as data subset'
$f=Fixture;$f.manifest.development_scope.computer_name='OTHER';Reject-Manifest $f 'wrong development host rejected'
$f=Fixture;$f.manifest.development_scope.active_architectures='x64|x86';Reject-Manifest $f 'string architectures rejected'
$f=Fixture;$f.manifest.live_runtime_before.passed='true';Reject-Manifest $f 'truthy claimed live baseline rejected'
$f=Fixture;$f.manifest.state_files[0].bytes=[string]$f.manifest.state_files[0].bytes;Reject-Manifest $f 'string file length rejected'
$f=Fixture;$json=$f.manifest|ConvertTo-Json -Depth 24 -Compress
foreach($bad in @($json.Replace('"passed":true','"passed":true,"PASSED":true'),($json+' {}'),$json.Replace('"runtime_pid_before":1234','"runtime_pid_before":1234.0'),$json.Replace('"runtime_pid_before":1234','"runtime_pid_before":1.234e3'),$json.Replace('"runtime_pid_before":1234','"runtime_pid_before":01234'),$json.Replace('"runtime_pid_before":1234','"runtime_pid_before":9223372036854775808'),$json.Replace('"MYCOMPUTER"','"\ud800"'))){Text $f.manifestPath $bad;Reject {Invoke-Fixture $f} ('strict raw JSON '+$checks.Count)}
[IO.File]::WriteAllBytes($f.manifestPath,[byte[]]@(0xff,0xfe,0xc0));Reject {Invoke-Fixture $f} 'malformed UTF8 rejected'
$f=Fixture;$writer=[IO.File]::Open($f.manifestPath,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
try{Reject {Invoke-Fixture $f} 'concurrent manifest writer rejected'}finally{$writer.Dispose()}
$f=Fixture;$file=Join-Path $f.state 'speech.json';$writer=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
try{Reject {Invoke-Fixture $f} 'concurrent state writer rejected'}finally{$writer.Dispose()}
$probe=[IO.File]::Open($f.manifestPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$probe.Dispose();Check $true 'failure releases manifest and previous file leases'
foreach($member in @('backup-manifest.json','state/speech.json','previous-package/payload/member-1.txt')){
    $f=Fixture;$file=Join-Path $f.root $member;$link=Join-Path $root ([guid]::NewGuid().ToString('N')+'.link');New-Item -ItemType HardLink -Path $link -Value $file|Out-Null
    try{Reject {Invoke-Fixture $f} ('native hardlink rejected '+$member)}finally{Remove-Item -LiteralPath $link}
    $f=Fixture;$file=Join-Path $f.root $member;Set-Content -LiteralPath $file -Stream surprise -Value 'owned synthetic alternate stream'
    try{Reject {Invoke-Fixture $f} ('native ADS rejected '+$member)}finally{Remove-Item -LiteralPath $file -Stream surprise}
}
$f=Fixture;$junction=Join-Path $f.state 'indirect';New-Item -ItemType Junction -Path $junction -Value $valid.state|Out-Null
try{Reject {Invoke-Fixture $f} 'native junction rejected before traversal'}finally{if((Split-Path -Parent $junction) -cne $f.state -or -not ((Get-Item -LiteralPath $junction -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe junction cleanup'};[IO.Directory]::Delete($junction)}
if(-not ('Yime.BackupTestStreams' -as [type])){Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Yime {
 public static class BackupTestStreams {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool DeleteFile(string path);
  public static void Create(string path){using(var handle=CreateFile(path,0x40000000,7,IntPtr.Zero,2,0,IntPtr.Zero)){if(handle.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());using(var s=new System.IO.FileStream(handle,System.IO.FileAccess.Write)){s.WriteByte(86);s.Flush(true);}}}
  public static void Remove(string path){if(!DeleteFile(path))throw new Win32Exception(Marshal.GetLastWin32Error());}
 }
}
'@}
foreach($directory in @('state/user-model','previous-package/payload')){
    $f=Fixture;$streamPath=(Join-Path $f.root $directory)+':hidden'
    if(-not $streamPath.StartsWith($root+'\',[StringComparison]::Ordinal) -or -not $streamPath.EndsWith(':hidden',[StringComparison]::Ordinal)){throw 'Unsafe owned stream fixture'}
    [Yime.BackupTestStreams]::Create($streamPath)
    try{Reject {Invoke-Fixture $f} ('native directory ADS rejected '+$directory)}finally{[Yime.BackupTestStreams]::Remove($streamPath)}
}
$f=Fixture
$directoryFacts=& $module {param($fixtureRoot)
    $leases=@{}
    try{
        $null=Get-BackupTree $fixtureRoot $leases
        $child=Join-Path $fixtureRoot 'state/user-model';$blocked=$false
        try{[IO.Directory]::Move($child,(Join-Path $fixtureRoot 'moved-model'))}catch{$blocked=$true}
        $transient=Join-Path $fixtureRoot 'transient.txt';[IO.File]::WriteAllText($transient,'owned fixture');$created=Test-Path -LiteralPath $transient;Remove-Item -LiteralPath $transient
        [pscustomobject]@{replacement_blocked=$blocked;transient_possible=$created}
    }finally{foreach($lease in $leases.Values){$lease.Dispose()}}
} $f.root
Check $directoryFacts.replacement_blocked 'directory lease blocks queued-child replacement before descent'
Check $directoryFacts.transient_possible 'directory leases do not claim continuous membership exclusion'
# Execute only the real backup producer's JSON serialization pipeline with
# synthetic variables and a synthetic data-record function. No helper entry,
# installed-package check, runtime launch, registry or actual state is called.
$backupSource=Join-Path $PSScriptRoot 'backup-local-trial-state.ps1';$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($backupSource,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$producer=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.PipelineAst] -and $n.Extent.Text.StartsWith("[ordered]@{schema_version='yimecore-quiesced-backup-v1'")},$true))
Check ($producer.Count -eq 1) 'exact backup manifest producer pipeline located'
$f=Fixture;$backup=$f.root;$stateRoot=$f.call.ExpectedStateRoot;$package=$f.call.ExpectedInstallRoot;$archiveState=$f.state
$scope=$f.manifest.development_scope;$before=$f.manifest.state_files;$packageBefore=$f.manifest.package_files
$status=@{runtime_pid=1234;broker_pid=1235};$liveBefore=$f.manifest.live_runtime_before
function Get-YimeCoreDataRecords([string]$Unused){$f.manifest.data_files}
& ([scriptblock]::Create($producer[0].Extent.Text))
Check (Invoke-Fixture $f).static_backup_verified 'real source producer serializer accepted with synthetic full snapshot'
$result=[ordered]@{schema_version='yimecore-native-maintenance-backup-tests-v1';passed=$true;checks_passed=$checks.Count;checks=$checks.ToArray();powershell_version=$PSVersionTable.PSVersion.ToString();
    module_sha256=Hash $modulePath;test_sha256=Hash $PSCommandPath;synthetic_owned_files_only=$true;actual_backup_read=$false;installed_package_read=$false;user_state_read=$false;backup_helper_executed=$false;product_executed=$false;registry_read=$false;execution_authorized=$false;L6_sealed=$false}
Json $out $result
Write-Output ('PASS: native backup reader '+$checks.Count+' checks; '+$out)
