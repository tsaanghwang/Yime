[CmdletBinding()]param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$out=[IO.Path]::GetFullPath($OutputPath)
if(-not $out.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Fresh repository .tmp output required'}
$cursor=Split-Path -Parent $out
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect test output'};$cursor=Split-Path -Parent $cursor}
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $out))
# A private memory-only canary proves health import does not Force-replace the
# existing module's retained registry. It owns no native handles or product data.
$processModule=Import-Module (Join-Path $PSScriptRoot 'native-maintenance-processes.psm1') -Scope Local -PassThru
$canaryId=[guid]::NewGuid().ToString('N');$canary=[pscustomobject]@{id=$canaryId}
& $processModule {param($id,$value)$script:ProcessObservations[$id]=[pscustomobject]@{items=@();public=$value}} $canaryId $canary
$module=$null
$checks=[Collections.Generic.List[object]]::new();$native=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){try{& $Body|Out-Null;$checks.Add([ordered]@{name=$Name;passed=$true})}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body){$failed=$false;try{& $Body|Out-Null}catch{$failed=$true};Require $failed 'Expected refusal'}
try{
    $module=Import-Module (Join-Path $PSScriptRoot 'native-maintenance-health.psm1') -Force -PassThru
    Check 'health-import-preserves-existing-retained-process-registry' {
        $kept=& $module {param($id,$value)& $script:HealthProcessModule {param($id,$value)$script:ProcessObservations.ContainsKey($id) -and [object]::ReferenceEquals($script:ProcessObservations[$id].public,$value)} $id $value} $canaryId $canary
        Require $kept 'Health import replaced an existing retained registry'
    }
    $pipe='\\.\pipe\YimeHealthFixture.'+[guid]::NewGuid().ToString('N')
    $observation=[pscustomobject]@{id=[guid]::NewGuid().ToString('N');evidence=@{runtime_ready=$true}}
    Check 'original-process-provider-rejects-unowned-observation-before-any-pipe' {
        Reject {Get-YimeCoreNativeMaintenanceHealth -ProcessObservation $observation -BrokerPipeName $pipe}
    }
    & $module {param($original)
        $script:HealthTestObservation=$original;$script:HealthTestMode='normal';$script:HealthTestReads=0;$script:HealthTestPipeCalls=0
        $script:OriginalHealthRead=${function:Read-HealthProcesses};$script:OriginalHealthPipe=${function:Invoke-HealthPipePair}
        function script:Read-HealthProcesses($Value){
            $script:HealthTestReads++
            if(-not [object]::ReferenceEquals($Value,$script:HealthTestObservation) -or $script:HealthTestMode -ceq 'closed'){throw 'Original retained reference required'}
            $rows=@([pscustomobject]@{role='runtime';pid=[int]101;parent_pid=[int]99;creation_filetime=[long]1000;image='C:\Synthetic\runtime.exe';sid='S-1-5-21-1-2-3-4';image_sha256=('a'*64);image_bytes=[long]10;file_identity='rt'},
                [pscustomobject]@{role='broker';pid=[int]102;parent_pid=[int]101;creation_filetime=[long]1100;image='C:\Synthetic\broker.exe';sid='S-1-5-21-1-2-3-4';image_sha256=('b'*64);image_bytes=[long]11;file_identity='br'})
            $result=[pscustomobject]@{schema_version='yimecore-native-maintenance-processes-v1';processes=$rows;native_handle_identity_observed=$true;native_parent_relation_observed=$true;public_image_hash_verified=$true}
            switch($script:HealthTestMode){
                missing {$result.processes=@($rows[0])};duplicates {$rows[1].role='runtime'};pid-string {$rows[0].pid='101'};creation-string {$rows[0].creation_filetime='1000'}
                pid-overlap {$rows[1].pid=101};wrong-parent {$rows[1].parent_pid=99};older-broker {$rows[1].creation_filetime=[long]500}
                unbound {$result.native_handle_identity_observed=$false};coerced {$result.public_image_hash_verified='true'}
                changed-after {if($script:HealthTestReads -gt 1){$rows[1].creation_filetime=[long]1200}}
                ended-after {if($script:HealthTestReads -gt 1){throw 'Observed process exited'}}
            }
            return $result
        }
        function script:Invoke-HealthPipePair($Pipe,$Runtime,$Broker){
            $script:HealthTestPipeCalls++
            if($script:HealthTestMode -ceq 'pipe-error'){throw 'Synthetic health timeout'}
            $rows=@(foreach($value in @($Broker,$Runtime)){
                $suffix=if($value.role -ceq 'broker'){'.health-v1'}else{'.runtime-health-v1'}
                [pscustomobject]@{Role=$value.role;PipeName=$Pipe+$suffix;ProcessId=$value.pid;CreationFileTime=$value.creation_filetime;HealthServiceResponsive=$true;NonceVerified=$true;PipeServerIdentityBound=$true}
            })
            switch($script:HealthTestMode){
                reply-partial {return $rows[0]};reply-duplicate {$rows[1].Role='broker'};reply-wrong-pipe {$rows[0].PipeName+='extra'}
                reply-wrong-pid {$rows[0].ProcessId=999};reply-stale {$rows[0].CreationFileTime=[long]999};reply-nonce-false {$rows[0].NonceVerified=$false}
                reply-coerced {$rows[0].PipeServerIdentityBound='true'}
            };return $rows
        }
    } $observation
    function Mode([string]$Name){& $module {param($m)$script:HealthTestMode=$m;$script:HealthTestReads=0;$script:HealthTestPipeCalls=0} $Name}
    function Observe {Get-YimeCoreNativeMaintenanceHealth -ProcessObservation $observation -BrokerPipeName $pipe}
    Check 'fresh-client-type-is-private-and-retained-reference-rechecked' {
        Mode normal;$receipt=Observe
        Require ($receipt.records.Count -eq 2 -and $receipt.health_service_responsive -and $receipt.nonce_verified -and $receipt.pipe_server_identity_bound) 'Incomplete narrow health receipt'
        Require ((& $module {$script:HealthTestReads}) -eq 2) 'Retained observation not checked before and after'
        Require ((& $module {$script:HealthClientType.Namespace}) -cmatch '^Yime\.Health_[a-f0-9]{32}$') 'Client type can be replaced by a global name'
        Require ($receipt.protocol_deadline_ms -eq 1000 -and $receipt.pair_shares_protocol_deadline) 'Pair does not share one protocol budget'
    }
    foreach($flag in @('runtime_ready','runtime_ready_verified','startup_path_verified','E7_accepted','L6_sealed','full_acceptance','execution_authorized','in_memory_code_identity_verified','local_product_ready','public_release_ready','user_state_read','cancellation_cleanup_hard_realtime')){
        Check ('honest-false-'+$flag){Mode normal;$receipt=Observe;Require ($receipt.$flag -is [bool] -and -not $receipt.$flag) 'Unsupported readiness or real-time claim'}
    }
    Check 'caller-editable-evidence-does-not-supply-process-identities' {Mode normal;$observation.evidence=@{processes=@{pid=999};runtime_ready=$true};$receipt=Observe;Require ($receipt.records[0].pid -eq 102) 'Caller evidence was used'}
    Check 'serialized-and-closed-observations-rejected' {
        Mode normal;$clone=$observation|ConvertTo-Json -Depth 10|ConvertFrom-Json
        Reject {Get-YimeCoreNativeMaintenanceHealth -ProcessObservation $clone -BrokerPipeName $pipe}
        Mode closed;Reject {Observe}
    }
    foreach($mode in @('missing','duplicates','pid-string','creation-string','pid-overlap','wrong-parent','older-broker','unbound','coerced','changed-after','ended-after',
        'pipe-error','reply-partial','reply-duplicate','reply-wrong-pipe','reply-wrong-pid','reply-stale','reply-nonce-false','reply-coerced')){
        Check ('reject-'+$mode){Mode $mode;Reject {Observe}}
    }
    Check 'failed-probe-still-rechecks-retained-process-observation' {Mode pipe-error;Reject {Observe};Require ((& $module {$script:HealthTestReads}) -eq 2) 'Failure skipped final process recheck'}
    foreach($bad in @($null,@($pipe),'YimeBroker','\\remote\pipe\name','\\.\PIPE\name','\\.\pipe\a\b','\\.\pipe\a/b','\\.\pipe\.hidden','\\.\pipe\a space',('\\.\pipe\a'+"`n"),('\\.\pipe\'+('a'*111)))){
        Check ('reject-noncanonical-pipe-'+$checks.Count){Reject {Get-YimeCoreNativeMaintenanceHealth -ProcessObservation $observation -BrokerPipeName $bad}}
    }
    Check 'public-api-has-no-nonce-pid-provider-or-timeout-override' {
        Require (@($module.ExportedFunctions.Keys).Count -eq 1) 'Unexpected health exports'
        $command=Get-Command Get-YimeCoreNativeMaintenanceHealth
        foreach($name in @('Nonce','RuntimePid','BrokerPid','Provider','Timeout','ClientType')){Require (-not $command.Parameters.ContainsKey($name)) 'Public trust override'}
    }

    # Real C# client against this same test process's new random named pipes.
    # No process creation, product endpoint, config, status or user state access.
    $fixtureNamespace='Yime.HealthFixture_'+[guid]::NewGuid().ToString('N')
    $fixtureSource=@'
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
namespace Yime.HealthFixture {
 public sealed class Servers : IDisposable {
  readonly NamedPipeServerStream broker, runtime;
  readonly Task brokerTask, runtimeTask;
  public readonly string Base;
  public readonly int Pid;
  public readonly long Creation;
  public byte[] BrokerNonce, RuntimeNonce;
  public int BrokerRequests, RuntimeRequests;
  public Exception Error;
  static void Put32(byte[] b,int p,uint n){for(int i=0;i<4;i++)b[p+i]=(byte)(n>>(8*i));}
  static void Put64(byte[] b,int p,ulong n){for(int i=0;i<8;i++)b[p+i]=(byte)(n>>(8*i));}
  static uint U32(byte[] b,int p){return (uint)b[p]|((uint)b[p+1]<<8)|((uint)b[p+2]<<16)|((uint)b[p+3]<<24);}
  public Servers(string mode) {
   string leaf="YimeOwnedHealth."+Guid.NewGuid().ToString("N");Base=@"\\.\pipe\"+leaf;
   using(Process self=Process.GetCurrentProcess()){Pid=self.Id;Creation=self.StartTime.ToUniversalTime().ToFileTimeUtc();}
   broker=new NamedPipeServerStream(leaf+".health-v1",PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous);
   runtime=new NamedPipeServerStream(leaf+".runtime-health-v1",PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous);
   brokerTask=Task.Factory.StartNew(()=>Serve(broker,1,mode));runtimeTask=Task.Factory.StartNew(()=>Serve(runtime,2,mode));
  }
  void Serve(NamedPipeServerStream pipe,uint role,string mode) {
   try {
    pipe.WaitForConnection();byte[] request=new byte[48];int total=0;
    while(total<48){int n=pipe.Read(request,total,48-total);if(n==0)return;total+=n;}
    if(Encoding.ASCII.GetString(request,0,8)!="YIMEH01\0"||U32(request,8)!=role||U32(request,12)!=0)throw new Exception("Client request contract differs");
    byte[] nonce=new byte[32];Buffer.BlockCopy(request,16,nonce,0,32);bool nonzero=false;foreach(byte value in nonce)nonzero|=value!=0;
    if(!nonzero)throw new Exception("Client nonce is all zero");
    if(role==1){BrokerNonce=nonce;Interlocked.Increment(ref BrokerRequests);}else{RuntimeNonce=nonce;Interlocked.Increment(ref RuntimeRequests);}
    if(mode=="no-response"&&role==1){Thread.Sleep(1300);return;}
    if(mode=="shared-budget"){Thread.Sleep(role==1?650:650);}
    byte[] reply=new byte[80];Buffer.BlockCopy(Encoding.ASCII.GetBytes("YIMER01\0"),0,reply,0,8);Put32(reply,8,role);Put32(reply,12,1);
    Buffer.BlockCopy(request,16,reply,16,32);Put32(reply,48,(uint)Pid);Put32(reply,52,role==1?0:(uint)Pid);Put64(reply,56,(ulong)Creation);Put64(reply,64,role==1?0:(ulong)Creation);
    if(role==1){
     if(mode=="magic")reply[0]^=1;
     if(mode=="role")Put32(reply,8,2);
     if(mode=="starting")Put32(reply,12,2);
     if(mode=="stopping")Put32(reply,12,3);
     if(mode=="unknown-state")Put32(reply,12,4);
     if(mode=="nonce")reply[16]^=1;
     if(mode=="pid")Put32(reply,48,(uint)Pid+1);
     if(mode=="creation")Put64(reply,56,(ulong)Creation+1);
     if(mode=="broker-related-pid")Put32(reply,52,1);
     if(mode=="broker-related-creation")Put64(reply,64,1);
     if(mode=="reserved")Put64(reply,72,1);
    } else {
     if(mode=="runtime-related-pid")Put32(reply,52,(uint)Pid+1);
     if(mode=="runtime-related-creation")Put64(reply,64,(ulong)Creation+1);
    }
    if(mode=="short"&&role==1){pipe.Write(reply,0,79);return;}
    if(mode=="fragmented") {for(int i=0;i<80;i++){pipe.Write(reply,i,1);}}
    else pipe.Write(reply,0,80);
    if(mode=="extra"&&role==1)pipe.WriteByte(42);
    if(mode=="no-eof"&&role==1)Thread.Sleep(1300);
   } catch(ObjectDisposedException) { } catch(IOException) { }
   catch(Exception e) {Error=e;}
   finally {pipe.Dispose();}
  }
  public void Dispose() {
   broker.Dispose();runtime.Dispose();
   if(!Task.WaitAll(new Task[]{brokerTask,runtimeTask},4000))throw new Exception("Owned fixture server did not drain");
   if(Error!=null)throw Error;
  }
 }
}
'@
    $types=@(Add-Type -TypeDefinition ($fixtureSource.Replace('namespace Yime.HealthFixture {',('namespace '+$fixtureNamespace+' {'))) -PassThru)
    $serverType=@($types|Where-Object {$_.FullName -ceq ($fixtureNamespace+'.Servers')})[0]
    $clientType=& $module {$script:HealthClientType}
    $priorNonce=$null
    foreach($mode in @('valid','fragmented','magic','role','starting','stopping','unknown-state','nonce','pid','creation','broker-related-pid','broker-related-creation',
        'runtime-related-pid','runtime-related-creation','reserved','short','extra','no-response','no-eof','shared-budget','wrong-os-pid','stale-os-creation')){
        Check ('native-own-pipe-'+$mode){
            $server=[Activator]::CreateInstance($serverType,@([string]$mode));$watch=[Diagnostics.Stopwatch]::StartNew();$accepted=$false;$message='';$reply=$null
            try{
                $expectedPid=$server.Pid;$expectedCreation=$server.Creation
                if($mode -ceq 'wrong-os-pid'){$expectedPid=[int]::MaxValue}
                if($mode -ceq 'stale-os-creation'){$expectedCreation++}
                try{$reply=$clientType::ProbePair($server.Base,$expectedPid,$expectedCreation,$expectedPid,$expectedCreation);$accepted=$true}catch{$message=$_.Exception.Message}
                $elapsed=$watch.ElapsedMilliseconds
                Require ($accepted -eq ($mode -in @('valid','fragmented'))) ('Unexpected client result: '+$message)
                Require ($clientType::OutstandingIo -eq 0) 'Client returned with pending IO'
                if($accepted){
                    Require ($reply.Count -eq 2 -and $server.BrokerRequests -eq 1 -and $server.RuntimeRequests -eq 1) 'Request count differs'
                    Require ([Convert]::ToBase64String($server.BrokerNonce) -cne [Convert]::ToBase64String($server.RuntimeNonce)) 'Nonce was reused across connections'
                    $currentNonce=[Convert]::ToBase64String($server.BrokerNonce)
                    Require ($currentNonce -cne $priorNonce) 'Nonce was reused across separate calls';$script:priorNonce=$currentNonce
                }
                if($mode -ceq 'wrong-os-pid'){Require ($message.Contains('another process') -and $server.BrokerRequests -eq 0) 'Actual pipe PID mismatch did not stop request transmission'}
                if($mode -ceq 'stale-os-creation'){Require ($message.Contains('creation identity differs') -and $server.BrokerRequests -eq 0) 'Actual process creation mismatch did not stop request transmission'}
                if($mode -in @('no-response','no-eof','shared-budget')){Require ($elapsed -ge 850 -and $elapsed -lt 2500) 'Protocol timeout/drain was not bounded as expected'}
                $native.Add([ordered]@{mode=$mode;accepted=$accepted;elapsed_ms=$elapsed;outstanding_io=$clientType::OutstandingIo;fixture_pid=$server.Pid;error=$message})
            }finally{$server.Dispose()}
        }
    }
    Check 'native-no-listener-times-out-without-background-IO' {
        $watch=[Diagnostics.Stopwatch]::StartNew()
        Reject {$clientType::ProbePair(('\\.\pipe\YimeAbsentHealth.'+[guid]::NewGuid().ToString('N')),$PID,([Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToFileTimeUtc()),$PID,([Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToFileTimeUtc()))}
        Require ($watch.ElapsedMilliseconds -lt 2500 -and $clientType::OutstandingIo -eq 0) 'Connect timeout retained work'
    }
    Remove-Module $module;$module=$null
    Check 'health-removal-preserves-existing-retained-process-registry' {
        $kept=& $processModule {param($id,$value)$script:ProcessObservations.ContainsKey($id) -and [object]::ReferenceEquals($script:ProcessObservations[$id].public,$value)} $canaryId $canary
        Require $kept 'Health removal closed another owner''s observation registry'
    }
    $failed=@($checks|Where-Object {-not $_.passed})
    $report=[ordered]@{schema_version='yimecore-native-maintenance-health-tests-v1';passed=($failed.Count -eq 0);checks_count=$checks.Count;failed_count=$failed.Count;
        powershell=$PSVersionTable.PSVersion.ToString();checks=$checks.ToArray();native_owned_pipe_cases=$native.ToArray();
        production_processes_queried=$false;product_pipe_connected=$false;product_executed=$false;user_state_read=$false;runtime_ready=$false;L6_sealed=$false;full_acceptance=$false;
        source_pins=@(foreach($path in @((Join-Path $PSScriptRoot 'native-maintenance-health.psm1'),(Join-Path $PSScriptRoot 'native-maintenance-health-client.cs'),$PSCommandPath)){
            [ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}})}
    [IO.File]::WriteAllText($out,($report|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
    Write-Output ('Health: '+$checks.Count+' checks; failed='+$failed.Count+'; '+$out)
    if($failed.Count){$failed|Format-Table name,error -AutoSize;exit 1}
}finally{
    if($null -ne $module){Remove-Module $module}
    & $processModule {param($id)$script:ProcessObservations.Remove($id)} $canaryId
}
