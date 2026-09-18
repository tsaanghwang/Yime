[CmdletBinding()]
param([Parameter(Mandatory)][string]$BundleDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..\..'))
Import-Module (Join-Path $repo 'installer\simple\Product.psm1') -Force
# Read-Package reads paths, required resources, manifest sizes and hashes only.
# Never call Setup, registration, startup or installed-product maintenance here.
$results=@(foreach($id in @('yimecore','rime-pime')){
    $package=Read-Package (Join-Path $BundleDirectory $id)
    if($package.product.id -cne $id){throw ('Unexpected product identity: '+$id)}
    [pscustomobject]@{
        product=$id
        version=$package.manifest.version
        file_count=@($package.manifest.files).Count
        passed=$true
    }
})
[pscustomobject]@{
    passed=$true
    products=$results
    setup_executed=$false
    product_executables_executed=$false
    registry_or_user_data_modified=$false
}|ConvertTo-Json -Depth 5
