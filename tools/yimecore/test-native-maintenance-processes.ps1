[CmdletBinding()]param([Parameter(Mandatory)][string]$OutputPath,[switch]$RunNativeFixture)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$out=[IO.Path]::GetFullPath($OutputPath)
if(-not $out.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Fresh repository .tmp output required'}
$cursor=Split-Path -Parent $out
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect test output'};$cursor=Split-Path -Parent $cursor}
New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force | Out-Null
$modulePath=Join-Path $PSScriptRoot 'native-maintenance-processes.psm1'
$module=Import-Module $modulePath -Force -PassThru
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){try{& $Body | Out-Null;$checks.Add([ordered]@{name=$Name;passed=$true})}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body){$rejected=$false;try{& $Body | Out-Null}catch{$rejected=$true};Require $rejected 'Expected refusal'}
$nativeEvidence=$null
if($RunNativeFixture){
    $fixture=Join-Path (Split-Path -Parent $out) ('own-processes-'+[guid]::NewGuid().ToString('N'))
    $bin=Join-Path $fixture 'bin';New-Item -ItemType Directory -Path $bin | Out-Null
    $stub=Join-Path $fixture 'OwnedProcessFixture.cs'
    $code=@'
using System;
using System.Diagnostics;
using System.IO;
class OwnedProcessFixture {
    static int Main(string[] args) {
        if(args.Length != 1) return 2;
        if(args[0] == "--broker") { Console.ReadLine(); return 0; }
        if(args[0] != "--runtime") return 2;
        var start=new ProcessStartInfo(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"YimeBroker.exe"),"--broker");
        start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardInput=true;
        using(var child=Process.Start(start)) {
            try {Console.WriteLine(child.Id);Console.Out.Flush();Console.ReadLine();}
            finally {if(!child.HasExited){child.StandardInput.WriteLine("stop");if(!child.WaitForExit(5000)){child.Kill();child.WaitForExit();}}}
        }
        return 0;
    }
}
'@
    [IO.File]::WriteAllText($stub,$code,[Text.UTF8Encoding]::new($false))
    $runtimePath=Join-Path $bin 'YimeCoreTrialRuntime.exe';$brokerPath=Join-Path $bin 'YimeBroker.exe'
    & 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /target:exe /platform:x64 ("/out:"+$runtimePath) $stub
    if($LASTEXITCODE -ne 0){throw 'Owned fixture compiler failed'}
    [IO.File]::Copy($runtimePath,$brokerPath,$false)
    $hash=(Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $start=[Diagnostics.ProcessStartInfo]::new($runtimePath,'--runtime');$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true
    $runtime=[Diagnostics.Process]::Start($start);$held=$null
    try {
        $ready=$runtime.StandardOutput.ReadLineAsync()
        if(-not $ready.Wait(5000) -or $ready.Result -notmatch '^[1-9][0-9]*$'){throw 'Owned helper handshake failed'}
        $brokerId=[int]$ready.Result
        # Feed only our two child PIDs to discovery. The real product process
        # enumerator is never called, even when the installed product is live.
        & $module {param($r,$b) $script:ownedRuntime=$r;$script:ownedBroker=$b
            function script:Get-MaintenanceProcessRows { @([pscustomobject]@{Name='YimeCoreTrialRuntime.exe';ProcessId=[int]$script:ownedRuntime},[pscustomobject]@{Name='YimeBroker.exe';ProcessId=[int]$script:ownedBroker}) }
        } $runtime.Id $brokerId
        $nativeParameters=@{TargetUserSid=$sid;ExpectedInstallRoot=$fixture;ExpectedRuntimeSha256=$hash;ExpectedBrokerSha256=$hash}
        Check 'native-own-runtime-broker-handles-and-five-identities' {
            $script:held=Open-YimeCoreNativeMaintenanceProcesses @nativeParameters
            $script:nativeEvidence=Assert-YimeCoreNativeMaintenanceProcessesCurrent $held
            Require ($nativeEvidence.processes.Count -eq 2 -and $nativeEvidence.processes[0].pid -eq $runtime.Id -and $nativeEvidence.processes[1].pid -eq $brokerId) 'Wrong OS process identity'
            Require ($nativeEvidence.processes[1].parent_pid -eq $runtime.Id -and $nativeEvidence.processes[0].sid -ceq $sid -and $nativeEvidence.processes[1].sid -ceq $sid) 'Native parent/SID mismatch'
            Require ($nativeEvidence.processes[0].image_sha256 -ceq $hash -and $nativeEvidence.processes[1].image_sha256 -ceq $hash) 'File hash mismatch'
            Require (-not $nativeEvidence.startup_path_verified -and -not $nativeEvidence.runtime_ready_verified -and -not $nativeEvidence.in_memory_code_identity_verified) 'Observation overclaimed readiness'
        }
        Check 'native-wrong-public-image-hash-refused' {$wrong=@{};foreach($key in $nativeParameters.Keys){$wrong[$key]=$nativeParameters[$key]};$wrong.ExpectedRuntimeSha256='0'*64;Reject {Get-YimeCoreNativeMaintenanceProcesses @wrong}}
        Check 'native-same-name-unapproved-root-refused' {$wrong=@{};foreach($key in $nativeParameters.Keys){$wrong[$key]=$nativeParameters[$key]};$wrong.ExpectedInstallRoot=$fixture+'-different';Reject {Get-YimeCoreNativeMaintenanceProcesses @wrong}}
        Check 'native-image-lease-denies-write' {Require ($null -ne $held) 'No retained observation';Reject {$stream=[IO.File]::Open($runtimePath,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$stream.Dispose()}}
        $runtime.StandardInput.WriteLine('stop');Require ($runtime.WaitForExit(5000)) 'Owned helper did not stop'
        Check 'native-retained-handle-rejects-terminated-process' {Require ($null -ne $held) 'No retained observation';Reject {Assert-YimeCoreNativeMaintenanceProcessesCurrent $held}}
        if($null -ne $held){Close-YimeCoreNativeMaintenanceProcesses $held}
        Check 'native-closed-observation-refused' {Require ($null -ne $held) 'No retained observation';Reject {Assert-YimeCoreNativeMaintenanceProcessesCurrent $held}}
    } finally {
        if($null -ne $held){Close-YimeCoreNativeMaintenanceProcesses $held}
        if(-not $runtime.HasExited){$runtime.StandardInput.WriteLine('stop');if(-not $runtime.WaitForExit(5000)){$runtime.Kill();$runtime.WaitForExit()}}
        $runtime.Dispose()
    }
}

& $module {param($Sid)
    $script:fixtureSid=$Sid;$script:mode='valid';$script:enumCalls=0;$script:pinReads=0;$script:sourceCalls=0;$script:objects=[Collections.Generic.List[object]]::new()
    function script:Initialize-MaintenanceProcessFacts {}
    function script:Get-MaintenanceProcessCallerSid {$script:fixtureSid}
    function script:Get-MaintenanceProcessSourcePins {$script:sourceCalls++;[pscustomobject]@{name='synthetic';sha256=if($script:mode -ceq 'source_changed' -and $script:sourceCalls -gt 1){'b'*64}else{'a'*64}}}
    function script:Get-MaintenanceProcessRows {
        $script:enumCalls++
        if($script:mode -ceq 'enumerator_throw'){throw 'Synthetic enumeration failed'}
        $rows=@([pscustomobject]@{Name='YimeCoreTrialRuntime.exe';ProcessId=101},[pscustomobject]@{Name='YimeBroker.exe';ProcessId=102})
        switch($script:mode){
            absent {$rows=@()};partial {$rows=@($rows[0])};multiple {$rows += [pscustomobject]@{Name='YimeBroker.exe';ProcessId=103}}
            unknown_name {$rows[1].Name='Other.exe'};duplicate_name {$rows[1].Name='YimeCoreTrialRuntime.exe'}
            string_pid {$rows[0].ProcessId='101'};bool_pid {$rows[0].ProcessId=$true};zero_pid {$rows[0].ProcessId=0};overflow_pid {$rows[0].ProcessId=[uint64]4294967296}
            duplicate_pid {$rows[1].ProcessId=101};membership_changed {if($script:enumCalls -gt 1){$rows[1].ProcessId=104}}
        };return $rows
    }
    function script:New-FakeDisposable($Value){$Value | Add-Member ScriptMethod Dispose {$this.closed=$true};$script:objects.Add($Value);return $Value}
    function script:Open-MaintenanceProcessPin([int]$ProcessId){if($script:mode -ceq 'pin_open_failed'){throw 'Pin failed'};New-FakeDisposable ([pscustomobject]@{pid=$ProcessId;closed=$false})}
    function script:Read-MaintenanceProcessPin($Pin){
        $script:pinReads++;if($Pin.closed -or $script:mode -ceq 'terminated' -or ($script:mode -ceq 'terminated_late' -and $script:pinReads -gt 4)){throw 'Pinned fake process exited'}
        $name=if($Pin.pid -eq 101){'YimeCoreTrialRuntime.exe'}else{'YimeBroker.exe'}
        $value=[pscustomobject]@{Pid=[int]$Pin.pid;ParentPid=[int]$(if($Pin.pid -eq 101){99}else{101});CreationFileTime=[long]$(if($Pin.pid -eq 101){1000}else{1100});Image=('C:\SyntheticProcessFixture\bin\'+$name);ProcessMachine=[uint16]0;NativeMachine=[uint16]0x8664}
        switch($script:mode){
            wrong_image {$value.Image='C:\Other\'+$name};wow64 {$value.ProcessMachine=[uint16]0x14c};wrong_arch {$value.NativeMachine=[uint16]0xAA64}
            token_race {$value.CreationFileTime=[long]1200};wrong_parent {if($Pin.pid -eq 102){$value.ParentPid=77}}
            child_older {if($Pin.pid -eq 102){$value.CreationFileTime=[long]900}}
            pid_reused {if($script:pinReads -gt 2){$value.CreationFileTime=[long]2000}}
            string_time {$value.CreationFileTime='1000'}
        };return $value
    }
    function script:Open-MaintenanceProcessTokenFacts([int]$ProcessId){
        if($script:mode -ceq 'token_open_failed'){throw 'Token failed'}
        $name=if($ProcessId -eq 101){'YimeCoreTrialRuntime.exe'}else{'YimeBroker.exe'}
        $value=[pscustomobject]@{Pid=$ProcessId;CreationFileTime=[long]$(if($ProcessId -eq 101){1000}else{1100});Image=('C:\SyntheticProcessFixture\bin\'+$name);Sid=$script:fixtureSid;Elevated=$false;PackageQuery=15700;closed=$false}
        switch($script:mode){foreign_sid {$value.Sid='S-1-5-21-1-2-3-4'};elevated {$value.Elevated=$true};elevation_string {$value.Elevated='false'};packaged {$value.PackageQuery=122};package_unknown {$value.PackageQuery=5};package_string {$value.PackageQuery='15700'};wrong_image {$value.Image='C:\Other\'+$name};child_older {if($ProcessId -eq 102){$value.CreationFileTime=[long]900}}}
        New-FakeDisposable $value
    }
    function script:Open-MaintenanceProcessFile([string]$Path,[string]$ExpectedSha256){if($script:mode -ceq 'hash_mismatch'){throw 'Hash mismatch'};if($script:mode -ceq 'indirect_image'){throw 'Indirect image'};New-FakeDisposable ([pscustomobject]@{path=$Path;sha256=$ExpectedSha256;bytes=[long]123;file_identity='synthetic-file';closed=$false})}
    function script:Assert-MaintenanceProcessFile($File){if($File.closed -or $script:mode -ceq 'file_identity_changed'){throw 'File changed'}}
    function script:Close-MaintenanceProcessFile($File){$File.Dispose()}
} $sid
function Set-Mode([string]$Mode){& $module {param($m) $script:mode=$m;$script:enumCalls=0;$script:pinReads=0;$script:sourceCalls=0;$script:objects.Clear()} $Mode}
$parameters=@{TargetUserSid=$sid;ExpectedInstallRoot='C:\SyntheticProcessFixture';ExpectedRuntimeSha256=('a'*64);ExpectedBrokerSha256=('b'*64)}
Check 'no-public-enumerator-scriptblock-or-pid-overrides' {
    foreach($name in @('Get-YimeCoreNativeMaintenanceProcesses','Open-YimeCoreNativeMaintenanceProcesses')){
        $cmd=Get-Command $name;foreach($parameter in @('Provider','Enumerator','ScriptBlock','RuntimePid','BrokerPid')){Require (-not $cmd.Parameters.ContainsKey($parameter)) 'Public trust override'}
    }
}
Check 'source-descriptor-executable-names-match' {
    $product=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local-product.json') -Raw | ConvertFrom-Json
    $paths=@($product.go_binaries | ForEach-Object {$_.path})
    Require ($paths -contains 'bin/YimeCoreTrialRuntime.exe' -and $paths -contains 'bin/YimeBroker.exe') 'Canonical product names changed'
}
Check 'synthetic-complete-native-identity-observation' {Set-Mode valid;$value=Get-YimeCoreNativeMaintenanceProcesses @parameters;Require ($value.processes.Count -eq 2 -and $value.native_handle_identity_observed -and -not $value.runtime_ready_verified -and -not $value.startup_path_verified) 'Observation mismatch';$objects=& $module {$script:objects.ToArray()};Require (@($objects | Where-Object {-not $_.closed}).Count -eq 0) 'Get leaked handles'}
foreach($mode in @('enumerator_throw','absent','partial','multiple','unknown_name','duplicate_name','string_pid','bool_pid','zero_pid','overflow_pid','duplicate_pid','membership_changed','pin_open_failed','terminated','terminated_late','wrong_image','wow64','wrong_arch','token_race','wrong_parent','child_older','pid_reused','string_time','token_open_failed','foreign_sid','elevated','elevation_string','packaged','package_unknown','package_string','hash_mismatch','indirect_image','file_identity_changed','source_changed')){
    Check ('reject-'+$mode){Set-Mode $mode;Reject {Get-YimeCoreNativeMaintenanceProcesses @parameters};$objects=& $module {$script:objects.ToArray()};Require (@($objects | Where-Object {-not $_.closed}).Count -eq 0) 'Failure leaked handles'}
}
Check 'closed-and-deserialized-contexts-rejected' {
    Set-Mode valid;$lease=Open-YimeCoreNativeMaintenanceProcesses @parameters
    try{$clone=$lease | ConvertTo-Json -Depth 12 | ConvertFrom-Json;Reject {Assert-YimeCoreNativeMaintenanceProcessesCurrent $clone};Reject {Close-YimeCoreNativeMaintenanceProcesses $clone};Assert-YimeCoreNativeMaintenanceProcessesCurrent $lease | Out-Null}
    finally{Close-YimeCoreNativeMaintenanceProcesses $lease}
    Reject {Assert-YimeCoreNativeMaintenanceProcessesCurrent $lease};Close-YimeCoreNativeMaintenanceProcesses $lease
}
Check 'caller-evidence-edit-does-not-change-native-observation' {
    Set-Mode valid;$lease=Open-YimeCoreNativeMaintenanceProcesses @parameters
    try{$lease.evidence.runtime_ready_verified=$true;$lease.evidence.processes[0].pid=999;$actual=Assert-YimeCoreNativeMaintenanceProcessesCurrent $lease;Require (-not $actual.runtime_ready_verified -and $actual.processes[0].pid -eq 101) 'Caller JSON changed observed identity'}finally{Close-YimeCoreNativeMaintenanceProcesses $lease}
}
Check 'caller-source-metadata-edit-does-not-change-private-baseline' {
    Set-Mode valid;$lease=Open-YimeCoreNativeMaintenanceProcesses @parameters
    try{$lease.evidence.source_pins[0].sha256='b'*64;$actual=Assert-YimeCoreNativeMaintenanceProcessesCurrent $lease;Require ($actual.source_pins[0].sha256 -ceq ('a'*64) -and -not $actual.desktop_session_verified) 'Caller modified private source baseline or desktop claim'}finally{Close-YimeCoreNativeMaintenanceProcesses $lease}
}
foreach($root in @('relative','C:\SyntheticProcessFixture\','C:\SyntheticProcessFixture\..\Elsewhere','\\server\share','C:\SyntheticProcessFixture:ads','C:\NUL','C:\SyntheticProcessFixture.')){
    Check ('reject-root-'+$root){$bad=@{};foreach($key in $parameters.Keys){$bad[$key]=$parameters[$key]};$bad.ExpectedInstallRoot=$root;Reject {Get-YimeCoreNativeMaintenanceProcesses @bad}}
}
$failed=@($checks | Where-Object {-not $_.passed})
$pins=@();foreach($path in @($modulePath,(Join-Path $PSScriptRoot 'native-maintenance-process-facts.cs'),$PSCommandPath,(Join-Path $PSScriptRoot '../dual-product/rime-pime-dp1u-native-facts.cs'))){$pins += [ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}}
$result=[ordered]@{schema_version='yimecore-native-maintenance-process-tests-v1';passed=($failed.Count -eq 0);powershell=$PSVersionTable.PSVersion.ToString();checks_count=$checks.Count;failed_count=$failed.Count;checks=$checks.ToArray();native_own_process_fixture_executed=[bool]$RunNativeFixture;native_observation=$nativeEvidence;source_pins=$pins;product_processes_enumerated=$false;installed_product_read_or_executed=$false;product_registry_read_or_written=$false;user_state_read=$false;product_start_stop_or_session_quota_changed=$false;note='Native execution, when requested, uses only compiled owned stub helpers and an internal enumerator of their PIDs. Observation does not prove startup/readiness or in-memory executable integrity.'}
[IO.File]::WriteAllText($out,(($result | ConvertTo-Json -Depth 18).Replace("`r`n","`n")+"`n"),[Text.UTF8Encoding]::new($false))
Write-Output "Native maintenance processes: $($checks.Count) checks, $($failed.Count) failed; $out"
if($failed.Count){$failed | ForEach-Object {[pscustomobject]$_} | Format-Table name,error -AutoSize;exit 1}
