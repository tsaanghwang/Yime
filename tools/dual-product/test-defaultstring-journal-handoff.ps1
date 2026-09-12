[CmdletBinding()]
param([string]$ChildRoot,[ValidateSet('Held','Released','BadDigest')][string]$ChildPhase='Held',[string]$PreparedSha256)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixtureParent=Join-Path $repo '.tmp\dual-product'
$reader=Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-candidate.psm1') -PassThru
if($ChildRoot){
    $ChildRoot=[IO.Path]::GetFullPath($ChildRoot)
    if([IO.Path]::GetDirectoryName($ChildRoot) -ine $fixtureParent -or [IO.Path]::GetFileName($ChildRoot) -cnotmatch '^dp1-lock-handoff-[0-9a-f]{32}$'){throw 'Child requires owned fixture root.'}
    $store=$null;$rejected=$false
    try{
        try{$store=& $reader {param($r) Open-CandidateJournal $r $false} (Join-Path $ChildRoot 'journal')}
        catch{
            if($ChildPhase -cne 'Held' -or $_.Exception.ToString() -notmatch 'IOException' -or $_.Exception.ToString() -notmatch 'transaction.lock'){throw}
            $rejected=$true
        }
        if($ChildPhase -ceq 'Held'){
            if(-not $rejected){throw 'Child acquired journal while parent held it.'}
        }else{
            $digest=if($ChildPhase -ceq 'BadDigest'){'0'*64}else{$PreparedSha256}
            $digestRejected=$false
            try{
                $plan=& $reader {param($s,$h) Read-CandidateJournal $s 'prepared.bin' $h} $store $digest
                if($plan.marker -cne 'handoff-fixture'){throw 'Wrong fixture plan.'}
            }catch{
                if($ChildPhase -cne 'BadDigest' -or $_.Exception.Message -notmatch 'original external prepared digest'){throw}
                $digestRejected=$true
            }
            if($ChildPhase -ceq 'BadDigest' -and -not $digestRejected){throw 'Child accepted wrong external digest.'}
        }
    }finally{if($store){$store.Dispose()}}
    [IO.File]::WriteAllText((Join-Path $ChildRoot ($ChildPhase+'-result.json')),(@{pid=$PID;phase=$ChildPhase;passed=$true}|ConvertTo-Json))
    exit 0
}
$root=Join-Path $fixtureParent ('dp1-lock-handoff-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory((Join-Path $root 'journal'))
$store=& $reader {param($r) Open-CandidateJournal $r $true} (Join-Path $root 'journal')
$ticket=[pscustomobject]@{store=$store;plan=[pscustomobject]@{marker='handoff-fixture'}}
try{
    $hash=& $reader {param($s,$v) Publish-CandidateJournal $s 'prepared.bin' $v} $store $ticket.plan
    function Invoke-FixtureChild([string]$Phase){
        $parameters=Join-Path $root ($Phase+'-parameters.json')
        [IO.File]::WriteAllText($parameters,(@{ChildRoot=$root;ChildPhase=$Phase;PreparedSha256=$hash}|ConvertTo-Json))
        & python (Join-Path $repo 'tools\powershell\run_checked.py') --script $PSCommandPath --edition ps5 --params-file $parameters
        if($LASTEXITCODE -ne 0){throw ('Separate child failed: '+$Phase)}
        $result=Get-Content -LiteralPath (Join-Path $root ($Phase+'-result.json')) -Raw|ConvertFrom-Json
        if($result.pid -eq $PID -or -not $result.passed){throw 'Expected a successful separate process.'}
    }
    Invoke-FixtureChild Held
    . (Join-Path $PSScriptRoot 'defaultstring-recovery-adapter.ps1')
    Release-RecoveryJournalForWorker $ticket
    if($null -ne $ticket.store -or $ticket.plan.marker -cne 'handoff-fixture'){throw 'Handoff did not preserve the plan and relinquish store.'}
    Invoke-FixtureChild Released
    Invoke-FixtureChild BadDigest
    $reopened=& $reader {param($r) Open-CandidateJournal $r $false} (Join-Path $root 'journal')
    try{$null=& $reader {param($s,$h) Read-CandidateJournal $s 'prepared.bin' $h} $reopened $hash}finally{$reopened.Dispose()}
    if(-not (Test-Path -LiteralPath (Join-Path $root 'journal\transaction.lock'))){throw 'Lock file was deleted.'}
    Write-Output ('PASS: actual cross-process lock exclusion, release/reopen, digest rejection and parent reacquisition; evidence '+$root)
}finally{if($ticket.store){$ticket.store.Dispose()}}
