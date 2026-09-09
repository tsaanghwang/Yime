[CmdletBinding()]
param([string]$OutputRoot,[ValidateSet('Tests','Parent','Worker')][string]$Mode='Tests',[string]$Scope,[string]$InfoPath,[string]$ReadyPath,[string]$ReleasePath)
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-candidate-coordinator.psm1') -PassThru -Scope Local
& $module {Initialize-CandidateCoordinator}
if($Mode -ne 'Tests'){
    if($Scope -cnotmatch '^fixture-[0-9a-f]{32}$'){throw 'Owned fixture scope required.'}
    $lease=$null
    try{
        if($Mode -eq 'Parent'){
            $lease=& $module {param($s)$script:CoordinatorType::OpenParent($s)} $Scope
            $value=[ordered]@{pid=$lease.ParentPid;created=$lease.ParentCreationFileTime;sid=$lease.TargetUserSid;token=$lease.DelegationToken}
            [IO.File]::WriteAllText($InfoPath,($value|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        }else{
            $v=Get-Content -LiteralPath $InfoPath -Raw|ConvertFrom-Json
            $lease=& $module {param($s,$v)$script:CoordinatorType::JoinWorker($s,[int]$v.pid,[long]$v.created,[string]$v.sid,[string]$v.token)} $Scope $v
            [IO.File]::WriteAllText($ReadyPath,'ready')
        }
        $deadline=[DateTime]::UtcNow.AddSeconds(90)
        while(-not(Test-Path -LiteralPath $ReleasePath)){if([DateTime]::UtcNow -gt $deadline){throw 'Owned fixture child timed out.'};Start-Sleep -Milliseconds 50}
    }finally{if($lease){$lease.Dispose()}}
    exit 0
}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if(-not $OutputRoot){$OutputRoot=Join-Path $repo ('.tmp\dual-product\coordinator-test-'+[guid]::NewGuid().ToString('N'))}
$out=[IO.Path]::GetFullPath($OutputRoot)
if(-not $out.StartsWith((Join-Path $repo '.tmp\dual-product')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Fresh owned fixture root required.'}
$null=[IO.Directory]::CreateDirectory($out)
$results=[Collections.Generic.List[object]]::new();$children=[Collections.Generic.List[object]]::new()
function Pass([string]$Name){$results.Add([pscustomobject]@{name=$Name;passed=$true});Write-Host ('PASS '+$Name)}
function Refuse([string]$Name,[scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};if(-not $rejected){throw ('Accepted: '+$Name)};Pass $Name}
function Wait-File([string]$Path){$deadline=[DateTime]::UtcNow.AddSeconds(15);while(-not(Test-Path -LiteralPath $Path)){if([DateTime]::UtcNow -gt $deadline){throw ('No child output: '+$Path)};Start-Sleep -Milliseconds 50}}
function Start-Child([string]$Kind,[string]$TokenScope,[string]$Info,[string]$Ready,[string]$Release){
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=(Get-Process -Id $PID).Path;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Mode '+$Kind+' -Scope '+$TokenScope+' -InfoPath "'+$Info+'" -ReadyPath "'+$Ready+'" -ReleasePath "'+$Release+'"'
    $p=[Diagnostics.Process]::Start($start);$children.Add($p);return $p
}
try{
    $scope='fixture-'+[guid]::NewGuid().ToString('N')
    $parent=& $module {param($s)$script:CoordinatorType::OpenParent($s)} $scope
    try{
        Pass 'fresh parent acquires fixed fixture gate'
        Refuse 'same scope cannot acquire twice' { $p=& $module {param($s)$script:CoordinatorType::OpenParent($s)} $scope; $p.Dispose() }
        Refuse 'unknown delegation rejected' { $p=& $module {param($s,$v)$script:CoordinatorType::JoinWorker($s,$v.ParentPid,$v.ParentCreationFileTime,$v.TargetUserSid,('0'*32))} $scope $parent;$p.Dispose() }
        Refuse 'wrong creation time rejected' { $p=& $module {param($s,$v)$script:CoordinatorType::JoinWorker($s,$v.ParentPid,($v.ParentCreationFileTime+1),$v.TargetUserSid,$v.DelegationToken)} $scope $parent;$p.Dispose() }
        Refuse 'wrong SID rejected' { $p=& $module {param($s,$v)$script:CoordinatorType::JoinWorker($s,$v.ParentPid,$v.ParentCreationFileTime,'S-1-5-18',$v.DelegationToken)} $scope $parent;$p.Dispose() }
        $worker=& $module {param($s,$v)$script:CoordinatorType::JoinWorker($s,$v.ParentPid,$v.ParentCreationFileTime,$v.TargetUserSid,$v.DelegationToken)} $scope $parent
        try{$parent.Dispose();Refuse 'worker pins gate after parent lease closes' {$p=& $module {param($s)$script:CoordinatorType::OpenParent($s)} $scope;$p.Dispose()}}finally{$worker.Dispose()}
        $next=& $module {param($s)$script:CoordinatorType::OpenParent($s)} $scope
        try{Pass 'last handle close allows fresh parent';Refuse 'old delegation cannot join a new interval' {$p=& $module {param($s,$v)$script:CoordinatorType::JoinWorker($s,$v.ParentPid,$v.ParentCreationFileTime,$v.TargetUserSid,$v.DelegationToken)} $scope $parent;$p.Dispose()}}finally{$next.Dispose()}
    }finally{$parent.Dispose()}
    # Actual different processes: crash the parent while its delegated worker lives.
    $scope='fixture-'+[guid]::NewGuid().ToString('N');$info=Join-Path $out 'parent.json';$ready=Join-Path $out 'worker.ready';$release=Join-Path $out 'release'
    $p=Start-Child Parent $scope $info $ready $release;Wait-File $info
    $w=Start-Child Worker $scope $info $ready $release;Wait-File $ready;Pass 'different worker process joined exact parent identity'
    $p.Kill();if(-not $p.WaitForExit(5000)){throw 'Owned parent did not exit'};Pass 'owned parent process terminated'
    Refuse 'worker excludes new maintenance after parent process death' {$lease=& $module {param($s)$script:CoordinatorType::OpenParent($s)} $scope;$lease.Dispose()}
    $stale=Get-Content -LiteralPath $info -Raw|ConvertFrom-Json
    Refuse 'dead parent cannot authorize another worker' {$lease=& $module {param($s,$v)$script:CoordinatorType::JoinWorker($s,[int]$v.pid,[long]$v.created,[string]$v.sid,[string]$v.token)} $scope $stale;$lease.Dispose()}
    $w.Kill();if(-not $w.WaitForExit(5000)){throw 'Owned worker did not exit'}
    $after=& $module {param($s)$script:CoordinatorType::OpenParent($s)} $scope
    try{Pass 'parent and worker crash releases kernel lifetime gate'}finally{$after.Dispose()}
    $scope='fixture-'+[guid]::NewGuid().ToString('N');$public=& $module {param($s)Add-CoordinatorContext ($script:CoordinatorType::OpenParent($s))} $scope
    try{
        $borrowed=Get-RimePimeCandidateCoordinatorHandle $public;if($borrowed -eq [IntPtr]::Zero){throw 'No inherited-child gate handle'};Pass 'original context lends fixed gate handle without closing it'
        $copy=$public|ConvertTo-Json|ConvertFrom-Json
        Refuse 'copied public context cannot lend live gate' {Get-RimePimeCandidateCoordinatorHandle $copy|Out-Null}
        Refuse 'copied public context cannot dispose live gate' {Close-RimePimeCandidateCoordinator $copy}
    }finally{Close-RimePimeCandidateCoordinator $public}
    Refuse 'closed public context rejected' {Close-RimePimeCandidateCoordinator $public}
    Refuse 'closed public context cannot lend handle' {Get-RimePimeCandidateCoordinatorHandle $public|Out-Null}
    $source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-candidate-coordinator.psm1') -Raw
    if($source -notmatch "OpenParent\('product'\)" -or $source -notmatch "JoinWorker\('product',"){throw 'Public fixed product gate lost'};Pass 'public API fixes product gate independently of SID and root'
    $report=[ordered]@{schema_version='yime-rime-pime-coordinator-test-v1';passed=$true;test_count=$results.Count;powershell=$PSVersionTable.PSVersion.ToString();owned_fixture=$true;actual_process_interruption_tested=$true;production_gate_opened=$false;installer_executed=$false;local12_touched=$false;results=@($results)}
    [IO.File]::WriteAllText((Join-Path $out 'result.json'),($report|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false));Write-Host ('PASS '+$results.Count+'; '+$out)
}finally{foreach($child in $children){try{if(-not $child.HasExited){$child.Kill();$null=$child.WaitForExit(5000)}}finally{$child.Dispose()}}}
