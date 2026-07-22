$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$verifier = Join-Path $PSScriptRoot 'verify-pe-architectures.ps1'
$x64Dll = Join-Path $root 'build64\PIMETextService\Release\PIMETextService.dll'
$launcher = Join-Path $root 'build\PIMELauncher\PIMELauncher.exe'
$workflow = Join-Path $root '.github\workflows\ci.yaml'
$codeOwners = Join-Path $root '.github\CODEOWNERS'
$rootBuild = Join-Path $root 'build.bat'
$installer = Join-Path $root 'installer\installer.nsi'
$devInstall = Join-Path $root 'tools\dev-install.ps1'
$installerLocales = Get-ChildItem -LiteralPath (Join-Path $root 'installer\locale') -Filter '*.nsh'
$launcherManifest = Join-Path $root 'PIMELauncher\Cargo.toml'
$launcherBuild = Join-Path $root 'PIMELauncher\build.rs'
$readme = Join-Path $root 'README.md'
$textServiceResource = Join-Path $root 'PIMETextService\PIMETextService.rc.in'

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

$requiredGovernanceGuards = @(
    'uses: tsaanghwang/Yime-build-contract/.github/workflows/validate.yml@d93a3e835cae58988792814d300d3c7cc872cfbb',
    'workflow_dispatch:',
    "branches: [main, yime-stable, 'codex/**']",
    'name: rust-i686-host',
    'name: native-build',
    'name: go-tests',
    'name: real-rime-tests',
    'name: go-race-msys2',
    'name: installer-package',
    'name: core-build',
    'Preserve legacy aggregate build contract',
    'needs: [build-contract, rust-i686-host, native-build, go-tests, real-rime-tests, go-race-msys2]',
    '.\tools\test-go.ps1',
    '.\tools\test-real-rime.ps1',
    '.\tools\write-build-manifest.ps1',
    '.\tools\test-installer-smoke.ps1',
    'uses: actions/download-artifact@v7'
)
foreach ($guard in $requiredGovernanceGuards) {
    if (-not $workflowText.Contains($guard)) {
        throw "Protected CI governance check is missing: $guard"
    }
}

$codeOwnersText = Get-Content -LiteralPath $codeOwners -Raw
foreach ($guard in @(
    '/AGENTS.md @tsaanghwang',
    '/.github/** @tsaanghwang',
    '/Build.ps1 @tsaanghwang',
    '/build.bat @tsaanghwang',
    '/CMakeLists.txt @tsaanghwang',
    '/tools/test-build-guards.ps1 @tsaanghwang',
    '/tools/test-go-race.ps1 @tsaanghwang',
    '/tools/test-go.ps1 @tsaanghwang',
    '/tools/test-real-rime.ps1 @tsaanghwang',
    '/tools/test-installer-smoke.ps1 @tsaanghwang',
    '/tools/verify-installed-runtime.ps1 @tsaanghwang',
    '/tools/write-build-manifest.ps1 @tsaanghwang',
    '/tools/verify-pe-architectures.ps1 @tsaanghwang',
    '/installer/** @tsaanghwang'
)) {
    if (-not $codeOwnersText.Contains($guard)) {
        throw "Protected CODEOWNERS entry is missing: $guard"
    }
}
Write-Host 'External build contract and named CI governance guards passed.'

if ($workflowText.Contains('CORE_RESULT:')) {
    throw 'Independent protected stages must not depend on an aggregate core-build result.'
}

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
$releaseVersion = (Get-Content -LiteralPath (Join-Path $root 'version.txt') -Raw).Trim()
$numericReleaseVersion = (($releaseVersion -split '-', 2)[0]) + '.0'
foreach ($fragment in @(
    "VIProductVersion `"$numericReleaseVersion`"",
    'VIAddVersionKey /LANG=${LANG_ID} "FileVersion" "${PRODUCT_VERSION}"',
    'VIAddVersionKey /LANG=${LANG_ID} "ProductVersion" "${PRODUCT_VERSION}"',
    'VIAddVersionKey /LANG=${LANG_ID} "ProductName" "${PRODUCT_NAME_VALUE}"',
    'VIAddVersionKey /LANG=${LANG_ID} "FileDescription" "${FILE_DESCRIPTION_VALUE}"',
    'VIAddVersionKey /LANG=${LANG_ID} "LegalCopyright" "Copyright (C) 2026 YIME contributors"'
)) {
    if (-not $installerText.Contains($fragment)) {
        throw "Installer/uninstaller VERSIONINFO guard is missing: $fragment"
    }
}
$launcherManifestText = Get-Content -LiteralPath $launcherManifest -Raw
$launcherBuildText = Get-Content -LiteralPath $launcherBuild -Raw
if (-not $launcherManifestText.Contains('winresource = "0.1"')) {
    throw 'PIMELauncher winresource build dependency is missing.'
}
foreach ($fragment in @(
    'join("..").join("version.txt")',
    '.set("FileVersion", version)',
    '.set("ProductVersion", version)',
    '.set("ProductName", "YIME")'
)) {
    if (-not $launcherBuildText.Contains($fragment)) {
        throw "PIMELauncher VERSIONINFO guard is missing: $fragment"
    }
}
$devInstallText = Get-Content -LiteralPath $devInstall -Raw
if ($devInstallText -match 'pythonRoot|nodeRoot|Copying Python backend|Copying Node backend') {
    throw 'Retired Python/Node payload handling returned to the developer installer.'
}
$localeText = ($installerLocales | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
if ($localeText -match 'PYTHON_SECTION_GROUP|NODE_SECTION_GROUP|MCBOPOMOFO|BRAILLE_CHEWING|SET_CHEWING') {
    throw 'Retired PIME input-method strings returned to installer locales.'
}
foreach ($fragment in @(
    '!macro InstallTextServiceDll ARCH SOURCE UPDATE_FLAG',
    'File /oname=PIMETextService.dll.new "${SOURCE}"',
    'Rename /REBOOTOK "$INSTDIR\${ARCH}\PIMETextService.dll.new" "$INSTDIR\${ARCH}\PIMETextService.dll"',
    'Exec ''"$INSTDIR\PIMELauncher.exe"'''
)) {
    if (-not $installerText.Contains($fragment)) {
        throw "Locked-DLL in-place upgrade guard is missing: $fragment"
    }
}
$upgradeFunctionMatch = [regex]::Match($installerText, '(?s)Function uninstallOldVersion.*?FunctionEnd')
if (-not $upgradeFunctionMatch.Success) {
    throw 'Could not locate installer in-place upgrade function.'
}
foreach ($forbiddenUpgradeFragment in @(
    'Delete /REBOOTOK "$INSTDIR\PIMELauncher.exe"',
    'Delete "$INSTDIR\version.txt"',
    'Delete "$INSTDIR\Uninstall.exe"'
)) {
    if ($upgradeFunctionMatch.Value.Contains($forbiddenUpgradeFragment)) {
        throw "Destructive pre-install upgrade step returned: $forbiddenUpgradeFragment"
    }
}

$requiredLegalFiles = @(
    'LICENSE.txt',
    'NOTICE.md',
    'AUTHORS.txt',
    'THIRD_PARTY_NOTICES.md',
    'LGPL-2.0.txt',
    'APACHE-2.0.txt',
    'json\LICENSE.MIT',
    'LICENSES\PIME-UPSTREAM-LICENSE.txt',
    'LICENSES\RIME-BSD-3-Clause.txt',
    'LICENSES\RIME-FROST-GPL-3.0.txt',
    'LICENSES\SIL-OFL-1.1.txt',
    'LICENSES\UNICODE-3.0.txt',
    'LICENSES\RUST-DEPENDENCIES.md'
)
foreach ($relativePath in $requiredLegalFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "Required legal notice is missing: $relativePath"
    }
}
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$noticeText = $strictUtf8.GetString([System.IO.File]::ReadAllBytes((Join-Path $root 'NOTICE.md')))
foreach ($fragment in @('Relationship to PIME', 'not an official EasyIME/PIME release')) {
    if (-not $noticeText.Contains($fragment)) {
        throw "Provenance notice content or UTF-8 encoding guard is missing: $fragment"
    }
}
$requiredInstallerLegalFragments = @(
    'SetOutPath "$INSTDIR\licenses"',
    'File "..\LICENSE.txt"',
    'File "..\NOTICE.md"',
    'File "..\THIRD_PARTY_NOTICES.md"',
    'File "..\LICENSES\PIME-UPSTREAM-LICENSE.txt"',
    'File "..\LICENSES\RIME-FROST-GPL-3.0.txt"',
    'File "..\LICENSES\RUST-DEPENDENCIES.md"',
    'RMDir /REBOOTOK /r "$INSTDIR\licenses"'
)
foreach ($fragment in $requiredInstallerLegalFragments) {
    if (-not $installerText.Contains($fragment)) {
        throw "Installer legal-notice packaging guard is missing: $fragment"
    }
}
$resourceText = Get-Content -LiteralPath $textServiceResource -Raw
foreach ($fragment in @('VALUE "CompanyName", "YIME Project"', 'VALUE "ProductName", "YIME"')) {
    if (-not $resourceText.Contains($fragment)) {
        throw "PIMETextService public YIME metadata guard is missing: $fragment"
    }
}
$legacyGoModule = 'github.com/EasyIME/' + 'pime-go'
$legacyModuleMatches = @(& git -C $root grep -n --fixed-strings $legacyGoModule -- 'go-backend/*.go' 'go-backend/**/*.go' 'go-backend/go.mod')
if ($legacyModuleMatches.Count -gt 0) {
    throw "Legacy upstream Go module namespace returned: $($legacyModuleMatches -join '; ')"
}

$retiredTrackedPaths = @('python', 'node', 'McBopomofoWeb', 'libchewing', 'tests')
foreach ($retiredPath in $retiredTrackedPaths) {
    $tracked = @(& git -C $root ls-files -- $retiredPath)
    if ($tracked.Count -gt 0) {
        throw "Retired path is still tracked: $retiredPath"
    }
}
$retiredUpstreamArtifacts = @(
    'PIMELauncher/rustup-init.exe',
    'PIMELauncher/cargo_check.log',
    'PIMELauncher/test_backend.py',
    'PIMELauncher/test_client.py',
    'PIMELauncher/test_client.ps1',
    'installer/README.txt',
    'installer/StdUtils.2015-11-16',
    'installer/inetc/Examples',
    'installer/inetc/Plugins/amd64-unicode',
    'installer/inetc/Plugins/x86-ansi',
    'installer/md5dll/ANSI',
    'installer/md5dll/MD5Example.nsi',
    'json/CMakeLists.txt',
    'json/cmake',
    'json/include',
    'json/nlohmann_json.natvis',
    'go-backend/deploy-server.ps1',
    'go-backend/pime/tray.go',
    'go-backend/input_methods/yime/icon-yin.ico',
    'go-backend/input_methods/yime/icon-yuan.ico',
    'go-backend/input_methods/yime/icons/zh.ico'
)
foreach ($retiredArtifact in $retiredUpstreamArtifacts) {
    $tracked = @(& git -C $root ls-files -- $retiredArtifact) | Where-Object {
        Test-Path -LiteralPath (Join-Path $root $_)
    }
    if ($tracked.Count -gt 0) {
        throw "Retired upstream or development artifact is still tracked: $retiredArtifact"
    }
}
$requiredNlohmannFiles = @('json/LICENSE.MIT', 'json/single_include/nlohmann/json.hpp')
foreach ($relativePath in $requiredNlohmannFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "Required minimal nlohmann/json file is missing: $relativePath"
    }
}
$requiredYimeIcons = @(
    'chi.ico', 'eng.ico',
    'chi_half_capsoff.ico', 'chi_half_capson.ico',
    'chi_full_capsoff.ico', 'chi_full_capson.ico',
    'eng_half_capsoff.ico', 'eng_half_capson.ico',
    'eng_full_capsoff.ico', 'eng_full_capson.ico',
    'half.ico', 'full.ico',
    'layout_horizontal.ico', 'layout_vertical.ico',
    'config.ico', 'lexicon.ico', 'reverse-lookup.ico', 'tools.ico'
)
$yimeIconDir = Join-Path $root 'go-backend\input_methods\yime\icons'
foreach ($iconName in $requiredYimeIcons) {
    if (-not (Test-Path -LiteralPath (Join-Path $yimeIconDir $iconName) -PathType Leaf)) {
        throw "Required Yime language-bar icon is missing: $iconName"
    }
}
$retiredRootFiles = @(
    'HACKING.txt',
    'PSF.txt',
    'appveyor.yml',
    'appveyor.after_build.bat',
    'appveyor.artifacts.ps1'
)
foreach ($retiredRootFile in $retiredRootFiles) {
    $tracked = @(& git -C $root ls-files -- $retiredRootFile)
    if ($tracked.Count -gt 0) {
        throw "Retired root file is still tracked: $retiredRootFile"
    }
}
$trackedRootData = @(
    & git -C $root ls-files -- '*.schema.yaml' '*.dict.yaml' '*.ocd' 'default.yaml' 'symbols.yaml' 'essay.txt' 't2*.json' 's2*.json' 'hk2*.json' 'tw2*.json'
) | Where-Object { -not $_.Contains('/') }
if ($trackedRootData.Count -gt 0) {
    throw "Retired root Rime/OpenCC data returned: $($trackedRootData -join ', ')"
}
$gitmodulesText = Get-Content -LiteralPath (Join-Path $root '.gitmodules') -Raw
if ($gitmodulesText -match 'McBopomofoWeb|libchewing|python/input_methods/rime/brise') {
    throw 'Retired submodule metadata is still present.'
}
Write-Host 'YIME-only build and installer guard test passed.'
Write-Host 'YIME provenance, metadata, and legal packaging guard test passed.'
Write-Host 'Build guard tests passed.'
