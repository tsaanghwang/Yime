[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')

$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if((Split-Path -Parent $output) -ine (Join-Path $repo '.tmp\yimecore-experiment') -or
    (Split-Path -Leaf $output) -cnotmatch '^maintenance-config-data-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a fresh immediate .tmp/yimecore-experiment/maintenance-config-data-* fixture output.'
}
Assert-YimeCorePlainPath $output
New-Item -ItemType Directory -Path $output | Out-Null

$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body) {
    try { & $Body; $checks.Add([ordered]@{name=$Name;passed=$true}) }
    catch { $checks.Add([ordered]@{name=$Name;passed=$false;reason=$_.Exception.Message}) }
}
function Assert-True([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message} }
function Must-Reject([scriptblock]$Body,[string]$Message) {
    $rejected=$false
    try { & $Body | Out-Null } catch { $rejected=$true }
    Assert-True $rejected $Message
}
function Write-Config([string]$Root,[string]$Name,[string]$Value) {
    if(-not (Test-Path -LiteralPath $Root)){New-Item -ItemType Directory -Path $Root | Out-Null}
    [IO.File]::WriteAllText((Join-Path $Root $Name),$Value)
}

$learningEnabled='{"schema_version":"yimecore-trial-learning-v1","enabled":true}'
$learningDisabled='{"schema_version":"yimecore-trial-learning-v1","enabled":false}'
$speechEnabled='{"schema_version":"yimecore-speech-settings-v1","enabled":true}'
$speechDisabled='{"schema_version":"yimecore-speech-settings-v1","enabled":false}'
$stateRoot=Join-Path $output 'synthetic-state'
$archiveState=Join-Path $output 'synthetic-archive'
Write-Config $stateRoot 'learning.json' $learningEnabled
Write-Config $stateRoot 'speech.json' $speechEnabled
Write-Config $archiveState 'learning.json' $learningEnabled
Write-Config $archiveState 'speech.json' $speechEnabled
# These are operational files, not portable user settings and not restore targets.
Write-Config $stateRoot 'runtime-config.json' 'synthetic operational state, never restored'
Write-Config $stateRoot 'runtime-status.json' 'synthetic operational state, never restored'
$before=@(Get-YimeCoreDataRecords $stateRoot)

Check 'actual-data-enumeration-includes-exact-learning-and-speech-settings' {
    Assert-True ($before.Count -eq 2) 'Maintenance data_files did not contain exactly the two synthetic product settings.'
    Assert-True (($before.path -join ',') -ceq 'learning.json,speech.json') 'Maintenance data_files omitted or reordered a product setting.'
    foreach($record in $before){
        $path=Join-Path $stateRoot $record.path
        Assert-True ($record.sha256 -ceq (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()) "Setting hash differs: $($record.path)"
    }
}
Check 'operational-state-is-not-a-restore-target' {
    Assert-True (-not ($before.path -contains 'runtime-config.json') -and -not ($before.path -contains 'runtime-status.json')) 'Operational runtime state entered portable settings.'
}
Check 'unchanged-product-settings-accepted' {
    Assert-YimeCoreUnchangedData $before @(Get-YimeCoreDataRecords $stateRoot)
}

Check 'changed-learning-setting-rejects-stale-restore' {
    Write-Config $stateRoot 'learning.json' $learningDisabled
    try { Must-Reject { Assert-YimeCoreUnchangedData $before @(Get-YimeCoreDataRecords $stateRoot) } 'Changed learning setting did not reject stale restore evidence.' }
    finally { Write-Config $stateRoot 'learning.json' $learningEnabled }
}
Check 'added-learning-setting-rejects-stale-restore' {
    $fixture=Join-Path $output 'learning-added'
    Write-Config $fixture 'speech.json' $speechEnabled
    $expected=@(Get-YimeCoreDataRecords $fixture)
    Write-Config $fixture 'learning.json' $learningEnabled
    Must-Reject { Assert-YimeCoreUnchangedData $expected @(Get-YimeCoreDataRecords $fixture) } 'Added learning setting did not reject stale restore evidence.'
}
Check 'deleted-learning-setting-rejects-stale-restore' {
    $fixture=Join-Path $output 'learning-deleted'
    Write-Config $fixture 'learning.json' $learningEnabled
    Write-Config $fixture 'speech.json' $speechEnabled
    $expected=@(Get-YimeCoreDataRecords $fixture)
    Remove-Item -LiteralPath (Join-Path $fixture 'learning.json')
    Must-Reject { Assert-YimeCoreUnchangedData $expected @(Get-YimeCoreDataRecords $fixture) } 'Deleted learning setting did not reject stale restore evidence.'
}
Check 'changed-speech-setting-rejects-stale-restore' {
    Write-Config $stateRoot 'speech.json' $speechDisabled
    try { Must-Reject { Assert-YimeCoreUnchangedData $before @(Get-YimeCoreDataRecords $stateRoot) } 'Changed speech setting did not reject stale restore evidence.' }
    finally { Write-Config $stateRoot 'speech.json' $speechEnabled }
}
Check 'added-speech-setting-rejects-stale-restore' {
    $fixture=Join-Path $output 'speech-added'
    Write-Config $fixture 'learning.json' $learningEnabled
    $expected=@(Get-YimeCoreDataRecords $fixture)
    Write-Config $fixture 'speech.json' $speechEnabled
    Must-Reject { Assert-YimeCoreUnchangedData $expected @(Get-YimeCoreDataRecords $fixture) } 'Added speech setting did not reject stale restore evidence.'
}
Check 'deleted-speech-setting-rejects-stale-restore' {
    $fixture=Join-Path $output 'speech-deleted'
    Write-Config $fixture 'learning.json' $learningEnabled
    Write-Config $fixture 'speech.json' $speechEnabled
    $expected=@(Get-YimeCoreDataRecords $fixture)
    Remove-Item -LiteralPath (Join-Path $fixture 'speech.json')
    Must-Reject { Assert-YimeCoreUnchangedData $expected @(Get-YimeCoreDataRecords $fixture) } 'Deleted speech setting did not reject stale restore evidence.'
}

$backupPath=Join-Path $PSScriptRoot 'backup-local-trial-state.ps1'
$restorePath=Join-Path $PSScriptRoot 'restore-local-trial-state.ps1'
$backupSource=Get-Content -LiteralPath $backupPath -Raw -Encoding UTF8
$restoreSource=Get-Content -LiteralPath $restorePath -Raw -Encoding UTF8
Check 'backup-manifest-derives-config-list-from-archived-state' {
    Assert-True ($backupSource.Contains('data_files=@(Get-YimeCoreDataRecords $archiveState)')) 'Backup manifest does not derive data_files from the copied archive state.'
}
Check 'restore-checks-archived-and-live-config-freshness' {
    Assert-True ($restoreSource.Contains('Assert-YimeCoreUnchangedData $manifest.data_files @(Get-YimeCoreDataRecords $archiveState)')) 'Restore does not rederive archived data_files before writes.'
    Assert-True ($restoreSource.Contains('Assert-YimeCoreUnchangedData $manifest.data_files @(Get-YimeCoreDataRecords $stateRoot)')) 'Restore does not reject live config changes before writes.'
}
Check 'actual-restore-loop-maps-only-both-private-settings' {
    $tokens=$null;$parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($restorePath,[ref]$tokens,[ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) 'Restore source parse failed.'
    # Select and execute only the exact production data-record loop. Entry code is never imported or run.
    $loops=@($ast.FindAll({param($node)
        $node -is [Management.Automation.Language.ForEachStatementAst] -and
        $node.Extent.Text.Contains("`$_.path -notmatch '/'") -and
        $node.Extent.Text.Contains('Join-Path $archiveState $record.path') -and
        $node.Extent.Text.Contains('Copy-Item')
    },$true))
    Assert-True ($loops.Count -eq 1) 'Unique actual restore data mapping loop not found.'
    $dataRecords=$before
    $script:copied=[Collections.Generic.List[object]]::new()
    function Copy-Item { param($LiteralPath,$Destination,[switch]$Force)
        $script:copied.Add([ordered]@{source=$LiteralPath;destination=$Destination;force=[bool]$Force})
    }
    & ([scriptblock]::Create($loops[0].Extent.Text))
    Assert-True ($script:copied.Count -eq 2) 'Both product settings did not reach the actual restore mapping.'
    foreach($name in @('learning.json','speech.json')) {
        $copy=@($script:copied | Where-Object {$_.source -ceq (Join-Path $archiveState $name)})
        Assert-True ($copy.Count -eq 1 -and $copy[0].destination -ceq (Join-Path $stateRoot $name) -and $copy[0].force) "Restore mapping escaped or omitted $name."
    }
}

$failed=@($checks | Where-Object {-not $_.passed})
$sources=[ordered]@{}
foreach($relative in @('tools/yimecore/local-maintenance-safety.ps1','tools/yimecore/backup-local-trial-state.ps1',
    'tools/yimecore/restore-local-trial-state.ps1','tools/yimecore/test-local-maintenance-config-data.ps1')) {
    $sources[$relative]=(Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$result=[ordered]@{
    schema_version='yimecore-local-maintenance-config-data-fixture-v1'
    passed=($failed.Count -eq 0);checks=$checks.ToArray();checks_count=$checks.Count;failed_count=$failed.Count
    source_sha256=$sources;powershell=$PSVersionTable.PSVersion.ToString()
    actual_restore_or_backup_executed=$false;process_started_or_stopped=$false;registry_mutated=$false
    production_or_user_data_read=$false;installed_recovery_passed=$false
    level='actual-source-data-enumeration-and-AST-mapping-with-mocked-copy'
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding UTF8
Write-Output "Maintenance config data fixture: $($checks.Count) checks, $($failed.Count) failed; $output"
if($failed.Count){exit 1}
