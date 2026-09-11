[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if((Split-Path -Parent $output) -cne (Join-Path $repo '.tmp\dual-product') -or (Split-Path -Leaf $output) -cnotmatch '^dp1-u-candidate-registration-test-[A-Za-z0-9-]+$' -or (Test-Path -LiteralPath $output)){throw 'New immediate repository-owned candidate registration fixture root required.'}
for($cursor=Split-Path -Parent $output;$cursor;$cursor=Split-Path -Parent $cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect test evidence root.'};if($cursor -eq (Split-Path -Qualifier $cursor)){break}}
$null=New-Item -ItemType Directory -Path $output
$path=Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-registration.psm1'
$beforeHash=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
$childSourcePath=Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-registration-child.cs'
$childSourceHash=(Get-FileHash $childSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
$module=Import-Module $path -Force -PassThru
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){try{& $Body;$checks.Add([pscustomobject]@{name=$Name;passed=$true})}catch{$checks.Add([pscustomobject]@{name=$Name;passed=$false;reason=$_.Exception.Message})}}
function Assert([bool]$Value,[string]$Reason){if(-not $Value){throw $Reason}}
function Reject([scriptblock]$Body,[string]$Pattern){try{& $Body;throw 'Unexpected admission.'}catch{if($_.Exception.Message -notmatch $Pattern){throw}}}
$argsMap=@{InstallRoot='C:\Dp1RegistrationFixture\product';PackageRoot='C:\Dp1RegistrationFixture\package';TargetUserSid='S-1-5-21-1-2-3-1001';AuthorizationPath='C:\Dp1RegistrationFixture\approval.json';TrustedApprovalSha256=('a'*64);BoundaryPath='C:\Dp1RegistrationFixture\boundary.json';PackageManifestSha256=('b'*64);DisplayVersion='DP1-U'}
$fixtureGate=[Threading.Semaphore]::new(0,1,('Local\Yime.CandidateRegistrationFixture.'+[guid]::NewGuid().ToString('N')))
$fixtureGateHandle=$fixtureGate.SafeWaitHandle.DangerousGetHandle();$argsMap.CoordinationHandle=$fixtureGateHandle
Check 'only-two-fixed-product-provider-exports' {Assert (@(Get-Command -Module $module.Name).Count -eq 2) 'Unexpected public mutation or test injection entry.'}
Check 'actual-daily-use-host-is-rejected-before-registry-or-file-read' {
    if([Environment]::MachineName -match '(?i)^MYCOMPUTER(?:\.|$)'){Reject {Get-RimePimeDp1UCandidateRegistrationObservation @argsMap} 'MYCOMPUTER daily-use target prohibited'}
    else {Assert ((Get-Content $path -Raw).Contains("if([Environment]::MachineName -match '(?i)^MYCOMPUTER(?:\.|`$)'")) 'Early protected host rejection missing.'}
}
function Encoded-ChildArguments([string]$Command){'-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))}
function Assert-FixtureSemaphoreAbsent([string]$Name) {
    try {$value=[Threading.Semaphore]::OpenExisting($Name)}
    catch {if($_.Exception.GetBaseException() -is [Threading.WaitHandleCannotBeOpenedException]){return};throw}
    $value.Dispose();throw 'Unexpected fixture semaphore remained alive.'
}
$fixtureHost=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Check 'real-contained-ordinary-child-exits-before-return' {
    $r=& $module {param($exe,$arguments,$gate) Invoke-CandidateContainedProcess $exe $arguments 10000 $gate} $fixtureHost (Encoded-ChildArguments 'exit 0') $fixtureGateHandle
    Assert ($r.ExitCode -eq 0 -and $r.JobEmptyBeforeReturn -and -not $r.TimedOut -and -not $r.DescendantsTerminated) 'Ordinary owned child completion not established.'
}
Check 'real-contained-failing-child-retains-exit-status' {
    $r=& $module {param($exe,$arguments,$gate) Invoke-CandidateContainedProcess $exe $arguments 10000 $gate} $fixtureHost (Encoded-ChildArguments 'exit 9') $fixtureGateHandle
    Assert ($r.ExitCode -eq 9 -and $r.JobEmptyBeforeReturn) 'Owned child error was lost.'
}
Check 'real-fast-exit-waits-for-job-accounting-without-false-descendants' {
    for($i=0;$i -lt 20;$i++){
        $r=& $module {param($exe,$gate) Invoke-CandidateContainedProcess $exe '/d /c exit 0' 10000 $gate} (Join-Path $env:SystemRoot 'System32\cmd.exe') $fixtureGateHandle
        Assert ($r.ExitCode -eq 0 -and $r.JobEmptyBeforeReturn -and -not $r.TimedOut -and -not $r.DescendantsTerminated) 'Fast clean exit misclassified as surviving descendants.'
    }
}
Check 'real-contained-timeout-terminates-and-drains-owned-job' {
    $r=& $module {param($exe,$arguments,$gate) Invoke-CandidateContainedProcess $exe $arguments 500 $gate} $fixtureHost (Encoded-ChildArguments 'Start-Sleep -Seconds 120') $fixtureGateHandle
    Assert ($r.TimedOut -and $r.JobEmptyBeforeReturn -and $r.ExitCode -ne 259) 'Timed-out child can remain active.'
}
Check 'real-contained-registrar-cannot-create-descendants' {
    $childArguments=Encoded-ChildArguments 'Start-Sleep -Seconds 120'
    $command="`$s=[Diagnostics.ProcessStartInfo]::new();`$s.FileName='$fixtureHost';`$s.Arguments='$childArguments';`$s.UseShellExecute=`$false;`$s.CreateNoWindow=`$true;try{`$p=[Diagnostics.Process]::Start(`$s);`$p.Dispose();exit 4}catch{exit 17}"
    $r=& $module {param($exe,$arguments,$gate) Invoke-CandidateContainedProcess $exe $arguments 10000 $gate} $fixtureHost (Encoded-ChildArguments $command) $fixtureGateHandle
    Assert ($r.ExitCode -eq 17 -and $r.JobEmptyBeforeReturn -and -not $r.DescendantsTerminated) 'Registrar was able to create a descendant without the retained coordinator gate.'
}
Check 'real-child-retains-only-explicit-coordination-handle' {
    $fixtureTypes=Add-Type -PassThru -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Threading.Tasks;
namespace Yime.CandidateHandleFixture {
 public static class Background {
  [DllImport("kernel32.dll",SetLastError=true)] private static extern bool SetHandleInformation(IntPtr h,uint mask,uint flags);
  public static void Inheritable(IntPtr handle) { if(!SetHandleInformation(handle,1,1)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); }
  public static Task<object> Run(Type type,string exe,string args,IntPtr gate) { return Task.Factory.StartNew<object>(() => type.GetMethod("Run").Invoke(null,new object[]{exe,args,10000,gate})); }
 }
}
'@
    $background=@($fixtureTypes|Where-Object{$_.Name -ceq 'Background'})[0]
    $name='Local\Yime.CandidateHandleFixture.'+[guid]::NewGuid().ToString('N');$otherName=$name+'.unrelated'
    $gate=[Threading.Semaphore]::new(0,1,$name);$unrelated=[Threading.Semaphore]::new(0,1,$otherName);$task=$null;$opened=$null
    $ready=Join-Path $output 'inherited-handle-ready.txt';$release=Join-Path $output 'inherited-handle-release.txt'
    try {
        $background::Inheritable($unrelated.SafeWaitHandle.DangerousGetHandle())
        $command="[IO.File]::WriteAllText('$($ready.Replace("'","''"))','ready');while(-not [IO.File]::Exists('$($release.Replace("'","''"))')){Start-Sleep -Milliseconds 25};exit 0"
        $type=& $module {$script:CandidateChildType}
        $task=$background::Run($type,$fixtureHost,(Encoded-ChildArguments $command),$gate.SafeWaitHandle.DangerousGetHandle())
        $deadline=[DateTime]::UtcNow.AddSeconds(8)
        while(-not (Test-Path -LiteralPath $ready)){if($task.IsCompleted -or [DateTime]::UtcNow -ge $deadline){throw 'Contained fixture did not reach inherited-handle check.'};Start-Sleep -Milliseconds 25}
        $gate.Dispose();$unrelated.Dispose()
        $opened=[Threading.Semaphore]::OpenExisting($name);$opened.Dispose();$opened=$null
        Assert-FixtureSemaphoreAbsent $otherName
        [IO.File]::WriteAllText($release,'release');Assert ($task.Wait(10000)) 'Contained inheritance fixture did not finish.'
        Assert $task.Result.JobEmptyBeforeReturn 'Job did not drain after inheritance fixture.'
        Assert-FixtureSemaphoreAbsent $name
    } finally {
        [IO.File]::WriteAllText($release,'release');if($null -ne $task){$null=$task.Wait(12000)}
        if($null -ne $opened){$opened.Dispose()};$gate.Dispose();$unrelated.Dispose()
    }
}
Check 'real-worker-termination-closes-job-and-terminates-owned-child' {
    $pidPath=(Join-Path $output 'owned-job-child-pid.txt').Replace("'","''")
    $innerArguments=Encoded-ChildArguments ("[IO.File]::WriteAllText('$pidPath',[string]`$PID);Start-Sleep -Seconds 120")
    $escapedModule=$path.Replace("'","''")
    $workerCommand="`$m=Import-Module '$escapedModule' -PassThru;`$g=[Threading.Semaphore]::new(0,1); & `$m { param(`$p,`$a,`$g) Invoke-CandidateContainedProcess `$p `$a 120000 `$g } '$fixtureHost' '$innerArguments' `$g.SafeWaitHandle.DangerousGetHandle() | Out-Null"
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$fixtureHost;$start.Arguments=Encoded-ChildArguments $workerCommand;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $worker=[Diagnostics.Process]::Start($start);$child=$null
    try {
        $null=$worker.Handle;$deadline=[DateTime]::UtcNow.AddSeconds(20)
        while(-not (Test-Path -LiteralPath $pidPath)) {if($worker.HasExited -or [DateTime]::UtcNow -ge $deadline){throw 'Owned fixture worker did not establish its job child.'};Start-Sleep -Milliseconds 25}
        $child=[Diagnostics.Process]::GetProcessById([int][IO.File]::ReadAllText($pidPath));$null=$child.Handle
        $worker.Kill();Assert ($worker.WaitForExit(10000)) 'Owned fixture worker did not exit.'
        Assert ($child.WaitForExit(10000)) 'Owned child survived loss of its worker/job handle.'
    } finally {
        if(-not $worker.HasExited){$worker.Kill();$null=$worker.WaitForExit(10000)}
        if($null -ne $child){$child.Dispose()};$worker.Dispose()
    }
}
# All calls below use private module-scope doubles for the native boundary.
Check 'real-reader-default-only-enumeration-retains-typed-system-value' {
    & $module {
        $testMode='present'
        function Assert-CandidateDefaultStringKind($Expected,$SystemValue){
            $kind=[Microsoft.Win32.RegistryValueKind]::String
            if($testMode -eq 'expanded-string'){$kind=[Microsoft.Win32.RegistryValueKind]::ExpandString}
            Assert-CandidateDefaultStringAgreement $kind $SystemValue $SystemValue
        }
        function Invoke-YimePimeStdRegProvMethod($Method,$Arguments,$ProviderArchitecture){
            if($ProviderArchitecture -ne 64){throw 'Wrong registry view.'}
            switch($Method){
                EnumValues {return [pscustomobject]@{ReturnValue=0;sNames=$null;Types=$null}}
                EnumKey {return [pscustomobject]@{ReturnValue=0;sNames=@('InprocServer32')}}
                GetStringValue {
                    if($Arguments.sValueName -cne ''){throw 'Default name not preserved.'}
                    if($testMode -eq 'denied'){return [pscustomobject]@{ReturnValue=5;sValue=$null}}
                    if($testMode -eq 'missing-or-wrong-type'){return [pscustomobject]@{ReturnValue=1;sValue=$null}}
                    if($testMode -eq 'null-data'){return [pscustomobject]@{ReturnValue=0;sValue=$null}}
                    $value=$testMode;if($testMode -eq 'expanded-string'){$value='present'}
                    return [pscustomobject]@{ReturnValue=0;sValue=$value}
                }
                default {throw 'Unexpected provider method; mutation prohibited.'}
            }
        }
        $tree=New-CandidateTree 'com-x64' LocalMachine Registry64 'SOFTWARE\fixture' @((New-CandidateValue '' String 'present')) @('InprocServer32')
        $r=Get-CandidateTreeObservation $tree
        if(-not $r.exists -or $r.values.Count -ne 1 -or $r.values[0].value -cne 'present' -or $r.values[0].reader -cne 'StdRegProv'){throw 'Default-only COM key lost its actual system value.'}
        foreach($testMode in @('denied','missing-or-wrong-type','null-data','foreign-value','expanded-string')){
            $rejected=$false
            try{$null=Get-CandidateTreeObservation $tree}catch{$rejected=$true}
            if(-not $rejected){throw ('Unsafe default value admitted: '+$testMode)}
        }
    }
}
Check 'supplemental-default-type-and-system-value-must-agree' {
    & $module {
        Assert-CandidateDefaultStringAgreement ([Microsoft.Win32.RegistryValueKind]::String) 'expected' 'expected'
        foreach($case in @(@([Microsoft.Win32.RegistryValueKind]::ExpandString,'expected'),@([Microsoft.Win32.RegistryValueKind]::DWord,7),@([Microsoft.Win32.RegistryValueKind]::String,'different'))){
            $rejected=$false
            try{Assert-CandidateDefaultStringAgreement $case[0] $case[1] 'expected'}catch{$rejected=$true}
            if(-not $rejected){throw 'Supplemental default type/value mismatch admitted.'}
        }
    }
}
# No system registry, product process, installer or private hive is touched.
& $module {
    $script:TestKeys=@{};$script:TestCalls=[Collections.Generic.List[string]]::new();$script:TestContext=$null;$script:TestDefault='';$script:TestLanguageReference=$false;$script:TestFail=''
    function script:Get-RimePimePeerProtectionSnapshot {param($b,$s) [pscustomobject]@{fixture=$true}}
    function script:Open-CandidateRegistrationContext($Request,[bool]$RequireElevated) {
        $script:TestCalls.Add('context:'+([string]$RequireElevated))
        $script:TestContext=[pscustomobject]@{request=$Request;authorization=[pscustomobject]@{state_root='C:\Dp1RegistrationFixture\state';recovery_root='C:\Dp1RegistrationFixture\recovery';package_sha256=('c'*64)};boundary=[pscustomobject]@{};leases=@();peer_protection=[pscustomobject]@{fixture=$true};current=[pscustomobject]@{Elevated=$RequireElevated}}
        return $script:TestContext
    }
    function script:Test-Key([string]$Hive,[string]$View,[string]$Key){$Hive+'|'+$View+'|'+$Key}
    function script:Get-YimePimeSystemRegistryKeyShape($Hive,$View,$Key) {
        $id=Test-Key $Hive $View $Key
        if(-not $script:TestKeys.ContainsKey($id)){return [pscustomobject]@{exists=$false;value_names=@();value_types=@();subkey_names=@()}}
        $row=$script:TestKeys[$id]
        if($script:TestFail -ceq 'null-arrays' -and $row.values.Count -eq 0 -and @($row.children).Count -eq 0){return [pscustomobject]@{exists=$true;value_names=$null;value_types=$null;subkey_names=$null}}
        [pscustomobject]@{exists=$true;value_names=@($row.values.Keys);value_types=@($row.values.Keys|ForEach-Object{if($row.values[$_].kind -ceq 'DWord'){4}else{1}});subkey_names=@($row.children)}
    }
    function script:Get-YimePimeSystemRegistryValueRecord($Expected) {
        if($Expected.id -ceq 'default-input-override'){return [pscustomobject]@{id=$Expected.id;exists=($script:TestDefault -cne '');value_kind=$(if($script:TestDefault -cne ''){'String'}else{$null});value=$script:TestDefault;reader='StdRegProv'}}
        $id=Test-Key $Expected.hive $Expected.view $Expected.key;$exists=$script:TestKeys.ContainsKey($id) -and $script:TestKeys[$id].values.ContainsKey($Expected.name)
        [pscustomobject]@{id=$Expected.id;hive=$Expected.hive;view=$Expected.view;key=$Expected.key;name=$Expected.name;exists=$exists;value_kind=$(if($exists){$script:TestKeys[$id].values[$Expected.name].kind}else{$null});value=$(if($exists){$script:TestKeys[$id].values[$Expected.name].value}else{$null});reader='StdRegProv'}
    }
    function script:Test-YimePimeTargetUserControlPanelReference($TargetUserSid){return $script:TestLanguageReference}
    function script:Set-TestTree($Tree) {
        $values=@{};foreach($value in $Tree.values){$values[$value.name]=@{kind=$value.value_kind;value=$value.value}}
        $script:TestKeys[(Test-Key $Tree.hive $Tree.view $Tree.key)]=@{values=$values;children=@($Tree.children)}
    }
    function script:Invoke-CandidateNativeRegistration($Context,[string]$Architecture,[bool]$Remove) {
        $script:TestCalls.Add('native:'+$Architecture+':'+$Remove)
        $trees=@(Get-CandidateRegistrationLayout $Context|Where-Object{$_.id -like ('com-'+$Architecture+'*') -or ($Architecture -ceq 'x64' -and $_.hive -ceq 'LocalMachine' -and $_.id -notlike 'com-*' -and $_.id -notlike 'marker-*')})
        foreach($tree in $trees){if($Remove){$script:TestKeys.Remove((Test-Key $tree.hive $tree.view $tree.key))}else{Set-TestTree $tree};if($script:TestFail -ceq 'native-partial'){throw 'Injected native partial error.'}}
    }
    function script:Invoke-CandidateNativeProbe($Context,[string]$Mode){$script:TestCalls.Add('probe:'+$Mode);if($script:TestFail -ceq 'probe'){throw 'Injected native probe failure.'}}
    function script:Invoke-CandidateTip([bool]$Remove) {
        $script:TestCalls.Add('tip:'+$Remove)
        foreach($tree in @(Get-CandidateRegistrationLayout $script:TestContext|Where-Object{$_.id -like 'user-*'})){Set-TestTree $tree}
        if($Remove){$leaf=@(Get-CandidateRegistrationLayout $script:TestContext|Where-Object{$_.id -ceq 'user-profile'})[0];$script:TestKeys[(Test-Key $leaf.hive $leaf.view $leaf.key)].values['Enable'].value='0'}
        if($script:TestFail -ceq 'default-change'){$script:TestDefault='changed'}
    }
    function script:Invoke-YimePimeSystemRegistryMethod($Method,$Hive,$Key,$ProviderArchitecture,$Values=@{}) {
        $hiveName=if([uint32]$Hive -eq 2147483650){'LocalMachine'}else{'Users'}
        $view=if($ProviderArchitecture -eq 32){'Registry32'}elseif($Key -like '*\CTF\TIP\*'){'Shared'}else{'Registry64'}
        $id=Test-Key $hiveName $view $Key;$script:TestCalls.Add('registry:'+$Method+':'+$Key)
        switch($Method) {
            CreateKey {if(-not $script:TestKeys.ContainsKey($id)){$script:TestKeys[$id]=@{values=@{};children=@()}}}
            SetStringValue {$script:TestKeys[$id].values[$Values.sValueName]=@{kind='String';value=[string]$Values.sValue}}
            DeleteValue {if($script:TestKeys.ContainsKey($id)){$script:TestKeys[$id].values.Remove($Values.sValueName)}}
            DeleteKey {
                $script:TestKeys.Remove($id)
                $parent=Split-Path -Parent $Key;$leaf=Split-Path -Leaf $Key;$parentId=Test-Key $hiveName $view $parent
                if($script:TestKeys.ContainsKey($parentId)){$script:TestKeys[$parentId].children=@($script:TestKeys[$parentId].children|Where-Object{$_ -cne $leaf})}
            }
            default {throw ('Unexpected system registry operation in fixture: '+$Method)}
        }
        [pscustomobject]@{ReturnValue=0}
    }
    function script:Get-FileHash {param($LiteralPath,$Algorithm) [pscustomobject]@{Hash=('c'*64)}}
}
function Reset-Fixture {& $module {$script:TestKeys=@{};$script:TestCalls.Clear();$script:TestDefault='';$script:TestLanguageReference=$false;$script:TestFail=''}}
function Apply([string]$Action){Invoke-RimePimeDp1UCandidateRegistration @argsMap -Action $Action -UninstallerSha256 ('c'*64)}
function Install-Fixture {Apply RegisterNative|Out-Null;Apply RegisterWow64|Out-Null;Apply EnableTip|Out-Null;Apply PublishMarkers|Out-Null}
Check 'fresh-observation-uses-native-vacancy-probes' {Reset-Fixture;$v=Get-RimePimeDp1UCandidateRegistrationObservation @argsMap -ExpectedState Vacant;Assert $v.actual_registration_probe_executed 'Native probe omitted.';Assert (-not $v.dp1_u_acceptance_passed) 'Synthetic observation became full acceptance.'}
Check 'all-install-actions-converge-typed-registration' {Reset-Fixture;Install-Fixture;$v=Get-RimePimeDp1UCandidateRegistrationObservation @argsMap -ExpectedState Present;Assert (@($v.trees|Where-Object{$_.exists}).Count -eq 36) 'Expected fixed closed tree count changed.';Assert $v.run.exists 'No autostart.'}
Check 'native-first-then-wow64-is-recorded' {Reset-Fixture;Install-Fixture;$calls=& $module {$script:TestCalls.ToArray()};Assert (($calls|Where-Object{$_ -like 'native:*'}) -join ',' -ceq 'native:x64:False,native:x86:False') 'Native mutation order changed.'}
Check 'repeated-native-registration-is-not-an-upgrade' {Reset-Fixture;Install-Fixture;Reject {Apply RegisterNative} 'vacancy';$v=Get-RimePimeDp1UCandidateRegistrationObservation @argsMap -ExpectedState Present;Assert $v.run.exists 'Existing state disturbed.'}
Check 'foreign-com-value-prevents-native-call' {Reset-Fixture;Install-Fixture;& $module {$key=@($script:TestKeys.Keys|Where-Object{$_ -like '*Registry32*InprocServer32'})[0];$script:TestKeys[$key].values['ThreadingModel'].value='Both';$script:TestCalls.Clear()};Reject {Apply UnregisterWow64} 'unknown state';Assert (@(& $module {$script:TestCalls|Where-Object{$_ -like 'native:*'}}).Count -eq 0) 'Foreign registry reached unregister.'}
Check 'unknown-subkey-is-preserved' {Reset-Fixture;Install-Fixture;& $module {$key=@($script:TestKeys.Keys|Where-Object{$_ -like '*Registry64*InprocServer32'})[0];$script:TestKeys[$key].children=@('Foreign')};Reject {Apply UnregisterNative} 'Foreign registration subkey';Assert (& $module {@($script:TestKeys.Values|Where-Object{$_.children -contains 'Foreign'}).Count -eq 1}) 'Foreign child lost.'}
Check 'wrong-registry-type-is-rejected' {Reset-Fixture;Install-Fixture;& $module {$key=@($script:TestKeys.Keys|Where-Object{$_ -like '*Users*LanguageProfile*' -and $script:TestKeys[$_].values.ContainsKey('Enable')})[0];$script:TestKeys[$key].values['Enable'].kind='String'};Reject {Get-RimePimeDp1UCandidateRegistrationObservation @argsMap -ExpectedState Present} 'mistyped'}
Check 'native-wmi-null-empty-arrays-preserve-real-default-values' {Reset-Fixture;Install-Fixture;& $module {$script:TestFail='null-arrays'};$v=Get-RimePimeDp1UCandidateRegistrationObservation @argsMap -ExpectedState Present;Assert (@($v.trees|Where-Object{$_.id -eq 'com-x64'}).values[0].value -ceq 'PIMETextService') 'Default COM value was treated as empty enumeration.'}
Check 'markers-before-native-removal-are-preserved' {Reset-Fixture;Install-Fixture;Reject {Apply RemoveMarkers} 'Native COM/TIP must be absent';Assert (Get-RimePimeDp1UCandidateRegistrationObservation @argsMap).run.exists 'Run removed too early.'}
Check 'shared-tsf-removal-waits-for-wow64' {Reset-Fixture;Install-Fixture;Reject {Apply UnregisterNative} 'Remove WOW64 COM';Assert (Get-RimePimeDp1UCandidateRegistrationObservation @argsMap).run.exists 'Unrelated state changed.'}
Check 'disable-native-unregister-marker-cleanup-converges-absence' {Reset-Fixture;Install-Fixture;Apply DisableTip|Out-Null;Apply UnregisterWow64|Out-Null;Apply UnregisterNative|Out-Null;Apply RemoveMarkers|Out-Null;$v=Get-RimePimeDp1UCandidateRegistrationObservation @argsMap -ExpectedState Absent;Assert (-not $v.run.exists) 'Run not removed.'}
Check 'foreign-run-never-overwritten' {Reset-Fixture;Install-Fixture;& $module {$key=@($script:TestKeys.Keys|Where-Object{$_ -like '*\Run'})[0];$script:TestKeys[$key].values['PIMELauncher'].value='foreign'};Reject {Apply PublishMarkers} 'autostart preserved'}
Check 'invalid-uninstaller-digest-blocks-marker-publication' {Reset-Fixture;Apply RegisterNative|Out-Null;Apply RegisterWow64|Out-Null;Apply EnableTip|Out-Null;Reject {Invoke-RimePimeDp1UCandidateRegistration @argsMap -Action PublishMarkers -UninstallerSha256 ('d'*64)} 'original explicitly approved';Assert (-not (Get-RimePimeDp1UCandidateRegistrationObservation @argsMap).run.exists) 'Run written despite wrong bytes.'}
Check 'probe-failure-prevents-marker-publication' {Reset-Fixture;Apply RegisterNative|Out-Null;Apply RegisterWow64|Out-Null;Apply EnableTip|Out-Null;& $module {$script:TestFail='probe'};Reject {Apply PublishMarkers} 'probe failure';Assert (-not (Get-RimePimeDp1UCandidateRegistrationObservation @argsMap).run.exists) 'Marker written despite probe failure.'}
Check 'partial-native-error-does-not-claim-success-or-delete-state' {Reset-Fixture;& $module {$script:TestFail='native-partial'};Reject {Apply RegisterNative} 'partial error';$v=Get-RimePimeDp1UCandidateRegistrationObservation @argsMap;Assert (@($v.trees|Where-Object{$_.exists}).Count -eq 1) 'Partial native output lost.';Assert (-not $v.dp1_u_acceptance_passed) 'Partial output claimed acceptance.'}
Check 'unexpected-default-change-is-reported' {Reset-Fixture;Apply RegisterNative|Out-Null;Apply RegisterWow64|Out-Null;& $module {$script:TestFail='default-change'};Reject {Apply EnableTip} 'Default input override changed'}
Check 'residual-language-reference-stops-user-cleanup' {Reset-Fixture;Install-Fixture;Apply DisableTip|Out-Null;Apply UnregisterWow64|Out-Null;Apply UnregisterNative|Out-Null;& $module {$script:TestLanguageReference=$true};Reject {Apply RemoveMarkers} 'Language list retains';Assert (Get-RimePimeDp1UCandidateRegistrationObservation @argsMap).run.exists 'Recovery markers discarded.'}
Check 'observation-never-requires-elevated-worker' {Reset-Fixture;$null=Get-RimePimeDp1UCandidateRegistrationObservation @argsMap;$calls=@(& $module {$script:TestCalls.ToArray()});Assert ($calls[0] -ceq 'context:False') 'Observation demands elevated mutation context.'}
Check 'mutation-requires-elevated-worker' {Reset-Fixture;Apply RegisterNative|Out-Null;$calls=& $module {$script:TestCalls.ToArray()};Assert ($calls[0] -ceq 'context:True') 'Mutation skipped elevated worker context.'}
Check 'result-retains-unproved-closure-fields' {Reset-Fixture;$r=Apply RegisterNative;foreach($name in @('full_native_product_transaction_complete','dp1_u_acceptance_passed','local12_touched','production_user_data_accessed','default_input_method_changed','hostile_same_sid_prevention_verified')){Assert ($r.$name -is [bool] -and -not $r.$name) ('Unproved claim: '+$name)}}
Check 'source-is-unchanged-by-fixture' {Assert ((Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $beforeHash) 'Provider source changed during regressions.';Assert ((Get-FileHash $childSourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $childSourceHash) 'Owned child helper source changed during regressions.'}
$summary=[pscustomobject][ordered]@{schema_version='yime-rime-pime-candidate-registration-test-v1';powershell_version=$PSVersionTable.PSVersion.ToString();source_sha256=$beforeHash;child_source_sha256=$childSourceHash;checks=$checks.ToArray();passed_count=@($checks|Where-Object{$_.passed}).Count;failed_count=@($checks|Where-Object{-not $_.passed}).Count;native_boundary_doubles_used=$true;real_owned_process_job_tests_executed=$true;real_system_registry_mutation_executed=$false;private_hive_used=$false;installer_executed=$false;product_runtime_executed=$false;local12_touched=$false;dp1_u_acceptance_passed=$false}
[IO.File]::WriteAllText((Join-Path $output 'result.json'),($summary|ConvertTo-Json -Depth 14),[Text.UTF8Encoding]::new($false))
$fixtureGate.Dispose()
$checks|ForEach-Object{if($_.passed){Write-Output ('PASS '+$_.name)}else{Write-Output ('FAIL '+$_.name+': '+$_.reason)}}
if($summary.failed_count){throw ('Candidate registration regressions failed: '+$summary.failed_count)}
Write-Output ('PASS '+$summary.passed_count+' candidate registration regressions; registration simulated, owned process/job boundaries executed.')
