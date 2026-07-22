param([Parameter(ValueFromRemainingArguments)][string[]]$CMakeArguments)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'initialize-dev-environment.ps1')

$cmakeCommand = Get-Command cmake.exe -ErrorAction SilentlyContinue
$cmakePath = if ($cmakeCommand) { $cmakeCommand.Source } else { $null }
if (-not $cmakePath) {
    foreach ($year in 2022, 2019) {
        foreach ($edition in 'BuildTools', 'Community', 'Professional', 'Enterprise') {
            $candidate = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\$year\$edition\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
            if (Test-Path -LiteralPath $candidate) { $cmakePath = $candidate; break }
        }
        if ($cmakePath) { break }
    }
}
if (-not $cmakePath) { throw 'CMake was not found on PATH or in Visual Studio.' }

& $cmakePath @CMakeArguments
exit $LASTEXITCODE
