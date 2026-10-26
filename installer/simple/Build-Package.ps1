[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('yimecore','rime-pime')][string]$Product,
    [Parameter(Mandatory)][string]$PayloadRoot,[Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$Version,
    [ValidateSet('windows-amd64','windows-arm64')][string]$Target='windows-amd64')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Product.psm1') -Force
$source=Assert-PlainPath $PayloadRoot;$output=Assert-PlainPath $OutputRoot
if(Test-Path -LiteralPath $output){throw 'Choose a new output directory'}
if($output.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be outside the source'}
$productInfo=Get-Product $Product
if($Target -ceq 'windows-arm64' -and $Product -cne 'yimecore'){throw 'Rime/PIME ARM64 packaging is not supported'}
if($Product -eq 'yimecore'){
    $descriptor=Get-Content -LiteralPath (Join-Path $source 'local-product.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($descriptor.identity.clsid -ine $productInfo.clsid -or $descriptor.identity.profile -ine $productInfo.profile){throw 'Use current-identity YimeCore artifacts, not the legacy trial'}
}
# Only application resources. Old installer/recovery directories are not shipped.
$allowed=if($Product -eq 'yimecore'){@('bin','data','indexes','x64','x86','help','professional-lexicons','speech','speech-capability.json','local-product.json','profile-icon.ico')}else{@('PIMELauncher.exe','backends.json','version.txt','go-backend','x64','x86','licenses')}
if($Target -ceq 'windows-arm64'){
    if(Test-Path -LiteralPath (Join-Path $source 'x64')){throw 'ARM64 packages must not contain a separate x64 COM payload'}
    $allowed=@($allowed | Where-Object {$_ -cne 'x64'})+@('arm64','build','package-manifest.json')
}elseif(Test-Path -LiteralPath (Join-Path $source 'arm64')){throw 'ARM64 payload requires an explicit windows-arm64 target'}
$payload=Join-Path $output 'payload';$null=[IO.Directory]::CreateDirectory($payload)
$files=@(foreach($file in Get-ProductFiles $source){
    $relative=$file.FullName.Substring($source.Length+1).Replace('\','/')
    if($relative.Split('/')[0] -cnotin $allowed){continue}
    $targetPath=Join-Path $payload $relative
    $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($targetPath))
    [IO.File]::Copy($file.FullName,$targetPath,$false)
    [ordered]@{path=$relative;bytes=$file.Length;sha256=(Get-ContentHash $targetPath)}
})
$manifest=[ordered]@{format='yime-simple-package-1';product=$Product;version=$Version;files=$files}
if($Target -ceq 'windows-arm64'){
    $manifest.format='yime-simple-package-2';$manifest.target=$Target
    $manifest.host_architecture='arm64';$manifest.tsf64_architecture='arm64x'
}
[IO.File]::WriteAllText((Join-Path $output 'product-package.json'),($manifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
foreach($name in @('Product.psm1','Setup.ps1','Setup.cmd')){[IO.File]::Copy((Join-Path $PSScriptRoot $name),(Join-Path $output $name),$false)}
$null=Read-Package $output
Write-Output ('Package ready: '+$output)
