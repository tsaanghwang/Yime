[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot ('.tmp/registration-query-' + [guid]::NewGuid().ToString('N'))
}
if (Test-Path -LiteralPath $OutputRoot) { throw 'Use a fresh registration-query output directory.' }
$null = New-Item -ItemType Directory -Path $OutputRoot
Start-Transcript -LiteralPath (Join-Path $OutputRoot 'transcript.txt') | Out-Null
try {
    foreach ($target in @(@{name='x64';platform='x64'}, @{name='x86';platform='Win32'})) {
        $build = Join-Path $OutputRoot $target.name
        & cmake -S (Join-Path $repoRoot 'YimeTextServiceExperiment') -B $build `
            -G 'Visual Studio 17 2022' -A $target.platform -DYIME_LOCAL_PRODUCT=ON
        if ($LASTEXITCODE -ne 0) { throw "Configure failed: $($target.name)" }
        & cmake --build $build --config Release --parallel --target YimeTextServiceRegistration YimeRegistrationQueryTests
        if ($LASTEXITCODE -ne 0) { throw "Build failed: $($target.name)" }
        # The test redirects HKLM only within its own process to a disposable
        # HKCU fixture. It never invokes TSF registration or installed binaries.
        & ctest --test-dir $build -C Release -R '^YimeRegistrationQueryTests$' --output-on-failure --no-tests=error
        if ($LASTEXITCODE -ne 0) { throw "Query regression failed: $($target.name)" }
    }
} finally {
    Stop-Transcript | Out-Null
}
Write-Output 'PASS: current-identity x64 and x86 registration-query regressions; no installed product mutation.'
