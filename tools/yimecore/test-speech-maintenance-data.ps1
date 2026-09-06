[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if((Split-Path -Parent $output) -ine (Join-Path $repo '.tmp\yimecore-experiment') -or
    (Split-Path -Leaf $output) -cnotmatch '^speech-maintenance-data-[a-zA-Z0-9-]+$' -or (Test-Path -LiteralPath $output)) {
    throw 'Use a fresh immediate .tmp/yimecore-experiment/speech-maintenance-data-* fixture output.'
}
Assert-YimeCorePlainPath $output
New-Item -ItemType Directory -Path $output | Out-Null
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body) {
    try { & $Body; $checks.Add([ordered]@{name=$Name;passed=$true}) }
    catch { $checks.Add([ordered]@{name=$Name;passed=$false;reason=$_.Exception.Message}) }
}
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Must-Reject([scriptblock]$Body) {
    $rejected=$false;try{& $Body | Out-Null}catch{$rejected=$true}
    Assert-True $rejected 'Changed speech settings did not reject stale restore evidence.'
}
$stateRoot=Join-Path $output 'synthetic-state'
$archiveState=Join-Path $output 'synthetic-archive'
New-Item -ItemType Directory -Path $stateRoot,$archiveState | Out-Null
$speechPath=Join-Path $stateRoot 'speech.json'
$enabled='{"schema_version":"yimecore-speech-settings-v1","enabled":true}'
$disabled='{"schema_version":"yimecore-speech-settings-v1","enabled":false}'
[IO.File]::WriteAllText($speechPath,$enabled)
[IO.File]::WriteAllText((Join-Path $archiveState 'speech.json'),$enabled)
# Unrelated operational state must not become a restore target.
[IO.File]::WriteAllText((Join-Path $stateRoot 'runtime-config.json'),'synthetic operational state, never restored')
[IO.File]::WriteAllText((Join-Path $stateRoot 'runtime-status.json'),'synthetic operational state, never restored')
$before=@(Get-YimeCoreDataRecords $stateRoot)
Check 'actual-data-enumeration-includes-speech-setting' {
    Assert-True ($before.Count -eq 1 -and $before[0].path -ceq 'speech.json') 'Speech setting omitted from maintenance data_files.'
    Assert-True ($before[0].sha256 -ceq (Get-FileHash -LiteralPath $speechPath -Algorithm SHA256).Hash.ToLowerInvariant()) 'Speech setting hash differs.'
}
Check 'unchanged-speech-setting-accepted' { Assert-YimeCoreUnchangedData $before @(Get-YimeCoreDataRecords $stateRoot) }
Check 'changed-speech-setting-rejects-stale-restore' {
    [IO.File]::WriteAllText($speechPath,$disabled)
    Must-Reject { Assert-YimeCoreUnchangedData $before @(Get-YimeCoreDataRecords $stateRoot) }
}
Check 'added-speech-setting-rejects-stale-restore' {
    Must-Reject { Assert-YimeCoreUnchangedData @() @(Get-YimeCoreDataRecords $stateRoot) }
}
Check 'deleted-speech-setting-rejects-stale-restore' {
    $withoutSpeech=Join-Path $output 'synthetic-state-without-speech'
    New-Item -ItemType Directory -Path $withoutSpeech | Out-Null
    Must-Reject { Assert-YimeCoreUnchangedData $before @(Get-YimeCoreDataRecords $withoutSpeech) }
}
Check 'actual-restore-loop-maps-only-private-speech-setting' {
    $restorePath=Join-Path $PSScriptRoot 'restore-local-trial-state.ps1'
    $tokens=$null;$parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($restorePath,[ref]$tokens,[ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) 'Restore source parse failed.'
    # Select only the exact data-record loop, never import or run the entry body.
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
    Assert-True ($script:copied.Count -eq 1) 'Speech setting did not reach actual restore mapping.'
    Assert-True ($script:copied[0].source -ceq (Join-Path $archiveState 'speech.json') -and
        $script:copied[0].destination -ceq $speechPath -and $script:copied[0].force) 'Restore target escaped the selected synthetic setting.'
}
$failed=@($checks | Where-Object {-not $_.passed})
$sources=[ordered]@{}
foreach($relative in @('tools/yimecore/local-maintenance-safety.ps1','tools/yimecore/restore-local-trial-state.ps1','tools/yimecore/test-speech-maintenance-data.ps1')) {
    $sources[$relative]=(Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$result=[ordered]@{schema_version='yimecore-speech-maintenance-data-fixture-v1';passed=($failed.Count -eq 0);
    checks=$checks.ToArray();checks_count=$checks.Count;failed_count=$failed.Count;source_sha256=$sources;
    powershell=$PSVersionTable.PSVersion.ToString();real_restore_or_backup_executed=$false;
    process_started_or_stopped=$false;registry_mutated=$false;production_or_user_data_read=$false;
    installed_recovery_passed=$false;level='actual-source-data-enumeration-and-AST-mapping-with-mocked-copy'}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding UTF8
Write-Output "Speech maintenance data fixture: $($checks.Count) checks, $($failed.Count) failed; $output"
if($failed.Count){exit 1}
