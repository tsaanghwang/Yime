# Build YIME: compile everything, then pack the NSIS installer.
# Usage (elevated PowerShell optional for build; installer step needs write access):
#   Set-Location $PSScriptRoot
#   .\Build.ps1

$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot
cmd /c build.bat
if ($LASTEXITCODE -ne 0) {
    throw "build.bat failed with exit code $LASTEXITCODE"
}

Set-Location (Join-Path $PSScriptRoot 'installer')
$makensis = 'C:\Program Files (x86)\NSIS\makensis.exe'
if (-not (Test-Path -LiteralPath $makensis)) {
    throw "NSIS not found: $makensis"
}
& $makensis /V2 .\installer.nsi
if ($LASTEXITCODE -ne 0) {
    throw "makensis failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host ("Done. Installer: {0}" -f (Join-Path $PSScriptRoot "installer\YIME-*-setup.exe"))


