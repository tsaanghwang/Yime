$ErrorActionPreference='Stop'
Write-Host 'Yime setup / uninstall'
Write-Host '1. Install or reinstall   2. Uninstall'
$action=switch(Read-Host 'Action'){'1'{'Install'}'2'{'Uninstall'}default{throw 'Choose 1 or 2'}}
Write-Host '1. YimeCore   2. Rime/PIME   3. Both'
$product=switch(Read-Host 'Product'){'1'{'yimecore'}'2'{'rime-pime'}'3'{'both'}default{throw 'Choose 1, 2 or 3'}}
& (Join-Path $PSScriptRoot 'Manage-Products.ps1') -Action $action -Product $product -PackageDirectory $PSScriptRoot
exit $LASTEXITCODE
