$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Product.psm1') -Force
function Contract([string]$target,[string]$hostArch,[string]$tsfArch) {
    [pscustomobject]@{product='yimecore-18u';format='yime-simple-package-18u-1';target=$target;host_architecture=$hostArch;tsf64_architecture=$tsfArch}
}
function MustReject($manifest) {
    $rejected=$false
    try { $null=Get-PackageContract $manifest } catch { $rejected=$true }
    if(-not $rejected){throw 'Invalid architecture tuple accepted'}
}
$x64=Get-PackageContract (Contract 'windows-amd64' 'amd64' 'x64')
$arm=Get-PackageContract (Contract 'windows-arm64' 'arm64' 'arm64')
if($x64.nativeDirectory -cne 'x64' -or @($x64.nativeDirectories).Count -ne 1 -or -not $x64.requireNativeProcess){throw 'x64 contract regression'}
if($arm.nativeDirectory -cne 'arm64' -or @($arm.nativeDirectories).Count -ne 1 -or -not $arm.requireNativeProcess){throw 'ARM64 contract regression'}
MustReject (Contract 'windows-arm64' 'amd64' 'arm64')
MustReject (Contract 'windows-arm64' 'arm64' 'arm64x')
MustReject (Contract 'windows-arm64' 'arm64' 'x64')
MustReject (Contract 'windows-amd64' 'arm64' 'x64')
MustReject (Contract 'windows-amd64' 'amd64' 'arm64')
$standard=[pscustomobject]@{product='yimecore';format='yime-simple-package-2';target='windows-arm64';host_architecture='arm64';tsf64_architecture='arm64x'}
$standardContract=Get-PackageContract $standard
if($standardContract.tsf64Architecture -cne 'arm64x' -or @($standardContract.nativeDirectories).Count -ne 2){throw 'Standard ARM64X contract regression'}
Write-Output 'PASS independent 18u native architecture contracts and standard ARM64X isolation'
