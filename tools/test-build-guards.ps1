$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$verifier = Join-Path $PSScriptRoot 'verify-pe-architectures.ps1'
$x64Dll = Join-Path $root 'build64\PIMETextService\Release\PIMETextService.dll'
$launcher = Join-Path $root 'build\PIMELauncher\PIMELauncher.exe'
$workflow = Join-Path $root '.github\workflows\ci.yaml'
$rootBuild = Join-Path $root 'build.bat'
$installer = Join-Path $root 'installer\installer.nsi'
$readme = Join-Path $root 'README.md'

try {
    & $verifier -RepoRoot $root -X86TextService $x64Dll -X64TextService $x64Dll -X86Launcher $launcher
    throw 'Architecture verifier accepted an x64 DLL in the Win32 slot.'
} catch {
    if ($_.Exception.Message -notmatch 'Win32 PIMETextService\.dll expected 0x014C but found 0x8664') {
        throw
    }
    Write-Host 'Architecture mismatch rejection test passed.'
}

& $verifier -RepoRoot $root

$workflowText = Get-Content -LiteralPath $workflow -Raw
$requiredRaceGuards = @(
    'uses: msys2/setup-msys2@v2',
    'install: mingw-w64-ucrt-x86_64-gcc',
    '.\tools\test-go-race.ps1 -GccPath $gcc -TimeoutSeconds 300'
)
foreach ($guard in $requiredRaceGuards) {
    if (-not $workflowText.Contains($guard)) {
        throw "CI race guard is missing: $guard"
    }
}
Write-Host 'CI MSYS2 Go race guard test passed.'

if (-not $workflowText.Contains('git submodule update --init --depth 1 libIME2')) {
    throw 'CI must checkout only the active libIME2 submodule.'
}
if ($workflowText.Contains('Build McBopomofo')) {
    throw 'Retired McBopomofo build step returned to CI.'
}
$rootBuildText = Get-Content -LiteralPath $rootBuild -Raw
if ($rootBuildText.Contains('npm run build:pime')) {
    throw 'Retired McBopomofo build step returned to build.bat.'
}
$readmeText = Get-Content -LiteralPath $readme -Raw
if ($readmeText.Contains('[Node.js]')) {
    throw 'Retired Node.js build prerequisite returned to README.md.'
}
$installerText = Get-Content -LiteralPath $installer -Raw
if ($installerText -match 'YIME_ENABLE_RETIRED_PIME_BACKENDS|\\python\\|\\node\\|McBopomofo|libchewing') {
    throw 'Retired PIME backend code or paths returned to the YIME installer.'
}
$retiredTrackedPaths = @('python', 'node', 'McBopomofoWeb', 'libchewing')
foreach ($retiredPath in $retiredTrackedPaths) {
    $tracked = @(& git -C $root ls-files -- $retiredPath)
    if ($tracked.Count -gt 0) {
        throw "Retired path is still tracked: $retiredPath"
    }
}
$gitmodulesText = Get-Content -LiteralPath (Join-Path $root '.gitmodules') -Raw
if ($gitmodulesText -match 'McBopomofoWeb|libchewing|python/input_methods/rime/brise') {
    throw 'Retired submodule metadata is still present.'
}
Write-Host 'YIME-only build and installer guard test passed.'
Write-Host 'Build guard tests passed.'
