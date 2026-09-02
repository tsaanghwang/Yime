[CmdletBinding()]
param([string]$InstalledPackage)
$ErrorActionPreference='Stop'
$out=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) ('.tmp\yimecore-local-product\maintenance-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out | Out-Null
$manager=Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($manager,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed $Name}
function Import-TestFunction([string]$Name) {
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
    if(-not $fn){throw "Missing function $Name"}
    # Extracted ScriptBlocks have no source-file PSScriptRoot; pin the same
    # owning directory that the real packaged function resolves at runtime.
    $body=$fn.Extent.Text.Replace("function $Name", "function script:$Name")
    $body=$body.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
    . ([scriptblock]::Create($body))
}
foreach($name in @('Get-RegistrationArchitectures','Test-FrozenInstallRoot','Get-FrozenRegistrationReferences',
        'Assert-ProductChild','Remove-ProductTree','Test-PreviousRuntimeIdentity','Get-PreviousRuntimeWasRunning',
        'Invoke-UninstallCore','Restore-PreviousInstallation','Test-NativeX64LauncherContent')){Import-TestFunction $name}
$NativeX64Only=$true; $NativeX64Rehearsal=$false; $nativeArchitecture='AMD64'
$arches=@(Get-RegistrationArchitectures)
Check ($arches.Count -eq 1 -and $arches[0].name -eq 'x64' -and $arches[0].action -eq 'register') 'normal native mode only executes x64'
$NativeX64Only=$false
Check (@(Get-RegistrationArchitectures).Count -eq 2) 'historical registration contract unchanged'
$NativeX64Rehearsal=$true
Check (@(Get-RegistrationArchitectures).Count -eq 1) 'fault-only rehearsal still separate'
$NativeX64Rehearsal=$false; $NativeX64Only=$true
$productRoot=Join-Path $out 'product'
$protected=Join-Path $productRoot 'previous'
$unreferenced=Join-Path $productRoot 'obsolete'
$frozen=@([ordered]@{dll_path=(Join-Path $protected 'x86\YimeTextServiceExperiment.dll')})
Check (Test-FrozenInstallRoot $protected $frozen) 'frozen DLL protects entire previous root'
Check (-not (Test-FrozenInstallRoot ($protected+'-other') $frozen)) 'similarly named sibling not treated as same root'
Check (-not (Test-FrozenInstallRoot $unreferenced $frozen)) 'unreferenced root distinguished'
Reject {Assert-ProductChild $productRoot 'fixture'} 'cannot delete broad product root'
$providerMode='found'
$TargetUserSid='S-1-5-21-111-222-333-1001';$clsid='{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
function Invoke-CimMethod {
    param($Namespace,$ClassName,$MethodName,$Arguments,$InputObject)
    if($MethodName -eq 'GetOwnerSid'){return [pscustomobject]@{Sid=$TargetUserSid;ReturnValue=0}}
    switch($providerMode){
        'missing' {return [pscustomobject]@{ReturnValue=2;sValue=$null}}
        'error' {return [pscustomobject]@{ReturnValue=5;sValue=$null}}
        'ambiguous' {return [pscustomobject]@{ReturnValue=0;sValue='%UNKNOWN%\x86\trial.dll'}}
        default {return [pscustomobject]@{ReturnValue=0;sValue=$frozen[0].dll_path}}
    }
}
Check (@(Get-FrozenRegistrationReferences).Count -eq 2) 'both machine and initiating-user frozen COM checked'
Reject {Remove-ProductTree $protected} 'central guard refuses immediate and deferred frozen deletion'
$providerMode='missing';Check (@(Get-FrozenRegistrationReferences).Count -eq 0) 'missing frozen registration is valid'
$providerMode='error';Reject {Get-FrozenRegistrationReferences} 'provider failure has no process-view fallback'
$providerMode='ambiguous';Reject {Get-FrozenRegistrationReferences} 'ambiguous frozen reference blocks cleanup'
$providerMode='found'

$stateRootPath=Join-Path $out 'state'
$now=[DateTime]::UtcNow
$config=[pscustomobject]@{install_root=$protected;runtime_path=(Join-Path $protected 'bin\YimeCoreTrialRuntime.exe');broker_path=(Join-Path $protected 'bin\YimeBroker.exe');state_root=$stateRootPath}
$status=[pscustomobject]@{state='running';runtime_pid=120;broker_pid=121;install_root=$protected;broker_path=$config.broker_path;state_root=$stateRootPath;updated_at=$now.ToString('o')}
$runtime=[pscustomobject]@{ProcessId=120;ParentProcessId=1;ExecutablePath=$config.runtime_path;CreationDate=$now.AddSeconds(-3)}
$broker=[pscustomobject]@{ProcessId=121;ParentProcessId=120;ExecutablePath=$config.broker_path;CreationDate=$now.AddSeconds(-2)}
$owners=@([pscustomobject]@{sid=$TargetUserSid;result=0},[pscustomobject]@{sid=$TargetUserSid;result=0})
$boot=$now.AddHours(-1)
Check (Test-PreviousRuntimeIdentity $config $status $runtime $broker $boot $TargetUserSid $owners) 'matching live PID image owner boot identity accepted'
foreach($scenario in @('missing-runtime','pid-reuse','wrong-image','missing-image','wrong-parent','old-boot','stale-update','future-update','wrong-state','wrong-root','wrong-owner','owner-error')) {
    $rt=$runtime|ConvertTo-Json|ConvertFrom-Json;$br=$broker|ConvertTo-Json|ConvertFrom-Json
    $st=$status|ConvertTo-Json|ConvertFrom-Json;$own=$owners|ConvertTo-Json|ConvertFrom-Json;$bt=$boot
    switch($scenario){
        'missing-runtime' {$rt=$null}
        'pid-reuse' {$rt.ProcessId=999}
        'wrong-image' {$br.ExecutablePath='C:\Windows\notepad.exe'}
        'missing-image' {$br.ExecutablePath=''}
        'wrong-parent' {$br.ParentProcessId=999}
        'old-boot' {$bt=$now}
        'stale-update' {$st.updated_at=$now.AddDays(-1).ToString('o')}
        'future-update' {$st.updated_at=$now.AddDays(1).ToString('o')}
        'wrong-state' {$st.state='stopped'}
        'wrong-root' {$st.state_root='C:\Other'}
        'wrong-owner' {$own[1].sid='S-1-5-18'}
        'owner-error' {$own[1].result=5}
    }
    Check (-not (Test-PreviousRuntimeIdentity $config $st $rt $br $bt $TargetUserSid $own)) "reject live identity $scenario"
}
$fakeProcesses=@()
function Get-CimInstance {param($ClassName,$Filter) if($ClassName -eq 'Win32_OperatingSystem'){return [pscustomobject]@{LastBootUpTime=$boot}};return $fakeProcesses}
Check (-not (Get-PreviousRuntimeWasRunning ($config|ConvertTo-Json))) 'stale running status without processes is not running'
$fakeProcesses=@($runtime,$broker)
New-Item -ItemType Directory -Path $stateRootPath | Out-Null
$status|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $stateRootPath 'runtime-status.json') -Encoding UTF8
Check (Get-PreviousRuntimeWasRunning ($config|ConvertTo-Json)) 'live state collector joins actual process evidence'
Reject {Get-PreviousRuntimeWasRunning ''} 'running installed image without configuration blocks maintenance'
$fakeProcesses=@([pscustomobject]@{ExecutablePath='';ProcessId=120})
Reject {Get-PreviousRuntimeWasRunning ($config|ConvertTo-Json)} 'inaccessible process cannot be called stopped'

# Exercise the real shared cleanup orchestration with side effects replaced by
# recording functions. No production registry or process mutation is performed.
$deleted=[Collections.Generic.List[string]]::new()
$calls=[Collections.Generic.List[string]]::new()
foreach($path in @($protected,$unreferenced)){New-Item -ItemType Directory -Path $path -Force|Out-Null}
function Get-RegisteredInstallRoots {return @($protected,$unreferenced)}
function Stop-TrialRuntime {param($installRoots)$calls.Add('stop')}
function Remove-InputMethodTip {$calls.Add('remove-tip')}
function Remove-TrialRegistration {param($installRoots)$calls.Add('unregister-x64')}
function Remove-StateRuntime {param([switch]$Purge)$calls.Add('keep-data')}
function Test-InstallMarker {param($root)return $true}
function Remove-ProductTree {param($root)$deleted.Add($root);return $false}
function Remove-ItemProperty {param($LiteralPath,$Name,$ErrorAction)}
function Remove-Item {param($LiteralPath,[switch]$Recurse,[switch]$Force,$ErrorAction)$calls.Add('remove:'+ $LiteralPath)}
$runKey='Registry::fixture-run';$uninstallKey='Registry::fixture-uninstall';$legacyMachineUninstallKey='Registry::fixture-machine';$productKeyName='YimeCoreExperimentalTrial';$PurgeUserData=$false
$cleanup=Invoke-UninstallCore
Check ($deleted.Count -eq 1 -and $deleted[0] -eq $unreferenced) 'shared uninstall deletes only unreferenced root'
Check (@($cleanup.preserved_install_roots) -contains $protected) 'result records frozen-root retention'
Check ($cleanup.user_model_preserved) 'uninstall retains user data'
Check (@($cleanup.frozen_registration_references).Count -eq 2) 'cleanup result records static provenance'

$restores=[Collections.Generic.List[string]]::new()
function Restore-RegistryKeySnapshot {param($path,$snapshot)$restores.Add($path)}
function Restore-RegistryValueSnapshot {param($path,$name,$snapshot)$restores.Add($path)}
function Invoke-Registration {throw 'No previous native registration should be synthesized'}
function Add-InputMethodTip {throw 'No previous native TIP should be synthesized'}
$userTipKey='Registry::fixture-user-tip'
Restore-PreviousInstallation '' '' @{exists=$false} @{exists=$false} @{exists=$false} $false @{exists=$false}
Check ($restores.Count -eq 4 -and $restores.Contains($userTipKey)) 'failed first install restores absent user TIP Run and uninstall snapshots'

Add-Type -Path (Join-Path $PSScriptRoot 'local-runtime-launcher.cs')
$actualToken=[YimeCore.LocalMaintenance.StandardUserLauncher]::InspectProcess($PID)
Check ($actualToken.Sid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) 'native token inspector reads actual current SID'
$token=[YimeCore.LocalMaintenance.TokenEvidence]::new()
$token.Sid=$TargetUserSid;$token.Elevated=$false;$token.Integrity=8192;$token.Session=1;$token.AppContainer=$false
Check ([YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardToken($token,$TargetUserSid,1)) 'expected medium token accepted'
foreach($scenario in @('elevated','high','low','sid','session','container')){
    $token.Elevated=$false;$token.Integrity=8192;$token.Sid=$TargetUserSid;$token.Session=1;$token.AppContainer=$false
    switch($scenario){'elevated'{$token.Elevated=$true}'high'{$token.Integrity=12288}'low'{$token.Integrity=4096}'sid'{$token.Sid='S-1-5-18'}'session'{$token.Session=2}'container'{$token.AppContainer=$true}}
    Check (-not [YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardToken($token,$TargetUserSid,1)) "reject launch token $scenario"
}
Check ($ast.Extent.Text.Contains("'NativeX64Only'")) 'normal x64 mode survives elevation argument forwarding'
Check ($ast.Extent.Text.Contains("`$uninstallCommand += ' -NativeX64Only'")) 'uninstall entry preserves normal x64 mode'
Check ($ast.Extent.Text.Contains('Assert-NativeX64LaunchSupport $package')) 'launcher content pinned before staging mutation'
Check ($ast.Extent.Text.Contains('Normal local maintenance must preserve the initiating user default state namespace used at logon.')) 'normal maintenance cannot diverge from logon data namespace'
$helperHash=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'local-runtime-launcher.cs') -Algorithm SHA256).Hash
$helperRecord=[pscustomobject]@{path='maintenance/local-runtime-launcher.cs';sha256=$helperHash}
Check (Test-NativeX64LauncherContent @{records=@($helperRecord)}) 'correct helper bytes accepted'
Check (-not (Test-NativeX64LauncherContent @{records=@()})) 'missing helper rejected before install'
Check (-not (Test-NativeX64LauncherContent @{records=@($helperRecord,$helperRecord)})) 'duplicate helper manifest entry rejected'
Check (-not (Test-NativeX64LauncherContent @{records=@([pscustomobject]@{path=$helperRecord.path;sha256='wrong'})})) 'stale helper bytes rejected before install'

if($InstalledPackage){
    $planState=Join-Path $out 'plan-state-must-not-exist'
    $planText=(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $manager -Action Plan -NativeX64Only -PackageRoot $InstalledPackage -StateRoot $planState) -join "`n"
    Check ($LASTEXITCODE -eq 0) 'native x64 plan reads complete existing package'
    $plan=$planText|ConvertFrom-Json
    Check (@($plan.active_registration_architectures).Count -eq 1 -and $plan.active_registration_architectures[0] -eq 'x64') 'real plan has only x64 registration'
    Check ($plan.frozen_registration_references -is [array]) 'single frozen dependency keeps stable JSON array shape'
    Check (-not (Test-Path -LiteralPath $planState)) 'read-only plan creates no AppData/state files'
    Check ($plan.standard_user_launcher_package_ready -eq $false) 'old installed package is not advertised as new-mode ready'
    $plan|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $out 'native-plan.json') -Encoding UTF8
}
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);powershell=$PSVersionTable.PSVersion.ToString();
    token_inspector=$actualToken;actual_elevated_to_medium_launch_tested=$false;live_install_or_rollback_executed=$false}|
    ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) local maintenance contracts. Evidence: $out"
