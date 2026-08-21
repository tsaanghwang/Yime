[CmdletBinding()]
param(
    [string]$Python
)

$ErrorActionPreference = 'Stop'
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $toolRoot 'invoke-python.ps1'

& $runner -Python $Python -m unittest discover -s (Join-Path $toolRoot 'tests') -v
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& $runner -Python $Python (Join-Path $toolRoot 'verify_target_lock.py')
exit $LASTEXITCODE
