[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
$controller=Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($controller,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$checks=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Body,[string]$Name){$caught=$false;try{& $Body|Out-Null}catch{$caught=$true};Check $caught $Name}
function Import-Function([string]$Name){
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $Name},$true)
    if(-not $fn){throw "Missing controller function $Name"}
    $body=$fn.Extent.Text.Replace("function $Name", "function script:$Name")
    # The real polling code runs against our child and synthetic status provider.
    # Only its deadline is shortened; no production entry or fake native type runs.
    if($Name -ceq 'Start-TrialRuntime'){$body=$body.Replace('AddSeconds(15)','AddSeconds(2)')}
    . ([scriptblock]::Create($body))
}
foreach($name in @('Assert-NativeDesktopRehearsalOptions','Initialize-RehearsalOutcomeFileType','Initialize-RehearsalOutcome',
    'Set-RehearsalPhase','Set-RehearsalRuntimeExit','Complete-RehearsalOutcome','Quote-Argument','Start-TrialRuntime')){Import-Function $name}
$root=Join-Path ([IO.Path]::GetTempPath()) ('yimecore-outcome-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$script:privateProcesses=New-Object 'Collections.Generic.List[object]'
$script:rehearsalOutcome=$null;$script:rehearsalOutcomeStream=$null
$script:rehearsalOutcomeExitCode=1
if(-not ('YimeOutcomeFixture.FaultStream' -as [type])){
Add-Type @'
using System;
using System.IO;
namespace YimeOutcomeFixture {
 public class FaultStream : FileStream {
  public string Failure;
  public FaultStream(string path,string failure) : base(path,FileMode.Open,FileAccess.ReadWrite,FileShare.Read) {Failure=failure;}
  public override void Write(byte[] buffer,int offset,int count) {
   if(Failure=="write-failed")throw new IOException("fixture Write failure");
   base.Write(buffer,offset,count);
  }
  public override void Flush(bool durable) {
   base.Flush(durable);
   if(durable && Failure.StartsWith("flush"))throw new IOException("fixture Flush failure");
  }
  public override void SetLength(long value) {
   if(Failure=="flush-and-invalidate-failed")throw new IOException("fixture invalidation failure");
   base.SetLength(value);
  }
 }
}
'@
}
$script:sourceHash=(Get-FileHash -LiteralPath $controller -Algorithm SHA256).Hash.ToLowerInvariant()
$TargetUserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$NativeDesktop=$true;$NativeDesktopRehearsal=$true;$NativeX64Only=$false;$NativeX64Rehearsal=$false
$PurgeUserData=$false;$NoLaunch=$false;$NoAutoStart=$false;$Action='Install';$Quiet=$true;$NativeLocalProduct=$false
function Get-RehearsalOutcomeEnvironment {
    [ordered]@{parent=$root;sid=$TargetUserSid;pid=$PID;created=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToFileTimeUtc();controller_sha256=$script:sourceHash}
}
function New-CaseOutcome {
    $script:RehearsalAttemptId=[guid]::NewGuid().ToString('N')
    $script:RehearsalOutcomePath=Join-Path $root ('native-desktop-rehearsal-'+$script:RehearsalAttemptId+'.json')
    Initialize-RehearsalOutcome
    $script:rehearsalOutcome.failure_manifest_sha256='a'*64;$script:rehearsalOutcome.source_manifest_sha256='b'*64
}
function Read-CaseOutcome {
    Get-Content -LiteralPath $RehearsalOutcomePath -Raw -Encoding UTF8|ConvertFrom-Json
}
function Start-Process {
    param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru)
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    if($script:childExit -ge 0){$info.FileName=Join-Path $env:SystemRoot 'System32\cmd.exe';$info.Arguments='/d /c exit '+$script:childExit}
    else{$info.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';$info.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 20"'}
    $process=New-Object Diagnostics.Process;$process.StartInfo=$info
    if(-not $process.Start()){throw 'Own fixture process did not launch'}
    # Hold a distinct handle before the controller disposes its Process wrapper.
    $watch=[Diagnostics.Process]::GetProcessById($process.Id);$null=$watch.Handle
    $script:privateProcesses.Add($watch);$script:childPid=$process.Id
    return $process
}
function Test-Path {
    param([string]$LiteralPath,$PathType)
    if($LiteralPath.EndsWith('\runtime-status.json')){return $script:showReady}
    if($PSBoundParameters.ContainsKey('PathType')){Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType}
    else{Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}
}
function Get-Content {
    param([string]$LiteralPath,[switch]$Raw,$Encoding)
    if($LiteralPath.EndsWith('\runtime-status.json')){return (@{state='running';runtime_pid=$script:childPid}|ConvertTo-Json -Compress)}
    Microsoft.PowerShell.Management\Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8
}
function Stop-PrivateProcesses {
    foreach($p in $script:privateProcesses){try{if(-not $p.HasExited){$p.Kill();$p.WaitForExit(5000)|Out-Null}}finally{$p.Dispose()}}
    $script:privateProcesses.Clear()
}
function Invoke-UninstallCore {param([switch]$ForReinstall,[string[]]$PreserveInstallRoots);$script:cleanupCalls++;@{}}
function Remove-ProductTree {param([string]$Path)
    if(-not ([IO.Path]::GetFullPath($Path)).StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup escaped root'}
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $Path -Recurse -Force
    # Delayed deletion is deliberately not asserted away by the outcome producer.
    @{deferred_delete_until_reboot=$true}
}
function Restore-PreviousInstallation {$script:restoreCalls++;if($script:restoreFailure){throw 'Synthetic rollback failure'}}
function Restore-FrozenUserTipSnapshot {if($script:finalizerFailure){throw 'Synthetic finalizer failure'}}
$transaction=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.TryStatementAst] -and $_.Body.Extent.Text.Contains('Start-TrialRuntime $runtimeConfig')})
Check ($transaction.Count -eq 1) 'select real controller transaction'
$tail=@();$started=$false
foreach($statement in $transaction[0].Body.Statements){
    if($statement -is [Management.Automation.Language.AssignmentStatementAst] -and $statement.Left.Extent.Text -ceq '$runtimeStatus'){$started=$true}
    if($started){$tail+=,$statement}
}
$body=($tail|ForEach-Object{$_.Extent.Text}) -join "`n"
$catch=($transaction[0].CatchClauses|ForEach-Object{$_.Extent.Text}) -join "`n"
$commit=[scriptblock]::Create("try {`n$body`n}`n$catch`nfinally "+$transaction[0].Finally.Extent.Text)
try {
    $RehearsalAttemptId='';$RehearsalOutcomePath=''
    Assert-NativeDesktopRehearsalOptions;Initialize-RehearsalOutcome
    Check ($null -eq $script:rehearsalOutcomeStream) 'legacy default emits no outcome'
    foreach($case in @('missing-id','wrong-id','missing-path','ordinary','plan','uninstall')){
        $RehearsalAttemptId='1'*32;$RehearsalOutcomePath=Join-Path $root ('native-desktop-rehearsal-'+$RehearsalAttemptId+'.json')
        $NativeDesktopRehearsal=$true;$Action='Install'
        switch($case){'missing-id'{$RehearsalAttemptId=''}'wrong-id'{$RehearsalAttemptId='not-a-run'}'missing-path'{$RehearsalOutcomePath=''}'ordinary'{$NativeDesktopRehearsal=$false}'plan'{$Action='Plan'}'uninstall'{$Action='Uninstall'}}
        Reject {Assert-NativeDesktopRehearsalOptions} "reject outcome option $case"
    }
    $NativeDesktopRehearsal=$true;$Action='Install'
    New-CaseOutcome
    Reject {Initialize-RehearsalOutcome} 'existing output cannot be overwritten'
    Reject {$stream=[IO.File]::Open($RehearsalOutcomePath,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$stream.Dispose()} 'outcome handle blocks foreign writers'
    Complete-RehearsalOutcome;$record=Read-CaseOutcome
    Check ($record.outcome -ceq 'preflight_or_staging_rejected' -and -not $record.rollback_attempted) 'preflight result does not claim rollback'
    Complete-RehearsalOutcome
    Check ($null -eq $script:rehearsalOutcomeStream) 'outcome completion is idempotent and releases handle'
    $script:rehearsalOutcome=$null
    $RehearsalOutcomePath=Join-Path $root 'wrong-name.json'
    Reject {Initialize-RehearsalOutcome} 'reject unbound outcome file name'
    $RehearsalOutcomePath=Join-Path (Split-Path -Parent $root) ('native-desktop-rehearsal-'+$RehearsalAttemptId+'.json')
    Reject {Initialize-RehearsalOutcome} 'reject nonarchive output parent'
    foreach($case in @('exit86','exit87','unexpected-success','timeout-kill','rollback-failed','finalizer-failed','partial-registration','write-failed','flush-failed','flush-and-invalidate-failed')){
        New-CaseOutcome
        $caseRoot=Join-Path $root $case;$targetRoot=Join-Path $caseRoot 'failed';$stagingRoot=Join-Path $caseRoot 'staging'
        $previousRoot=Join-Path $caseRoot 'old';$previousRoots=@($previousRoot);$stateRootPath=Join-Path $caseRoot 'state'
        foreach($dir in @($targetRoot,$previousRoot,$stateRootPath)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
        $runtimeConfig=@{install_root=$targetRoot;runtime_path=(Join-Path $targetRoot 'synthetic-fault.exe');broker_path=(Join-Path $targetRoot 'synthetic-broker.exe');state_root=$stateRootPath}
        $preinstallStarted=$true;$registrationStarted=$true;$previousRuntimeWasRunning=$true
        $previousConfigText='synthetic';$previousRunSnapshot=@{};$previousUninstallSnapshot=@{};$previousLegacyUninstallSnapshot=@{};$previousUserTipSnapshot=@{};$migrationLegacyUserTipSnapshot=@{}
        $script:rehearsalOutcome.registered_architectures=if($case -ceq 'partial-registration'){@('x64')}else{@('x64','x86')}
        Set-RehearsalPhase 'registered'
        $script:childExit=if($case -in @('unexpected-success','timeout-kill')){-1}elseif($case -ceq 'exit87'){87}else{86}
        $script:showReady=($case -ceq 'unexpected-success');$script:restoreFailure=($case -ceq 'rollback-failed');$script:finalizerFailure=($case -ceq 'finalizer-failed')
        $script:cleanupCalls=0;$script:restoreCalls=0
        if($case -in @('write-failed','flush-failed','flush-and-invalidate-failed')){
            $script:rehearsalOutcomeStream.Dispose()
            $script:rehearsalOutcomeStream=[YimeOutcomeFixture.FaultStream]::new($RehearsalOutcomePath,$case)
        }
        Reject {. $commit} "$case still propagates installation failure"
        if($case -in @('write-failed','flush-failed','flush-and-invalidate-failed')){
            Check ($script:restoreCalls -eq 1 -and $script:cleanupCalls -eq 1 -and (Test-Path -LiteralPath $previousRoot)) "$case cannot skip rollback before output"
            Check ($script:rehearsalOutcomeExitCode -eq 26 -and $null -eq $script:rehearsalOutcomeStream) "$case forces failure exit 26 and closes handle"
            Complete-RehearsalOutcome
            Check ($script:rehearsalOutcomeExitCode -eq 26) "$case repeated completion cannot erase output failure"
            if($case -ceq 'flush-and-invalidate-failed'){
                $partial=Read-CaseOutcome
                Check ($partial.outcome_complete -and $partial.required_controller_exit_code -eq 20 -and $script:rehearsalOutcomeExitCode -ne $partial.required_controller_exit_code) 'complete JSON after Flush failure is rejected by actual exit mismatch'
            }
            Stop-PrivateProcesses
            continue
        }
        $record=Read-CaseOutcome
        $expected=switch($case){'exit86'{'expected_fault_rollback_completed'}'exit87'{'unexpected_failure_rollback_completed'}'unexpected-success'{'unexpected_runtime_success_rollback_completed'}'timeout-kill'{'unexpected_failure_rollback_completed'}'rollback-failed'{'rollback_failed'}'finalizer-failed'{'protection_finalizer_failed'}'partial-registration'{'unexpected_failure_rollback_completed'}}
        Check ($record.outcome -ceq $expected) "$case has distinct typed result"
        $expectedExit=switch($case){'exit86'{20}'unexpected-success'{21}'rollback-failed'{22}'finalizer-failed'{23}default{24}}
        Check ($record.required_controller_exit_code -eq $expectedExit -and $script:rehearsalOutcomeExitCode -eq $expectedExit) "$case requires matching actual controller exit code"
        Check ($record.rollback_attempted -and $script:restoreCalls -eq 1 -and $script:cleanupCalls -eq 1) "$case reaches actual catch rollback path"
        Check ((Test-Path -LiteralPath $previousRoot) -and $record.outcome_complete) "$case retains old fixture and complete record"
        Check ($record.controller_sha256 -ceq $script:sourceHash -and $record.attempt_id -ceq $RehearsalAttemptId -and $record.target_user_sid -ceq $TargetUserSid) "$case binds producer source attempt and SID"
        Check (-not $record.independent_registry_restore_verified -and -not $record.data_restore_verified -and -not $record.deferred_delete_absence_verified -and -not $record.L6_sealed -and -not $record.execution_authorized) "$case cannot promote independent recovery or readiness"
        if($case -eq 'exit86'){Check ($record.fault_runtime.natural_exit_observed -and $record.fault_runtime.exit_code -eq 86 -and $record.fault_runtime.creation_filetime -gt 0) 'actual own cmd exit 86 is observed from retained Process'}
        if($case -eq 'timeout-kill'){Check (-not $record.fault_runtime.natural_exit_observed -and $null -eq $record.fault_runtime.exit_code -and $record.fault_runtime.controller_termination_requested) 'controller Kill never masquerades as natural fault exit'}
        if($case -eq 'finalizer-failed'){Check (-not $record.frozen_tip_finalizer_completed) 'finalizer exception cannot follow a published rollback success'}
        Check (($record.events.sequence -join ',') -ceq ((1..@($record.events).Count) -join ',')) "$case ordered events have no gaps"
        Stop-PrivateProcesses
    }
    # A failed output write occurs only after the catch has restored the old
    # installation. The retained handle is still closed on write failure.
    New-CaseOutcome;$script:rehearsalOutcomeStream.Dispose()
    Reject {Complete-RehearsalOutcome} 'failed final write does not produce successful evidence'
    Check ($null -eq $script:rehearsalOutcomeStream -and $script:rehearsalOutcomeExitCode -eq 26) 'failed final write releases stream and preserves failure exit'
    $elevate=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Restart-Elevated'},$true)
    $forward=@($elevate.Body.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text.StartsWith('if ($RehearsalOutcomePath)')})
    Check ($forward.Count -eq 1) 'UAC has explicit outcome argument forwarding'
    $arguments=@();. ([scriptblock]::Create($forward[0].Extent.Text))
    Check (($arguments -join '|') -ceq ('-RehearsalAttemptId|"'+$RehearsalAttemptId+'"|-RehearsalOutcomePath|"'+$RehearsalOutcomePath+'"')) 'UAC preserves attempt and outcome destination'
    # Run the real top-level trap in separate ordinary PowerShell processes.
    # Action=Plan makes its historical AppData error writer refuse before I/O.
    $trap=@($ast.EndBlock.Traps)
    Check ($trap.Count -eq 1) 'select real controller terminal trap'
    $shell=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    foreach($exit in @(1,20,21,22,23,24,25,26)){
        $childScript=Join-Path $root ('trap-'+$exit+'.ps1')
        $text='$ErrorActionPreference="Stop"; $Action="Plan"; $script:rehearsalOutcomeExitCode='+$exit+"`n"+
            'function Complete-RehearsalOutcome {}'+"`n"+$trap[0].Extent.Text+"`n"+'throw "Own fixture controller trap"'
        [IO.File]::WriteAllText($childScript,$text,[Text.UTF8Encoding]::new($false))
        $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$shell
        $info.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$childScript+'"'
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $child=[Diagnostics.Process]::new();$child.StartInfo=$info
        try {
            if(-not $child.Start()){throw 'Own trap fixture did not start'}
            $stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync()
            if(-not $child.WaitForExit(10000)){$child.Kill();$child.WaitForExit();throw 'Own trap fixture timed out'}
            Check ($child.ExitCode -eq $exit) ("real trap preserves OS child exit code "+$exit)
            $null=$stdout.GetAwaiter().GetResult();$null=$stderr.GetAwaiter().GetResult()
        } finally {$child.Dispose()}
    }
    $result=[ordered]@{schema_version='yimecore-native-rehearsal-outcome-tests-v1';passed=$true;checks_passed=$checks.Count;checks=$checks.ToArray();
        powershell_version=$PSVersionTable.PSVersion.ToString();controller_source_sha256=$script:sourceHash;
        real_own_child_exit86_observed=$true;real_controller_trap_exit_codes=@(1,20,21,22,23,24,25,26);controller_ast_executed=$true;full_controller_invoked=$false;
        registration_and_rollback_synthetic=$true;installer_executed=$false;product_executed=$false;user_state_read=$false;installed_local12_changed=$false;L6_sealed=$false}
    if($OutputPath){$result|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $OutputPath -Encoding UTF8}
    Write-Host ('PASS: native rehearsal outcome '+$checks.Count+' checks; own child processes and temporary fixtures only.')
} finally {
    if($script:rehearsalOutcomeStream){$script:rehearsalOutcomeStream.Dispose();$script:rehearsalOutcomeStream=$null}
    $script:rehearsalOutcome=$null
    $script:rehearsalOutcomeExitCode=1
    Stop-PrivateProcesses
    $full=[IO.Path]::GetFullPath($root);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $full) -notlike 'yimecore-outcome-fixture-*'){throw 'Unsafe fixture cleanup root'}
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $full -Recurse -Force
}
