[CmdletBinding()]
param(
    [Parameter(Mandatory)]$PackageRoot,
    [Parameter(Mandatory)]$ExpectedManifestSha256,
    [Parameter(Mandatory)]$OutputRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# This is an explicit isolated candidate execution test, not installed-product
# discovery or a NativeDesktop/maintenance acceptance adapter. No default roots.
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$allowedRoot=Join-Path $repoRoot '.tmp'
$candidateCommit='e2d9d4222b09c548f978101668940262b895e4fc'
$sourcePins=@(
    @{relative='tools/dual-product/rime-pime-dp1u-native-facts.cs';sha256='9969b68b42bc11428d4af6a8bb348a9658e248c0758b953bd9e3834109f97be4'},
    @{relative='tools/yimecore/native-maintenance-process-facts.cs';sha256='55e81dc42c9280aed1f054a816534d9961d5e52b99e2a098d89a5be0392b2370'},
    @{relative='tools/yimecore/native-maintenance-health-client.cs';sha256='cb9e7189d70e0c3a033ff6dd591d1c7ce91c637d92d9bf9a93f23b78be4858e3'},
    @{relative='tools/yimecore/native-maintenance-backup.psm1';sha256='847cf067dee46feb71d1384d900341c4445c5ca4eefe0698d8996ebcdc37d04c'},
    @{relative='tools/yimecore/native-maintenance-processes.psm1';sha256='2d15b76b555e68b550865508dd6b489ad26541f99fcc42c9f013e8c1a28c4132'},
    @{relative='tools/yimecore/native-maintenance-health.psm1';sha256='7aa2ae06343b2484bd65c24ef793efa3e4527972c516442478b8a2b990aaf398'}
)
$streams=[Collections.Generic.List[IO.FileStream]]::new()
$sources=[Collections.Generic.List[object]]::new()
$directories=@{}
$packageFiles=[Collections.Generic.List[object]]::new()
$owned=[Collections.Generic.List[object]]::new()
$nativePins=[Collections.Generic.List[object]]::new()
$factsType=$null;$processType=$null;$directoryType=$null;$jsonType=$null;$fixtureType=$null;$readerModule=$null
$processModule=$null;$healthModule=$null;$adapterLease=$null;$adapterLeaseClosed=$false;$adapterImportPreserved=$false
$adapterChecks=[Collections.Generic.List[string]]::new()
$createdOutput=$false;$success=$false;$failure=$null;$cleanupErrors=[Collections.Generic.List[string]]::new()
$rounds=[Collections.Generic.List[object]]::new();$exitRecords=[Collections.Generic.List[object]]::new()
$runtime=$null;$broker=$null;$stopper=$null;$runtimePin=$null;$brokerPin=$null;$manifestFile=$null;$manifest=$null
$stateRoot=$null;$pipe=$null

function Assert-HealthLiteralPath($Path) {
    if($Path -isnot [string] -or $Path -cnotmatch '^[A-Z]:\\[^\\]' -or $Path -match '[/\x00-\x1f"<>|?*%]' -or
        $Path.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($Path) -cne $Path){throw 'Explicit canonical local path required'}
    [void]([Text.UnicodeEncoding]::new($false,$false,$true)).GetBytes($Path)
    foreach($part in $Path.Substring(3).Split('\')){
        if(-not $part -or $part -match '[ .]$|~|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9]|\.git)(?:\.|$)' -or $part -in @('.','..')){throw 'Ambiguous or forbidden path component'}
    }
}
function Assert-HealthInside($Path,[string]$Root) {
    Assert-HealthLiteralPath $Path
    if(-not $Path.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Health fixture path must be a child of this repository .tmp'}
}
function Assert-HealthDisjoint([string]$Left,[string]$Right) {
    if($Left -ieq $Right -or $Left.StartsWith($Right+'\',[StringComparison]::OrdinalIgnoreCase) -or $Right.StartsWith($Left+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Candidate and output roots overlap'}
}
function Assert-HealthPlain([string]$Path) {
    $cursor=$Path
    while($cursor){
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect fixture path rejected'}
        $cursor=Split-Path -Parent $cursor
    }
}
function Get-HealthHash([IO.Stream]$Stream) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$Stream.Position=0;([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$Stream.Position=0}
}
function Read-HealthSource([string]$Path,$Hash=$null) {
    Assert-HealthPlain $Path
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$streams.Add($stream)
    if($stream.Length -lt 1 -or $stream.Length -gt 1048576){throw 'Bounded helper source required'}
    $actual=Get-HealthHash $stream
    if($null -ne $Hash -and $actual -cne $Hash){throw 'Reviewed health fixture helper source changed'}
    $reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true),$true,4096,$true)
    try{$text=$reader.ReadToEnd()}finally{$reader.Dispose();$stream.Position=0}
    $record=[pscustomobject]@{path=$Path;sha256=$actual;bytes=$stream.Length;stream=$stream;identity=$null;text=$text}
    $sources.Add($record);return $record
}
function New-HealthType([string]$Source,[string]$OldNamespace,[string]$TypeName) {
    if(($Source.Split(@($OldNamespace),[StringSplitOptions]::None)).Count -ne 2){throw 'Helper namespace must appear exactly once'}
    $ns='Yime.IsolatedHealth.N'+[guid]::NewGuid().ToString('N')
    $types=@(Add-Type -TypeDefinition ($Source.Replace($OldNamespace,('namespace '+$ns+' {'))) -PassThru)
    $wanted=@($types|Where-Object {$_.FullName -ceq ($ns+'.'+$TypeName)})
    if($wanted.Count -ne 1){throw 'Independent helper type was not compiled'}
    return $wanted[0]
}
function Get-HealthLiteral($Ast,[string]$Variable) {
    $assignments=@($Ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -ceq $Variable},$true))
    if($assignments.Count -ne 1){throw 'Pinned helper literal is ambiguous'}
    $value=$assignments[0].Right.Find({param($node)$node -is [Management.Automation.Language.StringConstantExpressionAst]},$true)
    if($null -eq $value -or $value.StringConstantType -ne 'SingleQuotedHereString'){throw 'Pinned helper must be a literal C# source'}
    return $value.Value
}
function Pin-HealthAncestors([string]$Path) {
    $chain=[Collections.Generic.List[string]]::new();$cursor=$Path
    while($cursor){$chain.Add($cursor);$cursor=Split-Path -Parent $cursor}
    for($i=$chain.Count-1;$i -ge 0;$i--){$entry=$chain[$i];if(-not $directories.ContainsKey($entry)){$directories[$entry]=$directoryType::Open($entry)}}
}
function New-HealthDirectory([string]$Path) {
    Assert-HealthInside $Path $allowedRoot
    Pin-HealthAncestors (Split-Path -Parent $Path)
    $fixtureType::CreateNewDirectory($Path)
    Pin-HealthAncestors $Path
    $directoryType::RejectNamedStreams($Path)
}
function Assert-HealthFilesCurrent {
    foreach($file in @($sources.ToArray())+@($packageFiles.ToArray())){
        Assert-HealthPlain $file.path
        if($factsType::VerifyFileHandle($file.stream,$file.path) -cne $file.identity -or $file.stream.Length -ne $file.bytes -or (Get-HealthHash $file.stream) -cne $file.sha256){throw 'Retained source/candidate bytes changed'}
    }
    if($null -ne $manifest){
        $again=& $readerModule {param($r,$d)Get-BackupTree $r $d} $PackageRoot $directories
        & $readerModule {param($tree,$map)Assert-BackupTreeRecords $tree $map -ExactDirectories} $again $packageRecords
    }
}
function Get-HealthCandidateRecords($Value) {
    $required=@('package_contract','tool_version','product_version','package_id','git_commit','source_manifest_sha256','files')
    & $readerModule {param($v,$keys)Assert-BackupObject $v $keys} $Value $required
    foreach($key in $Value.Keys){if($key -iin @('rehearsal_only','preparation_only','rehearsal_mode','expected_runtime_exit_code','source_package_id')){throw 'Fault or preparation-only package cannot enter the health execution fixture'}}
    foreach($pair in @(@('package_contract','yimecore-local-product-package-v1'),@('tool_version','yimecore-local-builder-v1'),@('product_version','0.1.0-local.13'),@('git_commit',$candidateCommit))){
        & $readerModule {param($v,$expected)Assert-BackupEqual $v $expected} $Value[$pair[0]] $pair[1]
    }
    & $readerModule {param($v)Assert-BackupHash $v} $Value.source_manifest_sha256
    & $readerModule {param($v,$expected)Assert-BackupEqual $v $expected} $Value.package_id ('yimecore-local-0.1.0-local.13-'+$Value.source_manifest_sha256.Substring(0,12))
    $records=& $readerModule {param($v)Get-BackupRecords $v} $Value.files
    if($records.Count -ne 85){throw 'Expected current 85-member local.13 candidate'}
    foreach($path in @('bin/YimeCoreTrialRuntime.exe','bin/YimeBroker.exe','build/source-manifest.json','local-product.json')){if(-not $records.ContainsKey($path) -or $records[$path].path -cne $path){throw 'Required exact candidate member missing'}}
    if($records.ContainsKey('package-manifest.json') -or $records.ContainsKey('install-metadata.json')){throw 'Installed or recursive manifest member rejected'}
    if($records['build/source-manifest.json'].sha256 -cne $Value.source_manifest_sha256){throw 'Candidate source manifest binding differs'}
    return ,$records
}
function New-HealthStartInfo([string]$Executable,[string[]]$Arguments) {
    # All supplied values were validated to exclude quotes/newlines. These
    # arguments have no trailing directory separator; Windows quoting is exact.
    foreach($arg in $Arguments){if($arg -match '["\x00-\x1f]' -or $arg.EndsWith('\')){throw 'Unsafe owned process argument'}}
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Executable
    $info.Arguments=(@($Arguments|ForEach-Object {'"'+$_+'"'}) -join ' ')
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WorkingDirectory=$OutputRoot
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($key in @('APPDATA','LOCALAPPDATA','TEMP','TMP','USERPROFILE')){$info.EnvironmentVariables[$key]=$privateEnvironment[$key]}
    return $info
}
function Start-HealthOwned([string]$Role,[string[]]$Arguments) {
    Assert-HealthFilesCurrent
    $process=[Diagnostics.Process]::new();$process.StartInfo=New-HealthStartInfo $runtimePath $Arguments
    $record=[pscustomobject]@{role=$Role;process=$process;started=$false;creation=[long]0;stdout=$null;stderr=$null;forced=$false;exit_recorded=$false}
    $owned.Add($record)
    if(-not $process.Start()){throw 'Owned candidate process failed to start'};$record.started=$true
    [void]$process.Handle
    $record.creation=$fixtureType::Creation($process.Handle)
    $record.stdout=$process.StandardOutput.ReadToEndAsync();$record.stderr=$process.StandardError.ReadToEndAsync()
    return $record
}
function Assert-HealthOwnedIdentity($Record,$Pin,[string]$Image,[int]$ExpectedParent,$Caller) {
    $actual=$Pin.Capture();$token=$factsType::OpenProcessFacts($Record.process.Id)
    try{
        if($actual.Pid -ne $Record.process.Id -or $actual.ParentPid -ne $ExpectedParent -or $actual.CreationFileTime -ne $Record.creation -or
            $actual.Image -ine $Image -or $actual.ProcessMachine -ne 0 -or $actual.NativeMachine -ne 0x8664 -or
            $token.Pid -ne $actual.Pid -or $token.CreationFileTime -ne $actual.CreationFileTime -or $token.Image -ine $Image -or
            $token.Sid -cne $Caller.Sid -or $token.Elevated){throw 'Owned native process SID/path/parent/creation identity differs'}
        $last=$Pin.Capture();if($last.CreationFileTime -ne $actual.CreationFileTime -or $last.ParentPid -ne $ExpectedParent){throw 'Owned process changed during identity observation'}
        [pscustomobject][ordered]@{role=$Record.role;pid=$actual.Pid;parent_pid=$actual.ParentPid;creation_filetime=$actual.CreationFileTime;
            image=$actual.Image;sid=$token.Sid;elevated=$token.Elevated;package_query=$token.PackageQuery;process_machine=$actual.ProcessMachine;native_machine=$actual.NativeMachine}
    }finally{$token.Dispose()}
}
function Complete-HealthOwned($Record,[int]$TimeoutMs) {
    if(-not $Record.process.WaitForExit($TimeoutMs)){throw 'Owned process did not exit within bounded wait'}
    $receipt=$fixtureType::Exited($Record.process.Handle,$Record.creation)
    if($receipt.Pid -ne $Record.process.Id){throw 'Owned exit PID differs'}
    foreach($task in @($Record.stdout,$Record.stderr)){
        if($null -ne $task){if(-not $task.Wait(5000)){throw 'Owned process output task did not drain'};[void]$task.GetAwaiter().GetResult()}
    }
    if(-not $Record.exit_recorded){
        $exitRecords.Add([pscustomobject][ordered]@{role=$Record.role;pid=$receipt.Pid;creation_filetime=$receipt.Creation;exit_filetime=$receipt.Exit;
            exit_code=$receipt.Code;original_handle_exit_verified=$true;test_harness_forced_termination=$Record.forced;
            runtime_stop_source_uses_broker_termination=($Record.role -ceq 'broker')})
        $Record.exit_recorded=$true
    }
    return $receipt.Code
}
function Assert-HealthRefusal([scriptblock]$Body,[string]$Name) {
    $rejected=$false;try{& $Body|Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw ('Expected adapter refusal: '+$Name)};$adapterChecks.Add($Name)
}
function Get-HealthPendingIo {
    if($null -eq $healthModule){return 0}
    & $healthModule {if($null -eq $script:HealthClientType){return 0};$script:HealthClientType::OutstandingIo}
}
function Read-HealthAdapterLease {
    $evidence=& $processModule {param($o)Assert-YimeCoreNativeMaintenanceProcessesCurrent -Observation $o} $adapterLease
    if($evidence.discovery_scope -cne 'explicit_process_references' -or $evidence.processes.Count -ne 2 -or
        $evidence.processes[0].pid -ne $runtime.process.Id -or $evidence.processes[0].creation_filetime -ne $runtime.creation -or
        $evidence.processes[1].pid -ne $broker.process.Id -or $evidence.processes[1].creation_filetime -ne $broker.creation -or
        $evidence.processes[0].image_sha256 -cne $packageRecords['bin/YimeCoreTrialRuntime.exe'].sha256 -or
        $evidence.processes[1].image_sha256 -cne $packageRecords['bin/YimeBroker.exe'].sha256){throw 'Production process adapter differs from the owned candidate'}
    return $evidence
}

try {
    Assert-HealthInside $PackageRoot $allowedRoot;Assert-HealthInside $OutputRoot $allowedRoot
    Assert-HealthDisjoint $PackageRoot $OutputRoot
    if($ExpectedManifestSha256 -isnot [string] -or $ExpectedManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Literal canonical expected manifest SHA256 required'}
    Assert-HealthPlain $PackageRoot;Assert-HealthPlain (Split-Path -Parent $OutputRoot)
    if(Test-Path -LiteralPath $OutputRoot){throw 'Output root must be new; preserve prior runs'}
    $selfSource=Read-HealthSource $PSCommandPath
    $loaded=@{}
    foreach($pin in $sourcePins){$loaded[$pin.relative]=Read-HealthSource (Join-Path $repoRoot $pin.relative) $pin.sha256}
    $factsType=New-HealthType $loaded[$sourcePins[0].relative].text 'namespace Yime.Dp1UNative {' 'Facts'
    $processType=New-HealthType $loaded[$sourcePins[1].relative].text 'namespace Yime.MaintenanceProcesses {' 'ProcessPin'
    # Reuse only reviewed read-only literals/functions, extracted from a held,
    # hash-pinned source. Never import or invoke the actual backup entry point.
    $parseErrors=$null;$tokens=$null
    $helperAst=[Management.Automation.Language.Parser]::ParseInput($loaded[$sourcePins[3].relative].text,[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw 'Pinned read-only helper parse failed'}
    $directoryType=New-HealthType (Get-HealthLiteral $helperAst 'directorySource') 'namespace Yime.BackupDirectories {' 'Pin'
    $jsonType=New-HealthType (Get-HealthLiteral $helperAst 'parser') 'namespace Yime.BackupParser {' 'Json'
    $functionNames=@('Assert-BackupString','Assert-BackupEqual','Assert-BackupInteger','Assert-BackupHash','Assert-BackupRoot','Assert-BackupRelative','Assert-BackupPlain',
        'Get-BackupStreamHash','Assert-BackupObject','Open-BackupFile','Read-BackupJson','Get-BackupRecords','Get-BackupTree','Assert-BackupTreeRecords')
    $definitions=@(foreach($name in $functionNames){
        $found=@($helperAst.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
        if($found.Count -ne 1){throw 'Pinned read-only helper function is ambiguous'};$found[0].Extent.Text
    }) -join "`n"
    $readerModule=New-Module -Name ('YimeHealthReader'+[guid]::NewGuid().ToString('N')) -ArgumentList @($factsType,$directoryType,$jsonType,$definitions) -ScriptBlock {
        param($native,$directory,$json,$definitions)
        Set-StrictMode -Version Latest
        $script:BackupNativeType=$native;$script:BackupDirectoryType=$directory;$script:BackupJsonType=$json
        . ([scriptblock]::Create($definitions))
        Export-ModuleMember -Function @()
    }
    $nativeFixture=@'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace Yime.HealthFixturePrimitives {
 public sealed class ExitRecord { public int Pid; public long Creation,Exit; public uint Code; }
 public static class Native {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateDirectoryW(string path,IntPtr security);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool WaitNamedPipeW(string path,uint timeout);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr h,out long creation,out long exit,out long kernel,out long user);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint GetProcessId(IntPtr h);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr h,out uint code);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr h,uint ms);
  public static void CreateNewDirectory(string path){if(!CreateDirectoryW(path,IntPtr.Zero))throw new Win32Exception(Marshal.GetLastWin32Error());}
  public static bool PipeAvailable(string path){if(WaitNamedPipeW(path,100))return true;int e=Marshal.GetLastWin32Error();if(e==2||e==121||e==231)return false;throw new Win32Exception(e);}
  public static long Creation(IntPtr h){long c,e,k,u;if(!GetProcessTimes(h,out c,out e,out k,out u))throw new Win32Exception(Marshal.GetLastWin32Error());if(c<=0)throw new InvalidOperationException("No process creation identity");return c;}
  public static ExitRecord Exited(IntPtr h,long expected){
   if(WaitForSingleObject(h,0)!=0)throw new InvalidOperationException("Original process handle is not signaled");
   long c,e,k,u;uint code;if(!GetProcessTimes(h,out c,out e,out k,out u)||!GetExitCodeProcess(h,out code))throw new Win32Exception(Marshal.GetLastWin32Error());
   uint pid=GetProcessId(h);if(pid==0||pid>Int32.MaxValue||c!=expected||e<c)throw new InvalidOperationException("Original exit identity differs");
   return new ExitRecord{Pid=(int)pid,Creation=c,Exit=e,Code=code};
  }
 }
}
'@
    $fixtureType=New-HealthType $nativeFixture 'namespace Yime.HealthFixturePrimitives {' 'Native'
    foreach($source in $sources){Pin-HealthAncestors (Split-Path -Parent $source.path);$source.identity=$factsType::VerifyFileHandle($source.stream,$source.path);$directoryType::RejectNamedStreams($source.path)}
    # Fresh standalone fixture process only. Import exact held module files and
    # retain their module objects; no private provider replacements or Force.
    foreach($name in @('native-maintenance-processes','native-maintenance-health')){
        if(@(Get-Module -Name $name -All).Count){throw 'Fixture requires initially unloaded production adapters'}
    }
    $processModule=Import-Module -Name (Join-Path $PSScriptRoot 'native-maintenance-processes.psm1') -Scope Local -PassThru
    Pin-HealthAncestors $PackageRoot
    $manifestFile=& $readerModule {param($s,$p,$h)Open-BackupFile $s $p $h} $streams (Join-Path $PackageRoot 'package-manifest.json') $ExpectedManifestSha256
    $packageFiles.Add($manifestFile)
    $manifest=& $readerModule {param($f)Read-BackupJson $f} $manifestFile
    $packageRecords=Get-HealthCandidateRecords $manifest
    $packageRecords.Add('package-manifest.json',[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal))
    $packageRecords['package-manifest.json'].Add('path','package-manifest.json')
    $packageRecords['package-manifest.json'].Add('sha256',$manifestFile.sha256)
    $packageRecords['package-manifest.json'].Add('bytes',$manifestFile.bytes)
    $tree=& $readerModule {param($r,$d)Get-BackupTree $r $d} $PackageRoot $directories
    & $readerModule {param($tree,$map)Assert-BackupTreeRecords $tree $map -ExactDirectories} $tree $packageRecords
    foreach($path in $tree.files){
        if($path -ceq 'package-manifest.json'){continue};$record=$packageRecords[$path]
        $file=& $readerModule {param($s,$p,$h,$n)Open-BackupFile $s $p $h $n} $streams (Join-Path $PackageRoot $path.Replace('/','\')) $record.sha256 $record.bytes
        $packageFiles.Add($file)
    }
    $descriptorFile=@($packageFiles|Where-Object {$_.path -ceq (Join-Path $PackageRoot 'local-product.json')})[0]
    $descriptor=& $readerModule {param($f)Read-BackupJson $f} $descriptorFile
    if($descriptor.version -isnot [string] -or $descriptor.version -cne '0.1.0-local.13' -or $descriptor.installable -isnot [bool] -or -not $descriptor.installable -or
        $descriptor.package_contract -isnot [string] -or $descriptor.package_contract -cne 'yimecore-local-product-package-v1'){throw 'Candidate descriptor is not current normal local.13'}
    Assert-HealthFilesCurrent
    $caller=$factsType::OpenProcessFacts($PID);$nativePins.Add($caller)
    if($caller.Elevated -or $caller.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or $factsType::Architecture() -cne 'x64'){throw 'Non-elevated same-SID native x64 fixture host required'}
    New-HealthDirectory $OutputRoot;$createdOutput=$true
    $privateEnvironment=@{}
    foreach($name in @('state','appdata','localappdata','temp','profile')){New-HealthDirectory (Join-Path $OutputRoot $name)}
    $privateEnvironment.APPDATA=Join-Path $OutputRoot 'appdata';$privateEnvironment.LOCALAPPDATA=Join-Path $OutputRoot 'localappdata'
    $privateEnvironment.TEMP=Join-Path $OutputRoot 'temp';$privateEnvironment.TMP=$privateEnvironment.TEMP;$privateEnvironment.USERPROFILE=Join-Path $OutputRoot 'profile'
    $stateRoot=Join-Path $OutputRoot 'state';$pipe='\\.\pipe\YimeBroker-health-candidate-'+[guid]::NewGuid().ToString('N')
    $runtimePath=Join-Path $PackageRoot 'bin\YimeCoreTrialRuntime.exe';$brokerPath=Join-Path $PackageRoot 'bin\YimeBroker.exe'
    $runtimeArgs=@('-install-root',$PackageRoot,'-broker',$brokerPath,'-state-root',$stateRoot,'-pipe',$pipe,'-no-toolbar')
    $runtime=Start-HealthOwned 'runtime' $runtimeArgs
    $runtimePin=$processType::Open($runtime.process.Id);$nativePins.Add($runtimePin)
    $runtimeIdentity=Assert-HealthOwnedIdentity $runtime $runtimePin $runtimePath $PID $caller
    # Exact owned parent filter only. CIM values are discovery hints; retained
    # native handle observations below authenticate every returned identity.
    $deadline=[DateTime]::UtcNow.AddSeconds(20);$rows=@()
    do{
        [void](Assert-HealthOwnedIdentity $runtime $runtimePin $runtimePath $PID $caller)
        $rows=@(Get-CimInstance -ClassName Win32_Process -Filter ('ParentProcessId='+$runtime.process.Id) -Property ProcessId,ParentProcessId,Name -ErrorAction Stop)
        if($rows.Count -gt 1){throw 'Unexpected additional child in isolated Runtime fixture'}
        if($rows.Count -eq 1){break};Start-Sleep -Milliseconds 50
    }while([DateTime]::UtcNow -lt $deadline)
    if($rows.Count -ne 1 -or $rows[0].Name -isnot [string] -or $rows[0].Name -cne 'YimeBroker.exe' -or
        ($rows[0].ProcessId -isnot [uint32] -and $rows[0].ProcessId -isnot [int]) -or $rows[0].ProcessId -le 0 -or $rows[0].ProcessId -gt [int]::MaxValue -or
        ($rows[0].ParentProcessId -isnot [uint32] -and $rows[0].ParentProcessId -isnot [int]) -or
        $rows[0].ParentProcessId -ne $runtime.process.Id){throw 'Exact isolated Broker child was not discovered'}
    $brokerPin=$processType::Open([int]$rows[0].ProcessId);$nativePins.Add($brokerPin)
    $broker=[pscustomobject]@{role='broker';process=[Diagnostics.Process]::GetProcessById([int]$rows[0].ProcessId);started=$true;creation=[long]0;stdout=$null;stderr=$null;forced=$false;exit_recorded=$false}
    [void]$broker.process.Handle;$broker.creation=$fixtureType::Creation($broker.process.Handle)
    # Do not add an unverified PID to the set permitted for cleanup.
    $brokerIdentity=Assert-HealthOwnedIdentity $broker $brokerPin $brokerPath $runtime.process.Id $caller
    if($broker.creation -lt $runtime.creation){throw 'Broker predates its owned Runtime'};$owned.Add($broker)
    do{
        [void](Assert-HealthOwnedIdentity $runtime $runtimePin $runtimePath $PID $caller)
        [void](Assert-HealthOwnedIdentity $broker $brokerPin $brokerPath $runtime.process.Id $caller)
        if($fixtureType::PipeAvailable($pipe)){break};Start-Sleep -Milliseconds 25
    }while([DateTime]::UtcNow -lt $deadline)
    if(-not $fixtureType::PipeAvailable($pipe)){throw 'Owned ordinary listener did not become available'}
    $openParameters=@{TargetUserSid=$caller.Sid;ExpectedInstallRoot=$PackageRoot;
        ExpectedRuntimeSha256=$packageRecords['bin/YimeCoreTrialRuntime.exe'].sha256;
        ExpectedBrokerSha256=$packageRecords['bin/YimeBroker.exe'].sha256;RuntimeProcess=$runtime.process;BrokerProcess=$broker.process}
    $adapterLease=& $processModule {param($p)Open-YimeCoreNativeMaintenanceProcesses @p} $openParameters
    $beforeImport=Read-HealthAdapterLease
    $healthModule=Import-Module -Name (Join-Path $PSScriptRoot 'native-maintenance-health.psm1') -Scope Local -PassThru
    $afterImport=Read-HealthAdapterLease
    if(($beforeImport|ConvertTo-Json -Depth 20 -Compress) -cne ($afterImport|ConvertTo-Json -Depth 20 -Compress)){throw 'Health import changed an existing live process lease'}
    $adapterImportPreserved=$true;$adapterChecks.Add('health import preserves original live process registry')
    $copy=$adapterLease|ConvertTo-Json -Depth 20|ConvertFrom-Json
    Assert-HealthRefusal {& $healthModule {param($o,$p)Get-YimeCoreNativeMaintenanceHealth -ProcessObservation $o -BrokerPipeName $p} $copy $pipe} 'serialized public observation refused'
    # The public projection is not authoritative; reads must use the registry's
    # original handles even when its caller-editable evidence is replaced.
    $adapterLease.evidence=[pscustomobject]@{caller_changed='not native evidence'}
    [void](Read-HealthAdapterLease);$adapterChecks.Add('caller evidence replacement does not replace native facts')
    for($round=1;$round -le 2;$round++){
        $beforeRuntime=Assert-HealthOwnedIdentity $runtime $runtimePin $runtimePath $PID $caller
        $beforeBroker=Assert-HealthOwnedIdentity $broker $brokerPin $brokerPath $runtime.process.Id $caller
        [void](Read-HealthAdapterLease)
        $health=& $healthModule {param($o,$p)Get-YimeCoreNativeMaintenanceHealth -ProcessObservation $o -BrokerPipeName $p} $adapterLease $pipe
        if($health.records.Count -ne 2 -or $health.health_service_responsive -isnot [bool] -or -not $health.health_service_responsive -or
            $health.retained_process_observation_rechecked -isnot [bool] -or -not $health.retained_process_observation_rechecked -or
            (Get-HealthPendingIo) -ne 0){throw 'Production health adapter incomplete or has pending IO'}
        [void](Read-HealthAdapterLease)
        [void](Assert-HealthOwnedIdentity $runtime $runtimePin $runtimePath $PID $caller)
        [void](Assert-HealthOwnedIdentity $broker $brokerPin $brokerPath $runtime.process.Id $caller)
        $rounds.Add([pscustomobject][ordered]@{round=$round;observed_at=[DateTime]::UtcNow.ToString('o');runtime=$beforeRuntime;broker=$beforeBroker;
            replies=$health.records;production_adapter=$health;
            retained_native_handles_rechecked=$true;outstanding_client_io=(Get-HealthPendingIo)})
    }
    Assert-HealthFilesCurrent
    $stopper=Start-HealthOwned 'stopper' @($runtimeArgs+@('-stop'))
    if((Complete-HealthOwned $stopper 10000) -ne 0){throw 'Owned candidate stopper failed'}
    if((Complete-HealthOwned $runtime 10000) -ne 0){throw 'Owned Runtime did not exit successfully after its stop request'}
    [void](Complete-HealthOwned $broker 10000)
    Assert-HealthRefusal {& $healthModule {param($o,$p)Get-YimeCoreNativeMaintenanceHealth -ProcessObservation $o -BrokerPipeName $p} $adapterLease $pipe} 'terminated original process references refused'
    & $processModule {param($o)Close-YimeCoreNativeMaintenanceProcesses -Observation $o} $adapterLease
    $adapterLeaseClosed=$true
    Assert-HealthRefusal {& $healthModule {param($o,$p)Get-YimeCoreNativeMaintenanceHealth -ProcessObservation $o -BrokerPipeName $p} $adapterLease $pipe} 'closed process observation refused'
    Assert-HealthFilesCurrent
    $success=$true
} catch {
    $failure=[pscustomobject]@{type=$_.Exception.GetType().FullName;message=$_.Exception.Message}
} finally {
    # No name-based termination, tree-wide kill, installer, or installed helper.
    # Only original Process instances authenticated as this fixture's own are
    # eligible. Runtime's own kill-on-job-close contains its Broker on failure.
    foreach($record in $owned){
        if($record.started -and -not $record.exit_recorded){
            try{
                if(-not $record.process.HasExited){$record.forced=$true;$record.process.Kill()}
                [void](Complete-HealthOwned $record 5000)
            }catch{$cleanupErrors.Add($record.role+': '+$_.Exception.Message)}
        }
    }
    if($null -ne $adapterLease -and -not $adapterLeaseClosed){
        try{& $processModule {param($o)Close-YimeCoreNativeMaintenanceProcesses -Observation $o} $adapterLease;$adapterLeaseClosed=$true}
        catch{$cleanupErrors.Add('Process adapter lease close: '+$_.Exception.Message)}
    }
    if((Get-HealthPendingIo) -ne 0){$cleanupErrors.Add('Health client retains pending IO')}
    if($cleanupErrors.Count){$success=$false}
    if($createdOutput){
        try{
            $report=[ordered]@{schema_version='yimecore-isolated-candidate-health-v2';passed=$success;required_test_exit_code=0;generated_at=[DateTime]::UtcNow.ToString('o');powershell=$PSVersionTable.PSVersion.ToString();
                package_root=$PackageRoot;package_manifest_sha256=$manifestFile.sha256;candidate_git_commit=$candidateCommit;candidate_package_id=$manifest.package_id;
                listed_payload_count=85;verified_package_file_count=$packageFiles.Count;output_root=$OutputRoot;state_root=$stateRoot;pipe_name=$pipe;
                source_pins=@($sources|ForEach-Object {[ordered]@{path=$_.path;sha256=$_.sha256;bytes=$_.bytes}});
                test_wrapper_in_candidate_source=$false;isolated_actual_candidate_parent_child_health=($success -and $rounds.Count -eq 2);
                rounds=$rounds.ToArray();original_handle_exits=$exitRecords.ToArray();failure=$failure;cleanup_errors=$cleanupErrors.ToArray();
                private_child_environment=@('APPDATA','LOCALAPPDATA','TEMP','TMP','USERPROFILE');ordinary_pipe_connection_opened=$false;
                production_process_discovery_used=$false;production_lease_adapter_integrated=($success -and $adapterImportPreserved -and $adapterLeaseClosed);
                process_discovery_scope='explicit_process_references';private_provider_replacements_used=$false;
                adapter_import_preserved_existing_lease=$adapterImportPreserved;adapter_lease_closed=$adapterLeaseClosed;adapter_regressions=$adapterChecks.ToArray();
                collector_integrated=$false;installed_product_executed=$false;
                installed_product_state_read=$false;user_state_read=$false;packaged_ancestry_excluded=$false;native_desktop_verified=$false;
                continuous_package_membership_verified=$false;in_memory_code_identity_verified=$false;runtime_ready=$false;config_consumed_verified=$false;
                startup_path_verified=$false;E7_accepted=$false;L6_sealed=$false;local_product_ready=$false;public_release_ready=$false;full_acceptance=$false}
            $resultPath=Join-Path $OutputRoot 'summary.json'
            $output=[IO.File]::Open($resultPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
            try{
                [void]$factsType::VerifyFileHandle($output,$resultPath)
                $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes(($report|ConvertTo-Json -Depth 20))
                $output.Write($bytes,0,$bytes.Length);$output.Flush($true)
            }finally{$output.Dispose()}
            Write-Output ('Isolated candidate health: passed='+$success+'; '+$resultPath)
        }catch{$success=$false;$cleanupErrors.Add('Result write failed: '+$_.Exception.Message)}
    }
    foreach($record in $owned){$record.process.Dispose()}
    if($null -ne $broker -and -not $owned.Contains($broker)){$broker.process.Dispose()}
    foreach($pin in $nativePins){$pin.Dispose()}
    foreach($stream in $streams){$stream.Dispose()}
    foreach($directory in $directories.Values){$directory.Dispose()}
    if($null -ne $readerModule){Remove-Module $readerModule}
    if($null -ne $healthModule){Remove-Module $healthModule}
    if($null -ne $processModule){Remove-Module $processModule}
}
if(-not $success){
    if($null -ne $failure){Write-Error ($failure.type+': '+$failure.message) -ErrorAction Continue}
    foreach($message in $cleanupErrors){Write-Error $message -ErrorAction Continue}
    exit 1
}
