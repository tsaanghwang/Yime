[CmdletBinding()]
param([string]$OutputRoot)
$ErrorActionPreference='Stop'
if(-not $OutputRoot){$OutputRoot=Join-Path $PSScriptRoot ('.tmp\simple-build-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss'))}
Push-Location $PSScriptRoot
try{
    & cmd.exe /c build.bat
    if($LASTEXITCODE -ne 0){throw 'Source build failed'}
    & (Join-Path $PSScriptRoot 'installer\simple\Build-RimePackage.ps1') -OutputRoot $OutputRoot
}finally{Pop-Location}
