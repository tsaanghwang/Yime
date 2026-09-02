[CmdletBinding()]
param([Parameter(Mandatory)][string]$BackupRoot,[Parameter(Mandatory)][string]$RecoveryProbe,[switch]$LocalProduct)
$ErrorActionPreference='Stop'
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
$manifest=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $backup 'backup-manifest.json') -Raw | ConvertFrom-Json
if ($manifest.schema_version -ne 'yimecore-quiesced-backup-v1' -or -not $manifest.passed -or
    -not $manifest.writers_stopped -or $manifest.source_state_root -ne $stateRoot -or
    -not (Test-YimeCoreScopeEvidence $manifest.development_scope $scope)) {throw 'Invalid quiesced backup identity.'}
if (Get-Process WINWORD -ErrorAction SilentlyContinue) {throw 'Close Word before restore.'}
if(-not $manifest.native_context_verified -or -not $manifest.data_files){throw 'Fresh native-context backup with explicit data records required.'}
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
    $evidence=Join-Path $clone 'recovery.json'
    & $RecoveryProbe -clone $clone -source-id ([string]$first.source_id) -output $evidence
    if($LASTEXITCODE -ne 0){throw "Offline journal recovery failed: $($record.path)"}
    $recoveryResults+=Get-Content -Encoding UTF8 -LiteralPath $evidence -Raw | ConvertFrom-Json
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
