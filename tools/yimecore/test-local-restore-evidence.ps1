[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$out=[IO.Path]::GetFullPath($OutputPath)
if(-not $out.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Fresh repository .tmp evidence file required.'}
$cursor=Split-Path -Parent $out
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect fixture output.'};$cursor=Split-Path -Parent $cursor}
New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force | Out-Null
$fixture=Join-Path $repo ('.tmp\local-restore-evidence-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$source=Join-Path $PSScriptRoot 'restore-local-trial-state.ps1'
$probeSource=Join-Path $PSScriptRoot 'model-recovery-probe.go'
$statsSource=Join-Path $repo 'go-backend\input_methods\yime\yimebroker\usermodel_store.go'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Restore source does not parse.'}
$functions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -match '^(Assert|ConvertFrom)-LocalRestore'},$true))
if($functions.Count -ne 3){throw 'Expected exactly the three pure restore evidence helpers.'}
foreach($function in $functions){. ([scriptblock]::Create($function.Extent.Text))}
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){try{& $Body | Out-Null;$checks.Add([ordered]@{name=$Name;passed=$true})}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body){$failed=$false;try{& $Body | Out-Null}catch{$failed=$true};Require $failed 'Expected evidence rejection.'}
function Write-Text([string]$Path,[string]$Value){[IO.File]::WriteAllText($Path,$Value,[Text.UTF8Encoding]::new($false))}
function New-Backup($StateRoot){[pscustomobject]@{schema_version='yimecore-quiesced-backup-v1';source_state_root=$StateRoot;passed=$true;writers_stopped=$true;native_context_verified=$true;development_scope=[pscustomobject]@{fixture=$true};data_files=@([pscustomobject]@{path='user-model/fixture/user-model.journal'});state_files=@([pscustomobject]@{path='user-model/fixture/user-model.journal'})}}
function New-Recovery($Clone){[pscustomobject]@{passed=$true;generation=3;source_id='owned-fixture';learned_record_count=2;clone=$Clone;stats=[pscustomobject]@{snapshot_generation=2;journal_generation=3;recovered_mutations=1;truncated_tail_bytes=0;checkpoint_failures=0;compactions=0;compaction_failures=0}}}
$expectedState=Join-Path $fixture 'state';$expectedClone=Join-Path $fixture 'clone'
Check 'protocol uses actual unversioned probe fields and durable statistics' {
    $producer=Get-Content -LiteralPath $probeSource -Raw -Encoding UTF8
    Require (-not $producer.Contains('"schema_version"')) 'The actual probe protocol changed; review this validator.'
    foreach($name in @('passed','generation','source_id','learned_record_count','stats','clone')){Require ($producer.Contains('"'+$name+'":')) ('Missing actual probe field: '+$name)}
    $stats=Get-Content -LiteralPath $statsSource -Raw -Encoding UTF8
    foreach($name in @('snapshot_generation','journal_generation','recovered_mutations','truncated_tail_bytes','checkpoint_failures','compactions','compaction_failures')){Require ($stats.Contains('json:"'+$name+'"')) ('Missing actual statistic: '+$name)}
    foreach($name in @('last_checkpoint_error','last_compaction_error','rollback_snapshot_path','migrated_from_schema')){Require ($stats.Contains('json:"'+$name+',omitempty"')) ('Missing actual optional statistic: '+$name)}
}
Check 'current backup JSON and current recovery JSON are admitted' {
    $backup=ConvertFrom-LocalRestoreEvidenceJson ((New-Backup $expectedState)|ConvertTo-Json -Depth 8)
    Assert-LocalRestoreBackupEvidence $backup $expectedState
    $recovery=ConvertFrom-LocalRestoreEvidenceJson ((New-Recovery $expectedClone)|ConvertTo-Json -Depth 8)
    Assert-LocalRestoreRecoveryEvidence $recovery $expectedClone 'owned-fixture'
}
foreach($field in @('passed','writers_stopped','native_context_verified')){
    foreach($bad in @($false,'false','true',1,@($true))){
        Check ('backup literal true rejects '+$field+' '+($bad|ConvertTo-Json -Compress)) {
            $value=New-Backup $expectedState;$value.$field=$bad
            Reject {Assert-LocalRestoreBackupEvidence $value $expectedState}
        }
    }
    Check ('missing backup boolean rejects '+$field) {$value=New-Backup $expectedState;$value.PSObject.Properties.Remove($field);Reject {Assert-LocalRestoreBackupEvidence $value $expectedState}}
    Check ('null backup boolean rejects '+$field) {$value=New-Backup $expectedState;$value.$field=$null;Reject {Assert-LocalRestoreBackupEvidence $value $expectedState}}
}
foreach($field in @('schema_version','source_state_root')){
    Check ('backup identity rejects array '+$field) {$value=New-Backup $expectedState;$value.$field=@($value.$field);Reject {Assert-LocalRestoreBackupEvidence $value $expectedState}}
    Check ('backup identity rejects mismatch '+$field) {$value=New-Backup $expectedState;$value.$field='wrong';Reject {Assert-LocalRestoreBackupEvidence $value $expectedState}}
}
foreach($bad in @($false,'false','true',1,@($true),$null)){
    Check ('probe passed rejects nontrue '+($bad|ConvertTo-Json -Compress)) {$value=New-Recovery $expectedClone;$value.passed=$bad;Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
}
foreach($field in @('clone','source_id')){
    Check ('probe exact identity rejects mismatch '+$field) {$value=New-Recovery $expectedClone;$value.$field+='-foreign';Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
    Check ('probe exact identity rejects array '+$field) {$value=New-Recovery $expectedClone;$value.$field=@($value.$field);Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
}
foreach($field in @('generation','learned_record_count')){
    foreach($bad in @(-1,'3',3.0,@(3),$null)){
        Check ('probe counter rejects '+$field+' '+($bad|ConvertTo-Json -Compress)) {$value=New-Recovery $expectedClone;$value.$field=$bad;Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
    }
}
Check 'probe missing required field rejected' {$value=New-Recovery $expectedClone;$value.PSObject.Properties.Remove('generation');Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
Check 'probe unknown schema field not invented or accepted' {$value=New-Recovery $expectedClone;$value|Add-Member schema_version 'invented';Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
Check 'probe canonical field case required' {$value=New-Recovery $expectedClone;$value.PSObject.Properties.Remove('clone');$value|Add-Member Clone $expectedClone;Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
Check 'probe missing statistic rejected' {$value=New-Recovery $expectedClone;$value.stats.PSObject.Properties.Remove('checkpoint_failures');Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
Check 'probe string statistic rejected' {$value=New-Recovery $expectedClone;$value.stats.recovered_mutations='1';Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
foreach($field in @('snapshot_generation','journal_generation','recovered_mutations','truncated_tail_bytes','checkpoint_failures','compactions','compaction_failures')){
    Check ('probe singleton statistic array rejected '+$field) {$value=New-Recovery $expectedClone;$value.stats.$field=@(1);Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
    Check ('probe multiple statistic array rejected '+$field) {$value=New-Recovery $expectedClone;$value.stats.$field=@(1,2);Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
    Check ('probe null statistic rejected '+$field) {$value=New-Recovery $expectedClone;$value.stats.$field=$null;Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
}
Check 'probe unknown statistic rejected' {$value=New-Recovery $expectedClone;$value.stats|Add-Member foreign 1;Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
Check 'actual optional string statistics remain compatible' {$value=New-Recovery $expectedClone;foreach($name in @('last_checkpoint_error','last_compaction_error','rollback_snapshot_path','migrated_from_schema')){$value.stats|Add-Member $name 'fixture'};Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}
Check 'optional statistics reject array coercion' {$value=New-Recovery $expectedClone;$value.stats|Add-Member last_checkpoint_error @('fixture');Reject {Assert-LocalRestoreRecoveryEvidence $value $expectedClone 'owned-fixture'}}
foreach($json in @('[{"passed":true}]','null','true','{"passed":false,"passed":true}','{"passed":true,"PASSED":true}','{"pa\u0073sed":true,"passed":true}','{"stats":{"generation":1,"generation":2}}','{"bad":"unterminated}','{"bad":]')){
    Check ('raw malformed or ambiguous JSON rejected '+$json) {Reject {ConvertFrom-LocalRestoreEvidenceJson $json}}
}
Check 'nested duplicate names in different objects and escaped strings remain valid JSON' {
    $value=ConvertFrom-LocalRestoreEvidenceJson '{"a":{"passed":true},"b":{"passed":true},"text":"[{}] \"escaped\" \\ value","items":[{"k":1},{"k":2}]}'
    Require ($value.a.passed -and $value.b.passed -and $value.items.Count -eq 2) 'Valid JSON was changed.'
}

# Execute the real admission/clone statements only, plus its original stop and
# first Move statement against exclusively owned fixture paths. Never dot-source
# the entry, discover a product, or run a native recovery/runtime executable.
$statements=@($ast.EndBlock.Statements)
$manifestStart=@($statements|Where-Object {$_.Extent.Text.StartsWith('$manifest=')})[0].Extent.StartOffset
$archiveStart=@($statements|Where-Object {$_.Extent.Text.StartsWith('$archiveState=')})[0].Extent.StartOffset
$cloneStart=@($statements|Where-Object {$_.Extent.Text.StartsWith('$cloneRoot=')})[0].Extent.StartOffset
$configStart=@($statements|Where-Object {$_.Extent.Text.StartsWith('$config=')})[0].Extent.StartOffset
$preflight=(@($statements|Where-Object {$_.Extent.StartOffset -ge $manifestStart -and $_.Extent.StartOffset -lt $archiveStart}|ForEach-Object {$_.Extent.Text}) -join "`n")
$cloneAdmission=(@($statements|Where-Object {$_.Extent.StartOffset -ge $cloneStart -and $_.Extent.StartOffset -lt $configStart}|ForEach-Object {$_.Extent.Text}) -join "`n")
$stop=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.PipelineAst] -and $n.Extent.Text -ceq "& (Join-Path `$PSScriptRoot 'stop-e6c-trial-runtime.ps1') | Out-Null"},$true))
$move=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.PipelineAst] -and $n.Extent.Text -ceq 'Move-Item -LiteralPath $liveModel -Destination $safetyModel'},$true))
if($stop.Count -ne 1 -or $move.Count -ne 1){throw 'Expected unique actual stop and first restore Move statements.'}
$admission=[scriptblock]::Create("param(`$FixtureHelperRoot)`n`$PSScriptRoot=`$FixtureHelperRoot`n"+$preflight+"`n"+$cloneAdmission+"`n"+$stop[0].Extent.Text+"`n"+$move[0].Extent.Text)
Check 'both actual evidence validations precede writer stop and live move' {
    Require ($manifestStart -lt $cloneStart -and $configStart -lt $stop[0].Extent.StartOffset -and $stop[0].Extent.StartOffset -lt $move[0].Extent.StartOffset) 'Admission order differs.'
    Require ($preflight.Contains('Assert-LocalRestoreBackupEvidence $manifest $stateRoot') -and $cloneAdmission.Contains('Assert-LocalRestoreRecoveryEvidence $recovery $clone $first.source_id')) 'Actual admission call missing.'
}
function Invoke-PrivateRestoreProbe {
    param($clone,[Alias('source-id')]$SourceId,$output)
    $script:ProbeCalls++;$global:LASTEXITCODE=0
    $value=New-Recovery $clone
    switch($script:ProbeMode){
        'probe-false' {$value.passed=$false}
        'probe-string' {$value.passed='false'}
        'probe-clone' {$value.clone+='-foreign'}
        'probe-source' {$value.source_id='foreign'}
        'probe-stats' {$value.stats.recovered_mutations='1'}
        'probe-stats-one-array' {$value.stats.recovered_mutations=@(1)}
        'probe-stats-many-array' {$value.stats.recovered_mutations=@(1,2)}
        'probe-stats-null' {$value.stats.recovered_mutations=$null}
        'probe-exit' {$global:LASTEXITCODE=86}
        'probe-no-output' {return}
        'probe-null-exit' {$global:LASTEXITCODE=$null}
    }
    $text=$value|ConvertTo-Json -Depth 8
    if($script:ProbeMode -ceq 'probe-array'){$text='['+$text+']'}
    if($script:ProbeMode -ceq 'probe-malformed'){$text='{'}
    if($script:ProbeMode -ceq 'probe-duplicate'){
        Require ([regex]::Matches($text,'"passed"\s*:\s*true').Count -eq 1) 'Duplicate-key fixture must alter exactly one producer field.'
        $text=[regex]::Replace($text,'"passed"\s*:\s*true','"passed": false, "passed": true')
    }
    Write-Text $output $text
}
function Invoke-AdmissionFixture([string]$Mode) {
    $case=Join-Path $fixture ([guid]::NewGuid().ToString('N'))
    $backup=Join-Path $case 'backup';$stateRoot=Join-Path $case 'state';$archiveState=Join-Path $backup 'state'
    $sourceModel=Join-Path $archiveState 'user-model\fixture';$liveModel=Join-Path $stateRoot 'user-model';$safetyModel=Join-Path $backup 'pre-restore-user-model'
    $PSScriptRoot=Join-Path $case 'owned-helper';$stopMarker=Join-Path $PSScriptRoot 'writer-stop-marker'
    foreach($path in @($sourceModel,$liveModel,$PSScriptRoot)){New-Item -ItemType Directory -Path $path -Force|Out-Null}
    Write-Text (Join-Path $sourceModel 'user-model.journal') '{"source_id":"owned-fixture"}'
    Write-Text (Join-Path $liveModel 'owned-canary') 'private fixture only'
    Write-Text (Join-Path $PSScriptRoot 'stop-e6c-trial-runtime.ps1') '[IO.File]::WriteAllText((Join-Path $PSScriptRoot ''writer-stop-marker''),''owned fixture only'')'
    $value=New-Backup $stateRoot
    if($Mode.StartsWith('backup-')){$value.($Mode.Substring(7))='false'}
    if($Mode -ceq 'journal-source-array'){Write-Text (Join-Path $sourceModel 'user-model.journal') '{"source_id":["owned-fixture"]}'}
    if($Mode -ceq 'preexisting-result'){Write-Text (Join-Path $sourceModel 'recovery.json') '{}'}
    Write-Text (Join-Path $backup 'backup-manifest.json') ($value|ConvertTo-Json -Depth 8)
    $scope=[pscustomobject]@{fixture=$true};$RecoveryProbe='Invoke-PrivateRestoreProbe'
    function Test-YimeCoreScopeEvidence($Evidence,$Expected){return $true}
    function Get-Process($Name){if($Name -cne 'WINWORD'){throw 'Unexpected process query in fixture.'};return $null}
    $script:ProbeMode=$Mode;$script:ProbeCalls=0;$errorText=$null
    try{& $admission $PSScriptRoot}catch{$errorText=$_.Exception.Message}
    [pscustomobject]@{failed=($null -ne $errorText);error=$errorText;stopped=(Test-Path -LiteralPath $stopMarker);moved=(Test-Path -LiteralPath $safetyModel);probe_calls=$script:ProbeCalls}
}
Check 'actual current success admission reaches only owned stop and move fixture' {$value=Invoke-AdmissionFixture 'valid';Require (-not $value.failed -and $value.stopped -and $value.moved -and $value.probe_calls -eq 1) ('Valid admission failed: '+$value.error)}
foreach($mode in @('backup-passed','backup-writers_stopped','backup-native_context_verified','journal-source-array','preexisting-result',
    'probe-false','probe-string','probe-clone','probe-source','probe-stats','probe-stats-one-array','probe-stats-many-array','probe-stats-null',
    'probe-exit','probe-no-output','probe-null-exit','probe-array','probe-malformed','probe-duplicate')){
    Check ('actual admission rejects before any writer stop or move '+$mode) {
        $value=Invoke-AdmissionFixture $mode
        Require ($value.failed -and -not $value.stopped -and -not $value.moved) ('Unsafe admission: '+($value|ConvertTo-Json -Compress))
        if($mode.StartsWith('backup-') -or $mode -in @('journal-source-array','preexisting-result')){Require ($value.probe_calls -eq 0) 'Probe ran before prerequisite validation.'}
    }
}
$failed=@($checks|Where-Object {-not $_.passed})
$sourceRecords=@(foreach($path in @($source,$PSCommandPath,$probeSource,$statsSource)){[ordered]@{path=$path;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}})
[ordered]@{schema_version='yimecore-local-restore-evidence-tests-v1';passed=($failed.Count -eq 0);checks_passed=$checks.Count-$failed.Count;checks=@($checks.ToArray());powershell_version=$PSVersionTable.PSVersion.ToString();sources=$sourceRecords;
    actual_restore_entry_executed=$false;actual_recovery_probe_executed=$false;actual_product_or_user_state_accessed=$false;actual_installer_executed=$false;private_admission_fixture_executed=$true;L6_sealed=$false;local_product_ready=$false;public_release_ready=$false}|
    ConvertTo-Json -Depth 10|Set-Content -LiteralPath $out -Encoding UTF8
if($failed.Count){throw "Local restore evidence failed: $($failed|ConvertTo-Json -Depth 4 -Compress)"}
$global:LASTEXITCODE=0
Write-Output "PASS: local restore evidence $($checks.Count) checks; private admission fixtures only."
