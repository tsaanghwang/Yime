param([switch]$SkipPackagedRime)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$verifier = Join-Path $PSScriptRoot 'verify-pe-architectures.ps1'
$peImportGateTest = Join-Path $root 'tools\dual-product\test-pe-import-gate.ps1'
$x64Dll = Join-Path $root 'build64\PIMETextService\Release\PIMETextService.dll'
$launcher = Join-Path $root 'build\PIMELauncher\PIMELauncher.exe'
$workflow = Join-Path $root '.github\workflows\ci.yaml'
$codeOwners = Join-Path $root '.github\CODEOWNERS'
$buildContract = Join-Path $PSScriptRoot 'validate-build-contract.ps1'
$rootBuild = Join-Path $root 'build.bat'
$rootBuildPowerShell = Join-Path $root 'Build.ps1'
$rootBuildCommand = Join-Path $root 'Build.cmd'
$goBuild = Join-Path $root 'go-backend\build.bat'
$coreImporter = Join-Path $root 'tools\import-yime-core-lexicon.ps1'
$coreSourceManifest = Join-Path $root 'go-backend\input_methods\yime\data\yime_core_source_manifest.json'
$reversePinyinSource = Join-Path $root 'go-backend\input_methods\yime\data\yime_pinyin_reverse_source.tsv'
$pinyinCodeMap = Join-Path $root 'go-backend\input_methods\yime\data\yime_pinyin_codes.tsv'
$systemCandidateExclusions = Join-Path $root 'go-backend\input_methods\yime\data\yime_system_candidate_exclusions.tsv'
$erhuaMixedManifest = Join-Path $root 'go-backend\input_methods\yime\data\yime_erhua_mixed_manifest.json'
$erhuaReverseSource = Join-Path $root 'go-backend\input_methods\yime\data\yime_erhua_reverse_source.tsv'
$pscPeripheralManifest = Join-Path $root 'go-backend\input_methods\yime\data\yime_psc_peripheral_manifest.json'
$thirdToneStage5CManifest = Join-Path $root 'go-backend\input_methods\yime\data\yime_third_tone_stage5c_manifest.json'
$particleAStage6DManifest = Join-Path $root 'go-backend\input_methods\yime\data\yime_particle_a_stage6d_manifest.json'
$rimeCacheChecker = Join-Path $root 'tools\check-rime-cache-freshness.ps1'
$rimeCacheTests = Join-Path $root 'tools\test-rime-cache-freshness.ps1'
$installedParticleAVerifier = Join-Path $root 'tools\verify-installed-particle-a-stage6d.ps1'
$installedParticleAVerifierTests = Join-Path $root 'tools\test-installed-particle-a-stage6d-verifier.ps1'
$releaseCertificateImporter = Join-Path $root 'tools\import-release-signing-certificate.ps1'
$microsoftAuthenticodeVerifier = Join-Path $root 'tools\verify-microsoft-authenticode.ps1'
$installer = Join-Path $root 'installer\installer.nsi'
$installerBuilder = Join-Path $root 'tools\build-rime-pime-installer.ps1'
$packagePlanModule = Join-Path $root 'tools\dual-product\rime-pime-package-plan.ps1'
$packageStagingModule = Join-Path $root 'tools\dual-product\rime-pime-package-staging.ps1'
$nsisStageGenerator = Join-Path $root 'tools\dual-product\rime-pime-nsis-stage.ps1'
$nsisStageTest = Join-Path $root 'tools\dual-product\test-rime-pime-nsis-stage.ps1'
$stagedBuildHelper = Join-Path $root 'tools\dual-product\rime-pime-staged-installer-build.ps1'
$stagedBuildTest = Join-Path $root 'tools\dual-product\test-rime-pime-staged-installer-build.ps1'
$devInstall = Join-Path $root 'tools\dev-install.ps1'
$devStop = Join-Path $root 'tools\dev-stop-pime.ps1'
$pimeOwnership = Join-Path $root 'tools\dual-product\rime-pime-ownership.ps1'
$directedStopContract = Join-Path $root 'tools\dual-product\rime-pime-directed-stop-contract.ps1'
$devBuildInstallVerify = Join-Path $root 'tools\dev-build-install-verify.ps1'
$installedRuntimeVerifier = Join-Path $root 'tools\verify-installed-runtime.ps1'
$buildPrereqs = Join-Path $root 'tools\assert-win32-build-prerequisites.ps1'
$buildEnvironment = Join-Path $root 'tools\invoke-build-environment.ps1'
$cmakeEnvironment = Join-Path $root 'tools\invoke-cmake.ps1'
$realRimeTest = Join-Path $root 'tools\test-real-rime.ps1'
$installerLocales = Get-ChildItem -LiteralPath (Join-Path $root 'installer\locale') -Filter '*.nsh'
$launcherManifest = Join-Path $root 'PIMELauncher\Cargo.toml'
$launcherBuild = Join-Path $root 'PIMELauncher\build.rs'
$launcherCargoConfig = Join-Path $root 'PIMELauncher\.cargo\config.toml'
$readme = Join-Path $root 'README.md'
$textServiceResource = Join-Path $root 'PIMETextService\PIMETextService.rc.in'
$pimeTextServiceSource = Join-Path $root 'PIMETextService\PIMETextService.cpp'
$pimeTextServiceHeader = Join-Path $root 'PIMETextService\PIMETextService.h'

$verifierCommon = @{RepoRoot=$root}
if ($SkipPackagedRime) { $verifierCommon.SkipPackagedRime = $true }
try {
    & $verifier @verifierCommon -X86TextService $x64Dll -X64TextService $x64Dll -X86Launcher $launcher
    throw 'Architecture verifier accepted an x64 DLL in the Win32 slot.'
} catch {
    if ($_.Exception.Message -notmatch 'Win32 PIMETextService\.dll expected 0x014C but found 0x8664') {
        throw
    }
    Write-Host 'Architecture mismatch rejection test passed.'
}

if (-not $SkipPackagedRime) {
    $goExecutableNames=@(
        'server.exe','tool-hub.exe','yime-trainer.exe','input-toolbar.exe',
        'settings-tool.exe','diagnostics-tool.exe','yime-layout-designer.exe',
        'lexicon-manager.exe','reverse-lookup.exe','system-lexicon-audit.exe',
        'lexicon-promotion-scan.exe','blocklist-manager.exe'
    )
    $tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $negativeGoRoot=Join-Path $tempBase ('yime-go-architecture-negative-'+[Guid]::NewGuid().ToString('N'))
    if ((Split-Path -Parent $negativeGoRoot) -ine $tempBase -or
        (Split-Path -Leaf $negativeGoRoot) -cnotmatch '^yime-go-architecture-negative-[0-9a-f]{32}$') {
        throw 'Unsafe Go architecture-negative fixture root.'
    }
    New-Item -ItemType Directory -Path $negativeGoRoot | Out-Null
    try {
        foreach ($name in $goExecutableNames) {
            Copy-Item -LiteralPath (Join-Path $root "go-backend\build\go-backend\$name") `
                -Destination (Join-Path $negativeGoRoot $name)
        }
        Copy-Item -LiteralPath $launcher -Destination (Join-Path $negativeGoRoot 'server.exe') -Force
        try {
            & $verifier @verifierCommon -GoBackendRoot $negativeGoRoot
            throw 'Architecture verifier accepted a Win32 executable in the x64 Go payload.'
        } catch {
            if ($_.Exception.Message -notmatch 'x64 packaged Go server\.exe expected 0x8664 but found 0x014C') { throw }
            Write-Host 'Go payload architecture mismatch rejection test passed.'
        }
    } finally {
        if ((Test-Path -LiteralPath $negativeGoRoot) -and
            (Split-Path -Parent ([IO.Path]::GetFullPath($negativeGoRoot))) -ieq $tempBase) {
            Remove-Item -LiteralPath $negativeGoRoot -Recurse -Force
        }
    }
}

& $verifier @verifierCommon

$workflowText = Get-Content -LiteralPath $workflow -Raw
& $buildContract

if ($workflowText -match '(?m)^\s*run:\s*&') {
    throw 'CI PowerShell commands must use YAML-safe block scalars instead of an anchor-like run: & value.'
}

$externalReusableWorkflowPattern = '(?m)^\s*uses:\s+(?!\./)[^/\s]+/[^/\s]+/\.github/workflows/'
foreach ($forbiddenExample in @(
    'uses: owner/project/.github/workflows/validate.yml@0123456789abcdef',
    '  uses: example/policy/.github/workflows/build.yml@0123456789abcdef'
)) {
    if ($forbiddenExample -notmatch $externalReusableWorkflowPattern) {
        throw "Cross-repository reusable-workflow guard missed: $forbiddenExample"
    }
}
foreach ($allowedExample in @(
    'uses: actions/checkout@v6',
    'uses: ./.github/workflows/validate.yml'
)) {
    if ($allowedExample -match $externalReusableWorkflowPattern) {
        throw "Cross-repository reusable-workflow guard rejected an allowed action: $allowedExample"
    }
}
if ($workflowText -match $externalReusableWorkflowPattern) {
    throw "CI must not call a reusable workflow from another repository: $($Matches[0].Trim())"
}
Write-Host 'CI cross-repository reusable-workflow rejection test passed.'

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
    'name: build-contract / validate-build-contract',
    '.\tools\validate-build-contract.ps1',
    'workflow_dispatch:',
    "branches: [main, yime-stable, 'codex/**']",
    'name: rust-i686-host',
    'name: lexicon-offline-tooling',
    'Enforce repository data boundary',
    '.\tools\lexicon\check_repository_data_boundary.py',
    'Verify internal PSC outline snapshot',
    '.\tools\verify_psc_outline_snapshot.py',
    'Verify vendored Win32 build dependencies',
    '.\tools\verify_vendored_build_dependencies.py',
    'Verify locked Windows toolchain metadata',
    '.\tools\verify_toolchain_lock.py',
    'Verify detached lexicon archive identity',
    '.\tools\lexicon\verify_external_archive_lock.py',
    'name: native-build',
    'Guard and track libIME2 component commits',
    '.\tools\check-libime2-change-boundary.ps1',
    '.\tools\test-libime2-change-boundary.ps1',
    'libime2-change-report-${{ github.sha }}',
    'name: go-tests',
    '.\tools\test-rime-cache-freshness.ps1',
    '.\tools\test-installed-particle-a-stage6d-verifier.ps1',
    'name: real-rime-tests',
    'name: go-race-msys2',
    'name: installer-package',
    'name: installer-payload',
    'name: release-sign-payload',
    'name: unsigned-installer-package',
    'name: release-installer-package',
    'name: release-sign-installer',
    'Preserve protected installer-package contract',
    'name: core-build',
    'Preserve legacy aggregate build contract',
    'needs: [build-contract, lexicon-offline-tooling, rust-i686-host, native-build, go-tests, real-rime-tests, go-race-msys2, nsis-preflight, contract-tests, dp1-long-contracts]',
    '.\tools\lexicon\replay-approved-handoff.ps1',
    '.\tools\evaluation\run.ps1',
    'verify_release_readiness.py --require-release',
    'verify_package_handoff.py',
    '.\tools\test-go.ps1',
    '.\tools\test-real-rime.ps1',
    '.\tools\assert-win32-build-prerequisites.ps1 -RequireToolchain',
    'cmake --build build64 --config Release --target PIMETextService PIMERpcResponseTests',
    'ctest --test-dir build64 -C Release -R "^PIMERpcResponseTests$" --output-on-failure',
    '.\tools\write-build-manifest.ps1',
    "Join-Path `$env:YIME_TRUSTED_SIGNING_ROOT 'tools\write-build-manifest.ps1'",
    '.\tools\test-installer-smoke.ps1',
    '-StaticOnly',
    'uses: ./.github/actions/prepare-pinned-nsis',
    '.\tools\ci\test-prepare-pinned-nsis.ps1',
    'nsis-version: 3.12',
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
    '/.githooks/** @tsaanghwang',
    '/Build.ps1 @tsaanghwang',
    '/build.bat @tsaanghwang',
    '/CMakeLists.txt @tsaanghwang',
    '/.cargo/** @tsaanghwang',
    '/tools/test-build-guards.ps1 @tsaanghwang',
    '/tools/validate-build-contract.ps1 @tsaanghwang',
    '/tools/verify_psc_outline_snapshot.py @tsaanghwang',
    '/tools/verify_vendored_build_dependencies.py @tsaanghwang',
    '/tools/toolchain.lock.json @tsaanghwang',
    '/tools/verify_toolchain_lock.py @tsaanghwang',
    '/tools/psc_outline_review_tool.py @tsaanghwang',
    '/tools/test_psc_outline_review_tool.py @tsaanghwang',
    '/tools/assert-data-source-boundary.ps1 @tsaanghwang',
    '/tools/data_import_approvals/** @tsaanghwang',
    '/tools/check-libime2-change-boundary.ps1 @tsaanghwang',
    '/tools/invoke-libime2-pre-push.ps1 @tsaanghwang',
    '/tools/enable-repository-hooks.ps1 @tsaanghwang',
    '/tools/test-libime2-change-boundary.ps1 @tsaanghwang',
    '/tools/test-go-race.ps1 @tsaanghwang',
    '/tools/test-go.ps1 @tsaanghwang',
    '/tools/test-real-rime.ps1 @tsaanghwang',
    '/tools/lexicon/** @tsaanghwang',
    '/yime/repository_boundary.py @tsaanghwang',
    '/tools/evaluation/** @tsaanghwang',
    '/internal_data/psc_outline/** @tsaanghwang',
    '/PIMELauncher/vendor/** @tsaanghwang',
    '/third_party/** @tsaanghwang',
    '/tools/test-installer-smoke.ps1 @tsaanghwang',
    '/tools/assert-win32-build-prerequisites.ps1 @tsaanghwang',
    '/tools/initialize-dev-environment.ps1 @tsaanghwang',
    '/tools/invoke-build-environment.ps1 @tsaanghwang',
    '/tools/invoke-cmake.ps1 @tsaanghwang',
    '/tools/verify-installed-runtime.ps1 @tsaanghwang',
    '/tools/verify-installed-particle-a-stage6d.ps1 @tsaanghwang',
    '/tools/test-installed-particle-a-stage6d-verifier.ps1 @tsaanghwang',
    '/tools/check-rime-cache-freshness.ps1 @tsaanghwang',
    '/tools/test-rime-cache-freshness.ps1 @tsaanghwang',
    '/tools/import-release-signing-certificate.ps1 @tsaanghwang',
    '/tools/verify-microsoft-authenticode.ps1 @tsaanghwang',
    '/tools/write-build-manifest.ps1 @tsaanghwang',
    '/tools/verify-pe-architectures.ps1 @tsaanghwang',
    '/installer/** @tsaanghwang'
)) {
    if (-not $codeOwnersText.Contains($guard)) {
        throw "Protected CODEOWNERS entry is missing: $guard"
    }
}
Write-Host 'In-repository build contract and named CI governance guards passed.'

if ($workflowText.Contains('CORE_RESULT:')) {
    throw 'Independent protected stages must not depend on an aggregate core-build result.'
}

if ($workflowText.Contains('git submodule update --init --depth 1 libIME2')) {
    throw 'CI must use the in-tree libIME2 component without a submodule checkout.'
}
$libIME2Index = @(& git -C $root ls-files -s -- libIME2)
if ($libIME2Index.Count -eq 0) {
    throw 'The in-tree libIME2 component is not tracked.'
}
if ($libIME2Index[0] -match '^160000\s') {
    throw 'libIME2 unexpectedly remains a gitlink instead of tracked source.'
}
foreach ($requiredLibIME2File in @('libIME2/CMakeLists.txt', 'libIME2/src/libIME.h')) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $requiredLibIME2File) -PathType Leaf)) {
        throw "The in-tree libIME2 component is incomplete: $requiredLibIME2File"
    }
}
if ($workflowText.Contains('Build McBopomofo')) {
    throw 'Retired McBopomofo build step returned to CI.'
}
$rootBuildText = Get-Content -LiteralPath $rootBuild -Raw
if ($rootBuildText.Contains('npm run build:pime')) {
    throw 'Retired McBopomofo build step returned to build.bat.'
}
foreach ($guard in @(
    'tools\invoke-build-environment.ps1',
    'rustup run stable-i686-pc-windows-msvc cargo build --release --target i686-pc-windows-msvc',
    '--build build --config Release --target PIMETextService PIMERegistrationStatus',
    '--build build64 --config Release --target PIMETextService PIMERegistrationStatus',
    '--build build_arm64 --config Release --target PIMETextService PIMERegistrationStatus'
)) {
    if (-not $rootBuildText.Contains($guard)) {
        throw "Win32 pinned-host build guard is missing: $guard"
    }
}
$goBuildText = Get-Content -LiteralPath $goBuild -Raw
foreach ($guard in @(
    'third_party\go-winres',
    'go build -mod=vendor -trimpath -buildvcs=false',
    'set "GOOS=windows"',
    'set "GOARCH=amd64"',
    '[ERROR] go-winres failed for',
    'Get-ChildItem -LiteralPath $env:YIME_PACKAGE_INPUT_METHODS -Recurse -File -Force | Unblock-File -ErrorAction Stop',
    'package staging gate still rejects every alternate stream that remains'
)) {
    if (-not $goBuildText.Contains($guard)) {
        throw "Offline go-winres build guard is missing: $guard"
    }
}
if ($workflowText.Contains('go install github.com/tc-hib/go-winres')) {
    throw 'CI must not download go-winres during the build.'
}
foreach ($guard in @(
    'yime_full.dict.yaml',
    'yime_variable.dict.yaml',
    'yime_shorthand.dict.yaml',
    'yime_full.schema.yaml',
    'yime_variable.schema.yaml',
    'yime_shorthand.schema.yaml',
    'yime_lexicon_manifest.json',
    'yime_core_source_manifest.json',
    'yime_runtime_profile.json',
    'yime_pinyin_reverse_source.tsv',
    'yime_pinyin_codes.tsv',
	'yime_system_candidate_exclusions.tsv',
    'yime_erhua_mixed_full.dict.yaml',
    'yime_erhua_mixed_variable.dict.yaml',
    'yime_erhua_mixed_shorthand.dict.yaml',
	'yime_erhua_mixed_sentence_full.dict.yaml',
	'yime_erhua_mixed_sentence_variable.dict.yaml',
	'yime_erhua_mixed_sentence_shorthand.dict.yaml',
	'yime_sentence_full.dict.yaml',
	'yime_sentence_variable.dict.yaml',
	'yime_sentence_shorthand.dict.yaml',
	'yime_third_tone_stage5c_full.dict.yaml',
	'yime_third_tone_stage5c_variable.dict.yaml',
	'yime_third_tone_stage5c_shorthand.dict.yaml',
	'yime_third_tone_stage5c_manifest.json',
	'yime_particle_a_stage6d_full.dict.yaml',
	'yime_particle_a_stage6d_variable.dict.yaml',
	'yime_particle_a_stage6d_shorthand.dict.yaml',
	'yime_particle_a_stage6d_manifest.json',
    'yime_erhua_mixed_manifest.json',
    'yime_erhua_reverse_source.tsv',
    'yime_erhua_mixed_full.schema.yaml',
    'yime_erhua_mixed_variable.schema.yaml',
    'yime_erhua_mixed_shorthand.schema.yaml',
    'yime_psc_peripheral_full.dict.yaml',
    'yime_psc_peripheral_variable.dict.yaml',
    'yime_psc_peripheral_shorthand.dict.yaml',
	'yime_psc_peripheral_sentence_full.dict.yaml',
	'yime_psc_peripheral_sentence_variable.dict.yaml',
	'yime_psc_peripheral_sentence_shorthand.dict.yaml',
    'yime_psc_peripheral_manifest.json',
    'yime_psc_peripheral_full.schema.yaml',
    'yime_psc_peripheral_variable.schema.yaml',
    'yime_psc_peripheral_shorthand.schema.yaml',
    'Removing retired single-mode trial artifacts'
)) {
    if (-not $goBuildText.Contains($guard)) {
        throw "Curated core three-mode package guard is missing: $guard"
    }
}
$coreImporterText = Get-Content -LiteralPath $coreImporter -Raw
foreach ($guard in @(
    'assert-data-source-boundary.ps1',
    '[string]$RepositoryImportApproval',
    'Get-FileHash -LiteralPath $resolvedInputPath -Algorithm SHA256',
    '$sourceHash -ne [string]$evidence.output_sha256',
    '$evidence.ranking_evidence.policy_id',
    '$evidence.ranking_evidence.distinct_texts_by_source',
    '[string]$SourceRevision',
    'go run ./cmd/yime-lexicon-derive',
    '[string]$PronunciationEntries',
    'go run ./cmd/yime-reverse-pinyin-derive',
    'go run ./cmd/yime-psc-peripheral-derive'
)) {
    if (-not $coreImporterText.Contains($guard)) {
        throw "Curated core evidence import guard is missing: $guard"
    }
}
if ($workflowText.Contains('repolevedavaj/install-nsis')) {
    throw 'NSIS preparation must use the repository-verified distribution without third-party overlays.'
}
foreach ($requiredScript in @($rimeCacheChecker, $rimeCacheTests, $installedParticleAVerifier, $installedParticleAVerifierTests, $releaseCertificateImporter, $microsoftAuthenticodeVerifier)) {
    if (-not (Test-Path -LiteralPath $requiredScript -PathType Leaf)) {
        throw "Required CI/runtime verification script is missing: $requiredScript"
    }
}
$devBuildInstallVerifyText = Get-Content -LiteralPath $devBuildInstallVerify -Raw
foreach ($guard in @('RimeCacheWaitSeconds', 'check-rime-cache-freshness.ps1', 'RequireFreshRimeCache', 'LongSessionAcceptancePath', 'RequireLongSessionAcceptance', 'verify-installed-particle-a-stage6d.ps1')) {
    if (-not $devBuildInstallVerifyText.Contains($guard)) {
        throw "Developer build/install verification is missing its bounded Rime-cache wait guard: $guard"
    }
}
$installedRuntimeVerifierText = Get-Content -LiteralPath $installedRuntimeVerifier -Raw
foreach ($guard in @('check-rime-cache-freshness.ps1', 'RequireFreshRimeCache', 'rimeCompiledCaches')) {
    if (-not $installedRuntimeVerifierText.Contains($guard)) {
        throw "Installed-runtime verification is missing its Rime-cache evidence guard: $guard"
    }
}
foreach ($guard in @('LongSessionAcceptancePath', 'RequireLongSessionAcceptance', 'rime-native-backend', 'RequiredClassifiedTransactionsPerPosition')) {
    if (-not $installedRuntimeVerifierText.Contains($guard)) {
        throw "Installed-runtime verification is missing its long-session acceptance guard: $guard"
    }
}
$extractJob = {
    param([string]$Name)
    $match = [regex]::Match($workflowText, "(?ms)^  $([regex]::Escape($Name)):\r?\n.*?(?=^  [A-Za-z0-9_-]+:\r?$|\z)")
    if (-not $match.Success) { throw "CI job is missing: $Name" }
    $match.Value
}
$nativePeGate=$rootBuildText.IndexOf('verify-pe-architectures.ps1" -RepoRoot "%ROOT_DIR%" -SkipPackagedRime')
$goPackageBuild=$rootBuildText.IndexOf('cmd /C build.bat')
$completePayloadGate=$rootBuildText.LastIndexOf('verify-pe-architectures.ps1" -RepoRoot "%ROOT_DIR%" %ARM64_PE_ARGS% || exit /b 1')
$arm64Build=$rootBuildText.IndexOf('--build build_arm64 --config Release --target PIMETextService PIMERegistrationStatus')
$arm64ArgumentsReset=$rootBuildText.IndexOf('set "ARM64_PE_ARGS="')
$arm64Arguments=$rootBuildText.IndexOf('set "ARM64_PE_ARGS=-Arm64TextService')
if ($nativePeGate -lt 0 -or $goPackageBuild -le $nativePeGate -or
    $completePayloadGate -le $goPackageBuild -or
    $arm64ArgumentsReset -lt 0 -or $arm64ArgumentsReset -ge $arm64Build -or
    $arm64Build -lt 0 -or $arm64Arguments -le $arm64Build -or $arm64Arguments -ge $nativePeGate -or
    [regex]::Matches($rootBuildText,'ARM64_PE_ARGS%').Count -ne 2 -or
    [regex]::Matches($rootBuildText,'-Arm64TextService').Count -ne 1 -or
    [regex]::Matches($rootBuildText,'-Arm64RegistrationStatus').Count -ne 1 -or
    [regex]::Matches($rootBuildText,'verify-pe-architectures\.ps1').Count -ne 2) {
    throw 'Root build must verify native artifacts first and the complete Go/Rime payload only after packaging.'
}
$verifierText=Get-Content -LiteralPath $verifier -Raw
foreach ($name in @(
    'server.exe','tool-hub.exe','yime-trainer.exe','input-toolbar.exe',
    'settings-tool.exe','diagnostics-tool.exe','yime-layout-designer.exe',
    'lexicon-manager.exe','reverse-lookup.exe','system-lexicon-audit.exe',
    'lexicon-promotion-scan.exe','blocklist-manager.exe')) {
    if (-not $verifierText.Contains("'$name'")) { throw "Packaged Go PE architecture gate is missing: $name" }
}
$nativeBuildJob = & $extractJob 'native-build'
$installerPayloadJob = & $extractJob 'installer-payload'
$unsignedInstallerJob = & $extractJob 'unsigned-installer-package'
$goPackageBuild = $installerPayloadJob.IndexOf('cmd /C build.bat')
$completePeGate = $installerPayloadJob.IndexOf('.\tools\verify-pe-architectures.ps1')
if (-not $nativeBuildJob.Contains('.\tools\test-build-guards.ps1 -SkipPackagedRime') -or
    $goPackageBuild -lt 0 -or $completePeGate -lt 0 -or $completePeGate -lt $goPackageBuild) {
    throw 'CI must defer the complete Rime payload PE/CRT gate until after the Go package build.'
}
foreach ($guard in @(
    "(Get-Content -LiteralPath .\version.txt -Raw).Trim()",
    '$expectedLeaf = "YIME-$version-setup.exe"',
    "Get-ChildItem -LiteralPath .\installer -File -Filter 'YIME-*-setup.exe'",
    '$installers.Count -ne 1',
    '$installers[0].Name -cne $expectedLeaf',
    '$installer = $installers[0]'
)) {
    if (-not $unsignedInstallerJob.Contains($guard)) {
        throw "Unsigned installer CI must select one exact version.txt-derived leaf: $guard"
    }
}
if ($unsignedInstallerJob.Contains('Select-Object -First 1')) {
    throw 'Unsigned installer CI must reject multiple versioned leaves instead of selecting an arbitrary first match.'
}
foreach ($jobName in @('release-sign-payload', 'release-sign-installer')) {
    $jobText = & $extractJob $jobName
    if (-not $jobText.Contains('secrets.YIME_SIGN_CERT_BASE64')) {
        throw "Release signing job does not import the protected certificate: $jobName"
    }
    foreach ($required in @(
        'environment: release-signing',
        'Checkout trusted signing implementation',
        'ref: ${{ github.event.repository.default_branch }}',
        'path: .trusted-signing',
        'persist-credentials: false',
        'Move trusted signing implementation outside source checkout',
        "Join-Path `$env:RUNNER_TEMP 'yime-trusted-signing'",
        'YIME_TRUSTED_SIGNING_ROOT',
        "Join-Path `$env:YIME_TRUSTED_SIGNING_ROOT 'tools\import-release-signing-certificate.ps1'"
    )) {
        if (-not $jobText.Contains($required)) {
            throw "Release signing trust-boundary guard is missing: $jobName -> $required"
        }
    }
    $moveStep = $jobText.IndexOf('Move trusted signing implementation outside source checkout')
    $certificateStep = $jobText.IndexOf('Import release signing certificate')
    if ($moveStep -lt 0 -or $certificateStep -le $moveStep -or
        -not $jobText.Contains("Test-Path -LiteralPath `$source") -or
        -not $jobText.Contains("Add-Content -LiteralPath `$env:GITHUB_ENV")) {
        throw "Trusted signing implementation can remain inside the source checkout when signing begins: $jobName"
    }
    foreach ($forbidden in @('repolevedavaj/install-nsis', './.github/actions/prepare-pinned-nsis', 'Invoke-WebRequest', 'go install ')) {
        if ($jobText.Contains($forbidden)) {
            throw "Release signing job executes untrusted setup after secrets are exposed: $jobName -> $forbidden"
        }
    }
}
foreach ($jobName in @('unsigned-installer-package', 'release-installer-package')) {
    $jobText = & $extractJob $jobName
    $nsisPreparation = $jobText.IndexOf('uses: ./.github/actions/prepare-pinned-nsis')
    $installerCompilation = $jobText.IndexOf('build-rime-pime-installer.ps1')
    if ($nsisPreparation -lt 0 -or $installerCompilation -le $nsisPreparation -or
        -not $jobText.Contains('nsis-version: 3.12')) {
        throw "NSIS packaging must prepare the repository-pinned distribution before compilation: $jobName"
    }
    if ($jobText.Contains('secrets.YIME_') -or $jobText.Contains('import-release-signing-certificate.ps1')) {
        throw "NSIS packaging job must not receive release signing secrets: $jobName"
    }
}
$devStopText = Get-Content -LiteralPath $devStop -Raw
foreach ($guard in @(
    '$ErrorActionPreference = "Stop"',
    'Stop-YimePimeOwnedProcesses',
    'exit 3'
)) {
    if (-not $devStopText.Contains($guard)) {
        throw "PIME stop verification guard is missing: $guard"
    }
}
if ($devStopText -match 'Stop-Process[^\r\n]+-ErrorAction\s+SilentlyContinue') {
    throw 'dev-stop-pime.ps1 must not suppress Stop-Process failures.'
}
if ($devStopText.Contains('Stop-ProcessByName')) {
    throw 'dev-stop-pime.ps1 must not terminate generic process names outside explicit install roots.'
}
$pimeOwnershipText = Get-Content -LiteralPath $pimeOwnership -Raw
$directedStopText = Get-Content -LiteralPath $directedStopContract -Raw
if (-not $pimeOwnershipText.Contains('Invoke-YimePimeDirectedStop') -or
    -not $directedStopText.Contains('Wait-Process -InputObject') -or
    -not $directedStopText.Contains('-ErrorAction Stop') -or
    -not $directedStopText.Contains('$remaining') -or
    -not $directedStopText.Contains('Acknowledged directed stop did not leave the selected product quiescent.')) {
    throw 'Directed Rime/PIME stop no longer proves exact-process quiescence after acknowledgement.'
}
$sourceEvidence = Get-Content -LiteralPath $coreSourceManifest -Raw -Encoding UTF8 | ConvertFrom-Json
$pscDeriveIndex = $coreImporterText.IndexOf('go run ./cmd/yime-psc-peripheral-derive')
$erhuaDeriveIndex = $coreImporterText.IndexOf('go run ./cmd/yime-erhua-mixed-derive')
if ($pscDeriveIndex -lt 0 -or $erhuaDeriveIndex -lt 0 -or $pscDeriveIndex -gt $erhuaDeriveIndex) {
    throw 'PSC peripheral derivation must precede explicit-erhua derivation so low-frequency weights are reproducible.'
}
$reversePinyinHash = (Get-FileHash -LiteralPath $reversePinyinSource -Algorithm SHA256).Hash.ToLowerInvariant()
$pinyinCodeMapHash = (Get-FileHash -LiteralPath $pinyinCodeMap -Algorithm SHA256).Hash.ToLowerInvariant()
$reversePinyinRows = [Math]::Max(0, (Get-Content -LiteralPath $reversePinyinSource -Encoding UTF8).Count - 1)
if ([string]$sourceEvidence.reverse_pinyin_source -ne 'yime_pinyin_reverse_source.tsv' -or
    [string]$sourceEvidence.reverse_pinyin_source_sha256 -ne $reversePinyinHash -or
    [int64]$sourceEvidence.reverse_pinyin_source_rows -ne $reversePinyinRows -or
    [string]$sourceEvidence.reverse_pinyin_code_map_sha256 -ne $pinyinCodeMapHash) {
    throw 'Reverse-Pinyin source sidecar does not match yime_core_source_manifest.json.'
}
$erhuaMixed = Get-Content -LiteralPath $erhuaMixedManifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not [bool]$erhuaMixed.summary.passed -or
    [int64]$erhuaMixed.summary.explicit_record_count -le 0 -or
    [int64]$erhuaMixed.summary.inherited_weight_record_count -ne [int64]$erhuaMixed.summary.explicit_record_count -or
    [int64]$erhuaMixed.summary.fixed_runtime_weight -ne 1 -or
    [int64]$erhuaMixed.summary.feature_projected_count -ne [int64]$erhuaMixed.summary.explicit_record_count -or
    [int64]$erhuaMixed.summary.pending_fusion_count -ne 0 -or
    ([int64]$erhuaMixed.summary.core_weight_record_count + [int64]$erhuaMixed.summary.psc_peripheral_weight_record_count) -ne [int64]$erhuaMixed.summary.explicit_record_count -or
    [int64]$erhuaMixed.summary.deferred_missing_weight_count -ne 0 -or
    [int64]$erhuaMixed.summary.routes_per_mode -ne ([int64]$erhuaMixed.summary.explicit_record_count + [int64]$erhuaMixed.summary.core_weight_record_count) -or
    [int64]$erhuaMixed.summary.runtime_alias_rows -ne ([int64]$erhuaMixed.summary.routes_per_mode * 3) -or
    [int64]$erhuaMixed.summary.sentence_alias_rows -ne ([int64]$erhuaMixed.summary.explicit_record_count * 3) -or
    [int64]$erhuaMixed.summary.sentence_dictionary_count -ne 3 -or
    [int64]$erhuaMixed.summary.declared_sound_unit_count -ne 18 -or
    [int64]$erhuaMixed.summary.dedicated_key_class_count -ne 15 -or
    [int64]$erhuaMixed.summary.feature_rule_count -ne 15 -or
    [int64]$erhuaMixed.summary.reverse_lookup_row_count -ne [int64]$erhuaMixed.summary.explicit_record_count) {
    throw 'Explicit-erhua mixed runtime manifest did not pass its completeness gates.'
}
foreach ($mode in @('full', 'variable', 'shorthand')) {
    foreach ($name in @("yime_erhua_mixed_${mode}.dict.yaml", "yime_erhua_mixed_sentence_${mode}.dict.yaml", "yime_sentence_${mode}.dict.yaml")) {
        $path = Join-Path $root "go-backend\input_methods\yime\data\$name"
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ([string]$erhuaMixed.output_sha256.$name -ne $hash) {
            throw "Explicit-erhua mixed dictionary hash mismatch: $name"
        }
    }
}
$erhuaReverseHash = (Get-FileHash -LiteralPath $erhuaReverseSource -Algorithm SHA256).Hash.ToLowerInvariant()
$erhuaReverseRows = [Math]::Max(0, (Get-Content -LiteralPath $erhuaReverseSource -Encoding UTF8).Count - 1)
if ([string]$erhuaMixed.output_sha256.'yime_erhua_reverse_source.tsv' -ne $erhuaReverseHash -or
    $erhuaReverseRows -ne [int64]$erhuaMixed.summary.reverse_lookup_row_count) {
    throw 'Explicit-erhua reverse sidecar does not match its manifest or expected row count.'
}
$pscPeripheral = Get-Content -LiteralPath $pscPeripheralManifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not [bool]$pscPeripheral.summary.passed -or
    [int64]$pscPeripheral.summary.source_record_count -ne 315 -or
    ([int64]$pscPeripheral.summary.neutral_tone_record_count + [int64]$pscPeripheral.summary.erhua_record_count) -ne [int64]$pscPeripheral.summary.source_record_count -or
    ([int64]$pscPeripheral.summary.encoded_record_count + [int64]$pscPeripheral.summary.already_in_core_record_count) -ne [int64]$pscPeripheral.summary.source_record_count -or
    [int64]$pscPeripheral.summary.runtime_rows_per_mode -ne [int64]$pscPeripheral.summary.encoded_record_count -or
    [int64]$pscPeripheral.summary.sentence_rows_per_mode -ne [int64]$pscPeripheral.summary.encoded_record_count -or
    [int64]$pscPeripheral.summary.fixed_peripheral_weight -ne 1) {
    throw 'PSC pronunciation peripheral manifest did not pass its completeness gates.'
}
foreach ($mode in @('full', 'variable', 'shorthand')) {
    foreach ($name in @("yime_psc_peripheral_${mode}.dict.yaml", "yime_psc_peripheral_sentence_${mode}.dict.yaml")) {
        $path = Join-Path $root "go-backend\input_methods\yime\data\$name"
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ([string]$pscPeripheral.output_sha256.$name -ne $hash) {
            throw "PSC pronunciation peripheral dictionary hash mismatch: $name"
        }
    }
}
$thirdToneStage5C = Get-Content -LiteralPath $thirdToneStage5CManifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not [bool]$thirdToneStage5C.summary.passed -or
    [int64]$thirdToneStage5C.summary.approved_alias_count -ne 24 -or
    [int64]$thirdToneStage5C.summary.three_mode_row_count -ne 72 -or
    [int64]$thirdToneStage5C.summary.fixed_runtime_weight -ne 1 -or
    -not [bool]$thirdToneStage5C.summary.canonical_routes_preserved) {
    throw 'Third-tone Stage 5C runtime manifest did not pass its completeness gates.'
}
foreach ($mode in @('full', 'variable', 'shorthand')) {
    $name = "yime_third_tone_stage5c_${mode}.dict.yaml"
    $path = Join-Path $root "go-backend\input_methods\yime\data\$name"
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$thirdToneStage5C.output_sha256.$name -ne $hash) {
        throw "Third-tone Stage 5C dictionary hash mismatch: $name"
    }
}
$particleAStage6D = Get-Content -LiteralPath $particleAStage6DManifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not [bool]$particleAStage6D.summary.passed -or
    [int64]$particleAStage6D.summary.excluded_candidate_count -ne 42 -or
    [int64]$particleAStage6D.summary.eligible_candidate_count -ne 6679 -or
    [int64]$particleAStage6D.summary.eligible_occurrence_count -ne 6680 -or
    [int64]$particleAStage6D.summary.retained_medial_candidate_count -ne 29 -or
    [int64]$particleAStage6D.summary.final_candidate_count -ne 6651 -or
    [int64]$particleAStage6D.summary.key_changing_candidate_count -ne 5618 -or
    [int64]$particleAStage6D.summary.shared_key_candidate_count -ne 1061 -or
    [int64]$particleAStage6D.summary.materialized_candidate_count -ne 5618 -or
    [int64]$particleAStage6D.summary.mode_row_counts.full -ne 5618 -or
    [int64]$particleAStage6D.summary.mode_row_counts.variable -ne 5618 -or
    [int64]$particleAStage6D.summary.mode_row_counts.shorthand -ne 5618 -or
    [int64]$particleAStage6D.summary.three_mode_row_count -ne 16854 -or
    [int64]$particleAStage6D.summary.fixed_runtime_weight -ne 1 -or
    -not [bool]$particleAStage6D.summary.canonical_routes_preserved) {
    throw 'Particle-a Stage 6D runtime manifest did not pass its completeness gates.'
}
foreach ($mode in @('full', 'variable', 'shorthand')) {
    $name = "yime_particle_a_stage6d_${mode}.dict.yaml"
    $path = Join-Path $root "go-backend\input_methods\yime\data\$name"
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$particleAStage6D.output_sha256.$name -ne $hash) {
        throw "Particle-a Stage 6D dictionary hash mismatch: $name"
    }
}
$systemExclusionRows = @(Import-Csv -LiteralPath $systemCandidateExclusions -Delimiter "`t" -Encoding UTF8)
if ($systemExclusionRows.Count -ne 42) {
    throw "System candidate exclusion gate has $($systemExclusionRows.Count) rows instead of 42."
}
foreach ($row in $systemExclusionRows) {
    if ($row.category -ne 'unverifiable_particle_a_fragment' -or
        $row.source_snapshot -ne 'wanxiang' -or
        $row.decision -ne 'exclude_runtime_candidate' -or
        [string]::IsNullOrWhiteSpace($row.note)) {
        throw "System candidate exclusion gate contains an invalid policy row: $($row.text)"
    }
    $characters = $row.text.ToCharArray()
    if ($characters.Count -ne 3 -or
        [int]$characters[1] -ne 0x554A -or
        $characters[0] -eq $characters[2]) {
        throw "System candidate exclusion gate contains a non-medial or reduplicative row: $($row.text)"
    }
}
Write-Host 'Curated core evidence and three-mode package guards passed.'
$prereqText = Get-Content -LiteralPath $buildPrereqs -Raw
foreach ($guard in @('stable-i686-pc-windows-msvc', 'third_party/corrosion', 'vendored-sources', 'RequireBuildArtifacts')) {
    if (-not $prereqText.Contains($guard)) {
        throw "Win32 prerequisite guard is missing: $guard"
    }
}
$buildEnvironmentText = Get-Content -LiteralPath $buildEnvironment -Raw
$cmakeEnvironmentText = Get-Content -LiteralPath $cmakeEnvironment -Raw
if (-not $buildEnvironmentText.Contains('initialize-dev-environment.ps1') -or -not $cmakeEnvironmentText.Contains('initialize-dev-environment.ps1')) {
    throw 'Build and VS Code CMake entry points must share proxy/PATH initialization.'
}
$realRimeText = Get-Content -LiteralPath $realRimeTest -Raw
foreach ($guard in @('go test -v', 'TestRealRimeKeepsCandidatesWhileCompletingFinalSyllable', 'TestRealRimeLongSessionSwitchesFirstMiddleAndFinalSegments', 'TestRealRimeParticleAStage6DDualTrackAcrossAllThreeSchemas', 'TestRealRimeExternalBuildAppliesPageSize')) {
    if (-not $realRimeText.Contains($guard)) {
        throw "Real librime CI guard is missing: $guard"
    }
}
$readmeText = Get-Content -LiteralPath $readme -Raw
if ($readmeText.Contains('[Node.js]')) {
    throw 'Retired Node.js build prerequisite returned to README.md.'
}
$installerText = Get-Content -LiteralPath $installer -Raw
if ($installerText -match 'YIME_ENABLE_RETIRED_PIME_BACKENDS|\\python\\|\\node\\|McBopomofo|libchewing') {
    throw 'Retired PIME backend code or paths returned to the YIME installer.'
}
$launcherCargoConfigText=Get-Content -LiteralPath $launcherCargoConfig -Raw
$verifierText=Get-Content -LiteralPath $verifier -Raw
$peImportGateTestText=Get-Content -LiteralPath $peImportGateTest -Raw
if(-not $launcherCargoConfigText.Contains('target-feature=+crt-static') -or
    [regex]::Matches($verifierText,'VerifyStaticCrt\s*=\s*\$true').Count -ne 11 -or
    $verifierText -notmatch 'X86Launcher[^\r\n]+VerifyStaticCrt\s*=\s*\$true' -or
    [regex]::Matches($verifierText,'PIMETextService\.dll''; VerifyStaticCrt = \$true').Count -ne 3 -or
    [regex]::Matches($verifierText,'PIMERegistrationStatus\.exe''; VerifyStaticCrt = \$true').Count -ne 3 -or
    $verifierText -notmatch 'RimeDll[^\r\n]+VerifyStaticCrt\s*=\s*\$true' -or
    $verifierText -notmatch 'RimeDeployer[^\r\n]+VerifyStaticCrt\s*=\s*\$true' -or
    $verifierText -notmatch 'RimeDictManager[^\r\n]+VerifyStaticCrt\s*=\s*\$true'){
    throw 'Native package components are not all guarded as static-CRT binaries.'
}
foreach ($guard in @(
    'Read-PeNormalImportNames',
    'Read-PeDelayImportNames',
    '$dataDirectoryOffset + (13 * 8)',
    'requires both -Arm64TextService and -Arm64RegistrationStatus explicitly',
    'msvcr.*',
    'api-ms-win-crt.*'
)) {
    if (-not $verifierText.Contains($guard)) {
        throw "PE normal/delay import closure guard is missing: $guard"
    }
}
foreach ($guard in @(
    'accepts-safe-normal-import',
    'accepts-safe-delay-import',
    'default-gate-ignores-unselected-stale-arm64-build-tree',
    'accepts-explicit-paired-arm64-inputs',
    'rejects-one-sided-arm64-input',
    'rejects-msvcr-in-normal-import-directory',
    "-ImportKind normal -ImportedDll 'msvcr120.dll'",
    'rejects-vcruntime-in-delay-import-directory',
    "-ImportKind delay -ImportedDll 'vcruntime140.dll'",
    'synthetic_pe_images_executed = $false'
)) {
    if (-not $peImportGateTestText.Contains($guard)) {
        throw "Synthetic PE import regression guard is missing: $guard"
    }
}
if (-not $workflowText.Contains('Test normal and delay PE import static CRT rejection') -or
    [regex]::Matches($workflowText,'test-pe-import-gate\.ps1').Count -ne 2) {
    throw 'CI must run the non-executing normal/delay PE import gate under PowerShell 5.1 and 7.'
}
if (-not $workflowText.Contains('Test pre-package copy-stage contract') -or
    [regex]::Matches($workflowText,'test-rime-pime-package-staging\.ps1').Count -ne 2) {
    throw 'CI must run the isolated pre-package copy-stage contract under PowerShell 5.1 and 7.'
}
if ($installerText -match 'DownloadVerifiedVCRedist|ensureVCRedist|vc_redist\.|inetc::get') {
    throw 'A runtime download path returned even though every packaged native component is static-CRT guarded.'
}
$localeText = ($installerLocales | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
if (-not $installerText.Contains('${IfNot} ${AtLeastWin10}') -or
    -not $installerText.Contains('${IfNot} ${AtLeastBuild} 18362') -or
    [regex]::Matches($installerText,'AtLeastWin10_1903_MESSAGE').Count -ne 2 -or
    $installerText.Contains('AtLeastWinVista') -or
    [regex]::Matches($localeText,'AtLeastWin10_1903_MESSAGE').Count -ne 3 -or
    $localeText.Contains('AtLeastWinVista')) {
    throw 'Installer and locale minimum-OS contract must remain Windows 10 version 1903.'
}
foreach ($localeFile in $installerLocales) {
    $oneLocale = Get-Content -LiteralPath $localeFile.FullName -Raw
    if ([regex]::Matches($oneLocale,'AtLeastWin10_1903_MESSAGE').Count -ne 1 -or
        -not $oneLocale.Contains('1903') -or $oneLocale.Contains('AtLeastWinVista')) {
        throw "Installer minimum-OS locale drifted: $($localeFile.Name)"
    }
}
$installInitText = [regex]::Match($installerText,
    '(?ms)^Function \.onInit\s+(.*?)^FunctionEnd').Groups[1].Value
$uninstallInitText = [regex]::Match($installerText,
    '(?ms)^Function un\.onInit\s+(.*?)^FunctionEnd').Groups[1].Value
$osGateIndex = $installInitText.IndexOf('${IfNot} ${AtLeastWin10}')
$buildGateIndex = $installInitText.IndexOf('${IfNot} ${AtLeastBuild} 18362')
$bootstrapIndex = $installInitText.IndexOf('Call bootstrapTargetUser')
if ([regex]::Matches($installerText,'(?m)^ManifestSupportedOS[ \t]+all[ \t]*\r?$').Count -ne 1 -or
    $osGateIndex -lt 0 -or $buildGateIndex -le $osGateIndex -or $bootstrapIndex -le $buildGateIndex -or
    [regex]::Matches($workflowText,'nsis-version: 3\.12').Count -ne 3 -or
    $workflowText.Contains('nsis-version: 3.08')) {
    throw 'Real Windows version reporting, pre-bootstrap admission, or the NSIS 3.12 build pin drifted.'
}
$rootPolicy=$installInitText.IndexOf('Call enforceInstallRootPolicy')
$targetBootstrap=$installInitText.IndexOf('Call bootstrapTargetUser')
if ($rootPolicy -lt 0 -or $targetBootstrap -le $rootPolicy -or
    -not $installerText.Contains('GetFullPathName $R0 "$PROGRAMFILES32\YIME"') -or
    -not $installerText.Contains('Command-line /D overrides and user-writable roots are not admitted.')) {
    throw 'Installer must reject alternate or user-writable roots before same-SID bootstrap.'
}
$arm64InstallBranch = [regex]::Match($installInitText,
    '(?ms)\$\{If\} \$\{IsNativeARM64\}(.*?)\$\{ElseIf\} \$\{IsNativeAMD64\}').Groups[1].Value
if (-not $arm64InstallBranch.Contains('Arm64X text-service surface') -or
    -not $arm64InstallBranch.Contains('x64-emulated') -or
    -not $arm64InstallBranch.Contains('Abort') -or
    $arm64InstallBranch.Contains('StrCpy $RimeNativeArchitecture "arm64"') -or
    $arm64InstallBranch.Contains('StrCpy $UPDATEARM64DLL "True"')) {
    throw 'Windows ARM64 installation must remain fail closed until Arm64X and all three host surfaces are sealed.'
}
$installerBuilderText = Get-Content -LiteralPath $installerBuilder -Raw
if($installerBuilderText -match '\[string\]\$RepoRoot\s*=\s*\(Split-Path\s+-Parent\s+\$PSScriptRoot\)' -or
    -not $installerBuilderText.Contains('if([string]::IsNullOrWhiteSpace($RepoRoot)){$RepoRoot=Split-Path -Parent $PSScriptRoot}')){
    throw 'The Rime/PIME builder must resolve its default repository root in the script body for PowerShell 5.1 compatibility.'
}
$buildLogicLeaseStart=$installerBuilderText.IndexOf('$buildLogicLeases=[Collections.Generic.List[object]]::new()')
$firstBuildLogicOpen=$installerBuilderText.IndexOf('$stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)',$buildLogicLeaseStart)
$firstModuleImport=$installerBuilderText.IndexOf('Import-Module -Name $stagingModule -Force')
$postImportTopology=$installerBuilderText.IndexOf('$record=Get-YimePimePayloadFileRecord $lease.Path',$firstModuleImport)
$firstPackageRead=$installerBuilderText.IndexOf('$package=Read-RimePimePackagePlan',$postImportTopology)
$stageLeaseOpen=$installerBuilderText.IndexOf('$leases=Open-RimePimeBuildInputLeases $expected',$firstPackageRead)
$stagedPeVerify=$installerBuilderText.IndexOf('& $stagePeVerifier -RepoRoot $stageResult.StageRoot',$stageLeaseOpen)
$makensisCall=$installerBuilderText.IndexOf('& $MakensisPath @arguments',$stagedPeVerify)
if($buildLogicLeaseStart -lt 0 -or $firstBuildLogicOpen -le $buildLogicLeaseStart -or
    $firstModuleImport -le $firstBuildLogicOpen -or $postImportTopology -le $firstModuleImport -or
    $firstPackageRead -le $postImportTopology -or $stageLeaseOpen -le $firstPackageRead -or
    $stagedPeVerify -le $stageLeaseOpen -or $makensisCall -le $stagedPeVerify -or
    -not $installerBuilderText.Contains('Build-logic source traverses a reparse point before import') -or
    -not $installerBuilderText.Contains('Hard-linked build-logic source rejected before import') -or
    -not $installerBuilderText.Contains('Alternate data stream on build-logic source rejected before import') -or
    -not $installerBuilderText.Contains("(Join-Path `$root 'tools\verify-pe-architectures.ps1')") -or
    -not $installerBuilderText.Contains('staged_pe_architecture_verified_under_read_leases=$true')){
    throw 'Every executable build-logic source, including the PE verifier, must be read-leased and topology-checked before import or invocation.'
}
$packagePlanModuleText = Get-Content -LiteralPath $packagePlanModule -Raw
$packageStagingModuleText = Get-Content -LiteralPath $packageStagingModule -Raw
$nsisStageGeneratorText = Get-Content -LiteralPath $nsisStageGenerator -Raw
$stagedBuildHelperText = Get-Content -LiteralPath $stagedBuildHelper -Raw
$stagedBuildTestText = Get-Content -LiteralPath $stagedBuildTest -Raw
$stagedBuilderCombinedText = $installerBuilderText + "`n" + $stagedBuildHelperText
$nsisStageTestText = Get-Content -LiteralPath $nsisStageTest -Raw
$rootBuildPowerShellText = Get-Content -LiteralPath $rootBuildPowerShell -Raw
$rootBuildCommandText = Get-Content -LiteralPath $rootBuildCommand -Raw
if ($installerText.Contains('!if /FileExists "..\build_arm64') -or
    $installerText.Contains('HAVE_ARM64_PIMETS') -or
    $installerText.Contains('INCLUDE_ARM64_ARTIFACTS') -or
    -not $installerText.Contains('!ifndef PACKAGE_PLAN_SHA256') -or
    -not $installerText.Contains('!ifndef PACKAGE_PLAN_X86_X64') -or
    -not $installerText.Contains('!ifdef PACKAGE_PLAN_X86_ARM64X') -or
    -not $installerText.Contains('!ifndef PACKAGE_STAGE_ROOT') -or
    -not $installerText.Contains('!ifndef PACKAGE_STAGE_MANIFEST_SHA256') -or
    -not $installerText.Contains('!ifndef PACKAGE_STAGE_CONTENT_SHA256') -or
    -not $installerText.Contains('!ifndef PACKAGE_PAYLOAD_NSH_PATH') -or
    -not $installerText.Contains('!ifndef PACKAGE_PAYLOAD_NSH_SHA256') -or
    -not $installerText.Contains('!ifndef PACKAGE_OUTPUT_PATH') -or
    -not $installerText.Contains('!include "${PACKAGE_PAYLOAD_NSH_PATH}"') -or
    -not $installerText.Contains('!define /file PRODUCT_VERSION "${PACKAGE_STAGE_ROOT}\payload\version.txt"') -or
    -not $installerText.Contains('OutFile "${PACKAGE_OUTPUT_PATH}"') -or
    -not $installerBuilderText.Contains('Read-RimePimePackagePlan -RepoRoot $root -PlanPath $PackagePlanPath -VerifyArtifacts') -or
    -not $installerBuilderText.Contains('New-RimePimePackageCopyStage') -or
    -not $installerBuilderText.Contains('Write-RimePimeNsisStageInclude') -or
    -not $installerBuilderText.Contains('RefreshReceiptOnly is not admitted after staged NSIS consumption') -or
    -not $installerBuilderText.Contains('only builds an unsigned disabled package') -or
    -not $installerBuilderText.Contains('YIME_SIGN_CERT_SHA1') -or
    -not $installerBuilderText.Contains('YIME_RELEASE_SIGNING_REQUIRED') -or
    -not $installerBuilderText.Contains('YIME_SIGNTOOL_EXE') -or
    -not $installerBuilderText.Contains('YIME_TIMESTAMP_URL') -or
    -not $installerBuilderText.Contains('"/DPACKAGE_PLAN_SHA256=$($package.Digest)"') -or
    -not $installerBuilderText.Contains("'/DPACKAGE_PLAN_X86_X64=1'") -or
    -not $installerBuilderText.Contains('"/DPACKAGE_STAGE_ROOT=$($stageResult.StageRoot)"') -or
    -not $installerBuilderText.Contains('"/DPACKAGE_STAGE_MANIFEST_SHA256=$($stageResult.ContentManifestDigest)"') -or
    -not $installerBuilderText.Contains('"/DPACKAGE_STAGE_CONTENT_SHA256=$($content.Manifest.content_tree_sha256)"') -or
    -not $installerBuilderText.Contains('"/DPACKAGE_PAYLOAD_NSH_PATH=$($include.IncludePath)"') -or
    -not $installerBuilderText.Contains('"/DPACKAGE_PAYLOAD_NSH_SHA256=$($include.IncludeDigest)"') -or
    -not $installerBuilderText.Contains('"/DPACKAGE_OUTPUT_PATH=$candidate"') -or
    -not $installerBuilderText.Contains("'/NOCD','/NOCONFIG'") -or
    -not $installerBuilderText.Contains('"/DPACKAGE_LOCALE_ROOT=$localeRoot"') -or
    -not $installerBuilderText.Contains("'/DPACKAGE_UNSIGNED_DISABLED_BUILD=1'") -or
    -not $installerBuilderText.Contains('signing_hook_processes_executed=$false') -or
    $installerBuilderText.Contains('/DPACKAGE_SIGN_FILE_PATH=') -or
    $installerBuilderText.Contains('/DPACKAGE_POWERSHELL_PATH=') -or
    -not $installerBuilderText.Contains('Push-Location $nsisIncludeRoot') -or
    [regex]::Matches($installerBuilderText,'Import-Module -Name \$(?:stagingModule|nsisStageModule|stagedBuildModule) -Force').Count -ne 3 -or
    -not $installerBuilderText.Contains('$buildLogicDigests') -or
    -not $packagePlanModuleText.Contains('function Read-RimePimePackagePlan') -or
    -not $packagePlanModuleText.Contains("closure_scope='declared-packaged-product-pe-inputs-only-not-installed-payload'") -or
    -not $packagePlanModuleText.Contains('Get-RimePimePackagedPePaths') -or
    -not $packagePlanModuleText.Contains('PE set is not the exact sealed allowlist') -or
    -not $rootBuildPowerShellText.Contains('rime-pime-package-plan.ps1') -or
    -not $rootBuildPowerShellText.Contains('-WritePlan -PlanRepoRoot $repoRoot -OutputPlanPath $planPath') -or
    -not $rootBuildPowerShellText.Contains('build-rime-pime-installer.ps1') -or
    -not $rootBuildPowerShellText.Contains('write-build-manifest.ps1') -or
    -not $rootBuildPowerShellText.Contains('Build.ps1 is an unsigned development entry') -or
    $rootBuildPowerShellText -match '(?i)\bmakensis(?:\.exe)?\b' -or
    -not $rootBuildCommandText.Contains('-File "%~dp0Build.ps1"') -or
    $rootBuildCommandText -match '(?i)makensis|installer\.nsi' -or
    [regex]::Matches($workflowText,'build-rime-pime-installer\.ps1').Count -ne 2 -or
    $workflowText.Contains("& 'C:\Program Files (x86)\NSIS\Bin\makensis.exe'") -or
    $workflowText.Contains('IncludeArm64Artifacts') -or
    $workflowText.Contains('INCLUDE_ARM64_ARTIFACTS')) {
    throw 'Current packaging must be bound to the sealed x86/x64 package plan and reject implicit ARM64 artifacts.'
}
$stageMacroCalls = [ordered]@{
    YimePimeStageTargetUserHelpers = 1
    YimePimeStageOwnershipHelpers = 1
    YimePimeStageRegistrationTools = 2
    YimePimeStageMainPayload = 1
    YimePimeStageTextServiceX86 = 1
    YimePimeStageTextServiceX64 = 1
}
foreach ($entry in $stageMacroCalls.GetEnumerator()) {
    $callPattern = '!insertmacro\s+' + [regex]::Escape([string]$entry.Key) + '(?:\s|$)'
    $definitionPattern = 'Add-RimePimeNsisMacro\s+\$lines\s+''' + [regex]::Escape([string]$entry.Key) + ''''
    if ([regex]::Matches($installerText, $callPattern).Count -ne [int]$entry.Value -or
        [regex]::Matches($nsisStageGeneratorText, $definitionPattern).Count -ne 1) {
        throw "Rime/PIME stage macro definition or call-site count drifted: $($entry.Key)"
    }
}
$directInstallerFiles = [regex]::Matches($installerText, '(?mi)^[ \t]*File(?:[ \t]|$)')
if ($directInstallerFiles.Count -ne 0 -or $installerText -match '(?mi)^[ \t]*File[ \t]+/r\b' -or
    $installerText -match '(?mi)^[ \t]*File[^\r\n]*\.\.\\') {
    throw 'installer.nsi must not read product bytes directly or recursively outside the sealed package stage.'
}
$bareBuiltinInclude='(?mi)^[ \t]*!include[ \t]+"(?:MUI2|x64|Winver|LogicLib|FileFunc)\.nsh"'
foreach($name in @('MUI2','x64','Winver','LogicLib','FileFunc')){
    if($installerText -match $bareBuiltinInclude -or
        -not $installerText.Contains('!include "${NSISDIR}\Include\'+$name+'.nsh"')){
        throw 'NSIS built-in includes must use the fixed NSISDIR path so repository-local shadow files cannot become compiler inputs.'
    }
}
if(-not $installerText.Contains('!include "${PACKAGE_LOCALE_ROOT}\${LANGLOAD}.nsh"') -or
    $installerText.Contains('!include "locale\${LANGLOAD}.nsh"') -or
    -not $installerText.Contains('-File "${PACKAGE_SIGN_FILE_PATH}"') -or
    $installerText.Contains('-File "..\tools\sign-file.ps1"') -or
    -not $installerText.Contains('!ifndef PACKAGE_UNSIGNED_DISABLED_BUILD') -or
    -not $installerText.Contains('!ifndef PACKAGE_POWERSHELL_PATH') -or
    [regex]::Matches($installerText,'(?m)^!(?:uninst)?finalize\s+''"\$\{PACKAGE_POWERSHELL_PATH\}"').Count -ne 2 -or
    $installerText -match '(?mi)^!(?:uninst)?finalize\s+''powershell\.exe\b'){
    throw 'Repository-local locale and signing-hook inputs must be absolute build definitions when makensis runs with /NOCD.'
}
if (-not $nsisStageTestText.Contains('definitions-only-module-generates-six-stage-only-macros') -or
    -not $nsisStageTestText.Contains('macro_file_reference_count') -or
    -not $nsisStageTestText.Contains('PACKAGE_STAGE_ROOT')) {
    throw 'The six-macro stage-only generator contract is not protected by its isolated synthetic test.'
}
$builderTokens=$null;$builderParseErrors=$null
$builderAst=[Management.Automation.Language.Parser]::ParseFile($installerBuilder,[ref]$builderTokens,[ref]$builderParseErrors)
if(@($builderParseErrors).Count -ne 0){
    throw ('Rime/PIME installer builder has PowerShell parse errors: '+(($builderParseErrors|ForEach-Object{$_.Message}) -join '; '))
}
$builderCommands=@($builderAst.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true))
$builderAssignments=@($builderAst.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst]},$true))
$monitorOpenCommands=@($builderCommands|Where-Object{$_.GetCommandName() -ceq 'Open-RimePimeMonitoredNsisStage'})
$monitorCompleteCommands=@($builderCommands|Where-Object{$_.GetCommandName() -ceq 'Complete-RimePimeMonitoredNsisStage'})
$preparedPublicationCommands=@($builderCommands|Where-Object{$_.GetCommandName() -ceq 'New-RimePimePreparedPublication'})
$publicationCommitCommands=@($builderCommands|Where-Object{$_.GetCommandName() -ceq 'Invoke-RimePimePublicationCommit'})
$monitorCloseCommands=@($builderCommands|Where-Object{$_.GetCommandName() -ceq 'Close-RimePimeMonitoredNsisStage'})
$makensisCommands=@($builderCommands|Where-Object{
    $_.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Ampersand -and
    $_.CommandElements.Count -gt 0 -and $_.CommandElements[0] -is [Management.Automation.Language.VariableExpressionAst] -and
    $_.CommandElements[0].VariablePath.UserPath -ceq 'MakensisPath'
})
$inputLeaseCommands=@($builderCommands|Where-Object{$_.GetCommandName() -ceq 'Open-RimePimeBuildInputLeases'})
$prebuildLeaseAssignments=@($builderAssignments|Where-Object{
    $assignment=$_
    $opens=@($assignment.Right.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Open-RimePimeBuildInputLeases'},$true))
    $assignment.Left.Extent.Text -ceq '$leases' -and $opens.Count -eq 1 -and
    $opens[0].CommandElements.Count -eq 2 -and $opens[0].CommandElements[1].Extent.Text -ceq '$expected'
})
$candidateLeaseAssignments=@($builderAssignments|Where-Object{
    $assignment=$_
    $opens=@($assignment.Right.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Open-RimePimeBuildInputLeases'},$true))
    $assignment.Left.Extent.Text -ceq '$candidateLeases' -and $opens.Count -eq 1 -and
    $opens[0].CommandElements.Count -eq 2 -and $opens[0].CommandElements[1].Extent.Text -ceq '$candidateExpected'
})
$candidateProbeCommands=@($builderCommands|Where-Object{
    $_.GetCommandName() -ceq 'Test-Path' -and $_.CommandElements.Count -eq 5 -and
    $_.CommandElements[1] -is [Management.Automation.Language.CommandParameterAst] -and
    $_.CommandElements[1].ParameterName -ceq 'LiteralPath' -and
    $_.CommandElements[2] -is [Management.Automation.Language.VariableExpressionAst] -and
    $_.CommandElements[2].VariablePath.UserPath -ceq 'candidate' -and
    $_.CommandElements[3] -is [Management.Automation.Language.CommandParameterAst] -and
    $_.CommandElements[3].ParameterName -ceq 'PathType' -and
    $_.CommandElements[4] -is [Management.Automation.Language.StringConstantExpressionAst] -and
    [string]$_.CommandElements[4].Value -ceq 'Leaf'
})
$candidateRecordAssignments=@($builderAssignments|Where-Object{
    $assignment=$_
    $records=@($assignment.Right.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Get-YimePimePayloadFileRecord'},$true))
    $assignment.Left.Extent.Text -ceq '$candidateRecord' -and $records.Count -eq 1 -and
    $records[0].CommandElements.Count -eq 2 -and
    $records[0].CommandElements[1] -is [Management.Automation.Language.VariableExpressionAst] -and
    $records[0].CommandElements[1].VariablePath.UserPath -ceq 'candidate'
})
$makensisExitGates=@($builderAst.FindAll({param($node) $node -is [Management.Automation.Language.IfStatementAst]},$true)|Where-Object{
    $ifNode=$_
    $binary=$null
    if($ifNode.Clauses.Count -eq 1){
        $condition=$ifNode.Clauses[0].Item1
        if($condition.PipelineElements.Count -eq 1 -and
            $condition.PipelineElements[0] -is [Management.Automation.Language.CommandExpressionAst] -and
            $condition.PipelineElements[0].Expression -is [Management.Automation.Language.BinaryExpressionAst]){
            $binary=$condition.PipelineElements[0].Expression
        }
    }
    $null -ne $binary -and $null -eq $ifNode.ElseClause -and
    $binary.Operator -eq [Management.Automation.Language.TokenKind]::Ine -and
    $binary.Left -is [Management.Automation.Language.VariableExpressionAst] -and
    $binary.Left.VariablePath.UserPath -ceq 'LASTEXITCODE' -and
    $binary.Right -is [Management.Automation.Language.ConstantExpressionAst] -and
    $binary.Right.Value -is [int] -and [int]$binary.Right.Value -eq 0 -and
    $ifNode.Clauses[0].Item2.Statements.Count -eq 1 -and
    $ifNode.Clauses[0].Item2.Statements[0] -is [Management.Automation.Language.ThrowStatementAst]
})
if($monitorOpenCommands.Count -ne 1 -or $monitorCompleteCommands.Count -ne 1 -or
    $preparedPublicationCommands.Count -ne 1 -or $publicationCommitCommands.Count -ne 1 -or
    $monitorCloseCommands.Count -ne 1 -or $makensisCommands.Count -ne 1 -or
    $inputLeaseCommands.Count -ne 2 -or $prebuildLeaseAssignments.Count -ne 1 -or
    $candidateProbeCommands.Count -ne 1 -or $candidateRecordAssignments.Count -ne 1 -or
    $candidateLeaseAssignments.Count -ne 1 -or $makensisExitGates.Count -ne 1){
    throw 'The builder must have one AST-visible monitored makensis lifecycle, candidate admission, preparation, and commit path.'
}
$makensisCommand=$makensisCommands[0]
if($makensisCommand.CommandElements.Count -ne 2 -or
    $makensisCommand.CommandElements[1] -isnot [Management.Automation.Language.VariableExpressionAst] -or
    -not $makensisCommand.CommandElements[1].Splatted -or
    $makensisCommand.CommandElements[1].VariablePath.UserPath -cne 'arguments'){
    throw 'The sole makensis command must use the reviewed splatted disabled-build argument array.'
}
$monitorOpen=$monitorOpenCommands[0]
$monitorComplete=$monitorCompleteCommands[0]
$preparedPublication=$preparedPublicationCommands[0]
$publicationCommit=$publicationCommitCommands[0]
$monitorClose=$monitorCloseCommands[0]
$membershipAssignments=@($builderAssignments|Where-Object{
    $_.Left.Extent.Text -ceq '$membershipInterval' -and
    $_.Right.Extent.StartOffset -le $monitorComplete.Extent.StartOffset -and
    $_.Right.Extent.EndOffset -ge $monitorComplete.Extent.EndOffset
})
$buildResultAssignments=@($builderAssignments|Where-Object{$_.Left.Extent.Text -ceq '$buildResult'})
$buildResultHashtables=@()
if($buildResultAssignments.Count -eq 1){
    $buildResultHashtables=@($buildResultAssignments[0].Right.FindAll({param($node) $node -is [Management.Automation.Language.HashtableAst]},$true)|Where-Object{
        $ancestor=$_.Parent
        while($ancestor -is [Management.Automation.Language.ConvertExpressionAst]){$ancestor=$ancestor.Parent}
        $ancestor -eq $buildResultAssignments[0].Right
    })
}
$schemaResultPairs=@()
$membershipResultPairs=@()
if($buildResultHashtables.Count -eq 1){
    $schemaResultPairs=@($buildResultHashtables[0].KeyValuePairs|Where-Object{
        $_.Item1 -is [Management.Automation.Language.StringConstantExpressionAst] -and
        [string]$_.Item1.Value -ceq 'schema_version'
    })
    $membershipResultPairs=@($buildResultHashtables[0].KeyValuePairs|Where-Object{
        $_.Item1 -is [Management.Automation.Language.StringConstantExpressionAst] -and
        [string]$_.Item1.Value -ceq 'nsis_compiler_membership_interval'
    })
}
if($buildResultAssignments.Count -ne 1 -or $buildResultHashtables.Count -ne 1 -or
    $schemaResultPairs.Count -ne 1 -or $membershipResultPairs.Count -ne 1){
    throw 'The successful buildResult must contain one exact schema_version and one nsis_compiler_membership_interval binding.'
}
$schemaResultValue=$schemaResultPairs[0].Item2
if($schemaResultValue -isnot [Management.Automation.Language.PipelineAst] -or
    $schemaResultValue.PipelineElements.Count -ne 1 -or
    $schemaResultValue.PipelineElements[0] -isnot [Management.Automation.Language.CommandExpressionAst] -or
    $schemaResultValue.PipelineElements[0].Expression -isnot [Management.Automation.Language.StringConstantExpressionAst] -or
    [string]$schemaResultValue.PipelineElements[0].Expression.Value -cne 'yime-rime-pime-staged-nsis-build-result-membership-interval-v1'){
    throw 'The successful buildResult schema_version must be the exact literal yime-rime-pime-staged-nsis-build-result-membership-interval-v1; bare result-v3 is not admissible.'
}
$membershipResultValue=$membershipResultPairs[0].Item2
if($membershipResultValue -isnot [Management.Automation.Language.PipelineAst] -or
    $membershipResultValue.PipelineElements.Count -ne 1 -or
    $membershipResultValue.PipelineElements[0] -isnot [Management.Automation.Language.CommandExpressionAst] -or
    $membershipResultValue.PipelineElements[0].Expression -isnot [Management.Automation.Language.VariableExpressionAst] -or
    $membershipResultValue.PipelineElements[0].Expression.VariablePath.UserPath -cne 'membershipInterval'){
    throw 'The successful buildResult membership binding must have the exact value $membershipInterval.'
}
$monitorOwningTries=@($builderAst.FindAll({param($node) $node -is [Management.Automation.Language.TryStatementAst]},$true)|Where-Object{
    $null -ne $_.Finally -and
    $_.Body.Extent.StartOffset -le $monitorOpen.Extent.StartOffset -and
    $_.Body.Extent.EndOffset -ge $publicationCommit.Extent.EndOffset -and
    $_.Finally.Extent.StartOffset -le $monitorClose.Extent.StartOffset -and
    $_.Finally.Extent.EndOffset -ge $monitorClose.Extent.EndOffset
})
if($membershipAssignments.Count -ne 1 -or $monitorOwningTries.Count -ne 1){
    throw 'Membership completion must be assigned once before publication and the monitor must close in the owning finally.'
}
$monitorCloseGuards=@($monitorOwningTries[0].Finally.FindAll({param($node) $node -is [Management.Automation.Language.IfStatementAst]},$true)|Where-Object{
    $guardIf=$_
    $guardBinary=$null
    if($guardIf.Clauses.Count -eq 1){
        $guardCondition=$guardIf.Clauses[0].Item1
        if($guardCondition.PipelineElements.Count -eq 1 -and
            $guardCondition.PipelineElements[0] -is [Management.Automation.Language.CommandExpressionAst] -and
            $guardCondition.PipelineElements[0].Expression -is [Management.Automation.Language.BinaryExpressionAst]){
            $guardBinary=$guardCondition.PipelineElements[0].Expression
        }
    }
    $null -ne $guardBinary -and $guardBinary.Operator -eq [Management.Automation.Language.TokenKind]::Ine -and
    $guardBinary.Left -is [Management.Automation.Language.VariableExpressionAst] -and
    $guardBinary.Left.VariablePath.UserPath -ceq 'null' -and
    $guardBinary.Right -is [Management.Automation.Language.VariableExpressionAst] -and
    $guardBinary.Right.VariablePath.UserPath -ceq 'compilerStage' -and
    $guardIf.Clauses[0].Item2.Extent.StartOffset -le $monitorClose.Extent.StartOffset -and
    $guardIf.Clauses[0].Item2.Extent.EndOffset -ge $monitorClose.Extent.EndOffset
})
if($monitorCloseGuards.Count -ne 1){
    throw 'Close-RimePimeMonitoredNsisStage must be inside the unique $null -ne $compilerStage guard in the owning finally.'
}
$leaseOpen = $installerBuilderText.IndexOf('$leases=Open-RimePimeBuildInputLeases $expected')
$preLease = if ($leaseOpen -ge 0) { $installerBuilderText.IndexOf('Test-RimePimeBuildInputLeases @($leases)', $leaseOpen) } else { -1 }
$preStage = $installerBuilderText.IndexOf('$preStage=Test-RimePimePackageCopyStage')
$preInclude = $installerBuilderText.IndexOf('$preInclude=Test-RimePimeNsisStageInclude')
$stagedPeVerify = $installerBuilderText.IndexOf('& $stagePeVerifier -RepoRoot $stageResult.StageRoot')
$postVerifierLease = if ($stagedPeVerify -ge 0) { $installerBuilderText.IndexOf('Test-RimePimeBuildInputLeases @($leases)', $stagedPeVerify) } else { -1 }
$makensisCall = $makensisCommand.Extent.StartOffset
$makensisExitGate = $makensisExitGates[0].Extent.StartOffset
$membershipComplete = $monitorComplete.Extent.StartOffset
$candidateProbe = $candidateProbeCommands[0].Extent.StartOffset
$candidateRecord = $candidateRecordAssignments[0].Extent.StartOffset
$candidateLeaseOpen = $candidateLeaseAssignments[0].Extent.StartOffset
$postLease = if ($makensisCall -ge 0) { $installerBuilderText.IndexOf('Test-RimePimeBuildInputLeases @($leases)', $makensisCall) } else { -1 }
$postStage = $installerBuilderText.IndexOf('$postStage=Test-RimePimePackageCopyStage')
$postInclude = $installerBuilderText.IndexOf('$postInclude=Test-RimePimeNsisStageInclude')
$prepareCandidate = $preparedPublication.Extent.StartOffset
$buildResultBinding = $buildResultAssignments[0].Extent.StartOffset
$publishCandidate = $publicationCommit.Extent.StartOffset
$closeCompilerMonitor = $monitorClose.Extent.StartOffset
if ($monitorOpen.Extent.StartOffset -lt 0 -or $leaseOpen -le $monitorOpen.Extent.StartOffset -or
    $preLease -le $leaseOpen -or $preStage -le $preLease -or
    $preInclude -le $preStage -or $stagedPeVerify -le $preInclude -or
    $postVerifierLease -le $stagedPeVerify -or $makensisCall -le $postVerifierLease -or
    $makensisExitGate -le $makensisCall -or $membershipComplete -le $makensisExitGate -or
    $candidateProbe -le $membershipComplete -or $candidateRecord -le $candidateProbe -or
    $candidateLeaseOpen -le $candidateRecord -or
    $postLease -le $candidateLeaseOpen -or
    $postStage -le $postLease -or $postInclude -le $postStage -or
    $prepareCandidate -le $postInclude -or $buildResultBinding -le $prepareCandidate -or
    $publishCandidate -le $buildResultBinding -or
    $closeCompilerMonitor -le $publishCandidate -or
    [regex]::Matches($installerBuilderText, 'Test-RimePimeBuildInputLeases @\(\$leases\)').Count -ne 3 -or
    [regex]::Matches($installerBuilderText, 'Test-RimePimePackageCopyStage').Count -ne 2 -or
    [regex]::Matches($installerBuilderText, 'Test-RimePimeNsisStageInclude').Count -ne 2 -or
    -not $stagedBuilderCombinedText.Contains('[IO.FileShare]::Read') -or
    $stagedBuilderCombinedText.Contains('[IO.FileShare]::ReadWrite') -or
    -not $stagedBuildHelperText.Contains('$share=[IO.FileShare]::Read -bor [IO.FileShare]::Delete') -or
    -not $stagedBuildHelperText.Contains('function Open-RimePimePublicationLock') -or
    -not $stagedBuildHelperText.Contains('[IO.FileShare]::None') -or
    -not $stagedBuildTestText.Contains('canonical-publication-lock-excludes-a-second-publisher-and-is-reusable') -or
    -not $stagedBuildTestText.Contains('fresh-publication-with-no-previous-bundle-commits-all-three-members') -or
    -not $stagedBuildHelperText.Contains('[IO.File]::Move($target,$backup);$state.OldMoved=$true') -or
    -not $stagedBuildHelperText.Contains("Name='receipt-sidecar-commit-marker'")) {
    throw 'NSIS wrapper must complete the monitored compiler interval, lease and reverify inputs, prepare, commit, and close the monitor in finally in admission order.'
}
$pimeTextServiceText = Get-Content -LiteralPath $pimeTextServiceSource -Raw
$pimeTextServiceHeaderText = Get-Content -LiteralPath $pimeTextServiceHeader -Raw
if (-not $installerText.Contains('!insertmacro YimePimeStageMainPayload') -or
    $installerText.Contains('SetOutPath "$INSTDIR\fonts"') -or
    $installerText -match 'File[^\r\n]*YinYuan-Regular\.ttf' -or
    $installerText -match '\$FONTS|CurrentVersion\\Fonts|AddFontResource\(|WM_FONTCHANGE|SendMessage 0xffff 0x001D' -or
    -not $pimeTextServiceText.Contains('L"\\go-backend\\input_methods\\yime\\data\\fonts\\YinYuan-Regular.ttf"') -or
    -not $pimeTextServiceText.Contains('AddFontResourceExW(privateFontPath_.c_str(), FR_PRIVATE, nullptr)') -or
    -not $pimeTextServiceText.Contains('RemoveFontResourceExW(privateFontPath_.c_str(), FR_PRIVATE, nullptr)') -or
    -not $pimeTextServiceHeaderText.Contains('std::wstring privateFontPath_')) {
    throw 'YinYuan candidate font must remain a symmetric per-host private resource.'
}
$mainInstallSection = [regex]::Match($installerText,
    '(?ms)^Section \$\(SECTION_MAIN\) SecMain\s+(.*?)^SectionEnd').Groups[1].Value
$finalVacancy = $mainInstallSection.LastIndexOf('Call verifyStagedRegistrationAbsent')
$unsealedBlock = $mainInstallSection.IndexOf('This Rime/PIME development package is not installable yet.')
$installAbort = $mainInstallSection.IndexOf('Abort',$unsealedBlock)
$firstPayloadWrite = $mainInstallSection.IndexOf('SetOverwrite on')
$uninstallSectionText = [regex]::Match($installerText,
    '(?ms)^Section "Uninstall"\s+(.*?)^SectionEnd').Groups[1].Value
$uninstallBlockedAtEntry = $uninstallSectionText -match
    '(?s)^\s*MessageBox[^\r\n]*development uninstaller is disabled until exact payload ownership, durable recovery and reboot-journal closure[^\r\n]*\r?\n\s*Abort\b'
$installInitBlockedAtEntry = $installInitText -match
    '(?s)^\s*MessageBox[^\r\n]*development installer is disabled until exact payload ownership, durable recovery and reboot-journal closure[^\r\n]*\r?\n\s*Abort\b'
$uninstallInitBlockedAtEntry = $uninstallInitText -match
    '(?s)^\s*MessageBox[^\r\n]*development uninstaller is disabled until exact payload ownership, durable recovery and reboot-journal closure[^\r\n]*\r?\n\s*Abort\b'
$releaseInstallerJob = & $extractJob 'release-installer-package'
$releaseBlock = $releaseInstallerJob.IndexOf('Block tagged installer until signed-uninstaller and removal closure')
$releasePackageBuild = $releaseInstallerJob.IndexOf('build-rime-pime-installer.ps1')
if ($finalVacancy -lt 0 -or $unsealedBlock -le $finalVacancy -or
    $firstPayloadWrite -le $unsealedBlock -or
    $installAbort -le $unsealedBlock -or $installAbort -ge $firstPayloadWrite -or
    -not $installInitBlockedAtEntry -or -not $uninstallInitBlockedAtEntry -or
    -not $uninstallBlockedAtEntry -or
    $releaseBlock -lt 0 -or $releasePackageBuild -le $releaseBlock -or
    -not $releaseInstallerJob.Contains("run: throw 'Tagged Rime/PIME installer release is disabled")) {
    throw 'Unsealed install/removal or signed-uninstaller work can reach a runnable tagged package.'
}
$releaseVersion = (Get-Content -LiteralPath (Join-Path $root 'version.txt') -Raw).Trim()
$numericReleaseVersion = (($releaseVersion -split '-', 2)[0]) + '.0'
foreach ($fragment in @(
    "VIProductVersion `"$numericReleaseVersion`"",
    'VIAddVersionKey /LANG=${LANG_ID} "FileVersion" "${PRODUCT_VERSION}"',
    'VIAddVersionKey /LANG=${LANG_ID} "ProductVersion" "${PRODUCT_VERSION}"',
    'VIAddVersionKey /LANG=${LANG_ID} "ProductName" "${PRODUCT_NAME_VALUE}"',
    'VIAddVersionKey /LANG=${LANG_ID} "FileDescription" "${FILE_DESCRIPTION_VALUE}"',
    'VIAddVersionKey /LANG=${LANG_ID} "LegalCopyright" "Copyright (C) 2026 YIME contributors"',
    'VIAddVersionKey /LANG=${LANG_ID} "PackageStageManifestSHA256" "${PACKAGE_STAGE_MANIFEST_SHA256}"',
    'VIAddVersionKey /LANG=${LANG_ID} "PackageStageContentSHA256" "${PACKAGE_STAGE_CONTENT_SHA256}"',
    'VIAddVersionKey /LANG=${LANG_ID} "PackagePayloadNshSHA256" "${PACKAGE_PAYLOAD_NSH_SHA256}"'
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
if (-not $installerText.Contains('WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"')) {
    throw 'Installer uninstall registration must publish InstallLocation.'
}
if (-not $devInstallText.Contains('RequireBuildArtifacts')) {
    throw 'Developer install must fail early with the shared build-artifact preflight.'
}
if ($localeText -match 'PYTHON_SECTION_GROUP|NODE_SECTION_GROUP|MCBOPOMOFO|BRAILLE_CHEWING|SET_CHEWING') {
    throw 'Retired PIME input-method strings returned to installer locales.'
}
foreach ($fragment in @(
    '!macro InstallTextServiceDll ARCH UPDATE_FLAG',
    'Only a vacant fresh root reaches this macro',
    '!insertmacro InstallTextServiceDll "x64" $UPDATEX64DLL',
    '!insertmacro YimePimeStageTextServiceX64',
    '!insertmacro InstallTextServiceDll "x86" $UPDATEX86DLL',
    '!insertmacro YimePimeStageTextServiceX86',
    'Exec ''"$INSTDIR\PIMELauncher.exe"'''
)) {
    if (-not $installerText.Contains($fragment)) {
        throw "Fresh-only installer guard is missing: $fragment"
    }
}
$installMacroMatch = [regex]::Match($installerText, '(?s)!macro InstallTextServiceDll .*?!macroend')
if (-not $installMacroMatch.Success -or $installMacroMatch.Value.Contains(' SOURCE ') -or
    $installMacroMatch.Value -match '(?mi)^[ \t]*File(?:[ \t]|$)|(?:Rename|Delete) /REBOOTOK') {
    throw 'Fresh-only text-service admission must not read source bytes or defer replacement of mapped old DLL bytes.'
}
$upgradeFunctionMatch = [regex]::Match($installerText, '(?s)Function uninstallOldVersion.*?FunctionEnd')
if (-not $upgradeFunctionMatch.Success) {
    throw 'Could not locate installer fresh-only admission function.'
}
foreach ($forbiddenUpgradeFragment in @(
    'Call stopRunningBackend',
    '/u /s',
    'RMDir',
    'DeleteReg',
    'Delete /REBOOTOK "$INSTDIR\PIMELauncher.exe"',
    'Delete "$INSTDIR\version.txt"',
    'Delete "$INSTDIR\Uninstall.exe"'
)) {
    if ($upgradeFunctionMatch.Value.Contains($forbiddenUpgradeFragment)) {
        throw "Destructive pre-install upgrade step returned: $forbiddenUpgradeFragment"
    }
}
if (-not $upgradeFunctionMatch.Value.Contains('In-place upgrade is not enabled')) {
    throw 'Current-family in-place upgrade must remain explicitly fail closed.'
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
    '!insertmacro MUI_PAGE_LICENSE "${PACKAGE_STAGE_ROOT}\payload\licenses\LGPL-2.0.txt"',
    '!insertmacro YimePimeStageMainPayload',
    'RMDir /REBOOTOK /r "$INSTDIR\licenses"'
)
foreach ($fragment in $requiredInstallerLegalFragments) {
    if (-not $installerText.Contains($fragment)) {
        throw "Installer legal-notice packaging guard is missing: $fragment"
    }
}
foreach ($relativePath in $requiredLegalFiles) {
    $canonical = $relativePath.Replace('\','/')
    if (-not $packageStagingModuleText.Contains("'$canonical'")) {
        throw "Required legal notice has no explicit pre-package stage binding: $canonical"
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

$retiredTrackedPaths = @('python', 'node', 'McBopomofoWeb', 'libchewing')
foreach ($retiredPath in $retiredTrackedPaths) {
    $tracked = @(& git -C $root ls-files -- $retiredPath)
    if ($tracked.Count -gt 0) {
        throw "Retired path is still tracked: $retiredPath"
    }
}

# The old upstream root test tree was retired with PIME.  The new root tests
# are restricted to the migrated, offline Yime lexicon/encoding toolchain.
$allowedOfflineTestPrefixes = @(
    'tests/README.md',
    'tests/__init__.py',
    'tests/test_',
    'tests/input_model/',
    'tests/lexicon_bundle/',
    'tests/pinyin_source_db/',
    'tests/syllable_analysis/',
    'tests/tools/',
    'tests/yime/',
    'tests/yinjie/'
)
$trackedOfflineTests = @(& git -C $root ls-files -- 'tests')
foreach ($testPath in $trackedOfflineTests) {
    $normalizedTestPath = $testPath.Replace('\', '/')
    $allowed = @($allowedOfflineTestPrefixes | Where-Object {
        $normalizedTestPath.StartsWith($_, [StringComparison]::Ordinal)
    }).Count -gt 0
    if (-not $allowed) {
        throw "Unclassified root test returned outside the offline Yime toolchain: $testPath"
    }
}
foreach ($runtimeOnlyFragment in @(
    'pywin32',
    'win32api',
    'win32gui',
    'pynput',
    'tkinter',
    'PyInstaller',
    'yime.input_method'
)) {
    $matches = @(& git -C $root grep -n --fixed-strings $runtimeOnlyFragment -- 'tests/*.py' 'tests/**/*.py')
    if ($matches.Count -gt 0) {
        throw "Prototype runtime dependency returned in offline tests: $($matches -join '; ')"
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
    'punct_chi.ico', 'punct_eng.ico',
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
if (Test-Path -LiteralPath (Join-Path $root '.gitmodules')) {
    throw 'Yime must not reintroduce submodule metadata after vendoring libIME2.'
}
Write-Host 'YIME-only build and installer guard test passed.'
Write-Host 'YIME provenance, metadata, and legal packaging guard test passed.'
Write-Host 'Build guard tests passed.'
