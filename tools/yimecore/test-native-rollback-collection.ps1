[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputPath)
if(-not $output.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Fresh repository .tmp evidence file required'}
New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
$root=Join-Path $repo ('.tmp/native-rollback-collection-fixtures-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$checks=New-Object 'Collections.Generic.List[string]'
function Check($Condition,[string]$Name){if(-not $Condition){throw "FAILED: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Name}
$source=Join-Path $PSScriptRoot 'native-rollback-collection.psm1'
$entry=Join-Path $PSScriptRoot 'invoke-native-rollback-collection.ps1'
$globalChildBefore=Get-Command Open-YimeCoreNativeMaintenanceChild -ErrorAction SilentlyContinue
$module=Import-Module $source -Force -PassThru
$attempt='abcdabcdabcdabcdabcdabcdabcdabcd'
$dependencies=@(& $module {$script:CollectionDependencyImports})
Check ($dependencies.Count -eq 8) 'dependencies import into collector module script scope'
$childDependency=@($dependencies|Where-Object Name -CEQ 'native-maintenance-child')[0]
$marker=[object]::new()
& $childDependency {param($value)$script:CollectionSmokeMarker=$value} $marker
& $module {Initialize-CollectionDependencies;Initialize-CollectionDependencies}
Check ([object]::ReferenceEquals($marker,(& $childDependency {$script:CollectionSmokeMarker}))) 'repeated initialization preserves dependency state without Force reload'
$globalChildAfter=Get-Command Open-YimeCoreNativeMaintenanceChild -ErrorAction SilentlyContinue
Check (($null -eq $globalChildBefore -and $null -eq $globalChildAfter) -or
    ($null -ne $globalChildBefore -and $null -ne $globalChildAfter -and [object]::ReferenceEquals($globalChildBefore.Module,$globalChildAfter.Module))) 'dependency imports preserve caller global command scope'
$entryPlan=(& $entry -AttemptId $attempt)|ConvertFrom-Json
Check ($entryPlan.schema_version -ceq 'yimecore-native-rollback-collection-plan-v1' -and -not $entryPlan.installer_executed -and -not $entryPlan.user_state_read) 'actual default entry performs only static Plan'
Check ([object]::ReferenceEquals($marker,(& $childDependency {$script:CollectionSmokeMarker}))) 'default entry does not force reload live dependency definitions'
$plan=Get-YimeCoreNativeRollbackCollectionPlan -AttemptId $attempt
Check (-not $plan.installer_executed -and -not $plan.user_state_read -and -not $plan.ready_to_execute -and -not $plan.rollback_acceptance) 'static plan has no execution or acceptance claim'
Check ($plan.layout.attempt_id -ceq $attempt -and $plan.layout.outcome_path.EndsWith('native-desktop-rehearsal-'+$attempt+'.json')) 'plan binds direct typed outcome path to explicit attempt'
Check ((Get-Command Invoke-YimeCoreNativeRollbackCollection).Parameters.Keys -notcontains 'PackageRoot' -and (Get-Command Invoke-YimeCoreNativeRollbackCollection).Parameters.Keys -notcontains 'Provider') 'public execution has no arbitrary package provider override'
foreach($bad in @('', ('A'*32), ('x'*32), '../escape', ('a'*31))){Reject {Get-YimeCoreNativeRollbackCollectionPlan -AttemptId $bad} 'reject ambiguous attempt'}
Reject {Invoke-YimeCoreNativeRollbackCollection -Execute:$false -AttemptId $attempt} 'explicit false Execute never begins native observations'

# Command construction is real; every mutating/capturing provider in the sequence
# below is replaced only inside this fresh module session. No installer/UAC/state.
$layout=$plan.layout
$inputs=[pscustomobject]@{normal=[pscustomobject]@{root='C:\fixture archive\normal'};fault=[pscustomobject]@{root='C:\fixture archive\fault'}}
$backupInfo=& $module {param($l,$i) New-CollectionStartInfo $l $i 'backup' '123:456'} $layout $inputs
$faultInfo=& $module {param($l,$i) New-CollectionStartInfo $l $i 'controller' '123:456'} $layout $inputs
Check (-not $backupInfo.UseShellExecute -and -not $backupInfo.RedirectStandardOutput -and $backupInfo.Arguments.Contains('-InstalledPackageRoot') -and -not $backupInfo.Arguments.Contains('-LocalProduct')) 'backup uses normal helper with explicit installed root and no redirected EOF'
Check ($faultInfo.UseShellExecute -and $faultInfo.Verb -ceq 'runas' -and $faultInfo.WindowStyle -eq 'Hidden') 'controller uses a retained direct UAC process with hidden worker window'
foreach($flag in @('-NativeDesktop','-NativeDesktopRehearsal','-NoElevation','-StandardUserInitiator "123:456"','-RehearsalAttemptId','-RehearsalOutcomePath','-StateRoot','-TargetUserSid','-InstallRoot')){Check ($faultInfo.Arguments.Contains($flag)) ('controller forwards '+$flag)}
Check ($faultInfo.Arguments.Contains('Manage-YimeCoreTrial.ps1') -and -not $faultInfo.Arguments.Contains('manage-local-product.ps1')) 'typed rehearsal bypasses ordinary wrapper without changing it'
Reject {& $module {Quote-CollectionArgument 'C:\bad"argument'}} 'reject embedded quote in fixed process arguments'
Reject {& $module {param($l,$i) New-CollectionStartInfo $l $i 'controller' '123'} $layout $inputs} 'reject missing creation time in initiator'

& $module {
    function script:Initialize-CollectionDependencies { }
    function script:Event([string]$Name){$script:Log.Add($Name);if($script:Failure -ceq $Name){throw ('synthetic '+$Name)}}
    function script:Get-CollectionLayout($AttemptId){[pscustomobject]@{attempt_id=$AttemptId;sid='S-1-5-21-1-2-3-4';previous_root=(Join-Path $script:Fixture 'old');previous_manifest_sha256=('a'*64);state_root=(Join-Path $script:Fixture 'state');target_root=(Join-Path $script:Fixture 'target');archive_parent=$script:Fixture;output_root=(Join-Path $script:Fixture 'out');backup_root=(Join-Path $script:Fixture 'backup');outcome_path=(Join-Path $script:Fixture 'outcome.json');powershell='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'}}
    function script:Open-CollectionContext($Layout){Event 'context';[pscustomobject]@{initiator='123:456'}}
    function script:Close-CollectionContext($Value){if($Value){Event 'close-context'}}
    function script:Open-CollectionSources {Event 'sources';[pscustomobject]@{records=@('fixture-source')}}
    function script:Close-CollectionSources($Value){if($Value){Event 'close-sources'}}
    function script:Open-CollectionInputs {Event 'inputs';[pscustomobject]@{normal=[pscustomobject]@{root=(Join-Path $script:Fixture 'normal');manifest_sha256=('1'*64)};fault=[pscustomobject]@{root=(Join-Path $script:Fixture 'fault');manifest_sha256=('2'*64)};controller_sha256=('3'*64)}}
    function script:Close-CollectionInputs($Value){if($Value){Event 'close-inputs'}}
    function script:Assert-CollectionFreshPaths($Layout){Event 'fresh'}
    function script:Assert-CollectionPrevious($Layout){Event 'previous'}
    function script:New-CollectionOutput($Layout){Event 'output';New-Item -ItemType Directory -Path $Layout.output_root | Out-Null;$Layout.output_root}
    function script:Write-CollectionJson($Root,$Name,$Value){Event ('write-'+$Name);$Value|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $Root $Name) -Encoding UTF8}
    function script:Start-CollectionChild($Info){$script:Kind=if($Info.Verb -ceq 'runas'){'controller'}else{'backup'};Event ('start-'+$script:Kind);[pscustomobject]@{kind=$script:Kind}}
    function script:Open-CollectionChild($Process,$Image){Event ('open-'+$Process.kind);$Process}
    function script:Wait-CollectionChild($Lease){Event ('wait-'+$Lease.kind);[pscustomobject]@{execution_budget_exceeded=($script:Failure -ceq ('budget-'+$Lease.kind));observation=[pscustomobject]@{pid=900;creation_filetime=1234567890L;exit_code=$(if($Lease.kind -ceq 'backup'){if($script:Failure -ceq 'backup-nonzero'){1}else{0}}else{if($script:Failure -ceq 'controller-26'){26}else{20}});exit_observed=$true;actual_exit_os_observed=$true}}}
    function script:Close-CollectionChild($Lease){if($Lease){Event ('close-child-'+$Lease.kind)}}
    function script:Drain-CollectionChild($Process){if($Process){Event ('drain-'+$Process.kind)}}
    function script:Read-CollectionBackup($Layout,$Child){
        Event 'backup-integrity';if($Child.exit_code -ne 0){throw 'nonzero reached backup admission'}
        [pscustomobject]@{static_backup_verified=$true;backup_manifest=[pscustomobject]@{sha256=('f'*64)};
            state_reference=[pscustomobject]@{root=(Join-Path $Layout.backup_root 'state');directories=@('logs','user-model','user-model/empty')};
            manifest=[pscustomobject]@{backup_root=$Layout.backup_root;source_state_root=$Layout.state_root;state_files=@(
                [pscustomobject]@{path='learning.json';bytes=5;sha256=('a'*64)},[pscustomobject]@{path='user-model/item';bytes=7;sha256=('b'*64)},
                [pscustomobject]@{path='runtime-config.json';bytes=9;sha256=('c'*64)},[pscustomobject]@{path='logs/runtime.log';bytes=3;sha256=('d'*64)})}}
    }
    function script:New-CollectionFixtureData($Root){
        $result=[pscustomobject]@{schema_version='yimecore-native-maintenance-data-v1';state_root=$Root;snapshot_sha256=('d'*64);
            records=@([pscustomobject]@{path='learning.json';kind='file';bytes=5;sha256=('a'*64)},[pscustomobject]@{path='user-model';kind='directory'},
                [pscustomobject]@{path='user-model/empty';kind='directory'},[pscustomobject]@{path='user-model/item';kind='file';bytes=7;sha256=('b'*64)});
            runtime_config=[pscustomobject]@{path='runtime-config.json';kind='file';bytes=9;sha256=('c'*64)}}
        switch -CaseSensitive ($script:Failure){
            'backup-both-changed' {$result.records[0].sha256='e'*64}
            'backup-file-size' {$result.records[0].bytes=6}
            'backup-file-string-size' {$result.records[0].bytes='5'}
            'backup-file-hash-array' {$result.records[0].sha256=@('a'*64)}
            'backup-file-case' {$result.records[0].path='Learning.json'}
            'backup-file-missing' {$result.records=@($result.records|Where-Object path -CNE 'learning.json')}
            'backup-file-added' {$result.records+=,[pscustomobject]@{path='speech.json';kind='file';bytes=1;sha256=('e'*64)}}
            'backup-file-duplicate' {$result.records+=,$result.records[0]}
            'backup-file-kind' {$result.records[0].kind='absent'}
            'backup-runtime-changed' {$result.runtime_config.sha256='e'*64}
            'backup-runtime-missing' {$result.runtime_config=[pscustomobject]@{path='runtime-config.json';kind='absent'}}
            'backup-runtime-path' {$result.runtime_config.path='runtime-status.json'}
            'backup-runtime-string-kind' {$result.runtime_config.kind=@('file')}
            'backup-directory-added' {$result.records+=,[pscustomobject]@{path='user-model/new-empty';kind='directory'}}
            'backup-directory-missing' {$result.records=@($result.records|Where-Object path -CNE 'user-model/empty')}
            'backup-directory-duplicate' {$result.records+=,$result.records[2]}
            'backup-data-wrong-root' {$result.state_root=Join-Path $script:Fixture 'unverified'}
            'backup-data-records-scalar' {$result.records=$result.records[0]}
        }
        $result
    }
    function script:Read-CollectionData($Root,$Shared){Event ('data-'+[string]$Shared);New-CollectionFixtureData $Root}
    function script:Compare-CollectionData($Before,$After){
        Event 'compare-data'
        $same=(($Before.records|ConvertTo-Json -Depth 8 -Compress) -ceq ($After.records|ConvertTo-Json -Depth 8 -Compress)) -and
            (($Before.runtime_config|ConvertTo-Json -Depth 8 -Compress) -ceq ($After.runtime_config|ConvertTo-Json -Depth 8 -Compress))
        [pscustomobject]@{unchanged=($same -and $script:Failure -cne 'data-changed')}
    }
    function script:Read-CollectionRegistry($Layout){Event 'registry';[pscustomobject]@{fixture=$true}}
    function script:Compare-CollectionRegistry($Before,$After){Event 'compare-registry';[pscustomobject]@{equal=($script:Failure -cne 'registry-changed')}}
    function script:Read-CollectionProcesses($Layout,$Backup){Event 'processes';[pscustomobject]@{fixture=$true}}
    function script:Read-CollectionOutcome($Layout,$Inputs,$Child){Event 'outcome';if($Child.pid -ne 900 -or $Child.creation_filetime -ne 1234567890L -or $Child.exit_code -ne 20){throw 'OS producer binding did not match'};[pscustomobject]@{expected_fault_procedure_observed=($script:Failure -cne 'unexpected-outcome')}}
}
function Run-Case([string]$Failure){
    $fixture=Join-Path $root ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $fixture|Out-Null
    & $module {param($f,$failure)$script:Fixture=$f;$script:Failure=$failure;$script:Log=New-Object 'Collections.Generic.List[string]'} $fixture $Failure
    $ok=$true;$value=$null;$failureText='';try{$value=Invoke-YimeCoreNativeRollbackCollection -Execute -AttemptId $attempt}catch{$ok=$false;$failureText=$_.Exception.Message+' '+$_.ScriptStackTrace}
    [pscustomobject]@{success=$ok;value=$value;log=@(& $module {$script:Log.ToArray()});root=$fixture;failure=$failureText}
}
$good=Run-Case ''
if(-not $good.success){throw $good.failure}
Check $good.success 'actual coordinator sequence completes with private fixture providers'
Check ($good.value.collection_completed -and $good.value.controller_exit_os_observed -and -not $good.value.rollback_acceptance -and -not $good.value.L6_sealed -and -not $good.value.local_product_ready -and -not $good.value.public_release_ready) 'successful observation sequence preserves honest unclosed acceptance'
Check ([array]::IndexOf($good.log,'wait-backup') -lt [array]::IndexOf($good.log,'backup-integrity') -and [array]::IndexOf($good.log,'backup-integrity') -lt [array]::IndexOf($good.log,'start-controller')) 'backup original child exit precedes integrity and fault launch'
Check ([array]::IndexOf($good.log,'processes') -gt [array]::IndexOf($good.log,'wait-backup')) 'Runtime baseline is recaptured after backup restart'
Check ([array]::IndexOf($good.log,'wait-controller') -lt [array]::IndexOf($good.log,'outcome') -and [array]::IndexOf($good.log,'outcome') -lt [array]::IndexOf($good.log,'compare-registry')) 'OS child observation supplies typed verdict before after comparisons'
$beforeRecord=Get-Content -LiteralPath (Join-Path $good.root 'out/before-observations.json') -Raw|ConvertFrom-Json
Check ($beforeRecord.backup_data_binding.bound -and $beforeRecord.backup_data_binding.protected_file_count -eq 3 -and $beforeRecord.backup_data_binding.protected_directory_count -eq 2) 'protected files runtime configuration and empty directories bind verified backup observation'
Check ($beforeRecord.backup_data_binding.files_bound_to_verified_manifest -and $beforeRecord.backup_data_binding.directories_bound_to_backup_reader_observation -and -not $beforeRecord.backup_data_binding.directories_recorded_by_manifest -and -not $beforeRecord.backup_data_binding.continuous_membership_protection) 'directory evidence is the backup reader tree observation not invented manifest membership'
foreach($failure in @('backup-both-changed','backup-file-size','backup-file-string-size','backup-file-hash-array','backup-file-case','backup-file-missing','backup-file-added','backup-file-duplicate','backup-file-kind',
    'backup-runtime-changed','backup-runtime-missing','backup-runtime-path','backup-runtime-string-kind','backup-directory-added','backup-directory-missing','backup-directory-duplicate','backup-data-wrong-root','backup-data-records-scalar')){
    $case=Run-Case $failure
    Check (-not $case.success -and $case.log -notcontains 'start-controller' -and $case.log -contains 'backup-integrity') ('verified backup binding fails closed before fault controller: '+$failure)
    $summary=Get-Content -LiteralPath (Join-Path $case.root 'out/collection-summary.json') -Raw|ConvertFrom-Json
    Check ($summary.final_stage -ceq 'backup-data-binding' -and -not $summary.controller_started -and -not $summary.collection_completed) ('binding failure is explicit incomplete stage: '+$failure)
    if($failure -ceq 'backup-both-changed'){
        $bothChanged=& $module {Compare-CollectionData (New-CollectionFixtureData 'C:\fixture\backup') (New-CollectionFixtureData 'C:\fixture\live')}
        Check $bothChanged.unchanged 'A to B backup and live trees would compare equal but cannot replace manifest A baseline'
    }
}
foreach($failure in @('context','sources','inputs','fresh','previous','output','write-source-observation.json','start-backup','open-backup','wait-backup','backup-nonzero','budget-backup','backup-integrity','data-False','data-True','data-changed','registry','processes')){
    $case=Run-Case $failure
    Check (-not $case.success -and $case.log -notcontains 'start-controller') ('preflight or backup failure cannot begin fault: '+$failure)
    if($case.log -contains 'start-backup' -and $failure -cne 'start-backup'){Check ($case.log -contains 'drain-backup') ('parent drains active backup before leaving: '+$failure)}
}
foreach($failure in @('start-controller','open-controller','wait-controller','budget-controller','controller-26','outcome','unexpected-outcome','registry-changed')){
    $case=Run-Case $failure
    Check (-not $case.success) ('failed controller observation cannot complete: '+$failure)
    if($failure -cne 'start-controller'){Check ([array]::IndexOf($case.log,'drain-controller') -ge 0 -and [array]::IndexOf($case.log,'drain-controller') -lt [array]::IndexOf($case.log,'close-context')) ('retained ordinary parent drains original controller before close: '+$failure)}
    $summary=Get-Content -LiteralPath (Join-Path $case.root 'out/collection-summary.json') -Raw|ConvertFrom-Json
    Check (-not $summary.collection_completed -and -not $summary.rollback_acceptance) ('failed summary never reports acceptance: '+$failure)
}
$noContext=Run-Case 'context'
Check ($noContext.log -notcontains 'inputs' -and $noContext.log -notcontains 'output' -and $noContext.log -notcontains 'previous') 'native context rejection precedes product roots and output mutation'
Remove-Module $module

# Exercise the real waiting loop with controlled slices: a soft timeout keeps
# waiting for the original handle and marks the attempt ineligible to advance.
$module=Import-Module $source -Force -PassThru
$waited=& $module {
    $script:slices=0
    function script:Wait-CollectionChildSlice($Lease){$script:slices++;[pscustomobject]@{exit_observed=($script:slices -ge 3);actual_exit_os_observed=($script:slices -ge 3);exit_code=$(if($script:slices -ge 3){20}else{$null})}}
    function script:Test-CollectionBudgetExceeded($Timer){$true}
    $result=Wait-CollectionChild ([pscustomobject]@{})
    [pscustomobject]@{result=$result;slices=$script:slices}
}
Check ($waited.slices -eq 3 -and $waited.result.execution_budget_exceeded -and $waited.result.parent_retained_until_child_exit) 'budget timeout drains subsequent wait slices without terminating the parent or child'
Remove-Module $module
$text=Get-Content -LiteralPath $source -Raw
Check (-not ($text -match '\.Kill\(|Stop-Process|ReadToEnd|NativeX64Rehearsal|PurgeUserData')) 'collector contains no kill EOF wait legacy rehearsal or purge path'
Check ($text.Contains('Read-YimeCoreNativeRehearsalOutcome') -and $text.Contains('-ExpectedProducerPid $Child.pid') -and $text.Contains('-ExpectedProducerCreationFileTime $Child.creation_filetime') -and $text.Contains('-ExpectedNormalPackageManifestSha256 $Inputs.normal.manifest_sha256')) 'consumer binds OS producer facts and normal package manifest'
[ordered]@{schema_version='yimecore-native-rollback-collection-tests-v1';passed=$true;checks_passed=$checks.Count;checks=@($checks.ToArray());powershell_version=$PSVersionTable.PSVersion.ToString();
    collector_source_sha256=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant();entry_source_sha256=(Get-FileHash -LiteralPath $entry).Hash.ToLowerInvariant();sequence_providers_private_fixture_only=$true;process_and_file_primitives_tested_separately=$true;
    real_initialization_and_default_plan_smoke_only=$true;
    actual_installer_executed=$false;actual_backup_executed=$false;actual_uac_requested=$false;actual_product_or_user_state_accessed=$false;L6_sealed=$false;rollback_acceptance=$false} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $output -Encoding UTF8
Write-Output "PASS: rollback collection $($checks.Count) checks; private source-sequence fixtures only."
