[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
$installedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'
$failureManifest='bbde69c4453a07c7cf915d641cd648f88ac8376fda0027881d857454344e1b07'
$failureRuntime='c109d17a918d26f19146ec6ae93e97515cb2e55f8771a52f0bb9f227df0c24ac'
$backupManifestHash='7d474b4ac32b47d68ee714e1613a2fbf756423acc8d1d67298b015cc4e435b12'
$expectedValidator='8f560a009bfead4a3bd8ca736d8b4008e0e0da32a350aeaf0a7fa0f1ad0addb4'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$failurePackage='C:\dev\Yime\.tmp\yimecore-experiment\local6-failure-runtime-rc1'
$backup='C:\Users\tsaan\YimeCore Recovery Archives\local6-backup-restore-20260903-110006-133432a3'
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$config=Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
$installed=[IO.Path]::GetFullPath([string]$config.install_root).TrimEnd('\')
if((Get-FileHash -LiteralPath (Join-Path $installed 'package-manifest.json')).Hash -ine $installedManifest){throw 'Current install is not the reviewed local.6 baseline.'}
if((Get-FileHash -LiteralPath (Join-Path $failurePackage 'package-manifest.json')).Hash -ine $failureManifest){throw 'Failure-only package changed.'}
if((Get-FileHash -LiteralPath (Join-Path $failurePackage 'bin\YimeCoreTrialRuntime.exe')).Hash -ine $failureRuntime){throw 'Failure runtime changed.'}
if((Get-FileHash -LiteralPath (Join-Path $backup 'backup-manifest.json')).Hash -ine $backupManifestHash){throw 'Recovery archive changed.'}
$manifest=Get-Content -LiteralPath (Join-Path $installed 'package-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')){
    $path=Join-Path $installed "maintenance\$name"
    $record=@($manifest.files|Where-Object{$_.path -ceq "maintenance/$name"})
    if($record.Count -ne 1 -or (Get-FileHash -LiteralPath $path).Hash -ine $record[0].sha256){throw "Installed helper mismatch: $name"}
    . $path
}
$currentPackage=Assert-LocalProductPackage $installed
$faultPackage=Assert-LocalProductPackage $failurePackage
if(-not $faultPackage.manifest.rehearsal_only){throw 'Failure-only marker is missing.'}
$failurePlanText=(& (Join-Path $failurePackage 'Maintain-YimeCore-Local.cmd') -Action Plan) -join "`n"
if($LASTEXITCODE -ne 0){throw "Failure package Plan failed: $failurePlanText"}
$failurePlan=$failurePlanText|ConvertFrom-Json
if([string]$failurePlan.install_root -cne 'C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-4bfa828009d1-bbde69c4'){throw 'Unexpected failure-package target root.'}
$plan=[ordered]@{action='local6-failed-upgrade-rollback';installed_root=$installed;installed_manifest_sha256=$installedManifest;
    failure_package=$failurePackage;failure_manifest_sha256=$failureManifest;failure_runtime_exit=86;recovery_archive=$backup;
    expected_result='upgrade fails and exact local.6 install, data, registration and ordinary runtime are restored';reboot_requested=$false}
if(-not $Execute){$plan|ConvertTo-Json -Depth 6;exit 0}
Assert-YimeCoreUnpackagedDataMaintenance
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $expectedSid){throw 'Use the Windows account that owns local.6.'}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use normal File Explorer double-click, not Run as administrator.'}
if(Get-Process WINWORD,Notepad -ErrorAction SilentlyContinue){throw 'Close Word and Notepad before rollback acceptance.'}
$context=Assert-LocalProductInstalledContext $installed $state
$liveBefore=Assert-LocalProductLiveRuntime $context
$backupManifest=Get-Content -LiteralPath (Join-Path $backup 'backup-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert-YimeCoreUnchangedData $backupManifest.data_files @(Get-YimeCoreDataRecords $state)
if(Test-Path -LiteralPath ([string]$failurePlan.install_root)){throw 'Failure target root is occupied; preserve it and re-plan.'}

$validator=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
if((Get-FileHash -LiteralPath $validator).Hash -ine $expectedValidator){throw 'Read-only registry validator changed; review before rollback acceptance.'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($validator,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-CutoverRegistrySnapshot'},$true)
if(-not $fn){throw 'Missing read-only registry snapshot helper.'}
. ([scriptblock]::Create($fn.Extent.Text))
function Write-Evidence($Value,[string]$Path){$Value|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $Path -Encoding UTF8}
function Same($Left,$Right){return (($Left|ConvertTo-Json -Depth 40 -Compress) -ceq ($Right|ConvertTo-Json -Depth 40 -Compress))}
function Get-ExceptionEvidence([Exception]$Exception){
    $result=@();$current=$Exception
    while($current){
        $nativeCode=$null
        if($current -is [ComponentModel.Win32Exception]){$nativeCode=$current.NativeErrorCode}
        $result+=[ordered]@{type=$current.GetType().FullName;message=$current.Message;hresult=$current.HResult;native_error_code=$nativeCode}
        $current=$current.InnerException
    }
    return $result
}
$evidence=Join-Path $env:USERPROFILE ('YimeCore Recovery Archives\local6-failed-upgrade-rollback-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
Assert-YimeCorePlainPath $evidence
New-Item -ItemType Directory -Path $evidence|Out-Null
$stage='capture-before';$passed=$false;$failureTriggered=$false;$failure=$null;$installerExit=$null
try{
    $beforeRegistry=Get-CutoverRegistrySnapshot
    $beforeData=@(Get-YimeCoreDataRecords $state)
    Write-Evidence $plan (Join-Path $evidence 'plan.json')
    Write-Evidence $beforeRegistry (Join-Path $evidence 'system-before.json')
    Write-Evidence $beforeData (Join-Path $evidence 'data-before.json')
    Write-Evidence $liveBefore (Join-Path $evidence 'live-before.json')
    $stage='trigger-failed-upgrade'
    $attemptStartedUtc=[DateTime]::UtcNow
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $failurePackage 'maintenance\manage-local-product.ps1')+'" -Action Upgrade'
    $process=[Diagnostics.Process]::new()
    $process.StartInfo.FileName=$ps;$process.StartInfo.Arguments=$arguments;$process.StartInfo.UseShellExecute=$false;$process.StartInfo.CreateNoWindow=$true
    $process.StartInfo.RedirectStandardOutput=$true;$process.StartInfo.RedirectStandardError=$true
    try{
        if(-not $process.Start()){throw 'Failure installer process did not start.'}
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();$process.WaitForExit();$installerExit=$process.ExitCode
        $stdoutText=$stdout.GetAwaiter().GetResult();$stderrText=$stderr.GetAwaiter().GetResult()
    }finally{$process.Dispose()}
    $stdoutText|Set-Content -LiteralPath (Join-Path $evidence 'failed-upgrade-stdout.txt') -Encoding UTF8
    $stderrText|Set-Content -LiteralPath (Join-Path $evidence 'failed-upgrade-stderr.txt') -Encoding UTF8
    $maintenanceErrorPath=Join-Path $state 'maintenance-last-error.txt'
    $maintenanceErrorText='';$maintenanceErrorCurrent=$false
    if(Test-Path -LiteralPath $maintenanceErrorPath){
        $maintenanceErrorItem=Get-Item -LiteralPath $maintenanceErrorPath
        $maintenanceErrorText=Get-Content -LiteralPath $maintenanceErrorPath -Raw -Encoding UTF8
        Copy-Item -LiteralPath $maintenanceErrorPath -Destination (Join-Path $evidence 'installer-maintenance-last-error.txt')
        $maintenanceErrorCurrent=($maintenanceErrorItem.LastWriteTimeUtc -ge $attemptStartedUtc -and
            $maintenanceErrorText -match 'trial runtime did not become ready' -and $maintenanceErrorText -match [regex]::Escape($failurePackage))
    }
    if($installerExit -eq 0 -or -not $maintenanceErrorCurrent){throw 'Expected failure runtime did not produce a current authoritative maintenance error.'}
    $failureTriggered=$true
    $stage='verify-rollback'
    $afterConfig=Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if([IO.Path]::GetFullPath([string]$afterConfig.install_root).TrimEnd('\') -cne $installed){throw 'Rollback did not restore the local.6 install root.'}
    if((Get-FileHash -LiteralPath (Join-Path $installed 'package-manifest.json')).Hash -ine $installedManifest){throw 'Rollback did not restore the local.6 package identity.'}
    $afterRegistry=Get-CutoverRegistrySnapshot
    $afterData=@(Get-YimeCoreDataRecords $state)
    Write-Evidence $afterRegistry (Join-Path $evidence 'system-after.json')
    Write-Evidence $afterData (Join-Path $evidence 'data-after.json')
    if(-not (Same $beforeRegistry $afterRegistry)){throw 'Rollback did not restore the complete registry snapshot.'}
    Assert-YimeCoreUnchangedData $beforeData $afterData
    $afterContext=Assert-LocalProductInstalledContext $installed $state
    $liveAfter=Assert-LocalProductLiveRuntime $afterContext
    Write-Evidence $liveAfter (Join-Path $evidence 'live-after.json')
    & (Join-Path $installed 'Maintain-YimeCore-Local.cmd') -Action Verify
    if($LASTEXITCODE -ne 0){throw 'Restored local.6 three-mode verification failed.'}
    if(-not (Test-Path -LiteralPath (Join-Path $backup 'previous-package\package-manifest.json'))){throw 'Independent recovery archive was not preserved.'}
    $passed=$true;$stage='local6-failed-upgrade-rollback-accepted'
}catch{
    $failure=[ordered]@{stage=$stage;message=$_.Exception.Message;type=$_.Exception.GetType().FullName;stack=$_.ScriptStackTrace;
        exception_chain=@(Get-ExceptionEvidence $_.Exception)}
    Write-Evidence $failure (Join-Path $evidence 'failure.json')
}
Write-Evidence ([ordered]@{schema_version='yimecore-local6-failed-upgrade-rollback-v1';passed=$passed;stage=$stage;failure=$failure;
    failure_installer_exit_code=$installerExit;failure_was_triggered=$failureTriggered;maintenance_error_correlated=$failureTriggered;installed_manifest_sha256=$installedManifest;
    package_identity_restored=$passed;user_data_preserved=$passed;complete_registry_restored=$passed;ordinary_runtime_restored=$passed;
    independent_recovery_archive_preserved=$passed;failure_target_root_absent=(-not (Test-Path -LiteralPath ([string]$failurePlan.install_root)));
    default_input_method_changed=$false;production_components_changed=$false;reboot_requested=$false;
    local_product_ready=$false;public_release_ready=$false}) (Join-Path $evidence 'summary.json')
if(-not $passed){Write-Host "BLOCKED: $stage; $($failure.message) Evidence: $evidence";exit 1}
Write-Host "PASS: local.6 failed upgrade triggered and exact package, data, registry and ordinary runtime rollback verified. Evidence: $evidence"
