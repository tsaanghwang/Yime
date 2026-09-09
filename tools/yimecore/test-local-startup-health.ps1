[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$out=[IO.Path]::GetFullPath($OutputPath)
if(-not $out.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)) {throw 'Fresh repository .tmp output required.'}
for($cursor=[IO.Path]::GetDirectoryName($out);$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)) {
    if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect fixture output.'}
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($out))
$fixture=Join-Path $repo ('.tmp\local-startup-health-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$runtimeSource=Join-Path $PSScriptRoot 'local-product-runtime.ps1'
$manageSource=Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1'
$testPath=$PSCommandPath
$testPin=(Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sourcePins=@(foreach($p in @($runtimeSource,$manageSource)) {[ordered]@{path=$p;bytes=(Get-Item -LiteralPath $p).Length;sha256=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}})
function Read-Ast([string]$Path) {
    $tokens=$null;$errors=$null;$value=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "Production source parse failed: $Path"};return $value
}
function Get-FunctionText($Ast,[string]$Name) {
    $rows=@($Ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $Name},$true))
    if($rows.Count -ne 1){throw "Expected one source function: $Name"};return $rows[0].Extent.Text
}
function Write-Text([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){try{& $Body|Out-Null;$checks.Add([ordered]@{name=$Name;passed=$true});Write-Host "PASS: $Name"}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message});Write-Host "FAIL: $Name - $($_.Exception.Message)"}}
function Reject([scriptblock]$Body){$caught=$false;try{& $Body|Out-Null}catch{$caught=$true};Require $caught 'Expected fail-closed rejection.'}
$runtimeAst=Read-Ast $runtimeSource;$manageAst=Read-Ast $manageSource
$helperNames=@('Get-LocalProductStartupHealthRequired','Get-LocalProductHealthImageHash','Assert-LocalProductStartedHealth')
foreach($name in $helperNames){. ([scriptblock]::Create((Get-FunctionText $runtimeAst $name)))}

# Only the launcher type reference is substituted. The actual production Start
# bodies, success gates, catch/Kill and finally/Dispose remain executable code.
$launcherNamespace='Yime.StartupFixture_'+[guid]::NewGuid().ToString('N')
$launcherCode=@'
using System;
using System.Diagnostics;
namespace __NS__ {
 public sealed class OwnedProcess : Process {
  public bool DisposeObserved;
  protected override void Dispose(bool disposing){if(disposing)DisposeObserved=true;base.Dispose(disposing);}
 }
 public static class Launcher {
  public static Process Next;
  public static string ExpectedPath;
  public static int Starts;
  public static Process Start(string path,string args,string root,string sid) {
   if(Next==null || Next.HasExited || path!=ExpectedPath)throw new InvalidOperationException("Only this fixture's owned process may be returned");
   Starts++; return Next;
  }
  public static object InspectProcess(int pid){return pid;}
  public static bool IsExpectedStandardToken(object token,string sid,int session){return true;}
 }
}
'@
$launcherTypes=Add-Type -TypeDefinition $launcherCode.Replace('__NS__',$launcherNamespace) -PassThru
$script:Launcher=@($launcherTypes|Where-Object {$_.FullName -ceq ($launcherNamespace+'.Launcher')})[0]
$script:OwnedType=@($launcherTypes|Where-Object {$_.FullName -ceq ($launcherNamespace+'.OwnedProcess')})[0]
foreach($pair in @(@($runtimeAst,'Start-LocalProductRuntime'),@($manageAst,'Start-TrialRuntime'))) {
    $text=Get-FunctionText $pair[0] $pair[1]
    Require ($text.Contains('[YimeCore.LocalMaintenance.StandardUserLauncher]')) 'Launcher seam changed.'
    . ([scriptblock]::Create($text.Replace('[YimeCore.LocalMaintenance.StandardUserLauncher]',('['+$launcherNamespace+'.Launcher]'))))
}

$statements=@($manageAst.EndBlock.Statements)
$packageStatements=@($statements|Where-Object {$_.Extent.Text -ceq '$package = Assert-Package $PackageRoot'})
$guardStatements=@($statements|Where-Object {$_.Extent.Text.Contains('A package requiring startup health cannot be installed with NoLaunch.')})
if($packageStatements.Count -ne 1 -or $guardStatements.Count -ne 1){throw 'Actual install policy admission block not found uniquely.'}
$installGuard=[scriptblock]::Create($packageStatements[0].Extent.Text+"`n"+$guardStatements[0].Extent.Text+"`n"+'$script:PreinstallReached=$true')
$startText=Get-FunctionText $manageAst 'Start-TrialRuntime'
Check 'actual install policy rejection precedes staging and preinstall' {
    $stage=@($manageAst.FindAll({param($n)$n -is [Management.Automation.Language.PipelineAst] -and $n.Extent.Text.StartsWith('New-Item -ItemType Directory -Path $stagingRoot')},$true))
    $preinstall=@($manageAst.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Extent.Text.Contains('$preinstall = Invoke-UninstallCore -ForReinstall')},$true))
    Require ($stage.Count -eq 1 -and $preinstall.Count -eq 1) 'Unique stage/preinstall source sites required.'
    Require ($packageStatements[0].Extent.EndOffset -lt $guardStatements[0].Extent.StartOffset -and $guardStatements[0].Extent.EndOffset -lt $stage[0].Extent.StartOffset -and $guardStatements[0].Extent.EndOffset -lt $preinstall[0].Extent.StartOffset) 'NoLaunch admission is after mutation.'
}
Check 'production success gates retain original process until health and old roots until startup' {
    foreach($text in @($startText,(Get-FunctionText $runtimeAst 'Start-LocalProductRuntime'))) {
        Require ($text.IndexOf('Assert-LocalProductStartedHealth') -lt $text.LastIndexOf('$process.Dispose()')) 'Health occurs after original Process disposal.'
    }
    $body=$manageAst.Extent.Text
    Require ($body.IndexOf('$runtimeStatus = if ($NoLaunch)') -lt $body.IndexOf('foreach ($oldRoot in $previousRoots)')) 'Old roots removed before startup acceptance.'
}

function New-Package([string]$Kind) {
    $root=Join-Path $fixture ([guid]::NewGuid().ToString('N'))
    $maintenance=Join-Path $root 'maintenance';[void][IO.Directory]::CreateDirectory($maintenance)
    $descriptor=[pscustomobject]@{display_name='owned fixture'}
    if($Kind -ne 'legacy'){$descriptor|Add-Member maintenance_health ([pscustomobject]@{protocol='yimecore-maintenance-health-v1';required_on_start=$true})}
    [pscustomobject]@{root=$root;descriptor=$descriptor;manifest=[pscustomobject]@{files=@([pscustomobject]@{path='bin/YimeCoreTrialRuntime.exe';sha256='a'*64},[pscustomobject]@{path='bin/YimeBroker.exe';sha256='b'*64})}}
}
$legacy=New-Package 'legacy';$modern=New-Package 'modern'
Check 'legacy absence preserves optional protocol and modern policy requires it' {
    Require (-not (Get-LocalProductStartupHealthRequired $legacy)) 'Legacy package was opted in.'
    Require (Get-LocalProductStartupHealthRequired $modern) 'Explicit policy not required.'
    Require ($null -eq (Assert-LocalProductStartedHealth $legacy $null $null -1 'fixture')) 'Legacy package attempted a probe.'
}
foreach($mode in @('null','true-string','true-bool','unknown','required-string','required-false','protocol-array','extra','missing','case','outer-case')) {
    Check ('policy rejects '+$mode) {
        $p=New-Package 'modern'
        switch($mode){
            'null' {$p.descriptor.maintenance_health=$null}
            'true-string' {$p.descriptor.maintenance_health='true'}
            'true-bool' {$p.descriptor.maintenance_health=$true}
            'unknown' {$p.descriptor.maintenance_health.protocol='unknown'}
            'required-string' {$p.descriptor.maintenance_health.required_on_start='true'}
            'required-false' {$p.descriptor.maintenance_health.required_on_start=$false}
            'protocol-array' {$p.descriptor.maintenance_health.protocol=@('yimecore-maintenance-health-v1')}
            'extra' {$p.descriptor.maintenance_health|Add-Member extra $true}
            'missing' {$p.descriptor.maintenance_health.PSObject.Properties.Remove('required_on_start')}
            'case' {$p.descriptor.maintenance_health.PSObject.Properties.Remove('protocol');$p.descriptor.maintenance_health|Add-Member Protocol 'yimecore-maintenance-health-v1'}
            'outer-case' {$policy=$p.descriptor.maintenance_health;$p.descriptor.PSObject.Properties.Remove('maintenance_health');$p.descriptor|Add-Member Maintenance_Health $policy}
        }
        Reject {Get-LocalProductStartupHealthRequired $p}
    }
}
foreach($mode in @('missing','duplicate','wrong-case','array','bad-hash')) {
    Check ('manifest image hash rejects '+$mode) {
        $p=New-Package 'modern'
        switch($mode){
            'missing' {$p.manifest.files=@($p.manifest.files[1])}
            'duplicate' {$p.manifest.files+=,$p.manifest.files[0]}
            'wrong-case' {$p.manifest.files[0].path='bin/yimecoretrialruntime.exe'}
            'array' {$p.manifest.files[0].sha256=@('a'*64)}
            'bad-hash' {$p.manifest.files[0].sha256='x'*64}
        }
        Reject {Get-LocalProductHealthImageHash $p 'bin/YimeCoreTrialRuntime.exe'}
    }
}

# These package-local modules are providers for wiring tests. They do not claim
# native parent/hash/token verification or run the actual named-pipe protocol.
$processFixture=@'
Set-StrictMode -Version 2.0
$script:Leases=@{};$script:Opens=0;$script:Closes=0;$script:Generation=[guid]::NewGuid().ToString('N')
$script:ExpectedRuntime=$null;$script:ExpectedBrokerId=0;$script:LastRuntime=$null;$script:LastBroker=$null;$script:LastBrokerHandle=$null
function Open-YimeCoreNativeMaintenanceProcesses {
 param($TargetUserSid,$ExpectedInstallRoot,$ExpectedRuntimeSha256,$ExpectedBrokerSha256,$RuntimeProcess,$BrokerProcess)
 if(-not[object]::ReferenceEquals($RuntimeProcess,$script:ExpectedRuntime) -or $RuntimeProcess.HasExited -or $BrokerProcess.HasExited -or
    $BrokerProcess.Id -ne $script:ExpectedBrokerId -or $ExpectedRuntimeSha256 -cne ('a'*64) -or $ExpectedBrokerSha256 -cne ('b'*64) -or [string]::IsNullOrWhiteSpace($TargetUserSid)) {throw 'Fixture native reference boundary rejected'}
 $script:Opens++;$script:LastRuntime=$RuntimeProcess;$script:LastBroker=$BrokerProcess;$script:LastBrokerHandle=$BrokerProcess.SafeHandle
 $value=[pscustomobject]@{id=[guid]::NewGuid().ToString('N')};$script:Leases[$value.id]=$value;return $value
}
function Assert-FixtureObservation($Observation) {
 if(-not $script:Leases.ContainsKey($Observation.id) -or -not[object]::ReferenceEquals($script:Leases[$Observation.id],$Observation)){throw 'Fixture observation invalidated'}
 if($script:LastRuntime.HasExited){throw 'Owned runtime exited during health'}
}
function Close-YimeCoreNativeMaintenanceProcesses {param($Observation)
 if(-not $script:Leases.ContainsKey($Observation.id) -or -not[object]::ReferenceEquals($script:Leases[$Observation.id],$Observation)){throw 'Unknown fixture lease'}
 $script:Leases.Remove($Observation.id);$script:Closes++
}
Export-ModuleMember -Function Open-YimeCoreNativeMaintenanceProcesses,Assert-FixtureObservation,Close-YimeCoreNativeMaintenanceProcesses
'@
$healthFixture=@'
Set-StrictMode -Version 2.0
$script:PM=Import-Module (Join-Path $PSScriptRoot 'native-maintenance-processes.psm1') -Scope Local -PassThru
$script:Calls=0
function Get-YimeCoreNativeMaintenanceHealth {param($ProcessObservation,$BrokerPipeName)
 $script:Calls++
 & $script:PM {param($v)Assert-FixtureObservation $v} $ProcessObservation
 $control=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixture-control.json') -Raw|ConvertFrom-Json
 if($BrokerPipeName -cne '\\.\pipe\Yime.Startup.OwnedFixture'){throw 'Wrong fixture pipe'}
 switch($control.mode) {
  'timeout' {throw 'Fixture protocol timeout; no real pipe opened'}
  'failure' {throw 'Fixture health failure'}
  'child-exit' {
   $e=[Threading.EventWaitHandle]::OpenExisting($control.event);try{$null=$e.Set()}finally{$e.Dispose()}
   & $script:PM {param($v)if(-not $script:LastRuntime.WaitForExit(5000)){throw 'Owned runtime did not exit'};Assert-FixtureObservation $v} $ProcessObservation
  }
 }
 $r=[pscustomobject]@{schema_version='yimecore-native-maintenance-health-v1';health_service_responsive=$true;nonce_verified=$true;pipe_server_identity_bound=$true;retained_process_observation_rechecked=$true;runtime_ready=$false;E7_accepted=$false;L6_sealed=$false}
 if($control.mode -ceq 'nonce'){$r.nonce_verified=$false}
 if($control.mode -ceq 'nonce-string'){$r.nonce_verified='true'}
 return $r
}
Export-ModuleMember -Function Get-YimeCoreNativeMaintenanceHealth
'@
foreach($p in @($legacy,$modern)) {
    Write-Text (Join-Path $p.root 'maintenance\native-maintenance-processes.psm1') $processFixture
    Write-Text (Join-Path $p.root 'maintenance\native-maintenance-health.psm1') $healthFixture
    Write-Text (Join-Path $p.root 'maintenance\local-product-runtime.ps1') (Get-Content -LiteralPath $runtimeSource -Raw)
    Write-Text (Join-Path $p.root 'maintenance\local-package-contract.ps1') 'function Assert-LocalProductPackage($Root){$script:AuditedRoots.Add($Root);if(-not $script:PackageCatalog.ContainsKey($Root)){throw ''Unknown fixture package''};return $script:PackageCatalog[$Root]}'
    # Give the untouched source blocks their real PowerShell file context. A
    # ScriptBlock.Create body has an empty automatic PSScriptRoot, unlike the
    # production script; only its package-local dependencies are fixtures.
    Write-Text (Join-Path $p.root 'maintenance\fixture-install-guard.ps1') $installGuard.ToString()
    $definitions=foreach($pair in @(@($runtimeAst,'Start-LocalProductRuntime'),@($manageAst,'Start-TrialRuntime'))){
        (Get-FunctionText $pair[0] $pair[1]).Replace('[YimeCore.LocalMaintenance.StandardUserLauncher]',('['+$launcherNamespace+'.Launcher]'))
    }
    Write-Text (Join-Path $p.root 'maintenance\fixture-start-functions.ps1') ($definitions -join "`r`n")
}
$script:PackageCatalog=@{};$script:PackageCatalog[$legacy.root]=$legacy;$script:PackageCatalog[$modern.root]=$modern
$script:AuditedRoots=[Collections.Generic.List[string]]::new()
$script:rehearsalOutcome=$null
function Assert-Package($Root){return $script:PackageCatalog[$Root]}
function Assert-LocalProductInstalledContext($Root,$State){Require ($Root -ceq $script:CurrentContext.package.root -and $State -ceq $script:CurrentContext.state_root) 'Unexpected fixture context';return $script:CurrentContext}
function Assert-YimeCoreUnpackagedDataMaintenance {}
function Initialize-LocalProductLauncher($Context) {}
function Initialize-StandardUserLauncher {}
function Assert-LocalProductLiveRuntime($Context){return [ordered]@{passed=$true;fixture_only=$true}}
function Get-PreviousRuntimeWasRunning($Json){return $true}
function Quote-Argument([string]$Value){return '"'+$Value+'"'}

foreach($case in @(@($legacy,$true,$false),@($modern,$false,$false),@($modern,$true,$true))) {
    $p=$case[0];$noLaunch=$case[1];$expectReject=$case[2]
    Check ('actual NoLaunch guard '+$(if($p -eq $legacy){'legacy'}else{'modern'})+' '+$noLaunch) {
        $NativeLocalProduct=$true;$NoLaunch=$noLaunch;$PackageRoot=$p.root;$PSScriptRoot=Join-Path $p.root 'maintenance';$script:PreinstallReached=$false
        $errorText=$null;try{. (Join-Path $p.root 'maintenance\fixture-install-guard.ps1')}catch{$errorText=$_.Exception.Message}
        Require (($null -ne $errorText) -eq $expectReject) ('Install policy result differs: '+$errorText)
        Require ($script:PreinstallReached -eq (-not $expectReject)) 'Rejected policy reached preinstall marker.'
        if($expectReject){Require ($errorText -ceq 'A package requiring startup health cannot be installed with NoLaunch.') 'A different error masked policy admission.'}
    }
}
foreach($mode in @('null','unknown','required-string')) {
    Check ('actual install guard rejects malformed '+$mode+' before preinstall') {
        $oldPolicy=$modern.descriptor.maintenance_health
        try {
            switch($mode){
                'null' {$modern.descriptor.maintenance_health=$null}
                'unknown' {$modern.descriptor.maintenance_health=[pscustomobject]@{protocol='unknown';required_on_start=$true}}
                'required-string' {$modern.descriptor.maintenance_health=[pscustomobject]@{protocol='yimecore-maintenance-health-v1';required_on_start='true'}}
            }
            $NativeLocalProduct=$true;$NoLaunch=$false;$PackageRoot=$modern.root;$script:PreinstallReached=$false
            $errorText=$null;try{. (Join-Path $modern.root 'maintenance\fixture-install-guard.ps1')}catch{$errorText=$_.Exception.Message}
            Require ($errorText -ceq 'Unsupported or malformed required startup health declaration.') ('Wrong malformed admission failure: '+$errorText)
            Require (-not $script:PreinstallReached) 'Malformed package reached preinstall marker.'
        }finally{$modern.descriptor.maintenance_health=$oldPolicy}
    }
}

$childScript=Join-Path $fixture 'owned-wait.ps1'
Write-Text $childScript @'
param([string]$EventName,[string]$ReadyPath)
$ErrorActionPreference='Stop'
$e=[Threading.EventWaitHandle]::OpenExisting($EventName)
try{[IO.File]::WriteAllText($ReadyPath,'ready');if(-not $e.WaitOne(90000)){exit 91}}finally{$e.Dispose()}
'@
$shell=(Get-Process -Id $PID).Path
$owned=[Collections.Generic.List[object]]::new()
function New-OwnedProcess {
    $name='Local\YimeStartupOwn_'+[guid]::NewGuid().ToString('N');$created=$false
    $event=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$name,[ref]$created)
    if(-not $created){$event.Dispose();throw 'Own event unexpectedly existed.'}
    $ready=Join-Path $fixture ([guid]::NewGuid().ToString('N')+'.ready')
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$shell
    $info.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$childScript+'" -EventName "'+$name+'" -ReadyPath "'+$ready+'"'
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $process=[Activator]::CreateInstance($script:OwnedType);$process.StartInfo=$info;$watch=$null;$item=$null
    try {
        if(-not $process.Start()){throw 'Owned helper failed to start.'};$null=$process.Handle
        $watch=[Diagnostics.Process]::GetProcessById($process.Id);$null=$watch.Handle
        if($watch.StartTime.ToUniversalTime().Ticks -ne $process.StartTime.ToUniversalTime().Ticks){throw 'Owned observer identity differs.'}
        $item=[pscustomobject]@{process=$process;watch=$watch;event=$event;event_name=$name;pid=$process.Id;closed=$false};$owned.Add($item)
        $deadline=[DateTime]::UtcNow.AddSeconds(5)
        while(-not(Test-Path -LiteralPath $ready)) {if($watch.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'Owned helper readiness failed.'};Start-Sleep -Milliseconds 25}
        return $item
    }catch {if($null -ne $item){$item.closed=$true};if($null -ne $watch){if(-not $watch.HasExited){$watch.Kill()};$watch.Dispose()};$process.Dispose();$event.Dispose();throw}
}
function Close-OwnedProcess($Item) {
    if($null -eq $Item -or $Item.closed){return};$Item.closed=$true
    try {
        $null=$Item.event.Set()
        if(-not $Item.watch.WaitForExit(5000)){$Item.watch.Kill();$null=$Item.watch.WaitForExit(5000)}
    }finally{$Item.process.Dispose();$Item.watch.Dispose();$Item.event.Dispose()}
}
function Invoke-StartupCase([string]$Kind,[string]$Mode,[bool]$UseLegacy=$false) {
    $p=if($UseLegacy){$legacy}else{$modern};$runtime=$null;$broker=$null;$pm=$null;$hm=$null;$other=$null
    try {
        $runtime=New-OwnedProcess;$broker=New-OwnedProcess
        $state=Join-Path $fixture ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($state)
        $config=[pscustomobject]@{install_root=$p.root;runtime_path=(Join-Path $p.root 'bin\YimeCoreTrialRuntime.exe');broker_path=(Join-Path $p.root 'bin\YimeBroker.exe');state_root=$state;pipe_name='\\.\pipe\Yime.Startup.OwnedFixture'}
        $context=[ordered]@{package=$p;config=$config;state_root=$state};$script:CurrentContext=$context
        Write-Text (Join-Path $state 'runtime-status.json') (([ordered]@{state='running';runtime_pid=$runtime.pid;broker_pid=$broker.pid})|ConvertTo-Json)
        Write-Text (Join-Path $p.root 'maintenance\fixture-control.json') (([ordered]@{mode=$Mode;event=$runtime.event_name})|ConvertTo-Json)
        $pm=Import-Module (Join-Path $p.root 'maintenance\native-maintenance-processes.psm1') -PassThru
        & $pm {param($r,$b)$script:ExpectedRuntime=$r;$script:ExpectedBrokerId=$b} $runtime.process $broker.pid
        # Retain an unrelated observation in the same module instance. The new
        # helper may close only its own lease and must not reload/unload this one.
        $other=& $pm {param($r,$b,$root)
            Open-YimeCoreNativeMaintenanceProcesses 'fixture-sid' $root ('a'*64) ('b'*64) $r $b
        } $runtime.process $broker.process $p.root
        $before=& $pm {$script:Generation}
        $script:Launcher::Next=$runtime.process;$script:Launcher::ExpectedPath=$config.runtime_path;$script:Launcher::Starts=0
        $NativeLocalProduct=$true;$TargetUserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $stateRootPath=$state;$PSScriptRoot=Join-Path $p.root 'maintenance'
        . (Join-Path $p.root 'maintenance\fixture-start-functions.ps1')
        # A modern outer package must not contaminate startup of the old root.
        $package=$modern;$script:AuditedRoots.Clear()
        $failed=$false;$rolledBack=$false;$value=$null;$errorText=$null
        try {
            if($Kind -ceq 'local'){$value=Start-LocalProductRuntime $context}
            elseif($Kind -ceq 'trial'){$value=Start-TrialRuntime $config}
            else {throw 'Unknown Start fixture kind'}
        }catch{$failed=$true;$rolledBack=$true;$errorText=$_.Exception.Message}
        $expectedFailure=$Mode -ne 'success'
        Require ($failed -eq $expectedFailure) ("Startup outcome differs: $Kind/$Mode/$UseLegacy $errorText")
        Require ($script:Launcher::Starts -eq 1) 'Original Start body did not invoke owned launcher exactly once.'
        if($failed){Require ($rolledBack -and $runtime.watch.WaitForExit(5000)) 'Failed health returned success or left this runtime running.'}
        else {
            Require (-not $runtime.watch.HasExited) 'Successful Start killed its runtime.'
            $health=if($UseLegacy){$null}else{$value.startup_health}
            if(-not $UseLegacy){Require ($health.nonce_verified -and -not $health.runtime_ready -and -not $health.E7_accepted -and -not $health.L6_sealed) 'Transport evidence was lost or promoted.'}
        }
        Require ($runtime.process.DisposeObserved) 'Original Start finally did not dispose its Process reference.'
        $current=Get-Module|Where-Object {$_.Path -ceq (Join-Path $p.root 'maintenance\native-maintenance-processes.psm1')}
        Require ($null -ne $current) 'Startup unloaded another observation module.'
        $facts=& $pm {param($o)[pscustomobject]@{generation=$script:Generation;leases=$script:Leases.Count;original=[object]::ReferenceEquals($script:Leases[$o.id],$o);opens=$script:Opens;closes=$script:Closes;last_broker_handle=$script:LastBrokerHandle}} $other
        Require ($facts.generation -ceq $before -and $facts.leases -eq 1 -and $facts.original) 'Another live observation was invalidated.'
        Require ($facts.opens -eq $(if($UseLegacy){1}else{2}) -and $facts.closes -eq $(if($UseLegacy){0}else{1})) 'Health lease was leaked or unexpectedly opened for legacy.'
        if(-not $UseLegacy){Require ($facts.last_broker_handle.IsClosed) 'Health helper left its own Broker handle open.'}
        if($Kind -ceq 'trial'){Require ($script:AuditedRoots.Count -eq 1 -and $script:AuditedRoots[0] -ceq $p.root) 'Rollback startup inherited the new package instead of auditing its own root.'}
    }finally{
        try {
            if($null -ne $other -and $null -ne $pm){& $pm {param($o)Close-YimeCoreNativeMaintenanceProcesses $o} $other}
        } finally {
            try {
                if($null -ne $p){$hm=Get-Module|Where-Object {$_.Path -ceq (Join-Path $p.root 'maintenance\native-maintenance-health.psm1')};if($null -ne $hm){Remove-Module $hm}}
                if($null -ne $pm){Remove-Module $pm}
            }finally{try{Close-OwnedProcess $runtime}finally{Close-OwnedProcess $broker}}
        }
    }
}
try {
    $pidFixture=$null
    try {
        $pidFixture=New-OwnedProcess
        $pidConfig=[pscustomobject]@{install_root=$modern.root;runtime_path=(Join-Path $modern.root 'bin\YimeCoreTrialRuntime.exe');broker_path=(Join-Path $modern.root 'bin\YimeBroker.exe')}
        foreach($mode in @('string','array','float','int64-overflow','zero','negative','null')) {
            Check ('startup helper rejects invalid broker PID '+$mode) {
                $invalidPid=switch($mode){'string' {'123'};'array' {,@(123)};'float' {[double]123};'int64-overflow' {[long][int]::MaxValue+1};'zero' {0};'negative' {-1};'null' {$null}}
                if($mode -ceq 'array'){Require ($invalidPid -is [array]) 'PID array fixture was flattened.'}
                $admissionError=$null
                try{Assert-LocalProductStartedHealth $modern $pidConfig $pidFixture.process $invalidPid 'fixture-sid'|Out-Null}catch{$admissionError=$_.Exception.Message}
                Require ($admissionError -ceq 'Startup health requires this launch and its exact package paths.') ('PID did not reject at admission: '+$admissionError)
                Require (-not $pidFixture.watch.HasExited) 'PID admission affected the owned runtime.'
            }
        }
    }finally{Close-OwnedProcess $pidFixture}
    foreach($kind in @('local','trial')) {
        Check ("actual $kind Start preserves legacy without health") {Invoke-StartupCase $kind 'success' $true}
        foreach($mode in @('success','failure','timeout','nonce','nonce-string','child-exit')) {
            Check ("actual $kind Start and original cleanup $mode") {Invoke-StartupCase $kind $mode}
        }
    }
}finally{foreach($item in $owned){Close-OwnedProcess $item};$script:Launcher::Next=$null}
Check 'all owned children and retained observers are closed' {Require (@($owned|Where-Object {-not $_.closed}).Count -eq 0) 'Owned child cleanup incomplete.'}
foreach($pin in $sourcePins){if((Get-FileHash -LiteralPath $pin.path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pin.sha256){throw 'Production source changed during startup tests.'}}
if((Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $testPin){throw 'Startup test source changed during execution.'}
$failed=@($checks|Where-Object {-not $_.passed})
$result=[ordered]@{schema_version='yimecore-local-startup-health-tests-v1';passed=($failed.Count -eq 0);checks_passed=$checks.Count-$failed.Count;checks_total=$checks.Count;failed_count=$failed.Count;checks=@($checks.ToArray());powershell_version=$PSVersionTable.PSVersion.ToString();sources=$sourcePins;test_source_sha256=$testPin;fixture_root=$fixture;owned_child_count=$owned.Count;
    actual_start_function_bodies_executed=$true;actual_install_policy_block_executed=$true;launcher_type_substituted_with_owned_process_provider=$true;health_and_process_providers_are_package_local_fixtures=$true;actual_named_pipe_health_protocol_executed=$false;actual_native_parent_or_token_acceptance=$false;actual_full_install_or_rollback_executed=$false;actual_product_or_user_state_accessed=$false;installer_executed=$false;installed_yimecore_local12_touched=$false;L6_sealed=$false;local_product_ready=$false;public_release_ready=$false}
Write-Text $out ($result|ConvertTo-Json -Depth 12)
if($failed.Count){throw "$($failed.Count) startup health regressions failed. Evidence: $out"}
Write-Host "PASS: $($checks.Count) startup health regressions. Evidence: $out"
$global:LASTEXITCODE=0
