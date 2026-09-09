param([string]$OutputRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-runtime.psm1') -Force -PassThru
$results=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body) { Write-Host ('Checking '+$Name);try{&$Body;$results.Add([pscustomobject]@{name=$Name;passed=$true})}catch{$results.Add([pscustomobject]@{name=$Name;passed=$false;error=$_.Exception.Message})} }
function Reject([scriptblock]$Body) { $failed=$false;try{&$Body|Out-Null}catch{$failed=$true};if(-not $failed){throw 'Expected rejection.'} }
function Ready { [pscustomobject]@{seqNum=2;success=$true;schema_version='yime-rime-pime-native-ready-v1';native_rime_ready=$true;schema_id='yime_core';backend_pid=123} }
Check 'typed-native-ready' {$v=Ready;$got=&$module {param($x) Assert-CandidateRuntimeReadyResponse $x 2} $v;if($got.backend_pid -ne 123){throw 'Lost backend binding.'}}
foreach($field in @('seqNum','success','schema_version','native_rime_ready','schema_id','backend_pid')) {
    $current=$field
    Check ('missing-'+$field) {$v=Ready;$v.PSObject.Properties.Remove($current);Reject {&$module {param($x) Assert-CandidateRuntimeReadyResponse $x 2} $v}}
    Check ('array-'+$field) {$v=Ready;$v.$current=@($v.$current);Reject {&$module {param($x) Assert-CandidateRuntimeReadyResponse $x 2} $v}}
}
foreach($case in @(@('success',$false),@('native_rime_ready',$false),@('schema_id','.default'),@('schema_id','other_product'),@('backend_pid',0),@('backend_pid','123'),@('seqNum','2'),@('seqNum',3))) {
    $badField=$case[0];$badValue=$case[1]
    Check ('invalid-'+$badField+'-'+[string]$badValue) {$v=Ready;$v.$badField=$badValue;Reject {&$module {param($x) Assert-CandidateRuntimeReadyResponse $x 2} $v}}
}
Check 'unknown-ready-field' {$v=Ready;$v|Add-Member ignored $true;Reject {&$module {param($x) Assert-CandidateRuntimeReadyResponse $x 2} $v}}
Check 'fabricated-live-context-rejected' {Reject {Test-RimePimeCandidateRuntimeReady -Context ([pscustomobject]@{context_id=[guid]::NewGuid().ToString('N')})}}
Check 'configuration-distinct-state' {$v=[pscustomobject]@{schema_version='yime-rime-pime-candidate-state-v1';install_root='C:\Candidate';state_root='C:\State';target_user_sid='S-1-5-21-1'};&$module {param($x) Assert-CandidateRuntimeConfiguration $x 'C:\Candidate' 'C:\State' 'S-1-5-21-1'} $v}
Check 'configuration-overlap-rejected' {$v=[pscustomobject]@{schema_version='yime-rime-pime-candidate-state-v1';install_root='C:\Candidate';state_root='C:\Candidate\State';target_user_sid='S-1-5-21-1'};Reject {&$module {param($x) Assert-CandidateRuntimeConfiguration $x 'C:\Candidate' 'C:\Candidate\State' 'S-1-5-21-1'} $v}}
Check 'configuration-SID-rejected' {$v=[pscustomobject]@{schema_version='yime-rime-pime-candidate-state-v1';install_root='C:\Candidate';state_root='C:\State';target_user_sid='S-1-5-21-2'};Reject {&$module {param($x) Assert-CandidateRuntimeConfiguration $x 'C:\Candidate' 'C:\State' 'S-1-5-21-1'} $v}}
Check 'configuration-singleton-string-rejected' {$v=[pscustomobject]@{schema_version=@('yime-rime-pime-candidate-state-v1');install_root='C:\Candidate';state_root='C:\State';target_user_sid='S-1-5-21-1'};Reject {&$module {param($x) Assert-CandidateRuntimeConfiguration $x 'C:\Candidate' 'C:\State' 'S-1-5-21-1'} $v}}
Check 'configuration-unknown-field-rejected' {$v=[pscustomobject]@{schema_version='yime-rime-pime-candidate-state-v1';install_root='C:\Candidate';state_root='C:\State';target_user_sid='S-1-5-21-1';extra=$true};Reject {&$module {param($x) Assert-CandidateRuntimeConfiguration $x 'C:\Candidate' 'C:\State' 'S-1-5-21-1'} $v}}
Check 'caller-rejects-wrong-SID-before-launch' {Reject {&$module {Assert-CandidateRuntimeCaller 'S-1-5-21-0'}}}
Check 'native-self-process-facts' {$facts=[Yime.CandidateRuntime.Facts]::OpenProcessFacts($PID);try{if($facts.Pid -ne $PID -or $facts.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or $facts.CreationFileTime -le 0){throw 'Native process observation mismatch.'}}finally{$facts.Dispose()}}
Check 'interrupted-removal-absence-needs-no-missing-image-pins' {
    $mock=New-Module -ScriptBlock {
        param($RuntimePath)
        . ([scriptblock]::Create([IO.File]::ReadAllText($RuntimePath).Replace(". (Join-Path `$PSScriptRoot 'rime-pime-directed-stop-contract.ps1')",'')))
        function Assert-CandidateRuntimeCaller([string]$TargetUserSid){}
        function Get-CandidateRuntimeProcesses([object]$Boundary){return @()}
        function Open-CandidateRuntimeBoundary {throw 'Image pinning must not be reached for already observed absence.'}
    } -ArgumentList (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-runtime.psm1')
    $r=&$mock {Stop-RimePimeCandidateOwnedRuntime -InstallRoot 'C:\OwnedCandidateFixture' -StateRoot 'C:\OwnedStateFixture' -TargetUserSid 'S-1-5-21-1' -LauncherSha256 ('a'*64) -BackendSha256 ('b'*64) -ConfigurationSha256 ('c'*64)}
    if($r.status -cne 'already-quiescent' -or $r.stopped_count -ne 0 -or $r.stopped_this_invocation -ne $false -or $r.desired_runtime_absence_observed -ne $true){throw 'Absence falsely attributed to a stop.'}
}
Check 'interrupted-removal-present-process-still-needs-image-pins' {
    $mock=New-Module -ScriptBlock {
        param($RuntimePath)
        . ([scriptblock]::Create([IO.File]::ReadAllText($RuntimePath).Replace(". (Join-Path `$PSScriptRoot 'rime-pime-directed-stop-contract.ps1')",'')))
        function Assert-CandidateRuntimeCaller([string]$TargetUserSid){}
        function Get-CandidateRuntimeProcesses([object]$Boundary){return [pscustomobject]@{facts=[IO.MemoryStream]::new();process=[IO.MemoryStream]::new()}}
        $script:pinCalled=$false
        function Open-CandidateRuntimeBoundary {$script:pinCalled=$true;throw 'Owned process requires its missing image pins.'}
    } -ArgumentList (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-runtime.psm1')
    Reject {&$mock {Stop-RimePimeCandidateOwnedRuntime -InstallRoot 'C:\OwnedCandidateFixture' -StateRoot 'C:\OwnedStateFixture' -TargetUserSid 'S-1-5-21-1' -LauncherSha256 ('a'*64) -BackendSha256 ('b'*64) -ConfigurationSha256 ('c'*64)}}
    if(-not (&$mock {$script:pinCalled})){throw 'Present-process recovery skipped the image boundary.'}
}
Check 'resume-no-owned-runtime-returns-null-without-launch' {
    $mock=New-Module -ScriptBlock {
        param($RuntimePath)
        . ([scriptblock]::Create([IO.File]::ReadAllText($RuntimePath).Replace(". (Join-Path `$PSScriptRoot 'rime-pime-directed-stop-contract.ps1')",'')))
        function Get-CandidateRuntimeProcesses([object]$Boundary){return @()}
        function Open-CandidateRuntimeBoundary {return [pscustomobject]@{leases=@([IO.MemoryStream]::new())}}
    } -ArgumentList (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-runtime.psm1')
    $r=&$mock {Get-RimePimeCandidateRuntimeContext -InstallRoot 'C:\OwnedCandidateFixture' -StateRoot 'C:\OwnedStateFixture' -TargetUserSid 'S-1-5-21-1' -LauncherSha256 ('a'*64) -BackendSha256 ('b'*64) -ConfigurationSha256 ('c'*64)}
    if($null -ne $r){throw 'Absence created a runtime context.'}
}
Check 'resume-foreign-topology-does-not-create-context' {
    $mock=New-Module -ScriptBlock {
        param($RuntimePath)
        . ([scriptblock]::Create([IO.File]::ReadAllText($RuntimePath).Replace(". (Join-Path `$PSScriptRoot 'rime-pime-directed-stop-contract.ps1')",'')))
        function Get-CandidateRuntimeProcesses([object]$Boundary){return [pscustomobject]@{facts=[IO.MemoryStream]::new();process=[IO.MemoryStream]::new()}}
        function Open-CandidateRuntimeBoundary {return [pscustomobject]@{leases=@([IO.MemoryStream]::new())}}
        function New-YimePimeDirectedStopRequest {throw 'Foreign topology rejected.'}
    } -ArgumentList (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-runtime.psm1')
    Reject {&$mock {Get-RimePimeCandidateRuntimeContext -InstallRoot 'C:\OwnedCandidateFixture' -StateRoot 'C:\OwnedStateFixture' -TargetUserSid 'S-1-5-21-1' -LauncherSha256 ('a'*64) -BackendSha256 ('b'*64) -ConfigurationSha256 ('c'*64)}}
    if((&$mock {$script:LiveContexts.Count}) -ne 0){throw 'Rejected topology retained a live context.'}
}
Check 'resume-adopts-current-fixture-process-without-start-or-stop' {
    $mock=New-Module -ScriptBlock {
        param($RuntimePath)
        . ([scriptblock]::Create([IO.File]::ReadAllText($RuntimePath).Replace(". (Join-Path `$PSScriptRoot 'rime-pime-directed-stop-contract.ps1')",'')))
        function Get-CandidateRuntimeProcesses([object]$Boundary){return [pscustomobject]@{facts=[IO.MemoryStream]::new();process=[IO.MemoryStream]::new()}}
        function Open-CandidateRuntimeBoundary {return [pscustomobject]@{leases=@([IO.MemoryStream]::new())}}
        function New-YimePimeDirectedStopRequest {
            $self=[Diagnostics.Process]::GetCurrentProcess()
            try{return [pscustomobject]@{launcher_pid=$PID;launcher_start_filetime_utc=$self.StartTime.ToUniversalTime().ToFileTimeUtc().ToString()}}finally{$self.Dispose()}
        }
    } -ArgumentList (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-runtime.psm1')
    $r=&$mock {Get-RimePimeCandidateRuntimeContext -InstallRoot 'C:\OwnedCandidateFixture' -StateRoot 'C:\OwnedStateFixture' -TargetUserSid 'S-1-5-21-1' -LauncherSha256 ('a'*64) -BackendSha256 ('b'*64) -ConfigurationSha256 ('c'*64)}
    try {
        if($r.launcher_pid -ne $PID -or $r.adopted_existing -ne $true -or $r.runtime_ready -ne $false -or $r.dp1_u_acceptance_passed -ne $false){throw 'Adoption falsely reported readiness or changed process.'}
        $clone=$r|ConvertTo-Json|ConvertFrom-Json;Reject {&$mock {param($x) Get-CandidateRuntimeContext $x} $clone}
    } finally {&$mock {param($x) $entry=Get-CandidateRuntimeContext $x;$entry.process.Dispose();foreach($l in $entry.boundary.leases){$l.Dispose()};$null=$script:LiveContexts.Remove($x.context_id)} $r}
}
Check 'private-native-pipe-server-PID-and-response' {
    $pipeName='YimeCandidateRuntimeTest-'+[guid]::NewGuid().ToString('N')
    $server=[IO.Pipes.NamedPipeServerStream]::new($pipeName,[IO.Pipes.PipeDirection]::InOut,1,[IO.Pipes.PipeTransmissionMode]::Byte,[IO.Pipes.PipeOptions]::Asynchronous)
    $client=[IO.Pipes.NamedPipeClientStream]::new('.',$pipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
    try {
        $connection=$server.WaitForConnectionAsync();$client.Connect(3000);if(-not $connection.Wait(3000)){throw 'Private pipe connect timeout.'}
        if([Yime.CandidateRuntime.PipeFacts]::ServerPid($client) -ne $PID){throw 'Private native pipe PID mismatch.'}
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes('{"fixture":true}'+"`n")
        $write=$server.WriteAsync($bytes,0,$bytes.Length)
        if([Yime.CandidateRuntime.PipeFacts]::ReadLine($client,3000) -cne '{"fixture":true}'){throw 'Private native pipe read mismatch.'}
        if(-not $write.Wait(3000)){throw 'Private pipe write timeout.'}
    } finally {$client.Dispose();$server.Dispose()}
}
Check 'private-native-pipe-bounded-response' {
    $pipeName='YimeCandidateRuntimeTest-'+[guid]::NewGuid().ToString('N')
    $server=[IO.Pipes.NamedPipeServerStream]::new($pipeName,[IO.Pipes.PipeDirection]::InOut,1,[IO.Pipes.PipeTransmissionMode]::Byte,[IO.Pipes.PipeOptions]::Asynchronous,65536,65536)
    $client=[IO.Pipes.NamedPipeClientStream]::new('.',$pipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
    try {
        $connection=$server.WaitForConnectionAsync();$client.Connect(3000);$null=$connection.Wait(3000)
        $bytes=[Text.Encoding]::ASCII.GetBytes(('x'*32769)+"`n");$write=$server.WriteAsync($bytes,0,$bytes.Length)
        Reject {[Yime.CandidateRuntime.PipeFacts]::ReadLine($client,10000)}
    } finally {$client.Dispose();$server.Dispose()}
}
$failed=@($results | Where-Object {-not $_.passed})
$report=[ordered]@{schema_version='yime-candidate-runtime-source-tests-v1';powershell=$PSVersionTable.PSVersion.ToString();passed=($failed.Count -eq 0);test_count=$results.Count;tests=$results.ToArray();actual_product_runtime_executed=$false;installer_executed=$false;production_registration_modified=$false;production_user_data_accessed=$false;local12_touched=$false;dp1_u_acceptance_passed=$false}
if($OutputRoot){$root=[IO.Path]::GetFullPath($OutputRoot);$null=New-Item -ItemType Directory -Path $root -Force;[IO.File]::WriteAllText((Join-Path $root 'result.json'),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
$report|ConvertTo-Json -Depth 8
if($failed.Count){exit 1}
