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
# stdin is deliberately closed after every owned launch. A private named event
# owns lifetime instead: EOF, CI's noninteractive host, and redirected handles
# must not be mistaken for a caller-requested stop.
function New-OwnedFixtureRelease {
    $name='Local\YimeMaintenanceProcessFixture.'+[guid]::NewGuid().ToString('N');$created=$false
    $handle=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$name,[ref]$created)
    if(-not $created){$handle.Dispose();throw 'Owned release event was already present'}
    [pscustomobject]@{name=$name;handle=$handle}
}
function New-OwnedFixtureStart([string]$Path,[string]$Mode,[string[]]$ReleaseNames) {
    if($Mode -cnotin @('--wait','--runtime') -or @($ReleaseNames|Where-Object {$_ -cnotmatch '^Local\\YimeMaintenanceProcessFixture\.[a-f0-9]{32}$'}).Count){throw 'Invalid owned fixture arguments'}
    $info=[Diagnostics.ProcessStartInfo]::new($Path,($Mode+' '+($ReleaseNames -join ' ')))
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true
    return $info
}
function Read-OwnedFixtureReady($Process) {
    $Process.StandardInput.Close()
    $ready=$Process.StandardOutput.ReadLineAsync()
    if(-not $ready.Wait(5000) -or $ready.Result -cnotmatch '^[1-9][0-9]*$'){throw 'Bounded owned fixture readiness handshake failed'}
    return [int]$ready.Result
}
function Stop-OwnedFixture($Process,$Release) {
    if($null -ne $Release){[void]$Release.handle.Set()}
    if($null -ne $Process -and -not $Process.HasExited){if(-not $Process.WaitForExit(5000)){$Process.Kill();$Process.WaitForExit();throw 'Owned fixture required forced cleanup after release'}}
}
$nativeEvidence=$null
$privateTypeEvidence=$null
try {
$waitRoot=Join-Path (Split-Path -Parent $out) ('owned-release-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($waitRoot)
$waitSource=Join-Path $waitRoot 'OwnedProcessFixture.cs';$waitHelper=Join-Path $waitRoot 'OwnedWait.exe'
$code=@'
using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading;
class OwnedProcessFixture {
    static EventWaitHandle Release(string name) {
        if(!Regex.IsMatch(name,@"\ALocal\\YimeMaintenanceProcessFixture\.[a-f0-9]{32}\z")) throw new ArgumentException("Owned event name required");
        return EventWaitHandle.OpenExisting(name);
    }
    static int Main(string[] args) {
        if(args.Length == 2 && args[0] == "--wait") {
            using(var release=Release(args[1])) {
                Console.WriteLine(Process.GetCurrentProcess().Id);Console.Out.Flush();
                return release.WaitOne(90000) ? 0 : 124;
            }
        }
        if(args.Length != 3 || args[0] != "--runtime") return 2;
        using(var release=Release(args[1])) using(var brokerRelease=Release(args[2])) {
            var start=new ProcessStartInfo(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"YimeBroker.exe"),"--wait "+args[2]);
            start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardInput=true;start.RedirectStandardOutput=true;
            using(var child=Process.Start(start)) {
                int result=3;
                try {
                    child.StandardInput.Close();var ready=child.StandardOutput.ReadLineAsync();
                    if(ready.Wait(5000) && ready.Result == child.Id.ToString()) {
                        Console.WriteLine(child.Id);Console.Out.Flush();
                        result=release.WaitOne(90000) ? 0 : 124;
                    }
                } finally {brokerRelease.Set();if(!child.WaitForExit(5000)){child.Kill();child.WaitForExit();result=125;}}
                return result;
            }
        }
    }
}
'@
[IO.File]::WriteAllText($waitSource,$code,[Text.UTF8Encoding]::new($false))
& 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /target:exe /platform:x64 ("/out:"+$waitHelper) $waitSource
if($LASTEXITCODE -ne 0){throw 'Owned release fixture compiler failed'}
if($RunNativeFixture){
    $fixture=Join-Path (Split-Path -Parent $out) ('own-processes-'+[guid]::NewGuid().ToString('N'))
    $bin=Join-Path $fixture 'bin';New-Item -ItemType Directory -Path $bin | Out-Null
    $runtimePath=Join-Path $bin 'YimeCoreTrialRuntime.exe';$brokerPath=Join-Path $bin 'YimeBroker.exe'
    [IO.File]::Copy($waitHelper,$runtimePath,$false)
    [IO.File]::Copy($runtimePath,$brokerPath,$false)
    $hash=(Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $runtimeRelease=New-OwnedFixtureRelease;$brokerRelease=New-OwnedFixtureRelease
    $start=New-OwnedFixtureStart $runtimePath '--runtime' @($runtimeRelease.name,$brokerRelease.name)
    $runtime=$null;$held=$null;$referenceHeld=$null;$brokerReference=$null
    try {
        $runtime=[Diagnostics.Process]::Start($start)
        $brokerId=Read-OwnedFixtureReady $runtime
        Check 'native-pair-survives-closed-stdin-until-explicit-release' {Require (-not $runtime.WaitForExit(200)) 'Owned Runtime stopped on stdin EOF'}
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
        $brokerReference=[Diagnostics.Process]::GetProcessById($brokerId)
        $referenceParameters=@{};foreach($key in $nativeParameters.Keys){$referenceParameters[$key]=$nativeParameters[$key]}
        $referenceParameters.RuntimeProcess=$runtime;$referenceParameters.BrokerProcess=$brokerReference
        Check 'native-original-references-open-without-global-discovery' {
            & $module {function script:Get-MaintenanceProcessRows {throw 'References must never discover global product processes'}}
            $script:referenceHeld=Open-YimeCoreNativeMaintenanceProcesses @referenceParameters
            $actual=Assert-YimeCoreNativeMaintenanceProcessesCurrent $referenceHeld
            Require ($actual.discovery_scope -ceq 'explicit_process_references' -and $actual.processes[0].pid -eq $runtime.Id -and $actual.processes[1].pid -eq $brokerId) 'Original native pair was not retained'
            Require (-not $actual.process_start_origin_authenticated) 'Reference adoption claimed authenticated process launch'
        }
        Check 'native-reference-close-preserves-caller-process-handles' {
            $lease=Open-YimeCoreNativeMaintenanceProcesses @referenceParameters
            Close-YimeCoreNativeMaintenanceProcesses $lease
            Require (-not $runtime.HasExited -and -not $brokerReference.HasExited -and -not $runtime.SafeHandle.IsClosed -and -not $brokerReference.SafeHandle.IsClosed) 'Closing lease disposed caller process'
        }
        Check 'native-disposed-original-reference-refused-without-pid-reopen' {
            $duplicate=[Diagnostics.Process]::GetProcessById($runtime.Id);$lease=$null
            try {
                $copy=@{};foreach($key in $referenceParameters.Keys){$copy[$key]=$referenceParameters[$key]};$copy.RuntimeProcess=$duplicate
                $lease=Open-YimeCoreNativeMaintenanceProcesses @copy
                $duplicate.Dispose()
                Reject {Assert-YimeCoreNativeMaintenanceProcessesCurrent $lease}
                Require (-not $runtime.HasExited) 'Owned helper was changed by disposed wrapper test'
            } finally {if($null -ne $lease){Close-YimeCoreNativeMaintenanceProcesses $lease};$duplicate.Dispose()}
        }
        # Restore the private discovery fixture for the existing global tests.
        & $module {function script:Get-MaintenanceProcessRows { @([pscustomobject]@{Name='YimeCoreTrialRuntime.exe';ProcessId=[int]$script:ownedRuntime},[pscustomobject]@{Name='YimeBroker.exe';ProcessId=[int]$script:ownedBroker}) }}
        Check 'native-wrong-public-image-hash-refused' {$wrong=@{};foreach($key in $nativeParameters.Keys){$wrong[$key]=$nativeParameters[$key]};$wrong.ExpectedRuntimeSha256='0'*64;Reject {Get-YimeCoreNativeMaintenanceProcesses @wrong}}
        Check 'native-same-name-unapproved-root-refused' {$wrong=@{};foreach($key in $nativeParameters.Keys){$wrong[$key]=$nativeParameters[$key]};$wrong.ExpectedInstallRoot=$fixture+'-different';Reject {Get-YimeCoreNativeMaintenanceProcesses @wrong}}
        Check 'native-image-lease-denies-write' {Require ($null -ne $held) 'No retained observation';Reject {$stream=[IO.File]::Open($runtimePath,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$stream.Dispose()}}
        Check 'native-reviewed-source-streams-held-through-observation' {
            Require ($null -ne $referenceHeld) 'No retained reference observation'
            foreach($path in @($modulePath,(Join-Path $PSScriptRoot 'native-maintenance-process-facts.cs'),(Join-Path $PSScriptRoot '../dual-product/rime-pime-dp1u-native-facts.cs'))){
                Reject {$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$stream.Dispose()}
            }
        }
        [void]$runtimeRelease.handle.Set();Require ($runtime.WaitForExit(5000) -and $runtime.ExitCode -eq 0) 'Owned helper did not stop after explicit release'
        Check 'native-original-references-reject-natural-exit' {Require ($null -ne $referenceHeld) 'No retained reference lease';Reject {Assert-YimeCoreNativeMaintenanceProcessesCurrent $referenceHeld}}
        Check 'native-retained-handle-rejects-terminated-process' {Require ($null -ne $held) 'No retained observation';Reject {Assert-YimeCoreNativeMaintenanceProcessesCurrent $held}}
        if($null -ne $held){Close-YimeCoreNativeMaintenanceProcesses $held}
        Check 'native-closed-observation-refused' {Require ($null -ne $held) 'No retained observation';Reject {Assert-YimeCoreNativeMaintenanceProcessesCurrent $held}}
    } finally {
        try{if($null -ne $referenceHeld){Close-YimeCoreNativeMaintenanceProcesses $referenceHeld}}
        finally{try{if($null -ne $held){Close-YimeCoreNativeMaintenanceProcesses $held}}
            finally{try{[void]$brokerRelease.handle.Set();Stop-OwnedFixture $runtime $runtimeRelease}finally{if($null -ne $runtime){$runtime.Dispose()};if($null -ne $brokerReference){$brokerReference.Dispose()};$runtimeRelease.handle.Dispose();$brokerRelease.handle.Dispose()}}}
    }
}

Check 'private-native-types-ignore-preloaded-global-fakes-and-bind-original-handle' {
    $childRoot=Join-Path (Split-Path -Parent $out) ('process-types-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($childRoot)
    $childPath=Join-Path $childRoot 'preloaded-types.ps1';$childOutput=Join-Path $childRoot 'summary.json'
    $beforeFacts='Yime.Dp1UNative.Facts' -as [type];$beforePin='Yime.MaintenanceProcesses.ProcessPin' -as [type]
    $childSource=@'
param([string]$ModulePath,[string]$ResultPath,[string]$HelperPath)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @"
using System;
namespace Yime.Dp1UNative { public static class Facts { public static object OpenProcessFacts(int pid){throw new Exception("Global fake Facts adopted");} } }
namespace Yime.MaintenanceProcesses { public static class ProcessPin { public static object Open(int pid){throw new Exception("Global fake ProcessPin adopted");} public static object OpenReference(System.Diagnostics.Process process){throw new Exception("Global fake reference pin adopted");} } }
"@
$m=Import-Module $ModulePath -Force -PassThru
$result=& $m {param($HelperPath)
    function New-Release {
        $name='Local\YimeMaintenanceProcessFixture.'+[guid]::NewGuid().ToString('N');$created=$false
        $handle=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$name,[ref]$created)
        if(-not $created){$handle.Dispose();throw 'Owned child release event already exists'}
        [pscustomobject]@{name=$name;handle=$handle}
    }
    function Ready-AfterEof($process){$process.StandardInput.Close();$ready=$process.StandardOutput.ReadLineAsync();if(-not $ready.Wait(5000) -or $ready.Result -cne [string]$process.Id){throw 'Owned child readiness failed'};if($process.WaitForExit(200)){throw 'Owned child exited on stdin EOF'}}
    $sources=Open-MaintenanceProcessSources;$pin=$null;$token=$null;$self=[Diagnostics.Process]::GetCurrentProcess();$own=$null;$reassociatedPin=$null;$reassociatedWrapper=$null;$reassociatedStarted=$false;$ownRelease=$null;$reassociatedRelease=$null;$forcedCleanup=$false
    try{
        Initialize-MaintenanceProcessFacts $sources
        if($script:ProcessFactsType.Namespace -cnotmatch '^Yime\.MaintenanceProcessLease_[a-f0-9]{32}$' -or $script:ProcessPinType.Namespace -cne $script:ProcessFactsType.Namespace){throw 'Private type namespace not used'}
        $pin=$script:ProcessPinType::OpenReference($self);$first=$pin.Capture()
        $token=$script:ProcessFactsType::OpenProcessFacts($self.Id)
        if($first.Pid -ne $self.Id -or $first.CreationFileTime -ne $token.CreationFileTime){throw 'Original self handle identity differs'}
        $pin.Dispose();$pin=$null
        if($self.HasExited -or $self.SafeHandle.IsClosed){throw 'Reference pin disposed caller handle'}
        $ownRelease=New-Release
        $setup=[Diagnostics.ProcessStartInfo]::new($HelperPath,('--wait '+$ownRelease.name))
        $setup.UseShellExecute=$false;$setup.CreateNoWindow=$true;$setup.RedirectStandardInput=$true;$setup.RedirectStandardOutput=$true
        $own=[Diagnostics.Process]::Start($setup);Ready-AfterEof $own;$reassociatedPin=$script:ProcessPinType::OpenReference($own)
        $originalId=$own.Id;[void]$ownRelease.handle.Set();if(-not $own.WaitForExit(5000) -or $own.ExitCode -ne 0){throw 'Owned process did not stop after explicit release'}
        $exitedRejected=$false;try{$reassociatedPin.Capture()|Out-Null}catch{$exitedRejected=$true};if(-not $exitedRejected){throw 'Exited original handle accepted'}
        $reassociatedPin.Dispose();$reassociatedPin=$null
        # The old target remains this live PowerShell process. Reassociation
        # refusal must therefore come from the original object/handle binding,
        # not merely from observing that a former helper already exited.
        $reassociatedWrapper=[Diagnostics.Process]::GetCurrentProcess();$reassociatedPin=$script:ProcessPinType::OpenReference($reassociatedWrapper)
        $reassociatedRelease=New-Release;$setup.Arguments='--wait '+$reassociatedRelease.name
        $reassociatedWrapper.Close();$reassociatedWrapper.StartInfo=$setup
        $reassociatedStarted=$reassociatedWrapper.Start();if(-not $reassociatedStarted){throw 'Own wrapper reassociation failed'}
        Ready-AfterEof $reassociatedWrapper
        $reassociatedRejected=$false;try{$reassociatedPin.Capture()|Out-Null}catch{$reassociatedRejected=$true};if(-not $reassociatedRejected){throw 'Process Close/Start association was reopened by PID'}
        if($self.HasExited){throw 'Old reassociated process is not live'}
        $closedRejected=$false;$duplicate=[Diagnostics.Process]::GetCurrentProcess();$closedPin=$null
        try{$closedPin=$script:ProcessPinType::OpenReference($duplicate);$duplicate.Dispose();try{$closedPin.Capture()|Out-Null}catch{$closedRejected=$true}}finally{if($null -ne $closedPin){$closedPin.Dispose()};$duplicate.Dispose()}
        if(-not $closedRejected){throw 'Disposed original reference accepted'}
        $rawClosedRejected=$false;$rawWrapper=[Diagnostics.Process]::GetCurrentProcess();$rawPin=$null
        try{$rawPin=$script:ProcessPinType::OpenReference($rawWrapper);$rawWrapper.SafeHandle.Dispose();try{$rawPin.Capture()|Out-Null}catch{$rawClosedRejected=$true}}finally{if($null -ne $rawPin){$rawPin.Dispose()};$rawWrapper.Dispose()}
        if(-not $rawClosedRejected -or $self.HasExited){throw 'Caller-closed SafeHandle accepted or caller process stopped'}
        [ordered]@{passed=$true;private_types=$true;original_handle_identity=$true;caller_handle_preserved=$true;exited_reference_rejected=$exitedRejected;reassociated_reference_rejected=$reassociatedRejected;reassociation_old_process_still_live=$true;disposed_reference_rejected=$closedRejected;raw_closed_handle_rejected=$rawClosedRejected;owned_helpers_survived_stdin_eof=$true;global_product_discovery_used=$false}
    }finally{
        if($null -ne $reassociatedRelease){[void]$reassociatedRelease.handle.Set()}
        if($null -ne $ownRelease){[void]$ownRelease.handle.Set()}
        if($null -ne $reassociatedWrapper){if($reassociatedStarted -and -not $reassociatedWrapper.HasExited){if(-not $reassociatedWrapper.WaitForExit(5000)){$forcedCleanup=$true;$reassociatedWrapper.Kill();$reassociatedWrapper.WaitForExit()}};$reassociatedWrapper.Dispose()}
        if($null -ne $own){if(-not $own.HasExited){if(-not $own.WaitForExit(5000)){$forcedCleanup=$true;$own.Kill();$own.WaitForExit()}};$own.Dispose()}
        if($null -ne $reassociatedRelease){$reassociatedRelease.handle.Dispose()};if($null -ne $ownRelease){$ownRelease.handle.Dispose()}
        if($null -ne $reassociatedPin){$reassociatedPin.Dispose()};if($null -ne $pin){$pin.Dispose()};if($null -ne $token){$token.Dispose()};$self.Dispose();Close-MaintenanceProcessSources $sources
        if($forcedCleanup){throw 'Owned reference fixture required forced cleanup after explicit release'}
    }
} $HelperPath
[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Remove-Module $m
'@
    [IO.File]::WriteAllText($childPath,$childSource,[Text.UTF8Encoding]::new($false))
    $shell=Join-Path $PSHOME $(if($PSVersionTable.PSVersion.Major -ge 7){'pwsh.exe'}else{'powershell.exe'})
    & $shell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $childPath -ModulePath $modulePath -ResultPath $childOutput -HelperPath $waitHelper
    Require ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $childOutput)) 'Private type/reference native child failed'
    $proof=Get-Content -LiteralPath $childOutput -Raw|ConvertFrom-Json
    Require ($proof.passed -eq $true -and $proof.private_types -eq $true -and $proof.reassociated_reference_rejected -eq $true -and $proof.reassociation_old_process_still_live -eq $true -and $proof.disposed_reference_rejected -eq $true -and $proof.raw_closed_handle_rejected -eq $true -and $proof.owned_helpers_survived_stdin_eof -eq $true) 'Native reference association proof missing'
    Require ([object]::ReferenceEquals($beforeFacts,('Yime.Dp1UNative.Facts' -as [type])) -and [object]::ReferenceEquals($beforePin,('Yime.MaintenanceProcesses.ProcessPin' -as [type]))) 'Disposable child polluted caller global types'
    $script:privateTypeEvidence=[ordered]@{passed=$true;raw_closed_handle_rejected=$proof.raw_closed_handle_rejected;reassociation_old_process_still_live=$proof.reassociation_old_process_still_live;evidence=@(foreach($path in @($childPath,$childOutput)){[ordered]@{path=$path;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}})}
}

& $module {param($Sid)
    $script:fixtureSid=$Sid;$script:mode='valid';$script:enumCalls=0;$script:pinReads=0;$script:sourceCalls=0;$script:objects=[Collections.Generic.List[object]]::new()
    $script:runtimeId=101;$script:brokerId=102;$script:referenceCalls=0
    function script:Initialize-MaintenanceProcessFacts {}
    function script:Get-MaintenanceProcessCallerSid {$script:fixtureSid}
    function script:Get-MaintenanceProcessSourcePins {$script:sourceCalls++;[pscustomobject]@{name='synthetic';sha256=if($script:mode -ceq 'source_changed' -and $script:sourceCalls -gt 1){'b'*64}else{'a'*64}}}
    function script:Open-MaintenanceProcessSources {
        $source=New-FakeDisposable ([pscustomobject]@{records=@([pscustomobject]@{name='synthetic';sha256=('a'*64)});files=@();closed=$false})
        return $source
    }
    function script:Assert-MaintenanceProcessSources($Sources){$script:sourceCalls++;if($Sources.closed -or $script:mode -ceq 'source_changed'){throw 'Pinned sources changed'}}
    function script:Close-MaintenanceProcessSources($Sources){$Sources.Dispose()}
    function script:Get-MaintenanceProcessRows {
        $script:enumCalls++
        if($script:mode -ceq 'enumerator_throw'){throw 'Synthetic enumeration failed'}
        $rows=@([pscustomobject]@{Name='YimeCoreTrialRuntime.exe';ProcessId=$script:runtimeId},[pscustomobject]@{Name='YimeBroker.exe';ProcessId=$script:brokerId})
        switch($script:mode){
            absent {$rows=@()};partial {$rows=@($rows[0])};multiple {$rows += [pscustomobject]@{Name='YimeBroker.exe';ProcessId=103}}
            unknown_name {$rows[1].Name='Other.exe'};duplicate_name {$rows[1].Name='YimeCoreTrialRuntime.exe'}
            string_pid {$rows[0].ProcessId='101'};bool_pid {$rows[0].ProcessId=$true};zero_pid {$rows[0].ProcessId=0};overflow_pid {$rows[0].ProcessId=[uint64]4294967296}
            duplicate_pid {$rows[1].ProcessId=101};membership_changed {if($script:enumCalls -gt 1){$rows[1].ProcessId=104}}
        };return $rows
    }
    function script:New-FakeDisposable($Value){$Value | Add-Member ScriptMethod Dispose {$this.closed=$true};$script:objects.Add($Value);return $Value}
    function script:Open-MaintenanceProcessPin([int]$ProcessId){if($script:mode -ceq 'pin_open_failed'){throw 'Pin failed'};New-FakeDisposable ([pscustomobject]@{pid=$ProcessId;closed=$false})}
    function script:Open-MaintenanceProcessReferencePin($Process){
        $script:referenceCalls++
        if($script:mode -ceq 'pin_open_failed' -or ($script:mode -ceq 'second_reference_open_failed' -and $script:referenceCalls -eq 2)){throw 'Reference pin failed'}
        New-FakeDisposable ([pscustomobject]@{pid=$Process.Id;closed=$false})
    }
    function script:Read-MaintenanceProcessPin($Pin){
        $script:pinReads++;if($Pin.closed -or $script:mode -ceq 'terminated' -or ($script:mode -ceq 'terminated_late' -and $script:pinReads -gt 4)){throw 'Pinned fake process exited'}
        $name=if($Pin.pid -eq $script:runtimeId){'YimeCoreTrialRuntime.exe'}else{'YimeBroker.exe'}
        $value=[pscustomobject]@{Pid=[int]$Pin.pid;ParentPid=[int]$(if($Pin.pid -eq $script:runtimeId){99}else{$script:runtimeId});CreationFileTime=[long]$(if($Pin.pid -eq $script:runtimeId){1000}else{1100});Image=('C:\SyntheticProcessFixture\bin\'+$name);ProcessMachine=[uint16]0;NativeMachine=[uint16]0x8664}
        switch($script:mode){
            wrong_image {$value.Image='C:\Other\'+$name};wow64 {$value.ProcessMachine=[uint16]0x14c};wrong_arch {$value.NativeMachine=[uint16]0xAA64}
            token_race {$value.CreationFileTime=[long]1200};wrong_parent {if($Pin.pid -eq $script:brokerId){$value.ParentPid=77}}
            child_older {if($Pin.pid -eq $script:brokerId){$value.CreationFileTime=[long]900}}
            pid_reused {if($script:pinReads -gt 2){$value.CreationFileTime=[long]2000}}
            string_time {$value.CreationFileTime='1000'}
        };return $value
    }
    function script:Open-MaintenanceProcessTokenFacts([int]$ProcessId){
        if($script:mode -ceq 'token_open_failed'){throw 'Token failed'}
        $name=if($ProcessId -eq $script:runtimeId){'YimeCoreTrialRuntime.exe'}else{'YimeBroker.exe'}
        $value=[pscustomobject]@{Pid=$ProcessId;CreationFileTime=[long]$(if($ProcessId -eq $script:runtimeId){1000}else{1100});Image=('C:\SyntheticProcessFixture\bin\'+$name);Sid=$script:fixtureSid;Elevated=$false;PackageQuery=15700;closed=$false}
        switch($script:mode){foreign_sid {$value.Sid='S-1-5-21-1-2-3-4'};elevated {$value.Elevated=$true};elevation_string {$value.Elevated='false'};packaged {$value.PackageQuery=122};package_unknown {$value.PackageQuery=5};package_string {$value.PackageQuery='15700'};wrong_image {$value.Image='C:\Other\'+$name};child_older {if($ProcessId -eq $script:brokerId){$value.CreationFileTime=[long]900}}}
        New-FakeDisposable $value
    }
    function script:Open-MaintenanceProcessFile([string]$Path,[string]$ExpectedSha256){if($script:mode -ceq 'hash_mismatch'){throw 'Hash mismatch'};if($script:mode -ceq 'indirect_image'){throw 'Indirect image'};New-FakeDisposable ([pscustomobject]@{path=$Path;sha256=$ExpectedSha256;bytes=[long]123;file_identity='synthetic-file';closed=$false})}
    function script:Assert-MaintenanceProcessFile($File){if($File.closed -or $script:mode -ceq 'file_identity_changed'){throw 'File changed'}}
    function script:Close-MaintenanceProcessFile($File){$File.Dispose()}
} $sid
function Set-Mode([string]$Mode){& $module {param($m) $script:mode=$m;$script:enumCalls=0;$script:pinReads=0;$script:sourceCalls=0;$script:referenceCalls=0;$script:objects.Clear()} $Mode}
$parameters=@{TargetUserSid=$sid;ExpectedInstallRoot='C:\SyntheticProcessFixture';ExpectedRuntimeSha256=('a'*64);ExpectedBrokerSha256=('b'*64)}
Check 'no-public-enumerator-scriptblock-or-pid-overrides' {
    foreach($name in @('Get-YimeCoreNativeMaintenanceProcesses','Open-YimeCoreNativeMaintenanceProcesses')){
        $cmd=Get-Command $name;foreach($parameter in @('Provider','Enumerator','ScriptBlock','RuntimePid','BrokerPid')){Require (-not $cmd.Parameters.ContainsKey($parameter)) 'Public trust override'}
    }
}
Check 'default-discovery-and-explicit-reference-parameter-sets' {
    foreach($name in @('Get-YimeCoreNativeMaintenanceProcesses','Open-YimeCoreNativeMaintenanceProcesses')){
        $cmd=Get-Command $name
        Require ($cmd.DefaultParameterSet -ceq 'Discovery') 'Discovery is no longer the default'
        foreach($parameter in @('RuntimeProcess','BrokerProcess')){
            Require ($cmd.Parameters.ContainsKey($parameter)) 'Missing original process reference parameter'
            $sets=$cmd.Parameters[$parameter].ParameterSets
            Require ($sets.Count -eq 1 -and $sets.ContainsKey('References') -and $sets['References'].IsMandatory) 'Reference pair is optional or leaked into discovery'
        }
    }
}
Check 'source-descriptor-executable-names-match' {
    $product=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local-product.json') -Raw | ConvertFrom-Json
    $paths=@($product.go_binaries | ForEach-Object {$_.path})
    Require ($paths -contains 'bin/YimeCoreTrialRuntime.exe' -and $paths -contains 'bin/YimeBroker.exe') 'Canonical product names changed'
}
Check 'synthetic-complete-native-identity-observation' {Set-Mode valid;$value=Get-YimeCoreNativeMaintenanceProcesses @parameters;Require ($value.processes.Count -eq 2 -and $value.native_handle_identity_observed -and -not $value.runtime_ready_verified -and -not $value.startup_path_verified -and $value.discovery_scope -ceq 'global_exact_pair') 'Observation mismatch';Require ((& $module {$script:enumCalls}) -ge 2) 'Default membership snapshots were removed';$objects=& $module {$script:objects.ToArray()};Require (@($objects | Where-Object {-not $_.closed}).Count -eq 0) 'Get leaked handles'}
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
# Only two genuine Process objects are supplied to the synthetic References
# branch. Their role facts are private fixtures, not a claim that self or the
# compiled event waiter is a product executable. No global product discovery
# is needed or allowed.
$referenceSelf=[Diagnostics.Process]::GetCurrentProcess();$referenceChild=$null;$referenceRelease=New-OwnedFixtureRelease
$start=New-OwnedFixtureStart $waitHelper '--wait' @($referenceRelease.name)
try {
    $referenceChild=[Diagnostics.Process]::Start($start)
    $referenceReadyId=Read-OwnedFixtureReady $referenceChild
    Check 'reference-fixture-survives-stdin-eof-until-explicit-release' {Require ($referenceReadyId -eq $referenceChild.Id -and -not $referenceChild.WaitForExit(200)) 'Owned reference fixture stopped on stdin EOF'}
    & $module {param($r,$b)$script:runtimeId=[int]$r;$script:brokerId=[int]$b} $referenceSelf.Id $referenceChild.Id
    $referenceParameters=@{};foreach($key in $parameters.Keys){$referenceParameters[$key]=$parameters[$key]}
    $referenceParameters.RuntimeProcess=$referenceSelf;$referenceParameters.BrokerProcess=$referenceChild
    Check 'reference-pair-complete-and-global-enumerator-never-called' {
        Set-Mode enumerator_throw
        $lease=Open-YimeCoreNativeMaintenanceProcesses @referenceParameters
        try{
            $actual=Assert-YimeCoreNativeMaintenanceProcessesCurrent $lease
            Require ($actual.discovery_scope -ceq 'explicit_process_references' -and $actual.processes[0].pid -eq $referenceSelf.Id -and $actual.processes[1].pid -eq $referenceChild.Id) 'Reference identities lost'
            Require (-not $actual.process_start_origin_authenticated -and -not $actual.runtime_ready_verified -and -not $actual.startup_path_verified) 'Reference observation overclaimed'
            Require ((& $module {$script:enumCalls}) -eq 0 -and (& $module {$script:referenceCalls}) -eq 2) 'References performed global/PID discovery'
        }finally{Close-YimeCoreNativeMaintenanceProcesses $lease}
        Require (-not $referenceSelf.SafeHandle.IsClosed -and -not $referenceChild.HasExited) 'Lease close changed caller process'
        $objects=& $module {$script:objects.ToArray()};Require (@($objects|Where-Object {-not $_.closed}).Count -eq 0) 'Reference success leaked source/process/file leases'
    }
    Check 'reference-get-wrapper-also-avoids-global-discovery-and-closes' {
        Set-Mode enumerator_throw;$actual=Get-YimeCoreNativeMaintenanceProcesses @referenceParameters
        Require ($actual.discovery_scope -ceq 'explicit_process_references' -and (& $module {$script:enumCalls}) -eq 0) 'Get wrapper lost parameter set'
        $objects=& $module {$script:objects.ToArray()};Require (@($objects|Where-Object {-not $_.closed}).Count -eq 0) 'Reference Get leaked handles'
    }
    foreach($badKind in @('null','pid','string','bool','array','object','serialized','same-reference','same-pid','closed','unstarted')){
        Check ('reference-shape-rejected-'+$badKind){
            Set-Mode valid;$bad=@{};foreach($key in $referenceParameters.Keys){$bad[$key]=$referenceParameters[$key]};$disposable=$null
            switch($badKind){
                null {$bad.RuntimeProcess=$null};pid {$bad.RuntimeProcess=$referenceSelf.Id};string {$bad.RuntimeProcess=[string]$referenceSelf.Id};bool {$bad.RuntimeProcess=$true}
                array {$bad.RuntimeProcess=@($referenceSelf)};object {$bad.RuntimeProcess=[pscustomobject]@{Id=$referenceSelf.Id;SafeHandle=$referenceSelf.SafeHandle}}
                serialized {$bad.RuntimeProcess=[Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($referenceSelf,1))}
                same-reference {$bad.BrokerProcess=$referenceSelf}
                same-pid {$disposable=[Diagnostics.Process]::GetCurrentProcess();$bad.BrokerProcess=$disposable}
                closed {$disposable=[Diagnostics.Process]::GetCurrentProcess();$disposable.Close();$bad.RuntimeProcess=$disposable}
                unstarted {$disposable=[Diagnostics.Process]::new();$bad.RuntimeProcess=$disposable}
            }
            try{Reject {Open-YimeCoreNativeMaintenanceProcesses @bad}}finally{if($null -ne $disposable){$disposable.Dispose()}}
            Require ((& $module {$script:enumCalls}) -eq 0) 'Malformed reference invoked discovery'
            if($badKind -notin @('same-pid','closed','unstarted')){Require ((& $module {$script:referenceCalls}) -eq 0) 'Wrong reference shape reached native pin'}
            $objects=& $module {$script:objects.ToArray()};Require (@($objects|Where-Object {-not $_.closed}).Count -eq 0) 'Shape refusal leaked leases'
        }
    }
    foreach($mode in @('second_reference_open_failed','pin_open_failed','token_open_failed','terminated','terminated_late','wrong_image','wow64','wrong_arch','token_race','wrong_parent','child_older','pid_reused','string_time','foreign_sid','elevated','elevation_string','packaged','package_unknown','package_string','hash_mismatch','indirect_image','file_identity_changed','source_changed')){
        Check ('reference-refused-and-all-partial-leases-released-'+$mode){
            Set-Mode $mode;Reject {Get-YimeCoreNativeMaintenanceProcesses @referenceParameters}
            Require ((& $module {$script:enumCalls}) -eq 0) 'Failure fell back to discovery'
            $objects=& $module {$script:objects.ToArray()};Require (@($objects|Where-Object {-not $_.closed}).Count -eq 0) 'Reference failure leaked source/process/file leases'
        }
    }
    Check 'reference-lease-serialized-observation-and-caller-edits-rejected' {
        Set-Mode enumerator_throw;$lease=Open-YimeCoreNativeMaintenanceProcesses @referenceParameters
        try {
            $clone=$lease|ConvertTo-Json -Depth 12|ConvertFrom-Json;Reject {Assert-YimeCoreNativeMaintenanceProcessesCurrent $clone};Reject {Close-YimeCoreNativeMaintenanceProcesses $clone}
            $lease.evidence.discovery_scope='global_exact_pair';$lease.evidence.processes[0].pid=1
            $actual=Assert-YimeCoreNativeMaintenanceProcessesCurrent $lease
            Require ($actual.discovery_scope -ceq 'explicit_process_references' -and $actual.processes[0].pid -eq $referenceSelf.Id) 'Caller evidence replaced retained association'
        }finally{Close-YimeCoreNativeMaintenanceProcesses $lease}
    }
    Check 'live-reference-registry-survives-health-import-and-removal' {
        Set-Mode enumerator_throw;$lease=Open-YimeCoreNativeMaintenanceProcesses @referenceParameters;$health=$null
        try {
            $health=Import-Module (Join-Path $PSScriptRoot 'native-maintenance-health.psm1') -Force -PassThru
            $linked=& $health {param($owner)[object]::ReferenceEquals($script:HealthProcessModule,$owner)} $module
            Require $linked 'Health imported a replacement process module'
            $actual=& $health {param($lease)Read-HealthProcesses $lease} $lease
            Require ($actual.discovery_scope -ceq 'explicit_process_references' -and $actual.processes[0].pid -eq $referenceSelf.Id) 'Health could not use original live reference lease'
            Remove-Module $health;$health=$null
            $actual=Assert-YimeCoreNativeMaintenanceProcessesCurrent $lease
            Require ($actual.processes[1].pid -eq $referenceChild.Id) 'Health removal invalidated original observation registry'
        }finally{if($null -ne $health){Remove-Module $health};Close-YimeCoreNativeMaintenanceProcesses $lease}
    }
    Check 'reference-fixture-exits-zero-after-explicit-event-release' {
        [void]$referenceRelease.handle.Set()
        Require ($referenceChild.WaitForExit(5000) -and $referenceChild.ExitCode -eq 0) 'Owned reference fixture did not acknowledge explicit release'
    }
}finally{
    try{Stop-OwnedFixture $referenceChild $referenceRelease}finally{if($null -ne $referenceChild){$referenceChild.Dispose()};$referenceRelease.handle.Dispose();$referenceSelf.Dispose();& $module {$script:runtimeId=101;$script:brokerId=102}}
}
Check 'bundle-cleanup-continues-after-first-file-dispose-error' {
    Set-Mode valid
    & $module {
        $items=@(foreach($index in 1..2){[pscustomobject]@{
            file=(New-FakeDisposable ([pscustomobject]@{closed=$false}));token=(New-FakeDisposable ([pscustomobject]@{closed=$false}));pin=(New-FakeDisposable ([pscustomobject]@{closed=$false}))
        }})
        $items[0].file | Add-Member ScriptMethod Dispose {$this.closed=$true;throw 'Synthetic first file dispose failure'} -Force
        $sources=Open-MaintenanceProcessSources;$bundle=[pscustomobject]@{items=$items;source_leases=$sources}
        $rejected=$false;try{Close-MaintenanceProcessBundle $bundle}catch{$rejected=$true}
        if(-not $rejected -or @($script:objects|Where-Object {-not $_.closed}).Count){throw 'Cleanup error lost or later leases leaked'}
    }
}
Check 'module-removal-cleans-all-observations-despite-earlier-dispose-error' {
    Set-Mode valid;$first=Open-YimeCoreNativeMaintenanceProcesses @parameters;$second=Open-YimeCoreNativeMaintenanceProcesses @parameters
    & $module {param($id)
        $script:ProcessObservations[$id].items[0].file | Add-Member ScriptMethod Dispose {$this.closed=$true;throw 'Synthetic removal dispose failure'} -Force
        $reported=$false;try{& $ExecutionContext.SessionState.Module.OnRemove}catch{$reported=$true}
        if(-not $reported -or $script:ProcessObservations.Count -ne 0 -or @($script:objects|Where-Object {-not $_.closed}).Count){throw 'OnRemove lost cleanup error or leaked a later observation'}
    } $first.id
    Reject {Assert-YimeCoreNativeMaintenanceProcessesCurrent $second}
}
$failed=@($checks | Where-Object {-not $_.passed})
$pins=@();foreach($path in @($modulePath,(Join-Path $PSScriptRoot 'native-maintenance-process-facts.cs'),$PSCommandPath,(Join-Path $PSScriptRoot '../dual-product/rime-pime-dp1u-native-facts.cs'),(Join-Path $PSScriptRoot 'native-maintenance-health.psm1'))){$pins += [ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}}
$result=[ordered]@{schema_version='yimecore-native-maintenance-process-tests-v1';passed=($failed.Count -eq 0);powershell=$PSVersionTable.PSVersion.ToString();checks_count=$checks.Count;failed_count=$failed.Count;checks=$checks.ToArray();native_own_process_fixture_executed=[bool]$RunNativeFixture;native_reference_association_fixture=$privateTypeEvidence;synthetic_reference_parameters_use_owned_cmd_process=$false;synthetic_reference_parameters_use_owned_event_waiter=$true;owned_fixture_stdin_explicitly_closed=$true;owned_fixture_release_protocol='Fresh named manual-reset event; createdNew required; 5s readiness and release bounds; helper expires with failure after 90s without release';owned_fixture_sources=@(foreach($path in @($waitSource,$waitHelper)){[ordered]@{path=$path;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}});native_observation=$nativeEvidence;source_pins=$pins;product_processes_enumerated=$false;installed_product_read_or_executed=$false;product_registry_read_or_written=$false;user_state_read=$false;product_start_stop_or_session_quota_changed=$false;note='Default tests use self/owned event-waiter handles and private identity fixtures. All owned helpers receive stdin EOF and remain live until an explicit named-event release. RunNativeFixture additionally uses compiled owned Runtime/Broker stubs and an internal enumerator of only their PIDs. No global product discovery or installed process is used; neither path proves startup/readiness or in-memory executable integrity.'}
[IO.File]::WriteAllText($out,(($result | ConvertTo-Json -Depth 18).Replace("`r`n","`n")+"`n"),[Text.UTF8Encoding]::new($false))
Write-Output "Native maintenance processes: $($checks.Count) checks, $($failed.Count) failed; $out"
if($failed.Count){$failed | ForEach-Object {[pscustomobject]$_} | Format-Table name,error -AutoSize;exit 1}
}finally{Remove-Module $module}
