[CmdletBinding()]
param([ValidateSet('Install','Uninstall','Check')][string]$Action='Install',
    [ValidateSet('yimecore','rime-pime','both')][string]$Product='both',
    [string]$CorePackage,[string]$RimePackage,[string]$PackageDirectory=$PSScriptRoot,[switch]$ResetData)
$ErrorActionPreference='Stop'
function Invoke-Setup($Item,[string]$Operation){
    # Each product owns its script scope, native types and exit code.
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$Item.entry,'-Action',$Operation)
    if($ResetData -and $Operation -ne 'Check'){$arguments+='-ResetData'}
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') @arguments
    if($LASTEXITCODE -ne 0){throw ($Operation+' failed for '+$Item.product+' (exit '+$LASTEXITCODE+'); remaining products were not attempted. Full setup logs: '+(Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Yime Setup Logs'))}
}
$selected=if($Product -eq 'both'){@('rime-pime','yimecore')}else{@($Product)}
$entries=@()
foreach($id in $selected){
    $package=if($id -eq 'yimecore'){$CorePackage}else{$RimePackage}
    if(-not $package){
        $matches=@(foreach($dir in Get-ChildItem -LiteralPath $PackageDirectory -Directory){
            $manifest=Join-Path $dir.FullName 'product-package.json'
            if(Test-Path -LiteralPath $manifest -PathType Leaf){
                $m=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json
                if($m.product -ceq $id){$dir.FullName}
            }
        })
        if($matches.Count -ne 1){throw ('Place exactly one extracted '+$id+' package beside this entry, or supply its explicit path')}
        $package=$matches[0]
    }
    $entry=Join-Path ([IO.Path]::GetFullPath($package)) 'Setup.ps1'
    if(-not (Test-Path -LiteralPath $entry -PathType Leaf)){throw ('Missing setup: '+$entry)}
    $record=Get-Content -LiteralPath (Join-Path $package 'product-package.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($record.product -cne $id){throw ('Wrong product package: '+$package)}
    $entries+=@([pscustomobject]@{product=$id;entry=$entry})
}
# Check every selected package before changing the first product.
foreach($item in $entries){
    Invoke-Setup $item 'Check'
}
if($Action -eq 'Check'){exit 0}
foreach($item in $entries){
    Invoke-Setup $item $Action
    Write-Output ($Action+' completed: '+$item.product)
}
