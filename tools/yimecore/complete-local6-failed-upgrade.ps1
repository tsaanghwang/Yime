[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
$evidence='C:\Users\tsaan\YimeCore Recovery Archives\local6-failed-upgrade-rollback-20260903-110721-19d95018'
$installedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'
$failureManifest='bbde69c4453a07c7cf915d641cd648f88ac8376fda0027881d857454344e1b07'
$backupManifestHash='7d474b4ac32b47d68ee714e1613a2fbf756423acc8d1d67298b015cc4e435b12'
$expectedValidator='8f560a009bfead4a3bd8ca736d8b4008e0e0da32a350aeaf0a7fa0f1ad0addb4'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$failurePackage='C:\dev\Yime\.tmp\yimecore-experiment\local6-failure-runtime-rc1'
$failureTarget='C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-4bfa828009d1-bbde69c4'
$backup='C:\Users\tsaan\YimeCore Recovery Archives\local6-backup-restore-20260903-110006-133432a3'
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
if(-not $Execute){[ordered]@{action='complete-local6-failed-upgrade-postacceptance';evidence=$evidence;writes='corrected evidence only';repeats_failure=$false;reboot_requested=$false}|ConvertTo-Json;exit 0}
$installedConfig=Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
$installed=[IO.Path]::GetFullPath([string]$installedConfig.install_root).TrimEnd('\')
if((Get-FileHash -LiteralPath (Join-Path $installed 'package-manifest.json')).Hash -ine $installedManifest){throw 'Current install is not the expected restored local.6 package.'}
$manifest=Get-Content -LiteralPath (Join-Path $installed 'package-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')){
    $path=Join-Path $installed "maintenance\$name"
    $record=@($manifest.files|Where-Object{$_.path -ceq "maintenance/$name"})
    if($record.Count -ne 1 -or (Get-FileHash -LiteralPath $path).Hash -ine $record[0].sha256){throw "Installed helper mismatch: $name"}
    . $path
}
Assert-YimeCoreUnpackagedDataMaintenance
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $expectedSid){throw 'Use the Windows account that ran the rollback rehearsal.'}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use normal File Explorer double-click, not Run as administrator.'}
if((Get-FileHash -LiteralPath (Join-Path $failurePackage 'package-manifest.json')).Hash -ine $failureManifest){throw 'Failure package changed after rehearsal.'}
if((Get-FileHash -LiteralPath (Join-Path $backup 'backup-manifest.json')).Hash -ine $backupManifestHash){throw 'Independent recovery archive changed after rehearsal.'}
$original=Get-Content -LiteralPath (Join-Path $evidence 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($original.passed -or $original.stage -cne 'trigger-failed-upgrade' -or [int]$original.failure_installer_exit_code -eq 0){throw 'Original failed-upgrade evidence is not the reviewed false-negative result.'}
if(Test-Path -LiteralPath (Join-Path $evidence 'corrected-postacceptance.json')){throw 'Corrected postacceptance already exists.'}
$evidenceItem=Get-Item -LiteralPath $evidence
$maintenanceErrorPath=Join-Path $state 'maintenance-last-error.txt'
$maintenanceErrorItem=Get-Item -LiteralPath $maintenanceErrorPath
$maintenanceErrorText=Get-Content -LiteralPath $maintenanceErrorPath -Raw -Encoding UTF8
if($maintenanceErrorItem.LastWriteTimeUtc -lt $evidenceItem.CreationTimeUtc -or
    $maintenanceErrorText -notmatch 'trial runtime did not become ready' -or
    $maintenanceErrorText -notmatch [regex]::Escape($failurePackage)){throw 'Authoritative maintenance error does not match this failed-upgrade run.'}

$validator=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
if((Get-FileHash -LiteralPath $validator).Hash -ine $expectedValidator){throw 'Read-only registry validator changed.'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($validator,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-CutoverRegistrySnapshot'},$true)
if(-not $fn){throw 'Missing read-only registry snapshot helper.'}
. ([scriptblock]::Create($fn.Extent.Text))
function Same($Left,$Right){return (($Left|ConvertTo-Json -Depth 40 -Compress) -ceq ($Right|ConvertTo-Json -Depth 40 -Compress))}
function Write-Evidence($Value,[string]$Name){$Value|ConvertTo-Json -Depth 40|Set-Content -LiteralPath (Join-Path $evidence $Name) -Encoding UTF8}
$beforeRegistry=Get-Content -LiteralPath (Join-Path $evidence 'system-before.json') -Raw -Encoding UTF8|ConvertFrom-Json
$afterRegistry=Get-CutoverRegistrySnapshot
if(-not (Same $beforeRegistry $afterRegistry)){throw 'Complete registry snapshot was not restored.'}
# Windows PowerShell 5.1 preserves a top-level JSON array as one pipeline
# object inside @(...). Assign first, then enumerate it explicitly so the
# immutable evidence and the live six-record inventory have the same shape.
$beforeData=Get-Content -LiteralPath (Join-Path $evidence 'data-before.json') -Raw -Encoding UTF8|ConvertFrom-Json
$beforeData=@($beforeData)
$afterData=@(Get-YimeCoreDataRecords $state)
Assert-YimeCoreUnchangedData $beforeData $afterData
if(Test-Path -LiteralPath $failureTarget){throw 'Failure target root still exists.'}
if(-not (Test-Path -LiteralPath (Join-Path $backup 'previous-package\package-manifest.json'))){throw 'Independent recovery package is missing.'}
$context=Assert-LocalProductInstalledContext $installed $state
$live=Assert-LocalProductLiveRuntime $context
& (Join-Path $installed 'bin\YimeCoreIndependenceAudit.exe') -package $installed -output (Join-Path $evidence 'restored-package-audit.json')
if($LASTEXITCODE -ne 0){throw 'Restored local.6 package audit failed.'}
Copy-Item -LiteralPath $maintenanceErrorPath -Destination (Join-Path $evidence 'installer-maintenance-last-error.txt')
Write-Evidence $afterRegistry 'system-after-corrected.json'
Write-Evidence $afterData 'data-after-corrected.json'
Write-Evidence $live 'live-after-corrected.json'
$result=[ordered]@{schema_version='yimecore-local6-failed-upgrade-corrected-postacceptance-v1';passed=$true;
    original_summary_preserved='summary.json';original_false_negative_reason='UAC child did not forward error text to parent stdout or stderr';
    failure_installer_exit_code=[int]$original.failure_installer_exit_code;authoritative_startup_failure_correlated=$true;
    package_identity_restored=$true;user_data_preserved=$true;complete_registry_restored=$true;ordinary_runtime_restored=$true;
    independent_recovery_archive_preserved=$true;failure_target_root_absent=$true;failure_not_repeated=$true;
    default_input_method_changed=$false;production_components_changed=$false;reboot_requested=$false;
    local_product_ready=$false;public_release_ready=$false}
Write-Evidence $result 'corrected-postacceptance.json'
Write-Host "PASS: existing local.6 failed-upgrade rollback independently verified without repeating failure. Evidence: $evidence"
