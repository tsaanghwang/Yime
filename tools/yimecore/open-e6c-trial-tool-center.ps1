[CmdletBinding()]
param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [ValidateSet('variable', 'full', 'shorthand')]
    [string]$Mode = 'variable'
)

$ErrorActionPreference = 'Stop'
$stateRootPath = [IO.Path]::GetFullPath($StateRoot)
$configPath = Join-Path $stateRootPath 'runtime-config.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "missing E6-C trial runtime configuration: $configPath"
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$installRoot = [IO.Path]::GetFullPath([string]$config.install_root)
$configuredStateRoot = [IO.Path]::GetFullPath([string]$config.state_root)
if (-not $configuredStateRoot.Equals($stateRootPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'configured E6-C state root does not match the requested Trial state root'
}
$toolCenter = Join-Path $installRoot 'bin\YimeCoreToolCenter.exe'
if (-not (Test-Path -LiteralPath $toolCenter -PathType Leaf)) {
    throw "installed E6-C Tool Center is unavailable: $toolCenter"
}
$statePath = Join-Path $stateRootPath 'yimecore_experimental_toolbar_state.json'
$argumentLine = '-InstallRoot "{0}" -StateRoot "{1}" -StatePath "{2}" -Mode {3} -Experimental' -f
    $installRoot.Replace('"', '\"'), $stateRootPath.Replace('"', '\"'),
    $statePath.Replace('"', '\"'), $Mode
$process = Start-Process -FilePath $toolCenter -ArgumentList $argumentLine -PassThru
Write-Host "YimeCore Trial Tool Center opened (PID $($process.Id))."
