param(
    [ValidateSet('x64', 'x86')][string]$Architecture = 'x64',
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$ProcessId
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not $ProcessId) {
    $host = & (Join-Path $PSScriptRoot 'start-tsf-debug-host.ps1') -Architecture $Architecture -RepoRoot $repoRoot
    $ProcessId = $host.ProcessId
}

$cdb = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\$Architecture\cdb.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $cdb) { throw "cdb.exe for $Architecture was not found. Install Windows SDK Debugging Tools." }
$symbolPaths = @(
    (Join-Path $repoRoot 'build\PIMETextService\Release'),
    (Join-Path $repoRoot 'build64\PIMETextService\Release')
) -join ';'

Write-Host "Attaching cdb to PID $ProcessId. Activate YIME in charmap after the debugger opens."
Start-Process -FilePath $cdb.FullName -ArgumentList @('-p', $ProcessId, '-y', $symbolPaths)
