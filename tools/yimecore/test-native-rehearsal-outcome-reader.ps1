[CmdletBinding()]param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=[IO.Path]::GetFullPath($OutputPath)
if(-not $output.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Fresh repository .tmp output required'}
$parent=Split-Path -Parent $output
$cursor=$parent
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect fixture output'};$cursor=Split-Path -Parent $cursor}
[IO.Directory]::CreateDirectory($parent)|Out-Null
$fixture=Join-Path $parent ('reader-own-files-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$modulePath=Join-Path $PSScriptRoot 'native-rehearsal-outcome-reader.psm1'
if(-not ('Yime.Dp1UNative.Facts' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot '../dual-product/rime-pime-dp1u-native-facts.cs')}
$readerModule=Import-Module $modulePath -Force -PassThru
$checks=New-Object 'Collections.Generic.List[string]'
$sourceCases=New-Object 'Collections.Generic.List[object]'
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Body,[string]$Name){$caught=$false;try{& $Body|Out-Null}catch{$caught=$true};Check $caught $Name}
$attempt=[guid]::NewGuid().ToString('N')
$path=Join-Path $fixture ('native-desktop-rehearsal-'+$attempt+'.json')
$created=[DateTime]::UtcNow.AddMinutes(-2).ToFileTimeUtc()
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$parameters=@{OutcomePath=$path;ActualControllerExitCode=20;ExpectedAttemptId=$attempt;ExpectedTargetUserSid=$sid;
    ExpectedControllerSha256=('a'*64);ExpectedSourceManifestSha256=('b'*64);ExpectedFailureManifestSha256=('c'*64);
    ExpectedProducerPid=1234;ExpectedProducerCreationFileTime=$created;ExpectedOutcomeDirectory=$fixture;
    ExpectedStateRoot='C:\SyntheticOutcome\state';ExpectedPreviousInstallRoot='C:\SyntheticOutcome\previous';ExpectedTargetInstallRoot='C:\SyntheticOutcome\target'}
function New-Record {
    $events=@();$phases=@('preflight','package_verified','baseline_verified','staged','preinstall_started','registered_x64','registered_x86','registered','fault_runtime_launched','fault_runtime_exited','rollback_started','previous_installation_restored','frozen_tip_finalizer_completed')
    foreach($phase in $phases){$events+=,[ordered]@{sequence=$events.Count+1;phase=$phase;observed_utc=([DateTime]::FromFileTimeUtc($created)).AddSeconds($events.Count+1).ToString('o')}}
    [ordered]@{schema_version='yimecore-native-desktop-rehearsal-outcome-v1';attempt_id=$attempt;producer_pid=1234;producer_creation_filetime=$created;target_user_sid=$sid;
        controller_sha256=('a'*64);failure_manifest_sha256=('c'*64);source_manifest_sha256=('b'*64);state_root=$parameters.ExpectedStateRoot;
        previous_install_root=$parameters.ExpectedPreviousInstallRoot;target_install_root=$parameters.ExpectedTargetInstallRoot;
        phase='frozen_tip_finalizer_completed';events=$events;registered_architectures=@('x64','x86');
        fault_runtime=[ordered]@{pid=4321;creation_filetime=$created+10000000;launch_path=($parameters.ExpectedTargetInstallRoot+'\bin\YimeCoreTrialRuntime.exe');natural_exit_observed=$true;exit_code=86;controller_termination_requested=$false};
        rollback_attempted=$true;rollback_procedure_completed=$true;frozen_tip_finalizer_completed=$true;unexpected_runtime_success=$false;outcome='expected_fault_rollback_completed';
        independent_registry_restore_verified=$false;data_restore_verified=$false;deferred_delete_absence_verified=$false;loaded_code_identity_verified=$false;
        execution_authorized=$false;L6_sealed=$false;local_product_ready=$false;public_release_ready=$false;outcome_complete=$true;required_controller_exit_code=20}
}
function Write-Record($Record){[IO.File]::WriteAllText($path,($Record|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))}
function Read-Record($Record,[int]$Exit=20){Write-Record $Record;$call=@{};foreach($key in $parameters.Keys){$call[$key]=$parameters[$key]};$call.ActualControllerExitCode=$Exit;Read-YimeCoreNativeRehearsalOutcome @call}
function Set-Events($Record,[string[]]$Names){$Record.events=@();foreach($name in $Names){$Record.events+=,[ordered]@{sequence=$Record.events.Count+1;phase=$name;observed_utc=([DateTime]::FromFileTimeUtc($created)).AddSeconds($Record.events.Count+1).ToString('o')}};$Record.phase=$Names[-1]}
$base=New-Record
$sourceCases.Add([pscustomobject]@{record=$base;exit=20;name='expected86'})
$value=Read-Record $base
Check ($value.record_consistent -and $value.expected_fault_procedure_observed -and $value.actual_controller_exit_code -eq 20) 'valid expected fault record and external actual exit agree'
Check (-not $value.actual_exit_os_authenticated -and -not $value.producer_process_authenticated -and -not $value.native_execution_authenticated -and -not $value.independent_restore_verified -and -not $value.source_readiness -and -not $value.ready_to_execute -and -not $value.local_product_ready -and -not $value.public_release_ready -and -not $value.L6_sealed) 'consistent record cannot grant native authenticity recovery readiness or L6'
Check ($value.outcome_sha256 -ceq (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()) 'same-stream byte hash matches returned record'
Check ($value.helper_type -cmatch '^Yime\.RehearsalReaderNative\.N[a-f0-9]{32}\.Facts$' -and $value.helper_source_sha256 -ceq '9969b68b42bc11428d4af6a8bb348a9658e248c0758b953bd9e3834109f97be4' -and -not $value.loaded_helper_identity_authenticated) 'reviewed helper compiled in isolated namespace despite loaded shared native type'
$oldPin=& $readerModule {$script:ReaderNativeFactsHash}
try{& $readerModule {$script:ReaderNativeFactsHash='0'*64};Reject {Read-YimeCoreNativeRehearsalOutcome @parameters} 'cached native type does not skip current helper source hash verification'}finally{& $readerModule {param($pin)$script:ReaderNativeFactsHash=$pin} $oldPin}
$firstType=$value.helper_type
Remove-Module $readerModule
$readerModule=Import-Module $modulePath -Force -PassThru
$reloaded=Read-YimeCoreNativeRehearsalOutcome @parameters
Check ($reloaded.helper_type -cne $firstType -and $reloaded.record_consistent) 'module reload never reuses preexisting native helper namespace'
$aliasCall=@{};foreach($key in $parameters.Keys){$aliasCall[$key]=$parameters[$key]};$aliasCall.Remove('ExpectedSourceManifestSha256');$aliasCall.ExpectedNormalPackageManifestSha256='b'*64
Check (Read-YimeCoreNativeRehearsalOutcome @aliasCall).record_consistent 'normal package manifest alias has exact producer derivation meaning'
Check (@((Get-Command Read-YimeCoreNativeRehearsalOutcome).Parameters.Keys|Where-Object {$_ -in @('Provider','ScriptBlock','Enumerator')}).Count -eq 0) 'no public provider or execution overrides'
foreach($field in @($base.Keys)){
    $record=New-Record;$record.Remove($field);Reject {Read-Record $record} ('reject missing '+$field)
    $record=New-Record;$record[$field]=$null;Reject {Read-Record $record} ('reject null complete-record field '+$field)
}
foreach($field in @('schema_version','attempt_id','producer_pid','producer_creation_filetime','target_user_sid','controller_sha256','failure_manifest_sha256','source_manifest_sha256','state_root','previous_install_root','target_install_root','phase','outcome','required_controller_exit_code')){
    $record=New-Record;$record[$field]=@($record[$field]);Reject {Read-Record $record} ('reject singleton array '+$field)
}
foreach($field in @('rollback_attempted','rollback_procedure_completed','frozen_tip_finalizer_completed','unexpected_runtime_success','outcome_complete','independent_registry_restore_verified','data_restore_verified','deferred_delete_absence_verified','loaded_code_identity_verified','execution_authorized','L6_sealed','local_product_ready','public_release_ready')){
    $record=New-Record;$record[$field]=[string]$record[$field];Reject {Read-Record $record} ('reject truthy string '+$field)
    $record=New-Record;$record[$field]=@($record[$field]);Reject {Read-Record $record} ('reject boolean array '+$field)
}
foreach($field in @('independent_registry_restore_verified','data_restore_verified','deferred_delete_absence_verified','loaded_code_identity_verified','execution_authorized','L6_sealed','local_product_ready','public_release_ready')){
    $record=New-Record;$record[$field]=$true;Reject {Read-Record $record} ('reject promoted claim '+$field)
}
foreach($exit in @(1,0,19,21,22,23,24,25,26,27)) {Reject {Read-Record (New-Record) $exit} ('reject actual exit '+$exit)}
foreach($key in @('ExpectedAttemptId','ExpectedTargetUserSid','ExpectedControllerSha256','ExpectedSourceManifestSha256','ExpectedFailureManifestSha256','ExpectedProducerPid','ExpectedProducerCreationFileTime','ExpectedOutcomeDirectory','ExpectedStateRoot','ExpectedPreviousInstallRoot','ExpectedTargetInstallRoot')){
    Write-Record (New-Record);$call=@{};foreach($k in $parameters.Keys){$call[$k]=$parameters[$k]}
    if($key -ceq 'ExpectedProducerPid'){$call[$key]=1235}elseif($key -ceq 'ExpectedProducerCreationFileTime'){$call[$key]=$created+1}
    elseif($key -ceq 'ExpectedAttemptId'){$call[$key]='e'*32}elseif($key -ceq 'ExpectedTargetUserSid'){$call[$key]='S-1-5-21-1-2-3-1001'}
    elseif($key.EndsWith('Sha256')){$call[$key]='d'*64}else{$call[$key]='C:\DifferentBinding'}
    Reject {Read-YimeCoreNativeRehearsalOutcome @call} ('reject changed expected binding '+$key)
}
foreach($key in @('ActualControllerExitCode','ExpectedProducerPid','ExpectedProducerCreationFileTime')){
    Write-Record (New-Record);$call=@{};foreach($k in $parameters.Keys){$call[$k]=$parameters[$k]};$call[$key]=[string]$call[$key]
    Reject {Read-YimeCoreNativeRehearsalOutcome @call} ('reject coerced external integer '+$key)
}
foreach($key in $parameters.Keys){
    Write-Record (New-Record);$call=@{};foreach($k in $parameters.Keys){$call[$k]=$parameters[$k]};$call[$key]=@($call[$key])
    Reject {Read-YimeCoreNativeRehearsalOutcome @call} ('reject external singleton array '+$key)
}
$cases=[ordered]@{
    'unknown field'={param($r)$r['extra']=1};'incomplete record'={param($r)$r.outcome_complete=$false}
    'missing event'={param($r)$r.events=@($r.events|Where-Object {$_.phase -cne 'registered_x86'})}
    'duplicate event'={param($r)$r.events[6].phase='registered_x64'}
    'reversed event'={param($r)$r.events[5].phase='registered_x86';$r.events[6].phase='registered_x64'}
    'unknown phase'={param($r)$r.events[1].phase='approved'}
    'sequence gap'={param($r)$r.events[3].sequence=7};'string sequence'={param($r)$r.events[0].sequence='1'}
    'event array phase'={param($r)$r.events[0].phase=@('preflight')};'event extra field'={param($r)$r.events[0].extra=$true}
    'time reversal'={param($r)$r.events[1].observed_utc=$r.events[0].observed_utc.Replace('Z','+00:00')}
    'backwards UTC time'={param($r)$r.events[2].observed_utc=$r.events[0].observed_utc}
    'event before producer'={param($r)$r.events[0].observed_utc=([DateTime]::FromFileTimeUtc($created)).AddSeconds(-1).ToString('o')}
    'terminal phase mismatch'={param($r)$r.phase='registered'}
    'missing architecture'={param($r)$r.registered_architectures=@('x64')}
    'scalar architecture'={param($r)$r.registered_architectures='x64'}
    'reversed architectures'={param($r)$r.registered_architectures=@('x86','x64')}
    'architecture array masquerade'={param($r)$r.registered_architectures=@(@('x64'),@('x86'))}
    'runtime missing'={param($r)$r.fault_runtime=$null};'runtime same producer PID'={param($r)$r.fault_runtime.pid=1234}
    'runtime string PID'={param($r)$r.fault_runtime.pid='4321'};'runtime zero PID'={param($r)$r.fault_runtime.pid=0}
    'runtime old creation'={param($r)$r.fault_runtime.creation_filetime=$created-1}
    'runtime future creation'={param($r)$r.fault_runtime.creation_filetime=$created+9000000000}
    'runtime missing exit'={param($r)$r.fault_runtime.Remove('exit_code')}
    'runtime wrong path'={param($r)$r.fault_runtime.launch_path='C:\Other\YimeCoreTrialRuntime.exe'}
    'runtime string natural exit'={param($r)$r.fault_runtime.natural_exit_observed='true'}
    'runtime string termination'={param($r)$r.fault_runtime.controller_termination_requested='false'}
    'runtime false natural86'={param($r)$r.fault_runtime.natural_exit_observed=$false}
    'runtime self kill86'={param($r)$r.fault_runtime.controller_termination_requested=$true}
    'runtime wrong exit87'={param($r)$r.fault_runtime.exit_code=87}
    'runtime string exit86'={param($r)$r.fault_runtime.exit_code='86'}
    'rollback missing'={param($r)$r.rollback_attempted=$false}
    'rollback incomplete'={param($r)$r.rollback_procedure_completed=$false}
    'finalizer incomplete'={param($r)$r.frozen_tip_finalizer_completed=$false}
    'unexpected success without stage'={param($r)$r.unexpected_runtime_success=$true}
    'required exit mismatch'={param($r)$r.required_controller_exit_code=24}
}
foreach($case in $cases.GetEnumerator()){$record=New-Record;& $case.Value $record;Reject {Read-Record $record} ('reject '+$case.Key)}
# Every typed failure remains observable as a failure, with no expected-fault pass.
$record=New-Record;$record.fault_runtime.exit_code=87;$record.outcome='unexpected_failure_rollback_completed';$record.required_controller_exit_code=24
$sourceCases.Add([pscustomobject]@{record=$record;exit=24;name='unexpected87'})
Check (-not (Read-Record $record 24).expected_fault_procedure_observed) 'exit87 classified as unexpected failure'
$record=New-Record;$record.events=@($record.events|Where-Object {$_.phase -cne 'fault_runtime_exited'});Set-Events $record @($record.events|ForEach-Object {$_.phase});$record.fault_runtime.natural_exit_observed=$false;$record.fault_runtime.exit_code=$null;$record.fault_runtime.controller_termination_requested=$true;$record.outcome='unexpected_failure_rollback_completed';$record.required_controller_exit_code=24
$sourceCases.Add([pscustomobject]@{record=$record;exit=24;name='controller-kill'})
Check (-not (Read-Record $record 24).expected_fault_procedure_observed) 'controller kill is unexpected failure never natural86'
$record=New-Record;$record.events[9].phase='unexpected_runtime_success';$record.fault_runtime.natural_exit_observed=$false;$record.fault_runtime.exit_code=$null;$record.unexpected_runtime_success=$true;$record.outcome='unexpected_runtime_success_rollback_completed';$record.required_controller_exit_code=21
$sourceCases.Add([pscustomobject]@{record=$record;exit=21;name='unexpected-success'})
Check (-not (Read-Record $record 21).expected_fault_procedure_observed) 'unexpected runtime success stays failure21'
$record=New-Record;Set-Events $record @($record.events|Where-Object {$_.phase -cne 'previous_installation_restored'}|ForEach-Object {$_.phase});$record.rollback_procedure_completed=$false;$record.outcome='rollback_failed';$record.required_controller_exit_code=22
$sourceCases.Add([pscustomobject]@{record=$record;exit=22;name='rollback-failed'})
Check (-not (Read-Record $record 22).expected_fault_procedure_observed) 'rollback failure stays failure22'
$record=New-Record;Set-Events $record @($record.events|Where-Object {$_.phase -cne 'frozen_tip_finalizer_completed'}|ForEach-Object {$_.phase});$record.frozen_tip_finalizer_completed=$false;$record.outcome='protection_finalizer_failed';$record.required_controller_exit_code=23
$sourceCases.Add([pscustomobject]@{record=$record;exit=23;name='finalizer-failed'})
Check (-not (Read-Record $record 23).expected_fault_procedure_observed) 'finalizer failure stays failure23'
$record=New-Record;Set-Events $record @('preflight');$record.failure_manifest_sha256=$null;$record.source_manifest_sha256=$null;$record.previous_install_root=$null;$record.target_install_root=$null;$record.registered_architectures=@();$record.fault_runtime=$null;$record.rollback_attempted=$false;$record.rollback_procedure_completed=$false;$record.frozen_tip_finalizer_completed=$false;$record.outcome='preflight_or_staging_rejected';$record.required_controller_exit_code=25
$sourceCases.Add([pscustomobject]@{record=$record;exit=25;name='preflight-rejected'})
Check (-not (Read-Record $record 25).expected_fault_procedure_observed) 'preflight rejection permits only unobserved null bindings'
$record=New-Record;Set-Events $record @('preflight','package_verified','baseline_verified','staged','preinstall_started','registered_x64','rollback_started','previous_installation_restored','frozen_tip_finalizer_completed');$record.registered_architectures=@('x64');$record.fault_runtime=$null;$record.outcome='unexpected_failure_rollback_completed';$record.required_controller_exit_code=24
$sourceCases.Add([pscustomobject]@{record=$record;exit=24;name='partial-registration'})
Check (-not (Read-Record $record 24).expected_fault_procedure_observed) 'partial architecture registration stays unexpected failure'
$record=New-Record;Set-Events $record @('preflight','package_verified','baseline_verified','frozen_tip_finalizer_completed');$record.registered_architectures=@();$record.fault_runtime=$null;$record.rollback_attempted=$false;$record.rollback_procedure_completed=$false;$record.outcome='preflight_or_staging_rejected';$record.required_controller_exit_code=25
$sourceCases.Add([pscustomobject]@{record=$record;exit=25;name='staging-failed-finalized'})
Check (-not (Read-Record $record 25).expected_fault_procedure_observed) 'staging failure finalizer is distinct from rollback'
$record=New-Record;$record.rollback_procedure_completed=$false;$record.outcome='rollback_failed';$record.required_controller_exit_code=22
$sourceCases.Add([pscustomobject]@{record=$record;exit=22;name='staging-cleanup-failed-after-restore'})
Check (-not (Read-Record $record 22).expected_fault_procedure_observed) 'restore stage does not imply rollback cleanup completed'
$record=New-Record;$json=$record|ConvertTo-Json -Depth 16 -Compress
foreach($bad in @($json.Replace('"attempt_id":','"attempt_id":"'+$attempt+'","attempt_id":'),$json.Replace('"attempt_id":','"ATTEMPT_ID":"'+$attempt+'","attempt_id":'),$json.Replace('"producer_pid":1234','"producer_pid":1234.0'),$json.Replace('"producer_pid":1234','"producer_pid":1.234e3'),$json.Replace('"producer_pid":1234','"producer_pid":01234'),$json.Replace('"producer_pid":1234','"producer_pid":9223372036854775808'),$json.Replace('"phase":"preflight"','"phase":"\ud800"'),($json+' {}'),('{"schema_version":'+$json))){
    [IO.File]::WriteAllText($path,$bad,[Text.UTF8Encoding]::new($false));Reject {Read-YimeCoreNativeRehearsalOutcome @parameters} ('reject strict JSON syntax variant '+$checks.Count)
}
[IO.File]::WriteAllBytes($path,[byte[]]@(0xFF,0xFE,0xC0));Reject {Read-YimeCoreNativeRehearsalOutcome @parameters} 'reject malformed UTF8'
[IO.File]::WriteAllText($path,'');Reject {Read-YimeCoreNativeRehearsalOutcome @parameters} 'reject empty missing output record'
[IO.File]::WriteAllText($path,(' '*262145));Reject {Read-YimeCoreNativeRehearsalOutcome @parameters} 'reject oversized record'
Write-Record (New-Record)
$writer=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
try{Reject {Read-YimeCoreNativeRehearsalOutcome @parameters} 'reject concurrent writer while opening evidence'}finally{$writer.Dispose()}
$link=Join-Path $fixture 'hardlink.json'
New-Item -ItemType HardLink -Path $link -Value $path|Out-Null
try{Reject {Read-YimeCoreNativeRehearsalOutcome @parameters} 'reject multiple hardlinks by actual file handle'}finally{Remove-Item -LiteralPath $link}
$junction=Join-Path $parent ('reader-owned-junction-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Junction -Path $junction -Value $fixture|Out-Null
try{
    $call=@{};foreach($k in $parameters.Keys){$call[$k]=$parameters[$k]};$call.ExpectedOutcomeDirectory=$junction;$call.OutcomePath=Join-Path $junction (Split-Path -Leaf $path)
    Reject {Read-YimeCoreNativeRehearsalOutcome @call} 'reject native junction ancestor'
}finally{
    if((Split-Path -Parent ([IO.Path]::GetFullPath($junction))) -cne $parent -or -not ((Get-Item -LiteralPath $junction -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Refuse unexpected junction cleanup target'}
    [IO.Directory]::Delete($junction)
}
# Source producer compatibility uses only its outcome functions and this owned
# fixture; no transaction, installed roots, registration or product code runs.
$controller=Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1';$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($controller,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Assert-NativeDesktopRehearsalOptions','Initialize-RehearsalOutcome','Initialize-RehearsalOutcomeFileType','Set-RehearsalPhase','Complete-RehearsalOutcome')){
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
    if(-not $fn){throw "Missing source producer $name"};. ([scriptblock]::Create($fn.Extent.Text.Replace('function '+$name,'function script:'+$name)))
}
$NativeDesktopRehearsal=$true;$NativeDesktop=$true;$NativeX64Only=$false;$NativeX64Rehearsal=$false;$PurgeUserData=$false;$NoLaunch=$false;$NoAutoStart=$false;$Action='Install'
$RehearsalAttemptId=$attempt;$RehearsalOutcomePath=$path;$stateRootPath=$parameters.ExpectedStateRoot;$TargetUserSid=$sid
function Get-RehearsalOutcomeEnvironment {@{parent=$fixture;pid=1234;created=$created;sid=$sid;controller_sha256=('a'*64)}}
# Producer forbids Git ancestors: this single filesystem guard is substituted
# for the owned .tmp fixture only. Reader file/handle checks remain native.
function Test-Path {param([string]$LiteralPath,$PathType)
    if((Split-Path -Leaf $LiteralPath) -ceq '.git'){return $false}
    if($PSBoundParameters.ContainsKey('PathType')){Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType}else{Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}
}
foreach($sourceCase in $sourceCases){
    Remove-Item -LiteralPath $path
    Initialize-RehearsalOutcome
    try{
        $synthetic=$sourceCase.record
        foreach($key in $synthetic.Keys){if($key -notin @('events','required_controller_exit_code')){$script:rehearsalOutcome[$key]=$synthetic[$key]}}
        $script:rehearsalOutcome.events.Clear()
        foreach($event in $synthetic.events){Set-RehearsalPhase $event.phase}
        Complete-RehearsalOutcome
        $call=@{};foreach($k in $parameters.Keys){$call[$k]=$parameters[$k]};$call.ActualControllerExitCode=$sourceCase.exit
        $observed=Read-YimeCoreNativeRehearsalOutcome @call
        Check ($observed.record_consistent -and $observed.expected_fault_procedure_observed -eq ($sourceCase.exit -eq 20) -and $script:rehearsalOutcomeExitCode -eq $sourceCase.exit) ('real source outcome classification serializer and finalizer compatible: '+$sourceCase.name)
    }finally{if($script:rehearsalOutcomeStream){$script:rehearsalOutcomeStream.Dispose()}}
}
$result=[ordered]@{schema_version='yimecore-native-rehearsal-outcome-reader-tests-v1';passed=$true;checks_passed=$checks.Count;checks=$checks.ToArray();powershell_version=$PSVersionTable.PSVersion.ToString();
    reader_source_sha256=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant();controller_source_sha256=(Get-FileHash -LiteralPath $controller -Algorithm SHA256).Hash.ToLowerInvariant();
    native_owned_file_handles_tested=$true;source_producer_outcome_functions_only=$true;source_producer_compatible_cases=$sourceCases.Count;actual_controller_invoked=$false;processes_launched=$false;product_registry_accessed=$false;installed_local12_read_or_changed=$false;user_state_read=$false;execution_authorized=$false;L6_sealed=$false}
[IO.File]::WriteAllText($output,(($result|ConvertTo-Json -Depth 8).Replace("`r`n","`n")+"`n"),[Text.UTF8Encoding]::new($false))
Write-Output ('PASS: native rehearsal outcome reader '+$checks.Count+' checks; owned files only; '+$output)
