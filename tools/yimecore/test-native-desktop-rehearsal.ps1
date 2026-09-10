[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
$controller=Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($controller,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$checks=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Body,[string]$Name){$failed=$false;try{$null=& $Body}catch{$failed=$true};Check $failed $Name}
function Import-ControllerFunction([string]$Name){
    $fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name},$true)
    if(-not $fn){throw "Missing controller function: $Name"}
    $body=$fn.Extent.Text.Replace("function $Name", "function script:$Name")
    if($Name -ceq 'Remove-ProductTree'){$body=$body.Replace('[YimeCoreTrial.NativeFile]','[YimeCoreRehearsalFixture.NativeFile]')}
    . ([scriptblock]::Create($body))
}
foreach($name in @('Assert-NativeDesktopRehearsalOptions','Assert-NativeDesktopRehearsalPackage','Assert-NativeDesktopRehearsalBaseline','Remove-ProductTree','Restore-PreviousInstallation')){Import-ControllerFunction $name}
$NativeX64Only=$false;$NativeDesktop=$true;$NativeDesktopRehearsal=$true;$NativeX64Rehearsal=$false;$NativeLocalProduct=$true
# The transaction now restores the captured registration state, rather than
# assuming that every previous architecture was registered.
$previousRegistrationSnapshot=@{
    x64=@{com_registered=$true;profile_registered=$true;categories_registered_count=5}
    x86=@{com_registered=$true;profile_registered=$true;categories_registered_count=5}
}
$Action='Install';$PurgeUserData=$false;$NoLaunch=$false;$NoAutoStart=$false
Assert-NativeDesktopRehearsalOptions
Check $true 'valid explicit desktop rehearsal options'
foreach($name in @('PurgeUserData','NoLaunch','NoAutoStart','NativeX64Only','NativeX64Rehearsal')){
    Set-Variable -Name $name -Value $true
    Reject {Assert-NativeDesktopRehearsalOptions} "reject incompatible option $name"
    Set-Variable -Name $name -Value $false
}
$NativeDesktop=$false;Reject {Assert-NativeDesktopRehearsalOptions} 'reject missing desktop architecture mode';$NativeDesktop=$true
$Action='Uninstall';Reject {Assert-NativeDesktopRehearsalOptions} 'reject rehearsal uninstall';$Action='Plan'
Assert-NativeDesktopRehearsalOptions;Check $true 'allow read-only rehearsal Plan';$Action='Install'
$marked=[pscustomobject]@{rehearsal_only=$true;preparation_only=$true;source_package_manifest_sha256=('a'*64)}
Assert-NativeDesktopRehearsalPackage $marked;Check $true 'accept explicit prepared failure-only manifest'
Reject {Assert-NativeDesktopRehearsalPackage ([pscustomobject]@{})} 'reject ordinary package in rehearsal'
Reject {Assert-NativeDesktopRehearsalPackage ([pscustomobject]@{rehearsal_only='true';preparation_only=$true;source_package_manifest_sha256=('a'*64)})} 'reject truthy string marker'
Reject {Assert-NativeDesktopRehearsalPackage ([pscustomobject]@{rehearsal_only=$true;preparation_only=$false;source_package_manifest_sha256=('a'*64)})} 'reject false preparation marker'
Reject {Assert-NativeDesktopRehearsalPackage ([pscustomobject]@{rehearsal_only=$true;preparation_only=$true;source_package_manifest_sha256='unknown'})} 'reject missing reviewed source identity'
$NativeDesktopRehearsal=$false
Reject {Assert-NativeDesktopRehearsalPackage $marked} 'reject failure package through ordinary install'
Assert-NativeDesktopRehearsalPackage ([pscustomobject]@{});Check $true 'ordinary package still accepted outside rehearsal'
$NativeDesktopRehearsal=$true

# Evaluate the controller's actual switch-forwarding loop without launching UAC.
$elevate=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Restart-Elevated'},$true)
$forward=$elevate.Find({param($node)$node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Extent.Text.Contains("'NativeDesktopRehearsal'")},$true)
Check ($null -ne $forward) 'UAC loop includes the explicit rehearsal switch'
$Force=$false;$Quiet=$true;$arguments=@()
. ([scriptblock]::Create($forward.Extent.Text))
Check ($arguments -contains '-NativeDesktopRehearsal' -and $arguments -contains '-NativeDesktop') 'desktop and rehearsal mode survive UAC forwarding'

# Select the real transaction's commit segment and its real catch/finally.
# No full controller, registry provider, installer, product or package script runs.
$transaction=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.TryStatementAst] -and $_.Body.Extent.Text.Contains('Start-TrialRuntime $runtimeConfig')})
Check ($transaction.Count -eq 1) 'identify one controller transaction boundary'
$tail=@();$started=$false
foreach($statement in $transaction[0].Body.Statements){
    if($statement -is [Management.Automation.Language.AssignmentStatementAst] -and $statement.Left.Extent.Text -ceq '$runtimeStatus'){$started=$true}
    if($started){$tail+=,$statement}
}
$tailText=($tail|ForEach-Object{$_.Extent.Text}) -join "`n"
$guard=@($tail|Where-Object{$_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text.StartsWith('if ($NativeDesktopRehearsal)')})
Check ($guard.Count -eq 1 -and $tailText.IndexOf($guard[0].Extent.Text) -lt $tailText.IndexOf('foreach ($oldRoot in $previousRoots)')) 'terminal rehearsal throw precedes all old-root cleanup'
$handler=($transaction[0].CatchClauses|ForEach-Object{$_.Extent.Text}) -join "`n"
$finalizer='finally '+$transaction[0].Finally.Extent.Text
$commit=[scriptblock]::Create("try {`n$tailText`n}`n$handler`n$finalizer")
$unguarded=[scriptblock]::Create("try {`n"+$tailText.Replace($guard[0].Extent.Text,'')+"`n}`n$handler`n$finalizer")
Check ($transaction[0].Extent.Text.Contains('Restore-PreviousInstallation')) 'terminal throw uses the existing transaction rollback'

# Use an independent fixture namespace. Never poison the product NativeFile type
# in a PowerShell session that could later run a real maintenance command.
$productNativeTypeBefore='YimeCoreTrial.NativeFile' -as [type]
if (-not ('YimeCoreRehearsalFixture.NativeFile' -as [type])) {
Add-Type -TypeDefinition @'
using System.Collections.Generic;
namespace YimeCoreRehearsalFixture {
    public static class NativeFile {
        public static readonly List<string> Deferred = new List<string>();
        public static bool MoveFileEx(string path, string destination, int flags) {
            Deferred.Add(path); return true;
        }
    }
}
'@
}
function Add-DeferredDeleteType {}
function Get-FrozenRegistrationReferences { @() }
function Test-FrozenInstallRoot {param($root,$references) $false}
function Test-InstallMarker {param($root) $true}
function Assert-ProductChild {param($path,$description)
    $full=[IO.Path]::GetFullPath($path)
    if(-not $full.StartsWith($script:caseRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Synthetic cleanup escaped test root.'}
    $full
}
function Remove-Item {param([string]$LiteralPath,[switch]$Recurse,[switch]$Force,[string]$ErrorAction)
    $script:removed.Add($LiteralPath)
    if($LiteralPath -eq $script:oldRoot -and $script:lockOldRoot){throw 'Synthetic sharing violation.'}
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Recurse:$Recurse -Force:$Force -ErrorAction Stop
}
function Get-RegistrationArchitecturesForRoot {param($root)
    if($script:baselineArchitecture -eq 'single'){@([pscustomobject]@{name='x64';action='register'})}
    else{@([pscustomobject]@{name='x64';action='register'},[pscustomobject]@{name='x86';action='register-com'})}
}
function Resolve-RegistrationAction {param($tool,$action) $action}
function Invoke-Registration {param($tool,$action,$dll,$label) $script:restoredArchitectures.Add($label)}
function Wait-RegistrationState {}
function Add-InputMethodTip {}
function Restore-RegistryKeySnapshot {param($key,$snapshot) $script:restoredRegistry.Add($key)}
function Restore-RegistryValueSnapshot {param($key,$name,$snapshot) $script:restoredRegistry.Add($key+'/'+$name)}
function Restore-FrozenUserTipSnapshot { $script:finallyObserved=$true }
function Complete-RehearsalOutcome {}
function Invoke-UninstallCore {param([switch]$ForReinstall,[string[]]$PreserveInstallRoots) $script:rollbackUninstallObserved=$true;@{}}
function Start-TrialRuntime {param($config)
    if($config.install_root -eq $script:oldRoot){$script:oldRuntimeRestored=$true;return @{state='running'}}
    if($script:injectedStartupFailure){throw 'Synthetic injected startup failure.'}
    return @{state='running'}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('yimecore-desktop-rehearsal-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
try{
    $script:baselineArchitecture='dual'
    Assert-NativeDesktopRehearsalBaseline $root $true;Check $true 'require existing running dual-architecture baseline'
    Reject {Assert-NativeDesktopRehearsalBaseline '' $true} 'reject absent rollback baseline'
    Reject {Assert-NativeDesktopRehearsalBaseline $root $false} 'reject stopped rollback baseline'
    $script:baselineArchitecture='single';Reject {Assert-NativeDesktopRehearsalBaseline $root $true} 'reject x64-only rollback baseline';$script:baselineArchitecture='dual'
    foreach($case in @('injected-failure','unexpected-success','ordinary-success','old-unguarded-lease')){
        $script:caseRoot=Join-Path $root $case
        $script:oldRoot=Join-Path $script:caseRoot 'previous'
        $targetRoot=Join-Path $script:caseRoot 'target';$stagingRoot=Join-Path $script:caseRoot 'staging';$stateRootPath=Join-Path $script:caseRoot 'state'
        foreach($directory in @($script:oldRoot,$targetRoot,$stateRootPath)){New-Item -ItemType Directory -Path $directory -Force|Out-Null}
        Set-Content -LiteralPath (Join-Path $script:oldRoot 'payload.txt') -Value 'synthetic previous package'
        $script:removed=New-Object 'Collections.Generic.List[string]';$script:restoredArchitectures=New-Object 'Collections.Generic.List[string]'
        $script:restoredRegistry=New-Object 'Collections.Generic.List[string]';[YimeCoreRehearsalFixture.NativeFile]::Deferred.Clear()
        $script:lockOldRoot=($case -eq 'old-unguarded-lease');$script:injectedStartupFailure=($case -eq 'injected-failure')
        $script:oldRuntimeRestored=$false;$script:finallyObserved=$false;$script:rollbackUninstallObserved=$false
        $NativeDesktopRehearsal=($case -ne 'ordinary-success');$NativeX64Rehearsal=$false;$NoLaunch=$false;$Quiet=$true
        $preinstallStarted=$true;$registrationStarted=$true;$previousRoots=@($script:oldRoot);$previousRoot=$script:oldRoot
        $previousConfigText=@{install_root=$script:oldRoot}|ConvertTo-Json -Compress;$runtimeConfig=@{install_root=$targetRoot}
        $previousRunSnapshot=@{};$previousUninstallSnapshot=@{};$previousLegacyUninstallSnapshot=@{};$previousUserTipSnapshot=@{}
        $previousRuntimeWasRunning=$true;$migrationLegacyUserTipSnapshot=@{};$preinstall=@{};$productName='synthetic'
        $userTipKey='fixture-user-tip';$runKey='fixture-run';$productKeyName='fixture-product';$uninstallKey='fixture-uninstall';$legacyMachineUninstallKey='fixture-legacy-uninstall'
        $utf8NoBom=New-Object Text.UTF8Encoding($false);$caught=$null
        try{if($case -eq 'old-unguarded-lease'){. $unguarded}else{. $commit}}catch{$caught=$_.Exception.Message}
        if($case -in @('injected-failure','unexpected-success')){
            Check ($null -ne $caught) "$case propagates the transaction failure"
            if($case -eq 'unexpected-success'){Check ($caught -like '*NativeDesktop failure-only rehearsal unexpectedly started*') 'unexpected success hits explicit terminal guard'}
            Check ((Test-Path -LiteralPath $script:oldRoot) -and $script:removed -notcontains $script:oldRoot) "$case preserves old root without deletion attempt"
            Check ([YimeCoreRehearsalFixture.NativeFile]::Deferred.Count -eq 0) "$case never queues reboot deletion"
            Check ($script:rollbackUninstallObserved -and -not (Test-Path -LiteralPath $targetRoot)) "$case removes failed target via existing rollback catch"
            Check (($script:restoredArchitectures -join '|') -ceq 'rollback x64 TSF registration|rollback x86 TSF registration') "$case restores both architecture registrations"
            Check ($script:restoredRegistry.Count -eq 4 -and $script:oldRuntimeRestored -and $script:finallyObserved) "$case restores snapshots, old runtime and final protection"
        }elseif($case -eq 'ordinary-success'){
            Check ($null -eq $caught -and -not(Test-Path -LiteralPath $script:oldRoot) -and -not $script:oldRuntimeRestored) 'ordinary upgrade success still commits normally'
        }else{
            Check ($null -eq $caught -and [YimeCoreRehearsalFixture.NativeFile]::Deferred.Count -gt 0) 'red counterexample: old-root lease alone still permits queued reboot deletion'
        }
    }
    Check (('YimeCoreTrial.NativeFile' -as [type]) -eq $productNativeTypeBefore) 'test leaves product native helper type unchanged'
    $result=[ordered]@{schema_version='yimecore-native-desktop-rehearsal-test-v1';passed=$true;powershell_version=$PSVersionTable.PSVersion.ToString();
        controller_source_sha256=(Get-FileHash -LiteralPath $controller -Algorithm SHA256).Hash.ToLowerInvariant();checks_passed=$checks.Count;checks=$checks.ToArray();
        synthetic_transaction_only=$true;actual_controller_invoked=$false;registry_mutated=$false;native_reboot_deletion_called=$false;
        installer_executed=$false;product_executed=$false;installed_local12_changed=$false;actual_native_rehearsal_passed=$false}
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'yimecore-desktop-rehearsal-*'){throw 'Unsafe fixture cleanup root.'}
    if(Test-Path -LiteralPath $resolved){Microsoft.PowerShell.Management\Remove-Item -LiteralPath $resolved -Recurse -Force}
}
if($OutputPath){$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8}
Write-Host ('PASS: NativeDesktop rehearsal '+$checks.Count+' synthetic contracts; no native maintenance executed.')
