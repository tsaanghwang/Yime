[CmdletBinding()]
param([Parameter(Mandatory)][string]$BackupRoot,[Parameter(Mandatory)][string]$RecoveryProbe,[switch]$LocalProduct)
$ErrorActionPreference='Stop'
function ConvertFrom-LocalRestoreEvidenceJson($Json) {
    if($Json -isnot [string] -or -not $Json.TrimStart().StartsWith('{')){throw 'A recovery evidence JSON object is required.'}
    # ConvertFrom-Json may collapse a one-element array or overwrite duplicate
    # object keys in PS5. Preserve that distinction before normal JSON parsing.
    $frames=[Collections.Generic.Stack[object]]::new()
    for($i=0;$i -lt $Json.Length;$i++) {
        $character=$Json[$i]
        if($character -eq '{'){$frames.Push([Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase));continue}
        if($character -eq '['){$frames.Push($null);continue}
        if($character -eq '}' -or $character -eq ']'){if($frames.Count -eq 0){throw 'Invalid recovery JSON nesting.'};[void]$frames.Pop();continue}
        if($character -ne '"'){continue}
        $start=$i;$i++;$closed=$false
        for(;$i -lt $Json.Length;$i++) {
            if($Json[$i] -eq '\'){$i++;continue}
            if($Json[$i] -eq '"'){$closed=$true;break}
        }
        if(-not $closed){throw 'Unterminated recovery JSON string.'}
        $next=$i+1;while($next -lt $Json.Length -and [char]::IsWhiteSpace($Json[$next])){$next++}
        if($next -lt $Json.Length -and $Json[$next] -eq ':') {
            if($frames.Count -eq 0 -or $null -eq $frames.Peek()){throw 'Invalid recovery JSON property.'}
            $token=$Json.Substring($start,$i-$start+1)
            $key=(ConvertFrom-Json -InputObject ('{"key":'+$token+'}')).key
            if(-not $frames.Peek().Add($key)){throw 'Duplicate recovery JSON property.'}
        }
    }
    $value=ConvertFrom-Json -InputObject $Json
    if($value -isnot [pscustomobject]){throw 'A recovery evidence JSON object is required.'}
    return $value
}
function Assert-LocalRestoreBackupEvidence($Manifest,$ExpectedStateRoot) {
    if($Manifest -isnot [pscustomobject] -or $Manifest.schema_version -isnot [string] -or
        $Manifest.schema_version -cne 'yimecore-quiesced-backup-v1' -or
        $Manifest.source_state_root -isnot [string] -or $Manifest.source_state_root -cne $ExpectedStateRoot) {
        throw 'Invalid quiesced backup identity.'
    }
    foreach($name in @('passed','writers_stopped','native_context_verified')) {
        if($Manifest.$name -isnot [bool] -or -not $Manifest.$name) {
            throw "Quiesced backup requires literal true: $name"
        }
    }
}
function Assert-LocalRestoreRecoveryEvidence($Evidence,$ExpectedClone,$ExpectedSourceId) {
    # model-recovery-probe.go has no schema_version field. Preserve its existing
    # six-field protocol, including the actual DurableUserModelStats shape.
    $fields=@('passed','generation','source_id','learned_record_count','stats','clone')
    if($Evidence -isnot [pscustomobject] -or @($Evidence.PSObject.Properties).Count -ne $fields.Count) {
        throw 'Invalid recovery probe result shape.'
    }
    foreach($name in @($Evidence.PSObject.Properties.Name)) {
        if($name -cnotin $fields){throw 'Unexpected recovery probe result field.'}
    }
    if($Evidence.passed -isnot [bool] -or -not $Evidence.passed -or
        $ExpectedClone -isnot [string] -or [string]::IsNullOrWhiteSpace($ExpectedClone) -or
        $ExpectedSourceId -isnot [string] -or [string]::IsNullOrWhiteSpace($ExpectedSourceId) -or
        $Evidence.clone -isnot [string] -or $Evidence.clone -cne $ExpectedClone -or
        $Evidence.source_id -isnot [string] -or $Evidence.source_id -cne $ExpectedSourceId) {
        throw 'Recovery probe did not confirm the exact clone and source identity.'
    }
    $statsRequired=@('snapshot_generation','journal_generation','recovered_mutations','truncated_tail_bytes',
        'checkpoint_failures','compactions','compaction_failures')
    $statsOptional=@('last_checkpoint_error','last_compaction_error','rollback_snapshot_path','migrated_from_schema')
    if($Evidence.stats -isnot [pscustomobject]){throw 'Invalid recovery probe statistics.'}
    foreach($name in $statsRequired) {
        if(@($Evidence.stats.PSObject.Properties.Name) -cnotcontains $name){throw 'Missing recovery probe statistic.'}
    }
    foreach($name in @($Evidence.stats.PSObject.Properties.Name)) {
        if($name -cnotin ($statsRequired+$statsOptional)){throw 'Unexpected recovery probe statistic.'}
        if($name -cin $statsOptional -and $Evidence.stats.$name -isnot [string]){throw 'Invalid recovery probe diagnostic type.'}
    }
    foreach($name in @('generation','learned_record_count')) {
        $value=$Evidence.$name
        if(($value -isnot [int] -and $value -isnot [long] -and $value -isnot [uint64]) -or $value -lt 0) {
            throw 'Recovery probe counters must be literal nonnegative integers.'
        }
    }
    foreach($name in $statsRequired) {
        # Do not collect these through a pipeline: it would enumerate an array
        # value into individually valid numbers and erase the invalid type.
        $value=$Evidence.stats.$name
        if(($value -isnot [int] -and $value -isnot [long] -and $value -isnot [uint64]) -or $value -lt 0) {
            throw 'Recovery probe counters must be literal nonnegative integers.'
        }
    }
}
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
$scope=Get-YimeCoreDevelopmentScope
Assert-YimeCoreUnpackagedDataMaintenance
$stateRoot=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'))
if ($LocalProduct) {
    . (Join-Path $PSScriptRoot 'local-package-contract.ps1')
    . (Join-Path $PSScriptRoot 'local-product-runtime.ps1')
    $localContext = Assert-LocalProductInstalledContext (Split-Path -Parent $PSScriptRoot) $stateRoot
    if ([IO.Path]::GetFullPath($RecoveryProbe) -ine (Join-Path $localContext.package.root 'bin\YimeCoreRecoveryProbe.exe')) {
        throw 'Local restore requires the manifest-verified packaged recovery probe.'
    }
    Initialize-LocalProductLauncher $localContext
    $null = Assert-LocalProductLiveRuntime $localContext
}
$backup=[IO.Path]::GetFullPath($BackupRoot)
$allowed=[IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'YimeCore Recovery Archives'))+'\'
if (-not $backup.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) {throw 'Backup is outside recovery archives.'}
Assert-YimeCorePlainPath $backup
Assert-YimeCorePlainPath $stateRoot
$manifest=ConvertFrom-LocalRestoreEvidenceJson (Get-Content -Encoding UTF8 -LiteralPath (Join-Path $backup 'backup-manifest.json') -Raw)
Assert-LocalRestoreBackupEvidence $manifest $stateRoot
if (-not (Test-YimeCoreScopeEvidence $manifest.development_scope $scope)) {throw 'Invalid quiesced backup identity.'}
if (Get-Process WINWORD -ErrorAction SilentlyContinue) {throw 'Close Word before restore.'}
if(-not $manifest.data_files){throw 'Fresh native-context backup with explicit data records required.'}
$archiveState=Join-Path $backup 'state'
Assert-YimeCoreArchiveRecords $archiveState $manifest.state_files
Assert-YimeCoreUnchangedData $manifest.data_files @(Get-YimeCoreDataRecords $archiveState)
foreach($record in $manifest.state_files) {
    $path=[IO.Path]::GetFullPath((Join-Path $archiveState $record.path))
    Assert-YimeCorePlainPath $path
    if (-not $path.StartsWith($archiveState+'\',[StringComparison]::OrdinalIgnoreCase) -or
        (Get-Item -LiteralPath $path).Length -ne $record.bytes -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $record.sha256) {throw "Backup integrity failed: $($record.path)"}
}
$cloneRoot=Join-Path $backup 'recovery-clones'
if(Test-Path -LiteralPath $cloneRoot){throw 'Use a fresh backup; recovery-clones already exists.'}
New-Item -ItemType Directory -Path $cloneRoot | Out-Null
$recoveryResults=@()
foreach($record in @($manifest.state_files | Where-Object { $_.path -like 'user-model/*user-model.journal' })) {
    $sourceDir=Split-Path -Parent (Join-Path $archiveState $record.path)
    $clone=Join-Path $cloneRoot ([Guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $sourceDir -Destination $clone -Recurse
    New-Item -ItemType File -Path (Join-Path $clone '.yime-recovery-clone') | Out-Null
    $first=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $clone 'user-model.journal') -TotalCount 1 | ConvertFrom-Json
    if($first.source_id -isnot [string] -or [string]::IsNullOrWhiteSpace($first.source_id)){throw 'Journal source identity must be a literal nonempty string.'}
    $evidence=Join-Path $clone 'recovery.json'
    if(Test-Path -LiteralPath $evidence){throw 'Recovery clone contains a preexisting probe result.'}
    & $RecoveryProbe -clone $clone -source-id $first.source_id -output $evidence
    if($LASTEXITCODE -isnot [int] -or $LASTEXITCODE -ne 0){throw "Offline journal recovery failed: $($record.path)"}
    $recovery=ConvertFrom-LocalRestoreEvidenceJson (Get-Content -Encoding UTF8 -LiteralPath $evidence -Raw)
    Assert-LocalRestoreRecoveryEvidence $recovery $clone $first.source_id
    $recoveryResults+=,$recovery
}
if(-not $recoveryResults.Count){throw 'No durable model journals found; cannot prove recovery.'}
$config=Get-Content -Encoding UTF8 (Join-Path $stateRoot 'runtime-config.json') -Raw | ConvertFrom-Json
$status=Get-Content -Encoding UTF8 (Join-Path $stateRoot 'runtime-status.json') -Raw | ConvertFrom-Json
if(-not (Get-YimeCoreLiveRuntimeEvidence $stateRoot).passed){throw 'Expected verified live runtime/Broker before restore.'}
$liveModel=Join-Path $stateRoot 'user-model'
$safetyModel=Join-Path $backup 'pre-restore-user-model'
$failedModel=Join-Path $backup 'failed-restore-user-model'
foreach($target in @($safetyModel,$failedModel)){if(Test-Path -LiteralPath $target){throw "Safety target already exists: $target"}}
# All directory moves use resolved explicit children of the verified state/archive.
if([IO.Path]::GetFullPath($liveModel) -ne ($stateRoot+'\user-model')){throw 'Invalid live model path.'}
$stopped=$false; $moved=$false; $restored=$false; $safetyFiles=$null
try {
    & (Join-Path $PSScriptRoot 'stop-e6c-trial-runtime.ps1') | Out-Null
    $stopped=$true
    foreach($processId in @([int]$status.runtime_pid,[int]$status.broker_pid)) {
        if(Get-Process -Id $processId -ErrorAction SilentlyContinue){throw "Writer still running: $processId"}
    }
    # Protect every restored category, including new/deleted files and settings.
    Assert-YimeCoreUnchangedData $manifest.data_files @(Get-YimeCoreDataRecords $stateRoot)
    $dataRecords=@($manifest.data_files)
    $safetyFiles=Join-Path $backup 'pre-restore-settings'
    if(Test-Path -LiteralPath $safetyFiles){throw 'Settings safety copy already exists.'}
    New-Item -ItemType Directory -Path $safetyFiles | Out-Null
    foreach($record in @($dataRecords | Where-Object {$_.path -notmatch '/'})){
        Copy-Item -LiteralPath (Join-Path $stateRoot $record.path) -Destination $safetyFiles
    }
    Move-Item -LiteralPath $liveModel -Destination $safetyModel
    $moved=$true
    Copy-Item -LiteralPath (Join-Path $archiveState 'user-model') -Destination $liveModel -Recurse
    # Restore only user data/settings. Never overwrite current runtime paths,
    # status, registration, diagnostic output or index-control requests.
    foreach($record in @($dataRecords | Where-Object {$_.path -notmatch '/'})){
        $target=Join-Path $stateRoot $record.path
        Copy-Item -LiteralPath (Join-Path $archiveState $record.path) -Destination $target -Force
    }
    $nativeFiles=@($dataRecords|ForEach-Object {Assert-YimeCoreNativeFile (Join-Path $stateRoot $_.path)})
    foreach($record in $dataRecords){
        if((Get-FileHash -LiteralPath (Join-Path $stateRoot $record.path) -Algorithm SHA256).Hash -ne $record.sha256){throw "Restored hash mismatch: $($record.path)"}
    }
    $restored=$true
} catch {
    if($moved){
        if(Test-Path -LiteralPath $liveModel){Move-Item -LiteralPath $liveModel -Destination $failedModel}
        Move-Item -LiteralPath $safetyModel -Destination $liveModel
    }
    if($safetyFiles -and (Test-Path -LiteralPath $safetyFiles)){
        foreach($file in Get-ChildItem -LiteralPath $safetyFiles -File){Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $stateRoot $file.Name) -Force}
    }
    throw
} finally {
    if($stopped){
        if ($LocalProduct) { Start-LocalProductRuntime $localContext | Out-Null }
        else { & (Join-Path $PSScriptRoot 'start-e6c-trial-runtime.ps1') | Out-Null }
    }
}
& (Join-Path $PSScriptRoot 'verify-e6c-trial-runtime.ps1') -LocalProduct:$LocalProduct | Out-Null
if($LASTEXITCODE -ne 0){throw 'Restored runtime probe failed.'}
$liveAfter=Get-YimeCoreLiveRuntimeEvidence $stateRoot
if(-not $liveAfter.passed){throw 'Restored runtime has no verified live process identity.'}
$result=[ordered]@{schema_version='yimecore-local-restore-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');
    development_scope=$scope;backup_root=$backup;offline_recovery=$recoveryResults;
    live_data_restored=$restored;restored_file_count=$dataRecords.Count;all_restored_hashes_match=$true;
    original_model_preserved_at=$safetyModel;runtime_three_mode_probe_passed=$true;
    native_context_verified=$true;system_visible_restored_files=$nativeFiles;live_runtime_after=$liveAfter;
    registry_mutation_requested=$false;passed=$true}
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $backup 'restore-evidence.json') -Encoding utf8
Write-Host "Live data restore passed; original data retained at $safetyModel"
