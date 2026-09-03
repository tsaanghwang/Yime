[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
. (Join-Path $PSScriptRoot 'local-package-contract.ps1')
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
Assert-LocalProductPlainPath $OutputRoot
if(Test-Path -LiteralPath $OutputRoot){throw 'Use a new package-test output directory.'}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed $Name}
$package=Assert-LocalProductPackage $PackageRoot
Check ($package.audit.passed -and $package.descriptor.installable) 'complete installable x64 contract passes without registry writes'
$nativePS=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$entry=Join-Path $PackageRoot 'maintenance\manage-local-product.ps1'
$planText=(& $nativePS -NoProfile -ExecutionPolicy Bypass -File $entry -Action Plan) -join "`n"
if($LASTEXITCODE -ne 0){throw "Package-local Plan failed: $planText"}
$plan=$planText|ConvertFrom-Json
Check ($plan.active_registration_architectures.Count -eq 1 -and $plan.active_registration_architectures[0] -eq 'x64') 'packaged manager plans only native x64'
Check ($plan.standard_user_launcher_package_ready -and -not $plan.arm64_tsf_artifacts_required) 'new contract has a pinned standard-user helper and no frozen payload requirement'
Check ($plan.product_name -eq $package.descriptor.display_name) 'installed-app name comes from validated canonical product identity'
Check (-not $plan.production_rime_pime_changed -and $plan.user_model_preserved_on_reinstall) 'production and user-data preservation remain in packaged plan'
Write-LocalProductJson $plan (Join-Path $OutputRoot 'packaged-plan.json')

# Test the actual CMD entry, not only powershell.exe -File. PS7 -> CMD -> PS5
# inherits a different PSModulePath than a direct PS7 -> powershell.exe call.
$relocated=Join-Path ([IO.Path]::GetTempPath()) ('Yime Local Maintenance '+[guid]::NewGuid().ToString('N'))
Assert-YimeCorePlainPath $relocated
New-Item -ItemType Directory -Path $relocated | Out-Null
Copy-Item -LiteralPath $PackageRoot -Destination (Join-Path $relocated 'package') -Recurse
$environmentBefore=$env:PSModulePath
Push-Location $env:SystemRoot
try {
    $cmdText=(& (Join-Path $relocated 'package\Maintain-YimeCore-Local.cmd')) -join "`n"
    if($LASTEXITCODE -ne 0){throw "Relocated CMD Plan failed: $cmdText"}
    $cmdPlan=$cmdText|ConvertFrom-Json
    Check ($cmdPlan.standard_user_launcher_package_ready -and $cmdPlan.package_root -eq (Join-Path $relocated 'package')) 'real CMD Plan works outside repository with spaces and unrelated working directory'
    Check ($env:PSModulePath -ceq $environmentBefore) 'native child module scope does not change calling environment'
    Write-LocalProductJson ([ordered]@{passed=$true;relocated_root=$relocated;plan=$cmdPlan;mutation_requested=$false}) (Join-Path $OutputRoot 'relocated-cmd-plan.json')
} finally { Pop-Location }

# Do not execute a mutating action as a test. Parse each packaged script and
# verify the front-door guard precedes dispatch; the existing ancestry fixture
# suite separately executes positive/negative guard branches with mocked CIM.
foreach($record in $package.manifest.files|Where-Object{$_.path -like '*.ps1'}) {
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PackageRoot $record.path),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "packaged PowerShell parses: $($record.path)"
}
$entryText=Get-Content -LiteralPath $entry -Raw -Encoding UTF8
Check ($entryText.IndexOf("if (`$Action -ne 'Plan') { Assert-YimeCoreUnpackagedDataMaintenance }") -lt $entryText.IndexOf('$package=Assert-LocalProductPackage')) 'native context required before non-Plan dispatch or data access'
Check ($entryText.Contains('-TargetUserSid $sid -NativeX64Only')) 'package entry forwards same SID and native-only mode'
$installCmdText=Get-Content -LiteralPath (Join-Path $PackageRoot 'Install-YimeCore-Local.cmd') -Raw -Encoding UTF8
Check ($installCmdText.Contains('PASS: YimeCore local product install or upgrade completed.') -and
    $installCmdText.Contains('BLOCKED: YimeCore local product install or upgrade failed.') -and
    $installCmdText.Contains('if /I not "%~1"=="/nopause" pause')) `
    'interactive install entry preserves a visible result while scripted callers can suppress pause'
foreach($script in @('backup-local-trial-state.ps1','restore-local-trial-state.ps1')) {
    $text=Get-Content -LiteralPath (Join-Path $PackageRoot "maintenance\$script") -Raw -Encoding UTF8
    Check ($text.Contains('Start-LocalProductRuntime $localContext') -and $text.Contains('Assert-LocalProductLiveRuntime $localContext')) "standard-user preflight/restart wired into $script"
}
$backupText=Get-Content -LiteralPath (Join-Path $PackageRoot 'maintenance\backup-local-trial-state.ps1') -Raw -Encoding UTF8
Check ($backupText.Contains('$localProductBackup = [bool]($LocalProduct -or') -and
    $backupText.Contains("Join-Path `$localContext.package.root 'maintenance\stop-e6c-trial-runtime.ps1'")) `
    'upgrade backup uses the manifest-verified currently installed stop helper'

# Exact archive inventory tests use disposable files only, never real AppData.
$archive=Join-Path $OutputRoot 'archive-fixture'
New-Item -ItemType Directory -Path $archive | Out-Null
$file=Join-Path $archive 'user-model.journal'
[IO.File]::WriteAllText($file,('{"text":"'+(-join [char[]](0x5B83,0x4EEC))+'"}'),[Text.UTF8Encoding]::new($false))
$records=@([ordered]@{path='user-model.journal';bytes=(Get-Item -LiteralPath $file).Length;sha256=(Get-FileHash -LiteralPath $file).Hash})
Assert-YimeCoreArchiveRecords $archive $records
Check $true 'UTF-8 archive hash and exact inventory accepted'
Reject {Assert-YimeCoreArchiveRecords $archive @($records[0],$records[0])} 'duplicate archive paths rejected'
foreach($path in @('../outside','/absolute','x//y','x\y','x:ads','x.','x ')) {
    $bad=[ordered]@{path=$path;bytes=1;sha256=('a'*64)}
    Reject {Assert-YimeCoreArchiveRecords $archive @($bad)} "unsafe archive path rejected: $path"
}
$extra=Join-Path $archive 'unlisted.txt'
[IO.File]::WriteAllText($extra,'unlisted')
Reject {Assert-YimeCoreArchiveRecords $archive $records} 'unlisted archive content rejected before clone or restore'
$missing=[ordered]@{path='missing';bytes=1;sha256=('a'*64)}
Reject {Assert-YimeCoreArchiveRecords $archive @($records[0],$missing)} 'missing listed archive content rejected'
$restoreText=Get-Content -LiteralPath (Join-Path $PackageRoot 'maintenance\restore-local-trial-state.ps1') -Raw -Encoding UTF8
Check ($restoreText.IndexOf('Assert-YimeCoreArchiveRecords') -lt $restoreText.IndexOf('$cloneRoot=')) 'archive validation precedes recovery clone writes'
Check ($restoreText.Contains('Assert-YimeCoreUnchangedData $manifest.data_files @(Get-YimeCoreDataRecords $archiveState)')) 'archive data-category list is derived and compared before restore'

$summary=[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);powershell=$PSVersionTable.PSVersion.ToString();
    actual_install_or_restore_executed=$false;actual_elevated_to_medium_launch_tested=$false;
    package_manifest_sha256=$package.manifest_sha256}
Write-LocalProductJson $summary (Join-Path $OutputRoot 'summary.json')
Write-Output "PASS: $($checks.Count) package-local maintenance contracts. Evidence: $OutputRoot"
