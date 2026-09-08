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
$testRoot = Join-Path $toolRoot 'tests'
$testModules = @(Get-ChildItem -LiteralPath $testRoot -Filter 'test*.py' -File | Sort-Object Name)
if ($testModules.Count -eq 0) {
    throw 'No offline lexicon test modules were found.'
}
# The forward-source proof intentionally rejects undeclared yime/syllable
# imports. Discovering the entire suite in one interpreter preloads unrelated
# lexicon-bundle modules into sys.modules. Keep every module, but give each the
# fresh interpreter that the production proof CLI also uses.
$testExitCode = 0
foreach ($testModule in $testModules) {
    & $runner -Python $Python -m unittest discover -s $testRoot -p $testModule.Name -v
    if ($LASTEXITCODE -ne 0) {
        $testExitCode = $LASTEXITCODE
    }
}
if ($testExitCode -ne 0) {
    exit $testExitCode
}
& $runner -Python $Python (Join-Path $toolRoot 'verify_target_lock.py')
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& $runner -Python $Python -m pytest -q (Join-Path (Split-Path -Parent (Split-Path -Parent $toolRoot)) 'tests') --disable-warnings
exit $LASTEXITCODE
