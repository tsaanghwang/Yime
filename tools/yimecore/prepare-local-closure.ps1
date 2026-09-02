[CmdletBinding()]
param([string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
$scope=Get-YimeCoreDevelopmentScope
Assert-YimeCoreNativeGo
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if(-not $OutputRoot){$OutputRoot=Join-Path $repo '.tmp\yimecore-experiment\native-closure-ready'}
$root=[IO.Path]::GetFullPath($OutputRoot)
if(-not $root.StartsWith((Join-Path $repo '.tmp\yimecore-experiment\'),[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $root)){throw 'Preparation requires a new experiment directory.'}
Assert-YimeCorePlainPath $root
$stateRoot=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$config=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $stateRoot 'runtime-config.json') -Raw|ConvertFrom-Json
$source=[string]$config.install_root
New-Item -ItemType Directory -Path $root|Out-Null
& (Join-Path $PSScriptRoot 'prepare-local-rollback-package.ps1') -SourcePackage $source -OutputRoot (Join-Path $root 'failure-package')
$probe=Join-Path $root 'ModelRecoveryProbe.exe'
Push-Location (Join-Path $repo 'go-backend')
try{& go build -trimpath -o $probe (Join-Path $PSScriptRoot 'model-recovery-probe.go');if($LASTEXITCODE -ne 0){throw 'Recovery probe build failed'}}finally{Pop-Location}
$inputs=@()
foreach($name in @('complete-local-trial-closure.ps1','backup-local-trial-state.ps1','restore-local-trial-state.ps1',
    'invoke-local-rollback-rehearsal.ps1','capture-local-maintenance-state.ps1','local-maintenance-safety.ps1',
    'development-scope.ps1','development-scope.json','manage-e6c-trial-install.ps1','stop-e6c-trial-runtime.ps1',
    'start-e6c-trial-runtime.ps1','verify-e6c-trial-runtime.ps1','repair-e6c-trial-autostart.ps1','repair-e6c-system-uninstall.ps1',
    'test-local-maintenance-encoding.ps1')) {
    $path=Join-Path $PSScriptRoot $name
    $inputs+=@([ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()})
}
$faultManifest=Join-Path $root 'failure-package\package-manifest.json'
$plan=[ordered]@{schema_version='yimecore-native-closure-plan-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');
    sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;development_scope=$scope;
    state_root=$stateRoot;source_install_root=$source;source_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $source 'package-manifest.json')).Hash;
    recovery_probe=$probe;recovery_probe_sha256=(Get-FileHash -LiteralPath $probe).Hash;
    failure_package=(Split-Path -Parent $faultManifest);failure_manifest_sha256=(Get-FileHash -LiteralPath $faultManifest).Hash;
    inputs=$inputs;frozen_payloads='copied from manifest-verified installed package without rebuilding or executing';
    live_mutations_performed=$false}
$plan|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $root 'plan.json') -Encoding utf8
Write-Host "Prepared native-context closure inputs only: $root"
