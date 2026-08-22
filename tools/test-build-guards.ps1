$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$verifier = Join-Path $PSScriptRoot 'verify-pe-architectures.ps1'
$x64Dll = Join-Path $root 'build64\PIMETextService\Release\PIMETextService.dll'
$launcher = Join-Path $root 'build\PIMELauncher\PIMELauncher.exe'
$workflow = Join-Path $root '.github\workflows\ci.yaml'
$codeOwners = Join-Path $root '.github\CODEOWNERS'
$buildContract = Join-Path $PSScriptRoot 'validate-build-contract.ps1'
$rootBuild = Join-Path $root 'build.bat'
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
$installer = Join-Path $root 'installer\installer.nsi'
$devInstall = Join-Path $root 'tools\dev-install.ps1'
$devStop = Join-Path $root 'tools\dev-stop-pime.ps1'
$devBuildInstallVerify = Join-Path $root 'tools\dev-build-install-verify.ps1'
$installedRuntimeVerifier = Join-Path $root 'tools\verify-installed-runtime.ps1'
$buildPrereqs = Join-Path $root 'tools\assert-win32-build-prerequisites.ps1'
$buildEnvironment = Join-Path $root 'tools\invoke-build-environment.ps1'
$cmakeEnvironment = Join-Path $root 'tools\invoke-cmake.ps1'
$realRimeTest = Join-Path $root 'tools\test-real-rime.ps1'
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
& $buildContract

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
    'needs: [build-contract, lexicon-offline-tooling, rust-i686-host, native-build, go-tests, real-rime-tests, go-race-msys2]',
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
    '.\tools\test-installer-smoke.ps1',
    'go install github.com/tc-hib/go-winres@v0.3.3',
    'uses: repolevedavaj/install-nsis@c14d0ea1b829818b4e9313d8e009b43f0a65fddd # v1.2.0',
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
    'rustup run stable-i686-pc-windows-msvc cargo build --release --target i686-pc-windows-msvc'
)) {
    if (-not $rootBuildText.Contains($guard)) {
        throw "Win32 pinned-host build guard is missing: $guard"
    }
}
$goBuildText = Get-Content -LiteralPath $goBuild -Raw
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
if ($workflowText -match 'uses:\s*repolevedavaj/install-nsis@(?![0-9a-f]{40}(?:\s|#|$))') {
    throw 'Third-party NSIS setup must be pinned to a full immutable commit SHA.'
}
foreach ($requiredScript in @($rimeCacheChecker, $rimeCacheTests, $installedParticleAVerifier, $installedParticleAVerifierTests, $releaseCertificateImporter)) {
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
foreach ($jobName in @('release-sign-payload', 'release-sign-installer')) {
    $jobText = & $extractJob $jobName
    if (-not $jobText.Contains('secrets.YIME_SIGN_CERT_BASE64')) {
        throw "Release signing job does not import the protected certificate: $jobName"
    }
    foreach ($forbidden in @('repolevedavaj/install-nsis', 'Invoke-WebRequest', 'go install ')) {
        if ($jobText.Contains($forbidden)) {
            throw "Release signing job executes untrusted setup after secrets are exposed: $jobName -> $forbidden"
        }
    }
}
foreach ($jobName in @('unsigned-installer-package', 'release-installer-package')) {
    $jobText = & $extractJob $jobName
    if ($jobText.Contains('secrets.YIME_') -or $jobText.Contains('import-release-signing-certificate.ps1')) {
        throw "NSIS packaging job must not receive release signing secrets: $jobName"
    }
}
$devStopText = Get-Content -LiteralPath $devStop -Raw
foreach ($guard in @(
    '-ErrorAction Stop',
    '$remainingProcesses',
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
if (-not $installerText.Contains('WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"')) {
    throw 'Installer uninstall registration must publish InstallLocation.'
}
if (-not $devInstallText.Contains('RequireBuildArtifacts')) {
    throw 'Developer install must fail early with the shared build-artifact preflight.'
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
