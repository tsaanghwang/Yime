[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageRoot,
    [Parameter(Mandatory)][string]$ReportPath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=[IO.Path]::GetFullPath($PackageRoot)
$report=[IO.Path]::GetFullPath($ReportPath)
if(Test-Path -LiteralPath $report){throw 'Preserve prior package-validation evidence.'}
Import-Module (Join-Path $root 'Product.psm1') -Force
$package=Read-Package $root
if($package.manifest.product -cne 'yimecore'){throw 'Expected the standalone YimeCore package.'}
if($package.manifest.version -cne '0.1.0-local.13-registration-fix-20260929'){throw 'Expected the distinct registration-fix package version.'}
if(@($package.manifest.files).Count -ne 65){throw 'Expected the complete 65-file YimeCore payload.'}
$result=[ordered]@{
    schema_version='yimecore-registration-fix-read-package-v1'
    passed=$true
    package_root=$root
    product=$package.manifest.product
    version=$package.manifest.version
    payload_files=@($package.manifest.files).Count
    product_manifest_sha256=(Get-ContentHash (Join-Path $root 'product-package.json'))
    powershell_version=$PSVersionTable.PSVersion.ToString()
    package_only=$true
    setup_executed=$false
    registration_executed=$false
    installed_product_mutated=$false
}
[IO.File]::WriteAllText($report,($result|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output ('PASS: complete standalone YimeCore package read-only validation; '+$report)
