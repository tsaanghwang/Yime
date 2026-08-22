[CmdletBinding()]
param(
    [string]$Python
)

$ErrorActionPreference = 'Stop'
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $toolRoot 'invoke-python.ps1'

& $runner -Python $Python (Join-Path $toolRoot 'check_repository_data_boundary.py')
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& $runner -Python $Python -m unittest discover -s (Join-Path $toolRoot 'tests') -v
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& $runner -Python $Python (Join-Path $toolRoot 'verify_target_lock.py')
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& $runner -Python $Python -m pytest -q (Join-Path (Split-Path -Parent (Split-Path -Parent $toolRoot)) 'tests') --disable-warnings
exit $LASTEXITCODE
