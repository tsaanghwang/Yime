Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:CollectionSource=$PSCommandPath
$script:CollectionModules=@('native-maintenance-context.psm1','local13-maintenance-inputs.psm1','native-maintenance-child.psm1',
    'native-maintenance-backup.psm1','native-maintenance-data.psm1','native-maintenance-evidence.psm1',
    'native-maintenance-processes.psm1','native-rehearsal-outcome-reader.psm1')
# Import definitions in this module's script scope. Never force-reload a shared
# dependency: it may own live native leases in this same initiating process.
$script:CollectionDependencyImports=@(foreach($name in $script:CollectionModules){Import-Module (Join-Path $PSScriptRoot $name) -Scope Local -PassThru})

function Assert-CollectionAttempt($AttemptId) {
    if($AttemptId -isnot [string] -or $AttemptId -cnotmatch '^[a-f0-9]{32}$'){throw 'An explicit canonical 32-hex attempt is required'}
}
function Get-CollectionLayout([string]$AttemptId) {
    $archive=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) 'YimeCore Recovery Archives'
    [pscustomobject]@{attempt_id=$AttemptId;sid='S-1-5-21-2783006668-770716121-2150155084-1001';
        previous_root='C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-62af8b507c91-9b3366b3';
        previous_manifest_sha256='9b3366b350ef2b23fd285fc9d97d876bf1ae6e2fc0f8613c647640f01184502e';
        state_root=(Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'YimeCore Experimental Trial');
        target_root=('C:\Program Files\YimeCore Experimental Trial\native-desktop-rehearsal-'+$AttemptId);
        archive_parent=$archive;output_root=(Join-Path $archive ('native-maintenance-rollback-'+$AttemptId));
        backup_root=(Join-Path $archive ('native-maintenance-backup-'+$AttemptId));
        outcome_path=(Join-Path $archive ('native-desktop-rehearsal-'+$AttemptId+'.json'));
        powershell=(Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) 'System32\WindowsPowerShell\v1.0\powershell.exe')}
}
function Get-YimeCoreNativeRollbackCollectionPlan {
    [CmdletBinding()]param([Parameter(Mandatory)]$AttemptId)
    Assert-CollectionAttempt $AttemptId
    [pscustomobject]@{schema_version='yimecore-native-rollback-collection-plan-v1';layout=(Get-CollectionLayout $AttemptId);
        steps=@('retain ordinary native PS5 Explorer initiator','open fixed public candidate leases','backup with pinned normal helper and retained child exit 0',
            'verify fresh backup bytes and independent before observations','direct same-SID UAC fault controller with retained initiator',
            'wait original child handle and bind typed outcome','compare independent after observations');
        timeout_policy='Mark overtime, keep the PS5 initiator alive until the original child exits, then refuse to advance';
        rollback_acceptance=$false;execution_authorized=$false;ready_to_execute=$false;installed_package_read=$false;user_state_read=$false;
        installer_executed=$false;L6_sealed=$false;local_product_ready=$false;public_release_ready=$false}
}
function Initialize-CollectionDependencies {
    if($script:CollectionDependencyImports.Count -ne $script:CollectionModules.Count){throw 'Collection dependency definitions are incomplete'}
    foreach($command in @('Open-YimeCoreNativeMaintenanceContext','Open-YimeCoreLocal13MaintenanceInputs','Open-YimeCoreNativeMaintenanceChild',
        'Read-YimeCoreNativeMaintenanceBackup','Get-YimeCoreNativeMaintenanceDataSnapshot','Get-YimeCoreNativeMaintenanceSnapshot',
        'Get-YimeCoreNativeMaintenanceProcesses','Read-YimeCoreNativeRehearsalOutcome')){Get-Command $command -ErrorAction Stop | Out-Null}
}
function Open-CollectionContext($Layout) {
    if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSEdition -cne 'Desktop'){throw 'Execute requires the retained ordinary Windows PowerShell 5.1 parent'}
    $context=Open-YimeCoreNativeMaintenanceContext -TargetUserSid $Layout.sid
    try {
        $first=$context.evidence.ancestry[0]
        if($first.pid -ne $PID -or $first.image -ine $Layout.powershell){throw 'Initiator is not the native PS5 process'}
        return [pscustomobject]@{context=$context;initiator=([string]$first.pid+':'+[string]$first.creation_filetime)}
    }catch{Close-YimeCoreNativeMaintenanceContext $context;throw}
}
function Close-CollectionContext($Context){if($Context){Close-YimeCoreNativeMaintenanceContext $Context.context}}
function Open-CollectionSources {
    $streams=New-Object 'Collections.Generic.List[object]';$records=@()
    try {
        foreach($name in (@('native-rollback-collection.psm1','invoke-native-rollback-collection.ps1')+$script:CollectionModules+
            @('native-maintenance-process-facts.cs','../dual-product/rime-pime-dp1u-native-facts.cs'))){
            $path=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $name));$s=[IO.File]::Open($path,'Open','Read','Read');$streams.Add($s)
            $sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash($s))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
            $records+=@([pscustomobject]@{path=$path;bytes=$s.Length;sha256=$hash});$s.Position=0
        }
        [pscustomobject]@{streams=$streams;records=$records}
    }catch{foreach($s in $streams){$s.Dispose()};throw}
}
function Close-CollectionSources($Sources){if($Sources){foreach($s in $Sources.streams){$s.Dispose()}}}
function Open-CollectionInputs {Open-YimeCoreLocal13MaintenanceInputs}
function Close-CollectionInputs($Inputs){if($Inputs){Close-YimeCoreLocal13MaintenanceInputs $Inputs}}
function Assert-CollectionFreshPaths($Layout) {
    foreach($path in @($Layout.backup_root,$Layout.target_root,$Layout.outcome_path,$Layout.output_root)){
        if(Test-Path -LiteralPath $path){throw 'An attempt path is occupied; preserve it and use a fresh attempt'}
        $cursor=Split-Path -Parent $path
        while($cursor){if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect attempt path rejected'}};$cursor=Split-Path -Parent $cursor}
    }
}
function Assert-CollectionPrevious($Layout) {
    # Public manifest only. The pinned normal backup helper independently checks
    # the complete installed context before it stops any writer.
    $path=Join-Path $Layout.previous_root 'package-manifest.json'
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Layout.previous_manifest_sha256){throw 'The reviewed previous installation changed'}
}
function New-CollectionOutput($Layout){New-YimeCoreNativeObservationDirectory -OutputRoot $Layout.output_root}
function Write-CollectionJson($Root,[string]$Name,$Value) {
    if($Name -cnotmatch '^[a-z0-9-]+\.json$'){throw 'Fixed observation leaf required'}
    $path=Join-Path $Root $Name
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
    try {
        [Yime.Dp1UNative.Facts]::VerifyFileHandle($stream,$path) | Out-Null
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 100)+"`n")
        $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)
    } finally {$stream.Dispose()}
}
function Quote-CollectionArgument([string]$Value) {
    if(-not $Value -or $Value -match '[\x00-\x1f"]' -or $Value.EndsWith('\')){throw 'Unsafe fixed command argument'}
    '"'+$Value+'"'
}
function New-CollectionStartInfo($Layout,$Inputs,[ValidateSet('backup','controller')][string]$Kind,[string]$Initiator) {
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Layout.powershell
    $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $info.CreateNoWindow=$true
    if($Kind -ceq 'backup'){
        $helper=Join-Path $Inputs.normal.root 'maintenance\backup-local-trial-state.ps1'
        $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-CollectionArgument $helper),
            '-BackupRoot',(Quote-CollectionArgument $Layout.backup_root),'-InstalledPackageRoot',(Quote-CollectionArgument $Layout.previous_root))
        $info.UseShellExecute=$false;$info.WorkingDirectory=$Inputs.normal.root
    }else{
        if($Initiator -cnotmatch '^[1-9][0-9]*:[1-9][0-9]*$'){throw 'Retained initiator identity required'}
        $helper=Join-Path $Inputs.fault.root 'maintenance\Manage-YimeCoreTrial.ps1'
        $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-CollectionArgument $helper),'-Action','Install',
            '-PackageRoot',(Quote-CollectionArgument $Inputs.fault.root),'-InstallRoot',(Quote-CollectionArgument $Layout.target_root),
            '-StateRoot',(Quote-CollectionArgument $Layout.state_root),'-TargetUserSid',(Quote-CollectionArgument $Layout.sid),
            '-NativeDesktop','-NativeDesktopRehearsal','-NoElevation','-StandardUserInitiator',(Quote-CollectionArgument $Initiator),
            '-RehearsalAttemptId',(Quote-CollectionArgument $Layout.attempt_id),'-RehearsalOutcomePath',(Quote-CollectionArgument $Layout.outcome_path))
        $info.UseShellExecute=$true;$info.Verb='runas';$info.WorkingDirectory=$Inputs.fault.root
    }
    # Do not redirect stdio: restored resident descendants can inherit pipe
    # handles and make EOF outlive the controller. Wait the original handle.
    $info.Arguments=$arguments -join ' ';return $info
}
function Start-CollectionChild($Info){$child=[Diagnostics.Process]::Start($Info);if(-not $child){throw 'No child process was created'};return $child}
function Open-CollectionChild($Process,$Image){Open-YimeCoreNativeMaintenanceChild -Process $Process -ExpectedImagePath $Image}
function Wait-CollectionChildSlice($Lease){Wait-YimeCoreNativeMaintenanceChild -Lease $Lease -TimeoutMilliseconds 1000}
function Close-CollectionChild($Lease){if($Lease){Close-YimeCoreNativeMaintenanceChild -Lease $Lease}}
function Test-CollectionBudgetExceeded($Timer) {$Timer.ElapsedMilliseconds -ge 300000}
function Wait-CollectionChild($Lease) {
    $timer=[Diagnostics.Stopwatch]::StartNew();$overtime=$false
    do {
        $observation=Wait-CollectionChildSlice $Lease
        if($observation.exit_observed -isnot [bool] -or $observation.actual_exit_os_observed -isnot [bool]){throw 'Child observer returned invalid literal facts'}
        if(Test-CollectionBudgetExceeded $timer){$overtime=$true}
    }while(-not $observation.exit_observed)
    if(-not $observation.actual_exit_os_observed -or ($observation.exit_code -isnot [int] -and $observation.exit_code -isnot [long])){throw 'No original child OS exit was observed'}
    [pscustomobject]@{observation=$observation;execution_budget_exceeded=$overtime;parent_retained_until_child_exit=$true}
}
function Drain-CollectionChild($Process) {
    if($null -ne $Process){
        # Includes Open/Wait/receipt failures. Do not let the initiating PS5
        # process end while a controller still needs its ordinary launch token.
        $Process.WaitForExit();$Process.Dispose()
    }
}
function Read-CollectionBackup($Layout,$Child) {
    Read-YimeCoreNativeMaintenanceBackup -BackupRoot $Layout.backup_root -ExpectedStateRoot $Layout.state_root `
        -ExpectedInstallRoot $Layout.previous_root -ExpectedPreviousManifestSha256 $Layout.previous_manifest_sha256 -ActualBackupExitCode $Child.exit_code
}
function Read-CollectionData($Root,[bool]$Shared) {
    Get-YimeCoreNativeMaintenanceDataSnapshot -StateRoot $Root -BaselineSchemaVersion 'yimecore-native-maintenance-data-v1' -SharedObservation:$Shared
}
function Compare-CollectionData($Before,$After){Compare-YimeCoreNativeMaintenanceDataSnapshots -Before $Before -After $After -AllowDifferentRoots}
function Assert-CollectionBackupDataBinding($Layout,$Backup,$Data) {
    # The backup reader already validated the entire archive and released its
    # leases. Bind the later data observation to those exact verified bytes;
    # comparing two freshly changed B trees must not replace verified baseline A.
    Assert-CollectionTrue $Backup.static_backup_verified 'backup verification before binding'
    $stateRoot=Join-Path $Layout.backup_root 'state'
    if($Data.schema_version -isnot [string] -or $Data.schema_version -cne 'yimecore-native-maintenance-data-v1' -or
        $Data.state_root -isnot [string] -or $Data.state_root -cne $stateRoot -or
        $Backup.state_reference.root -isnot [string] -or $Backup.state_reference.root -cne $stateRoot -or
        $Backup.manifest.backup_root -isnot [string] -or $Backup.manifest.backup_root -cne $Layout.backup_root -or
        $Backup.manifest.source_state_root -isnot [string] -or $Backup.manifest.source_state_root -cne $Layout.state_root -or
        $Backup.manifest.state_files -isnot [array] -or $Backup.state_reference.directories -isnot [array] -or $Data.records -isnot [array]){throw 'Backup data observation does not bind the verified archive and source roots'}
    $categories=@('learning.json','professional-lexicons.json','speech.json','yime_blocklist.txt','yime_user_phrases.txt','yimecore_experimental_toolbar_state.json')
    $expected=@{};$expectedDirs=@{};$actual=@{};$actualDirs=@{}
    foreach($row in $Backup.manifest.state_files){
        if($row.path -isnot [string]){throw 'Literal backup record path required'}
        if($row.path.StartsWith('user-model/',[StringComparison]::Ordinal) -or $categories -ccontains $row.path -or $row.path -ceq 'runtime-config.json'){
            Assert-CollectionBoundFile $row
            if($expected.ContainsKey($row.path)){throw 'Duplicate verified backup data record'};$expected[$row.path]=$row
        }
    }
    foreach($relative in $Backup.state_reference.directories){
        if($relative -isnot [string]){throw 'Literal observed backup directory required'}
        if($relative -ceq 'user-model' -or $relative.StartsWith('user-model/',[StringComparison]::Ordinal)){
            if($expectedDirs.ContainsKey($relative)){throw 'Duplicate observed backup directory'};$expectedDirs[$relative]=$relative
        }
    }
    foreach($row in $Data.records){
        if($row.path -isnot [string] -or $row.kind -isnot [string]){throw 'Literal data path and kind required'}
        if($row.kind -ceq 'file'){
            Assert-CollectionBoundFile $row
            if(-not $expected.ContainsKey($row.path) -or $row.path -ceq 'runtime-config.json' -or $actual.ContainsKey($row.path)){throw 'Added duplicate or misplaced data file'}
            $actual[$row.path]=$row
        }elseif($row.kind -ceq 'directory'){
            if(-not $expectedDirs.ContainsKey($row.path) -or $expectedDirs[$row.path] -cne $row.path -or $actualDirs.ContainsKey($row.path)){throw 'Added or duplicate data directory'}
            $actualDirs[$row.path]=$row
        }else{throw 'Unsupported bound data kind'}
    }
    $runtime=$Data.runtime_config
    if($runtime.path -isnot [string] -or $runtime.path -cne 'runtime-config.json' -or $runtime.kind -isnot [string]){throw 'Runtime configuration record is not canonical'}
    if($runtime.kind -ceq 'file'){
        Assert-CollectionBoundFile $runtime
        if(-not $expected.ContainsKey('runtime-config.json')){throw 'Runtime configuration was added after verified backup'};$actual['runtime-config.json']=$runtime
    }elseif($runtime.kind -cne 'absent' -or $expected.ContainsKey('runtime-config.json')){throw 'Runtime configuration is missing or changed kind'}
    if($expected.Count -ne $actual.Count -or $expectedDirs.Count -ne $actualDirs.Count){throw 'Verified backup data membership is missing from later observation'}
    foreach($path in $expected.Keys){
        $before=$expected[$path];$after=$actual[$path]
        if($null -eq $after -or $before.path -cne $after.path -or $before.bytes -ne $after.bytes -or $before.sha256 -cne $after.sha256){throw 'Later backup data differs from verified manifest bytes'}
    }
    foreach($hash in @($Backup.backup_manifest.sha256,$Data.snapshot_sha256)){if($hash -isnot [string] -or $hash -cnotmatch '^[a-f0-9]{64}$'){throw 'Binding evidence digest missing'}}
    [pscustomobject]@{schema_version='yimecore-native-rollback-backup-data-binding-v1';bound=$true;
        backup_manifest_sha256=$Backup.backup_manifest.sha256;data_snapshot_sha256=$Data.snapshot_sha256;
        state_root=$stateRoot;protected_file_count=$actual.Count;protected_directory_count=$actualDirs.Count;
        files_bound_to_verified_manifest=$true;directories_bound_to_backup_reader_observation=$true;directories_recorded_by_manifest=$false;
        continuous_membership_protection=$false;independent_restore_verified=$false;execution_authorized=$false}
}
function Assert-CollectionBoundFile($Row) {
    if($Row.path -isnot [string] -or [string]::IsNullOrWhiteSpace($Row.path) -or
        ($Row.bytes -isnot [int] -and $Row.bytes -isnot [long]) -or $Row.bytes -lt 0 -or
        $Row.sha256 -isnot [string] -or $Row.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Literal bound file path size and SHA256 required'}
}
function Read-CollectionRegistry($Layout){Get-YimeCoreNativeMaintenanceSnapshot -TargetUserSid $Layout.sid}
function Compare-CollectionRegistry($Before,$After){Assert-YimeCoreNativeMaintenanceSnapshotEqual -Before $Before -After $After}
function Read-CollectionProcesses($Layout,$Backup) {
    $runtime=@($Backup.manifest.package_files|Where-Object path -CEQ 'bin/YimeCoreTrialRuntime.exe')
    $broker=@($Backup.manifest.package_files|Where-Object path -CEQ 'bin/YimeBroker.exe')
    if($runtime.Count -ne 1 -or $broker.Count -ne 1){throw 'Backup lacks the exact previous process image records'}
    Get-YimeCoreNativeMaintenanceProcesses -TargetUserSid $Layout.sid -ExpectedInstallRoot $Layout.previous_root `
        -ExpectedRuntimeSha256 $runtime[0].sha256 -ExpectedBrokerSha256 $broker[0].sha256
}
function Read-CollectionOutcome($Layout,$Inputs,$Child) {
    Read-YimeCoreNativeRehearsalOutcome -OutcomePath $Layout.outcome_path -ActualControllerExitCode $Child.exit_code `
        -ExpectedAttemptId $Layout.attempt_id -ExpectedTargetUserSid $Layout.sid -ExpectedControllerSha256 $Inputs.controller_sha256 `
        -ExpectedNormalPackageManifestSha256 $Inputs.normal.manifest_sha256 -ExpectedFailureManifestSha256 $Inputs.fault.manifest_sha256 `
        -ExpectedProducerPid $Child.pid -ExpectedProducerCreationFileTime $Child.creation_filetime -ExpectedOutcomeDirectory $Layout.archive_parent `
        -ExpectedStateRoot $Layout.state_root -ExpectedPreviousInstallRoot $Layout.previous_root -ExpectedTargetInstallRoot $Layout.target_root
}
function Assert-CollectionTrue($Value,[string]$Name){if($Value -isnot [bool] -or -not $Value){throw "Required observation failed: $Name"}}
function Invoke-YimeCoreNativeRollbackCollection {
    [CmdletBinding()]param([Parameter(Mandatory)][switch]$Execute,[Parameter(Mandatory)]$AttemptId)
    if(-not $Execute){throw 'Explicit Execute is required; use the separate static Plan function'}
    Assert-CollectionAttempt $AttemptId
    Initialize-CollectionDependencies
    $layout=Get-CollectionLayout $AttemptId
    $context=$null;$sources=$null;$inputs=$null;$out=$null;$child=$null;$lease=$null;$stage='native-parent';$completed=$false
    $result=[ordered]@{schema_version='yimecore-native-rollback-collection-v1';attempt_id=$AttemptId;collection_completed=$false;
        backup_started=$false;controller_started=$false;execution_requested=$true;execution_authorized=$false;
        controller_exit_os_observed=$false;controller_loaded_script_authenticated=$false;rollback_acceptance=$false;
        independent_data_restore_verified=$false;deferred_delete_absence_verified=$false;independent_system_visibility_verified=$false;
        startup_verified=$false;runtime_ready_verified=$false;L6_sealed=$false;local_product_ready=$false;public_release_ready=$false}
    try {
        $context=Open-CollectionContext $layout
        $sources=Open-CollectionSources;$stage='candidate-inputs';$inputs=Open-CollectionInputs
        $stage='fresh-paths';Assert-CollectionFreshPaths $layout;Assert-CollectionPrevious $layout
        $out=New-CollectionOutput $layout
        Write-CollectionJson $out 'source-observation.json' $sources.records
        $stage='backup-child';$info=New-CollectionStartInfo $layout $inputs 'backup' $context.initiator
        $child=Start-CollectionChild $info;$result.backup_started=$true;$lease=Open-CollectionChild $child $layout.powershell
        $wait=Wait-CollectionChild $lease;Write-CollectionJson $out 'backup-child.json' $wait
        Close-CollectionChild $lease;$lease=$null;Drain-CollectionChild $child;$child=$null
        if($wait.execution_budget_exceeded -or $wait.observation.exit_code -ne 0){throw 'Backup child failed or exceeded budget; do not begin fault rehearsal'}
        $stage='backup-integrity';$backup=Read-CollectionBackup $layout $wait.observation;Assert-CollectionTrue $backup.static_backup_verified 'backup bytes'
        Write-CollectionJson $out 'backup-verification.json' $backup
        $stage='before-observations';$backupData=Read-CollectionData (Join-Path $layout.backup_root 'state') $false
        $stage='backup-data-binding';$backupDataBinding=Assert-CollectionBackupDataBinding $layout $backup $backupData
        $stage='before-observations'
        $beforeData=Read-CollectionData $layout.state_root $true;$beforeEquality=Compare-CollectionData $backupData $beforeData
        Assert-CollectionTrue $beforeEquality.unchanged 'backup and current data/config'
        $beforeRegistry=Read-CollectionRegistry $layout;$beforeProcesses=Read-CollectionProcesses $layout $backup
        Write-CollectionJson $out 'before-observations.json' ([ordered]@{backup_data=$backupData;backup_data_binding=$backupDataBinding;data=$beforeData;registry=$beforeRegistry;processes=$beforeProcesses})
        $stage='controller-child';$info=New-CollectionStartInfo $layout $inputs 'controller' $context.initiator
        $child=Start-CollectionChild $info;$result.controller_started=$true;$lease=Open-CollectionChild $child $layout.powershell
        $wait=Wait-CollectionChild $lease;Write-CollectionJson $out 'controller-child.json' $wait
        Close-CollectionChild $lease;$lease=$null;Drain-CollectionChild $child;$child=$null
        $result.controller_exit_os_observed=$wait.observation.actual_exit_os_observed
        if($wait.execution_budget_exceeded){throw 'Controller exceeded budget; original child has exited but no further maintenance may proceed'}
        $stage='typed-outcome';$outcome=Read-CollectionOutcome $layout $inputs $wait.observation
        Assert-CollectionTrue $outcome.expected_fault_procedure_observed 'expected fault procedure record'
        Write-CollectionJson $out 'typed-outcome.json' $outcome
        $stage='after-observations';$afterRegistry=Read-CollectionRegistry $layout;$registryEquality=Compare-CollectionRegistry $beforeRegistry $afterRegistry
        Assert-CollectionTrue $registryEquality.equal 'registry equality'
        $afterData=Read-CollectionData $layout.state_root $true;$dataEquality=Compare-CollectionData $backupData $afterData
        Assert-CollectionTrue $dataEquality.unchanged 'data/config equality'
        $afterProcesses=Read-CollectionProcesses $layout $backup
        Write-CollectionJson $out 'after-observations.json' ([ordered]@{registry=$afterRegistry;data=$afterData;processes=$afterProcesses;registry_equality=$registryEquality;data_equality=$dataEquality})
        $result.collection_completed=$true;$completed=$true
        $result.observed_scope='Original child OS exit plus typed fault record and independent point observations; no restore/uninstall, continuous protection, startup or final acceptance inferred'
    }finally{
        try{Drain-CollectionChild $child}finally{
            try{Close-CollectionChild $lease}finally{
                try{Close-CollectionInputs $inputs}finally{try{Close-CollectionSources $sources}finally{Close-CollectionContext $context}}
            }
        }
        if($out){$result.final_stage=$stage;Write-CollectionJson $out 'collection-summary.json' $result}
    }
    if(-not $completed){throw 'Rollback evidence collection is incomplete'}
    [pscustomobject]$result
}
Export-ModuleMember -Function Get-YimeCoreNativeRollbackCollectionPlan,Invoke-YimeCoreNativeRollbackCollection
