[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
$count=0
function Expect-Rejection([scriptblock]$Action) {
    $rejected=$false
    try{& $Action}catch{$rejected=$true}
    if(-not $rejected){throw 'Expected a safety rejection.'}
}
$config=[pscustomobject]@{install_root='C:\Trial';runtime_path='C:\Trial\bin\YimeCoreTrialRuntime.exe';broker_path='C:\Trial\bin\YimeBroker.exe';state_root='C:\State'}
$status=[pscustomobject]@{state='running';runtime_pid=10;broker_pid=11;install_root='C:\Trial';broker_path=$config.broker_path;state_root='C:\State';updated_at='2026-01-01T00:02:01Z'}
$runtime=[pscustomobject]@{ProcessId=10;ExecutablePath=$config.runtime_path;CreationDate='2026-01-01T00:01:00Z'}
$broker=[pscustomobject]@{ProcessId=11;ParentProcessId=10;ExecutablePath=$config.broker_path;CreationDate='2026-01-01T00:02:00Z'}
$boot='2026-01-01T00:00:00Z'
if(-not (Test-YimeCoreLiveIdentity $config $status $runtime $broker $boot)){throw 'Valid live identity rejected'}
$count++
foreach($case in @('missing_runtime','missing_broker','wrong_path','missing_path','wrong_parent','stale_status','prior_boot','wrong_pid','wrong_root')) {
    $rt=$runtime.PSObject.Copy();$br=$broker.PSObject.Copy();$st=$status.PSObject.Copy();$bt=$boot
    switch($case){
        missing_runtime{$rt=$null} missing_broker{$br=$null}
        wrong_path{$rt.ExecutablePath='C:\Other\YimeCoreTrialRuntime.exe'} missing_path{$br.ExecutablePath=$null}
        wrong_parent{$br.ParentProcessId=99} stale_status{$st.updated_at='2025-12-31T00:00:00Z'}
        prior_boot{$bt='2026-01-02T00:00:00Z'} wrong_pid{$st.runtime_pid=99} wrong_root{$st.state_root='C:\Other'}
    }
    if(Test-YimeCoreLiveIdentity $config $st $rt $br $bt){throw "False live pass: $case"}
    $count++
}
$expected=@([ordered]@{path='user-model/a';bytes=1;sha256='aa'},[ordered]@{path='yime_user_phrases.txt';bytes=2;sha256='bb'})
Assert-YimeCoreUnchangedData $expected $expected
$count++
foreach($case in @('learning_changed','lexicon_changed','new_file','deleted_file')) {
    $actual=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $expected)
    switch($case){learning_changed{$actual[0].sha256='cc'}lexicon_changed{$actual[1].sha256='cc'}
        new_file{$actual+=@([pscustomobject]@{path='yime_blocklist.txt';bytes=0;sha256='dd'})}deleted_file{$actual=@($actual[0])}}
    Expect-Rejection {Assert-YimeCoreUnchangedData $expected $actual}
    $count++
}
# A provider failure never falls back to the process registry view.
function Invoke-CimMethod {return [pscustomobject]@{ReturnValue=5}}
Expect-Rejection {Read-YimeCoreSystemKey 2147483651 'test'}
$count++
function Invoke-CimMethod {return [pscustomobject]@{ReturnValue=2}}
if((Read-YimeCoreSystemKey 2147483651 'test').exists){throw 'Missing key reported present'}
$count++
function Invoke-CimMethod {return [pscustomobject]@{ReturnValue=0;sNames=$null;Types=$null}}
$empty=Read-YimeCoreSystemKey 2147483651 'test'
if(-not $empty.exists -or $empty.values.Count -ne 0 -or $empty.children.Count -ne 0){throw 'Empty system key not captured correctly'}
$count++
function Invoke-CimMethod($Namespace,$ClassName,$MethodName,$Arguments) {
    switch($MethodName){
        EnumValues{return [pscustomobject]@{ReturnValue=0;sNames=@('z','a');Types=@(1,4)}}
        EnumKey{return [pscustomobject]@{ReturnValue=0;sNames=$null}}
        GetStringValue{return [pscustomobject]@{ReturnValue=0;sValue='value'}}
        GetDWORDValue{return [pscustomobject]@{ReturnValue=0;uValue=1}}
        default{throw 'Unexpected registry mock method'}
    }
}
$sorted=Read-YimeCoreSystemKey 2147483651 'test'
if($sorted.values[0].name -ne 'a' -or $sorted.values[0].kind -ne 4 -or $sorted.values[1].name -ne 'z'){throw 'Registry insertion order must not affect equality'}
$count++
foreach($name in @('backup-local-trial-state.ps1','restore-local-trial-state.ps1','invoke-local-rollback-rehearsal.ps1','complete-local-trial-closure.ps1')) {
    $source=Get-Content -LiteralPath (Join-Path $PSScriptRoot $name) -Raw
    if($source -notmatch 'Assert-YimeCoreUnpackagedDataMaintenance'){throw "Native guard missing: $name"}
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "Parse failed: $name / $($errors[0])"}
    $count++
}
$restore=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'restore-local-trial-state.ps1') -Raw
if($restore.IndexOf('Assert-YimeCoreUnchangedData') -gt $restore.IndexOf('Move-Item -LiteralPath $liveModel')){throw 'Data freshness guard must precede all live moves'}
$count++
Write-Host "Local maintenance safety: $count cases passed; no live data or registry mutations."
$fixture=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) ('.tmp\yimecore-experiment\shared-data-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
$journal=Join-Path $fixture 'journal'
$writer=[IO.File]::Open($journal,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try {
    $bytes=[Text.Encoding]::UTF8.GetBytes('test journal bytes')
    $writer.Write($bytes,0,$bytes.Length);$writer.Flush()
    $record=Get-YimeCoreSharedFileRecord $journal
    if($record.bytes -ne $bytes.Length){throw 'Shared journal length mismatch'}
}finally{$writer.Dispose()}
if($record.sha256 -ne (Get-FileHash -LiteralPath $journal).Hash.ToLowerInvariant()){throw 'Shared journal hash mismatch'}
Write-Host 'Shared live-writer-compatible journal read passed; disposable fixture retained under experiment output.'
