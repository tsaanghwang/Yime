# Exercise the real Setup stop function with inert private child processes.
# Get-Process is restricted to these children; no installed product is queried,
# stopped, registered or launched. The first case obtains a real stale-CIM error.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$tokens=$null;$errors=$null
$setup=Join-Path $PSScriptRoot '../Setup.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($setup,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup does not parse'}
$functions=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Stop-SetupProductProcesses'},$true))
if($functions.Count -ne 1){throw 'Expected one actual stop function'}
. ([scriptblock]::Create($functions[0].Extent.Text))
$script:processes=@();$script:children=@();$script:notFound=$null;$script:mode='';$script:cimCalls=0;$script:ownerCalls=0;$script:gracefulCalls=0
$script:expectedSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$shell=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$root=[IO.Path]::GetDirectoryName($shell)
$product=[pscustomobject]@{id='yimecore-18u';exe='not-this-inert-shell.exe'}
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
public class StopProcessRaceFixture {
 public int Id=424242,pins,kills,waits,pathReads;
 public bool exited,disposed,refreshed,foreignAfterPin,exitOnKill=true,waitTimeout,waitError;
 public int killError;
 public bool invalidOperation;
 public string ownedPath,foreignPath;
 public string Path {get {pathReads++;return refreshed&&foreignAfterPin?foreignPath:ownedPath;}}
 public IntPtr Handle {get {pins++;return new IntPtr(424242);}}
 public bool HasExited {get {return exited;}}
 public void Refresh(){if(pins!=1)throw new InvalidOperationException("Refresh must follow the retained handle");refreshed=true;}
 public void Kill(){kills++;exited=exitOnKill;if(invalidOperation)throw new InvalidOperationException("Exit race fixture");if(killError!=0)throw new Win32Exception(killError);}
 public bool WaitForExit(int timeout){waits++;if(waitError)throw new Win32Exception(6);return !waitTimeout&&exited;}
 public void Dispose(){disposed=true;}
}
'@
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function New-InertChild {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$shell
    $command='[Console]::WriteLine("READY"); $null=[Console]::ReadLine(); exit 0'
    $info.Arguments='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle='Hidden'
    $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $child=[Diagnostics.Process]::new();$child.StartInfo=$info
    Assert ($child.Start()) 'Inert child did not start'
    $script:children+=,$child
    $ready=$child.StandardOutput.ReadLineAsync()
    Assert ($ready.Wait(10000) -and $ready.Result -ceq 'READY') 'Inert child startup handshake failed'
    return $child
}
function Exit-InertChild($Child){
    $Child.StandardInput.Close()
    Assert ($Child.WaitForExit(10000)) 'Inert child did not exit after EOF'
}
function Get-Process {return $script:processes}
function Get-CimInstance {
    param($ClassName,$Filter)
    $script:cimCalls++
    Assert ($ClassName -ceq 'Win32_Process') 'Unexpected CIM class'
    if($script:mode -eq 'real-notfound'){
        return CimCmdlets\Get-CimInstance -ClassName Win32_Process -Filter $Filter
    }
    if($script:mode -eq 'missing-exited'){Exit-InertChild $script:processes[0];return $null}
    if($script:mode -eq 'missing-live'){return $null}
    if($script:mode -eq 'missing-before-signal'){$script:processes[0].exited=$true;return $null}
    if($script:mode -eq 'pin-all'){
        Assert ($script:processes[0].pins -eq 1 -and $script:processes[1].pins -eq 1) 'All selected handles must be pinned before the first ownership query'
    }
    return [pscustomobject]@{ProcessId=$script:processes[0].Id}
}
function Invoke-CimMethod {
    param($InputObject,$MethodName)
    $script:ownerCalls++
    Assert ($MethodName -ceq 'GetOwnerSid') 'Stop helper must only query CIM ownership'
    switch($script:mode){
        'real-notfound' {
            Exit-InertChild $script:processes[0]
            try{CimCmdlets\Invoke-CimMethod -InputObject $InputObject -MethodName GetOwnerSid -ErrorAction Stop}
            catch [Microsoft.Management.Infrastructure.CimException]{$script:notFound=$_.Exception;throw}
            throw 'Expected stale real Win32_Process owner lookup to fail'
        }
        'notfound-live' {throw $script:notFound}
        'notfound-before-signal' {$script:processes[0].exited=$true;throw $script:notFound}
        'other-cim-exited' {Exit-InertChild $script:processes[0];throw [Microsoft.Management.Infrastructure.CimException]::new('Different CIM failure')}
        'other-error-exited' {Exit-InertChild $script:processes[0];throw [InvalidOperationException]::new('Different failure')}
        'foreign-owner' {return [pscustomobject]@{ReturnValue=0;Sid='other-user'}}
        'owner-error' {return [pscustomobject]@{ReturnValue=2;Sid=$script:expectedSid}}
    }
    return [pscustomobject]@{ReturnValue=0;Sid=$script:expectedSid}
}
function Run-Native {
    param($Path,$Arguments)
    $script:gracefulCalls++
    Assert ($Arguments[0] -ceq '-stop') 'Standard runtime graceful stop arguments changed'
    Exit-InertChild $script:processes[0]
}
function Invoke-Case([string]$Mode,[bool]$Fails,[bool]$ExpectedExit){
    $child=New-InertChild
    $script:processes=@($child);$script:mode=$Mode;$script:cimCalls=0;$script:ownerCalls=0
    # A second private handle observes the original process after Setup disposes
    # its snapshot. No lookup by PID is used to decide whether an error is benign.
    $witness=[Diagnostics.Process]::GetProcessById($child.Id);$null=$witness.Handle
    $caught=$null
    try{
        try{Stop-SetupProductProcesses $product $root 'unused-isolated-state' $script:expectedSid}catch{$caught=$_}
        Assert (($null -ne $caught) -eq $Fails) ('Unexpected stop result: '+$Mode+' '+$caught)
        Assert ($witness.HasExited -eq $ExpectedExit) ('Unexpected original process state: '+$Mode)
        if($Mode -eq 'real-notfound'){
            Assert ($null -ne $script:notFound -and $script:notFound.NativeErrorCode -eq [Microsoft.Management.Infrastructure.NativeErrorCode]::NotFound) 'Actual stale CIM error was not MI NotFound'
            Write-Output ('Actual stale GetOwnerSid: MI='+[int]$script:notFound.NativeErrorCode+'; '+$script:notFound.NativeErrorCode)
        }
    }finally{if(-not $witness.HasExited){$witness.Kill();$null=$witness.WaitForExit(10000)};$witness.Dispose()}
    Write-Output ('PASS '+$Mode)
}
try{
    Invoke-Case 'real-notfound' $false $true
    Invoke-Case 'notfound-live' $true $false
    Invoke-Case 'other-cim-exited' $true $true
    Invoke-Case 'other-error-exited' $true $true
    Invoke-Case 'foreign-owner' $true $false
    Invoke-Case 'owner-error' $true $false
    Invoke-Case 'missing-live' $true $false
    Invoke-Case 'missing-exited' $false $true
    Invoke-Case 'normal-kill' $false $true
    $product=[pscustomobject]@{id='yimecore';exe=[IO.Path]::GetFileName($shell)}
    Invoke-Case 'standard-graceful' $false $true
    Assert ($script:gracefulCalls -eq 1) 'Standard graceful stop branch changed'
    # A deterministic runtime/job model proves handles are all pinned first;
    # the second original object exits with the first and is never queried/killed.
    $script:processes=@()
    foreach($number in @(1,2)){
        $fake=[pscustomobject]@{Id=$number;Path=(Join-Path $root ('inert-'+$number+'.exe'));pins=0;exited=$false;kills=0;waits=0;disposed=$false}
        $fake|Add-Member ScriptProperty Handle {$this.pins++;return [IntPtr]$this.Id}
        $fake|Add-Member ScriptProperty HasExited {return $this.exited}
        $fake|Add-Member ScriptMethod Refresh {if($this.pins -ne 1){throw 'Refresh changed the pin order'}}
        $fake|Add-Member ScriptMethod Kill {$this.kills++;foreach($other in $script:processes){$other.exited=$true}}
        $fake|Add-Member ScriptMethod WaitForExit {param($Timeout);$this.waits++;return $this.exited}
        $fake|Add-Member ScriptMethod Dispose {$this.disposed=$true}
        $script:processes+=,$fake
    }
    $script:mode='pin-all';$script:cimCalls=0;$script:ownerCalls=0
    Stop-SetupProductProcesses $product $root 'unused-isolated-state' $script:expectedSid
    Assert ($script:cimCalls -eq 1 -and $script:ownerCalls -eq 1 -and $script:processes[0].kills -eq 1 -and $script:processes[1].kills -eq 0) 'Exited original child must not be queried or killed using a replacement PID'
    Assert ($script:processes[0].disposed -and $script:processes[1].disposed) 'Pinned snapshot handles were not released'
    Assert ($script:processes[1].waits -eq 1) 'Job-exited original child must still receive a kernel completion wait'
    Write-Output 'PASS pin-all-and-job-child-exit'
    foreach($case in @('path-changed-after-pin','kill-access-denied-live','kill-access-denied-exited','kill-other-error-exited','kill-invalid-live','kill-invalid-exited','wait-timeout','already-exited-before-signal','notfound-before-signal','missing-before-signal','already-exited-signaled','kernel-wait-error')){
        $fake=[StopProcessRaceFixture]::new();$fake.ownedPath=Join-Path $root 'private-inert.exe';$fake.foreignPath=Join-Path ([IO.Path]::GetPathRoot($root)) 'foreign-process.exe'
        $fails=$true
        switch($case){
            'path-changed-after-pin' {$fake.foreignAfterPin=$true;$fails=$false}
            'kill-access-denied-live' {$fake.killError=5;$fake.exitOnKill=$false}
            'kill-access-denied-exited' {$fake.killError=5;$fails=$false}
            'kill-other-error-exited' {$fake.killError=87}
            'kill-invalid-live' {$fake.invalidOperation=$true;$fake.exitOnKill=$false}
            'kill-invalid-exited' {$fake.invalidOperation=$true;$fails=$false}
            'wait-timeout' {$fake.waitTimeout=$true;$fake.exitOnKill=$false}
            'already-exited-before-signal' {$fake.exited=$true;$fake.waitTimeout=$true}
            'notfound-before-signal' {$fake.waitTimeout=$true}
            'missing-before-signal' {$fake.waitTimeout=$true}
            'already-exited-signaled' {$fake.exited=$true;$fails=$false}
            'kernel-wait-error' {$fake.exited=$true;$fake.waitError=$true}
        }
        $script:processes=@($fake);$script:mode=$case;$script:cimCalls=0;$script:ownerCalls=0;$caught=$null
        try{Stop-SetupProductProcesses $product $root 'unused-isolated-state' $script:expectedSid}catch{$caught=$_}
        Assert (($null -ne $caught) -eq $fails) ('Unexpected boundary result: '+$case+' '+$caught)
        Assert ($fake.pins -eq 1 -and $fake.refreshed -and $fake.pathReads -eq 2 -and $fake.disposed) ('Pinned identity/path/disposal changed: '+$case)
        if($case -eq 'path-changed-after-pin'){Assert ($fake.kills -eq 0 -and $script:cimCalls -eq 0) 'Changed foreign path must never be queried or terminated'}
        if($case -in @('already-exited-before-signal','notfound-before-signal','missing-before-signal','already-exited-signaled','kernel-wait-error')){
            Assert ($fake.kills -eq 0 -and $fake.waits -eq 1) ('Exited status must not bypass the held-handle completion wait: '+$case)
        }
        Write-Output ('PASS '+$case)
    }
    Write-Output 'PASS 23 isolated stop cases; no installed product touched'
}finally{
    foreach($child in $script:children){
        try{if(-not $child.HasExited){$child.Kill();$null=$child.WaitForExit(10000)}}catch{}
        $child.Dispose()
    }
}
