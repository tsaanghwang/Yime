[CmdletBinding()]
param([string]$FailurePackage)
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1'
$source=Get-Content -LiteralPath $path -Raw
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Get-RegistrationArchitectures','Get-PackageRecords','Assert-Package')) {
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $fn){throw "Missing function $name"}
    . ([scriptblock]::Create($fn.Extent.Text))
}
$nativeArchitecture='AMD64';$NativeX64Rehearsal=$true
$architectures=@(Get-RegistrationArchitectures)
if($architectures.Count -ne 1 -or $architectures[0].name -ne 'x64'){throw 'Frozen executables would be invoked by rehearsal.'}
$NativeX64Rehearsal=$false
if(@(Get-RegistrationArchitectures).Count -ne 2){throw 'Historical general installer behavior was changed.'}
if($source -notmatch '\$NativeX64Rehearsal -and \$registryPath -like'){throw 'Frozen per-user COM cleanup not guarded.'}
$terminal=$source.IndexOf("if (`$NativeX64Rehearsal) { throw 'Failure-only rehearsal unexpectedly started")
if($terminal -lt 0 -or $terminal -gt $source.IndexOf('    foreach ($oldRoot in $previousRoots)')){throw 'Rehearsal could delete old roots if the fault did not fire.'}
if($source -notmatch '-not \$package.manifest.rehearsal_only'){throw 'Rehearsal must reject normal packages.'}
if($FailurePackage) {
    $package=Assert-Package $FailurePackage
    if(-not $package.manifest.rehearsal_only){throw 'Missing fault-package marker.'}
    $managerHash=(Get-FileHash -LiteralPath (Join-Path $FailurePackage 'maintenance\Manage-YimeCoreTrial.ps1')).Hash
    if($managerHash -ne (Get-FileHash -LiteralPath $path).Hash){throw 'Staging would replace manager with unmanifested bytes.'}
    foreach($record in $package.manifest.frozen_payload_provenance.copied_unchanged){
        if((Get-FileHash -LiteralPath (Join-Path $FailurePackage $record.path)).Hash -ne $record.sha256){throw 'Frozen payload differs from provenance.'}
    }
    Write-Host 'Prepared failure-package full manifest, current staged manager and frozen byte provenance passed.'
}
Write-Host 'Native x64 rehearsal guards: 5 cases passed; no registration tools executed.'
