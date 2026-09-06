[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent = Join-Path $repo '.tmp\dual-product'
if ((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-registration-completeness-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a new immediate .tmp/dual-product/dp1-registration-completeness-* fixture root.'
}
for ($cursor = $expectedParent; $cursor; $cursor = Split-Path -Parent $cursor) {
    if ((Test-Path -LiteralPath $cursor) -and
        ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Registration-completeness evidence path traverses a reparse point.'
    }
    if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
}
if (-not (Test-Path -LiteralPath $expectedParent)) {
    New-Item -ItemType Directory -Path $expectedParent -Force | Out-Null
}
New-Item -ItemType Directory -Path $output | Out-Null

$sourceFiles = @(
    'Build.ps1',
    'Build.cmd',
    'CMakeLists.txt',
    'libIME2/src/ImeModule.cpp',
    'PIMETextService/DllEntry.cpp',
    'PIMETextService/PIMETextService.cpp',
    'PIMETextService/PIMETextService.h',
    'PIMETextService/CMakeLists.txt',
    'PIMETextService/RegistrationStatus.cpp',
    'PIMELauncher/.cargo/config.toml',
    'tools/verify-pe-architectures.ps1',
    'tools/test-build-guards.ps1',
    'tools/test-installer-smoke.ps1',
    'tools/build-rime-pime-installer.ps1',
    'tools/dual-product/rime-pime-package-plan.ps1',
    'tools/dual-product/rime-pime-package-staging.ps1',
    'tools/dual-product/rime-pime-nsis-stage.ps1',
    'tools/dual-product/test-rime-pime-nsis-stage.ps1',
    'tools/dual-product/rime-pime-staged-installer-build.ps1',
    'tools/dual-product/test-rime-pime-staged-installer-build.ps1',
    'tools/dual-product/rime-pime-payload-closure.ps1',
    'tools/dual-product/test-rime-pime-payload-closure.ps1',
    'tools/dual-product/test-pe-import-gate.ps1',
    'tools/dual-product/test-rime-pime-installer-static.ps1',
    'installer/installer.nsi',
    'installer/locale/English.nsh',
    'installer/locale/SimpChinese.nsh',
    'installer/locale/TradChinese.nsh',
    '.github/workflows/ci.yaml',
    '.github/CODEOWNERS',
    'tools/sign-file.ps1',
    'tools/sign-release.ps1',
    'tools/import-release-signing-certificate.ps1',
    'tools/verify-release-signatures.ps1',
    'tools/write-build-manifest.ps1'
)
$source = @{}
$beforeHashes = [ordered]@{}
foreach ($relative in $sourceFiles) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $source[$relative] = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $beforeHashes[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    } else {
        $source[$relative] = ''
        $beforeHashes[$relative] = 'missing'
    }
}

$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Body) {
    try { & $Body; $checks.Add([ordered]@{name=$Name;passed=$true}) }
    catch { $checks.Add([ordered]@{name=$Name;passed=$false;reason=$_.Exception.Message}) }
}
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }

$cpp = $source['libIME2/src/ImeModule.cpp']
$dllEntry = $source['PIMETextService/DllEntry.cpp']
$textService = $source['PIMETextService/PIMETextService.cpp']
$textServiceHeader = $source['PIMETextService/PIMETextService.h']
$rootCmake = $source['CMakeLists.txt']
$cmake = $source['PIMETextService/CMakeLists.txt']
$probe = $source['PIMETextService/RegistrationStatus.cpp']
$launcherConfig = $source['PIMELauncher/.cargo/config.toml']
$peGuard = $source['tools/verify-pe-architectures.ps1']
$buildGuards = $source['tools/test-build-guards.ps1']
$staticVerifier = $source['tools/test-installer-smoke.ps1']
$installerBuilder = $source['tools/build-rime-pime-installer.ps1']
$packagePlan = $source['tools/dual-product/rime-pime-package-plan.ps1']
$packageStaging = $source['tools/dual-product/rime-pime-package-staging.ps1']
$nsisStage = $source['tools/dual-product/rime-pime-nsis-stage.ps1']
$nsisStageTest = $source['tools/dual-product/test-rime-pime-nsis-stage.ps1']
$stagedBuildHelper = $source['tools/dual-product/rime-pime-staged-installer-build.ps1']
$stagedBuildTest = $source['tools/dual-product/test-rime-pime-staged-installer-build.ps1']
$payloadClosure = $source['tools/dual-product/rime-pime-payload-closure.ps1']
$payloadClosureTest = $source['tools/dual-product/test-rime-pime-payload-closure.ps1']
$peImportGateTest = $source['tools/dual-product/test-pe-import-gate.ps1']
$installerStaticTest = $source['tools/dual-product/test-rime-pime-installer-static.ps1']
$installer = $source['installer/installer.nsi']
$rootBuildPowerShell = $source['Build.ps1']
$rootBuildCommand = $source['Build.cmd']
$workflow = $source['.github/workflows/ci.yaml']
$codeOwners = $source['.github/CODEOWNERS']
$signFile = $source['tools/sign-file.ps1']
$signRelease = $source['tools/sign-release.ps1']
$importReleaseSigningCertificate = $source['tools/import-release-signing-certificate.ps1']
$verifyReleaseSignatures = $source['tools/verify-release-signatures.ps1']
$buildManifest = $source['tools/write-build-manifest.ps1']
$registerProfiles = [regex]::Match($cpp,
    '(?ms)^HRESULT\s+ImeModule::registerLangProfiles\([^\r\n]*\)\s*\{.*?(?=^HRESULT\s+ImeModule::|\z)').Value
$registerServer = [regex]::Match($cpp,
    '(?ms)^HRESULT\s+ImeModule::registerServer\([\s\S]*?\)\s*\{.*?(?=^HRESULT\s+ImeModule::|\z)').Value
$unregisterServer = [regex]::Match($cpp,
    '(?ms)^HRESULT\s+ImeModule::unregisterServer\([^\r\n]*\)\s*\{.*?(?=^[A-Za-z_][^\r\n]*\s+ImeModule::|\z)').Value
$registerSection = [regex]::Match($installer, '(?ms)^Section "" Register\s+(.*?)^SectionEnd').Groups[1].Value
$mainSection = [regex]::Match($installer, '(?ms)^Section \$\(SECTION_MAIN\) SecMain\s+(.*?)^SectionEnd').Groups[1].Value
$uninstallSection = [regex]::Match($installer, '(?ms)^Section "Uninstall"\s+(.*?)^SectionEnd').Groups[1].Value
$checkedExecMacro = [regex]::Match($installer,
    '(?ms)^!macro RunCheckedRegistrationCommand\b(.*?)^!macroend').Groups[1].Value
$uninstallOld = [regex]::Match($installer,
    '(?ms)^Function uninstallOldVersion\s+(.*?)^FunctionEnd').Groups[1].Value
$installInit = [regex]::Match($installer,
    '(?ms)^Function \.onInit\s+(.*?)^FunctionEnd').Groups[1].Value
$uninstallInit = [regex]::Match($installer,
    '(?ms)^Function un\.onInit\s+(.*?)^FunctionEnd').Groups[1].Value

Check 'installer-minimum-os-is-windows-10-1903' {
    $osGate = $installInit.IndexOf('${IfNot} ${AtLeastWin10}')
    $buildGate = $installInit.IndexOf('${IfNot} ${AtLeastBuild} 18362')
    $rootPolicy = $installInit.IndexOf('Call enforceInstallRootPolicy')
    $bootstrap = $installInit.IndexOf('Call bootstrapTargetUser')
    Assert-True ([regex]::Matches($installer,'(?m)^ManifestSupportedOS[ \t]+all[ \t]*\r?$').Count -eq 1 -and
        $osGate -ge 0 -and $buildGate -gt $osGate -and $rootPolicy -gt $buildGate -and
        $bootstrap -gt $rootPolicy -and
        $installer.Contains('GetFullPathName $R0 "$PROGRAMFILES32\YIME"') -and
        $installer.Contains('Command-line /D overrides and user-writable roots are not admitted.') -and
        [regex]::Matches($installInit,'AtLeastWin10_1903_MESSAGE').Count -eq 2 -and
        -not $installer.Contains('AtLeastWinVista')) `
        'Installer minimum OS can drift below Windows 10 version 1903.'
    foreach($relative in @('installer/locale/English.nsh','installer/locale/SimpChinese.nsh',
            'installer/locale/TradChinese.nsh')) {
        $locale = $source[$relative]
        Assert-True ([regex]::Matches($locale,'AtLeastWin10_1903_MESSAGE').Count -eq 1 -and
            $locale.Contains('1903') -and -not $locale.Contains('AtLeastWinVista')) `
            "Installer locale minimum-OS message drifted: $relative"
    }
}
Check 'installer-arm64-admission-is-fail-closed-until-arm64x' {
    $arm64Branch = [regex]::Match($installInit,
        '(?ms)\$\{If\} \$\{IsNativeARM64\}(.*?)\$\{ElseIf\} \$\{IsNativeAMD64\}').Groups[1].Value
    Assert-True ($arm64Branch.Contains('Arm64X text-service surface') -and
        $arm64Branch.Contains('x64-emulated') -and $arm64Branch.Contains('Abort') -and
        -not $arm64Branch.Contains('StrCpy $RimeNativeArchitecture "arm64"') -and
        -not $arm64Branch.Contains('StrCpy $UPDATEARM64DLL "True"')) `
        'An incomplete plain-ARM64 package can still be installed without x64-emulated TSF coverage.'
}
Check 'one-sealed-package-plan-drives-architecture-signing-build-and-static-closure' {
    Assert-True (-not $installer.Contains('!if /FileExists "..\build_arm64') -and
        -not $installer.Contains('HAVE_ARM64_PIMETS') -and
        -not $installer.Contains('INCLUDE_ARM64_ARTIFACTS') -and
        $installer.Contains('!ifndef PACKAGE_PLAN_SHA256') -and
        $installer.Contains('!ifndef PACKAGE_PLAN_X86_X64') -and
        $installer.Contains('!ifdef PACKAGE_PLAN_X86_ARM64X') -and
        $installer.Contains('PackagePlanSHA256') -and $installer.Contains('PackageArchitectures')) `
        'NSIS can be compiled without the sealed package-plan identity or can infer stale ARM64 artifacts.'
    foreach($entry in @($signRelease,$verifyReleaseSignatures,$buildManifest)) {
        Assert-True ($entry.Contains('Read-RimePimePackagePlan') -and
            -not $entry.Contains('IncludeArm64Artifacts') -and
            -not $entry.Contains('INCLUDE_ARM64_ARTIFACTS')) `
            'A signing or manifest tool retains an independent architecture-selection switch.'
    }
    Assert-True ($packagePlan.Contains('yime-rime-pime-package-plan-v1') -and
        $packagePlan.Contains("closure_scope='declared-packaged-product-pe-inputs-only-not-installed-payload'") -and
        $packagePlan.Contains("@('x86','x64')") -and $packagePlan.Contains("'x86' -and `$architectures[1] -ceq 'arm64x'") -and
        $packagePlan.Contains('reserved but not admitted') -and $packagePlan.Contains('1048576') -and
        $packagePlan.Contains('Assert-RimePimeNoReparsePath $sidecar') -and
        $packagePlan.Contains('Get-RimePimePackagedPePaths') -and
        $packagePlan.Contains('Test-RimePimePortableExecutableFile') -and
        $packagePlan.Contains('PE set is not the exact sealed allowlist') -and
        $installerBuilder.Contains('Read-RimePimePackagePlan') -and
        $installerBuilder.Contains('only builds an unsigned disabled package') -and
        $installerBuilder.Contains('YIME_SIGN_CERT_SHA1') -and
        $installerBuilder.Contains('YIME_RELEASE_SIGNING_REQUIRED') -and
        $installerBuilder.Contains('YIME_SIGNTOOL_EXE') -and
        $installerBuilder.Contains('YIME_TIMESTAMP_URL') -and
        $installerBuilder.Contains('/DPACKAGE_PLAN_SHA256=') -and
        $installerBuilder.Contains('/DPACKAGE_PLAN_X86_X64=1') -and
        $stagedBuildHelper.Contains("schema_version='yime-rime-pime-package-build-receipt-v1'") -and
        $stagedBuildHelper.Contains('Read-RimePimePackageBuildReceipt') -and
        $buildManifest.Contains('sourceTreeDirty = $sourceStatus.Count -gt 0') -and
        $buildManifest.Contains('Requested manifest commit does not match the checked-out source HEAD.') -and
        $buildManifest.Contains("kind = if (`$sourceTreeDirty) { 'working-tree' } else { 'git-commit' }") -and
        $staticVerifier.Contains('commitIsCompleteSourceIdentity') -and
        $installerStaticTest.Contains('production-manifest-writer-rejects-github-sha-head-mismatch') -and
        $installerStaticTest.Contains('unsigned-installer-wrapper-rejects-inherited-signing-context-before-reading-inputs') -and
        $installerStaticTest.Contains('rejects-inconsistent-working-tree-source-identity') -and
        $workflow.Contains('-ExpectedSourceTreeDirty false') -and
        [regex]::Matches($workflow,'Move trusted signing implementation outside source checkout').Count -eq 2 -and
        [regex]::Matches($workflow,"Join-Path \`$env:RUNNER_TEMP 'yime-trusted-signing'").Count -eq 2 -and
        [regex]::Matches($workflow,"Join-Path \`$env:YIME_TRUSTED_SIGNING_ROOT 'tools\\write-build-manifest.ps1'").Count -eq 1 -and
        -not ($workflow -match '(?m)^\s*run:\s*&') -and
        $rootBuildPowerShell.Contains('rime-pime-package-plan.ps1') -and
        $rootBuildPowerShell.Contains('-WritePlan -PlanRepoRoot $repoRoot -OutputPlanPath $planPath') -and
        $rootBuildPowerShell.Contains('build-rime-pime-installer.ps1') -and
        $rootBuildPowerShell.Contains('write-build-manifest.ps1') -and
        $rootBuildPowerShell.Contains('Build.ps1 is an unsigned development entry') -and
        $rootBuildPowerShell -notmatch '(?i)\bmakensis(?:\.exe)?\b' -and
        $rootBuildCommand.Contains('-File "%~dp0Build.ps1"') -and
        $rootBuildCommand -notmatch '(?i)makensis|installer\.nsi' -and
        $staticVerifier.Contains('Read-RimePimePackageBuildReceipt') -and
        $installerStaticTest.Contains('default-closure-ignores-existing-unselected-arm64-artifacts') -and
        $installerStaticTest.Contains('rejects-reserved-arm64x-plan-profile') -and
        $installerStaticTest.Contains('rejects-artifact-changed-after-package-plan-seal') -and
        $installerStaticTest.Contains('rejects-wrong-machine-even-when-plan-hash-is-resealed') -and
        $installerStaticTest.Contains('rejects-delay-crt-even-when-plan-hash-is-resealed') -and
        $installerStaticTest.Contains('rejects-extra-pe-in-recursively-packaged-go-tree') -and
        $installerStaticTest.Contains('rejects-omitted-package-plan-file-record') -and
        $workflow.Contains('Seal default x86/x64 package plan') -and
        [regex]::Matches($workflow,'build-rime-pime-installer\.ps1').Count -eq 2 -and
        $workflow.Contains("Join-Path `$env:YIME_TRUSTED_SIGNING_ROOT 'tools\sign-release.ps1') -Root `$env:GITHUB_WORKSPACE -IncludeInstaller") -and
        -not $workflow.Contains('IncludeArm64Artifacts') -and
        -not $workflow.Contains('INCLUDE_ARM64_ARTIFACTS') -and
        -not $workflow.Contains("& 'C:\Program Files (x86)\NSIS\Bin\makensis.exe'")) `
        'Package planning, compilation, signing, receipt, manifest, or static closure can select independent architectures.'
}
Check 'installer-consumes-one-sealed-stage-through-six-explicit-macros' {
    $directFiles = [regex]::Matches($installer, '(?mi)^[ \t]*File(?:[ \t]|$)')
    Assert-True ($directFiles.Count -eq 0 -and
        -not ($installer -match '(?mi)^[ \t]*File[ \t]+/r\b') -and
        -not ($installer -match '(?mi)^[ \t]*File[^\r\n]*\.\.\\')) `
        'installer.nsi can still read a product source directly or through recursive File selection.'
    foreach($fragment in @(
        '!ifndef PACKAGE_STAGE_ROOT',
        '!ifndef PACKAGE_STAGE_MANIFEST_SHA256',
        '!ifndef PACKAGE_STAGE_CONTENT_SHA256',
        '!ifndef PACKAGE_PAYLOAD_NSH_PATH',
        '!ifndef PACKAGE_PAYLOAD_NSH_SHA256',
        '!ifndef PACKAGE_OUTPUT_PATH',
        '!include "${PACKAGE_PAYLOAD_NSH_PATH}"',
        '!define /file PRODUCT_VERSION "${PACKAGE_STAGE_ROOT}\payload\version.txt"',
        '!insertmacro MUI_PAGE_LICENSE "${PACKAGE_STAGE_ROOT}\payload\licenses\LGPL-2.0.txt"',
        'OutFile "${PACKAGE_OUTPUT_PATH}"',
        'VIAddVersionKey /LANG=${LANG_ID} "PackageStageManifestSHA256" "${PACKAGE_STAGE_MANIFEST_SHA256}"',
        'VIAddVersionKey /LANG=${LANG_ID} "PackageStageContentSHA256" "${PACKAGE_STAGE_CONTENT_SHA256}"',
        'VIAddVersionKey /LANG=${LANG_ID} "PackagePayloadNshSHA256" "${PACKAGE_PAYLOAD_NSH_SHA256}"'
    )) {
        Assert-True ($installer.Contains($fragment)) "Sealed NSIS stage definition or identity is missing: $fragment"
    }
    $stageMacroCalls = [ordered]@{
        YimePimeStageTargetUserHelpers = 1
        YimePimeStageOwnershipHelpers = 1
        YimePimeStageRegistrationTools = 2
        YimePimeStageMainPayload = 1
        YimePimeStageTextServiceX86 = 1
        YimePimeStageTextServiceX64 = 1
    }
    foreach($entry in $stageMacroCalls.GetEnumerator()) {
        $callPattern = '!insertmacro\s+' + [regex]::Escape([string]$entry.Key) + '(?:\s|$)'
        $definitionPattern = 'Add-RimePimeNsisMacro\s+\$lines\s+''' + [regex]::Escape([string]$entry.Key) + ''''
        Assert-True ([regex]::Matches($installer,$callPattern).Count -eq [int]$entry.Value -and
            [regex]::Matches($nsisStage,$definitionPattern).Count -eq 1) `
            "Stage macro definition or call-site count drifted: $($entry.Key)"
    }
    $installMacro = [regex]::Match($installer,'(?ms)^!macro InstallTextServiceDll ARCH UPDATE_FLAG\s+(.*?)^!macroend')
    Assert-True ($installMacro.Success -and -not $installMacro.Value.Contains(' SOURCE ') -and
        -not ($installMacro.Value -match '(?mi)^[ \t]*File(?:[ \t]|$)|(?:Rename|Delete) /REBOOTOK') -and
        $registerSection.Contains('!insertmacro InstallTextServiceDll "x64" $UPDATEX64DLL') -and
        $registerSection.Contains('!insertmacro YimePimeStageTextServiceX64') -and
        $registerSection.Contains('!insertmacro InstallTextServiceDll "x86" $UPDATEX86DLL') -and
        $registerSection.Contains('!insertmacro YimePimeStageTextServiceX86')) `
        'Text-service admission still accepts an arbitrary source or is not followed by its architecture-specific stage macro.'

    foreach($fragment in @(
        'Get-RimePimeCurrentPackageStageDeclaration',
        'New-RimePimePackageCopyStage',
        'Write-RimePimeNsisStageInclude',
        'Open-RimePimeBuildInputLeases',
        'foreach($row in @($content.Manifest.files))',
        'RefreshReceiptOnly is not admitted after staged NSIS consumption',
        '"/DPACKAGE_STAGE_ROOT=$($stageResult.StageRoot)"',
        '"/DPACKAGE_STAGE_MANIFEST_SHA256=$($stageResult.ContentManifestDigest)"',
        '"/DPACKAGE_STAGE_CONTENT_SHA256=$($content.Manifest.content_tree_sha256)"',
        '"/DPACKAGE_PAYLOAD_NSH_PATH=$($include.IncludePath)"',
        '"/DPACKAGE_PAYLOAD_NSH_SHA256=$($include.IncludeDigest)"',
        '"/DPACKAGE_OUTPUT_PATH=$candidate"',
        "'/DPACKAGE_UNSIGNED_DISABLED_BUILD=1'"
    )) {
        Assert-True ($installerBuilder.Contains($fragment)) "Staged NSIS wrapper guard is missing: $fragment"
    }
    $leaseOpen = $installerBuilder.IndexOf('$leases=Open-RimePimeBuildInputLeases $expected')
    $preLease = if($leaseOpen -ge 0){$installerBuilder.IndexOf('Test-RimePimeBuildInputLeases @($leases)',$leaseOpen)}else{-1}
    $preStage = $installerBuilder.IndexOf('$preStage=Test-RimePimePackageCopyStage')
    $preInclude = $installerBuilder.IndexOf('$preInclude=Test-RimePimeNsisStageInclude')
    $stagedPeVerify = $installerBuilder.IndexOf('& $stagePeVerifier -RepoRoot $stageResult.StageRoot')
    $postVerifierLease = if($stagedPeVerify -ge 0){$installerBuilder.IndexOf('Test-RimePimeBuildInputLeases @($leases)',$stagedPeVerify)}else{-1}
    $makensisCall = $installerBuilder.IndexOf('& $MakensisPath @arguments')
    $postLease = if($makensisCall -ge 0){$installerBuilder.IndexOf('Test-RimePimeBuildInputLeases @($leases)',$makensisCall)}else{-1}
    $postStage = $installerBuilder.IndexOf('$postStage=Test-RimePimePackageCopyStage')
    $postInclude = $installerBuilder.IndexOf('$postInclude=Test-RimePimeNsisStageInclude')
    $publish = $installerBuilder.IndexOf('$receipt=Invoke-RimePimePublicationCommit')
    $combinedBuild = $installerBuilder + "`n" + $stagedBuildHelper
    Assert-True ($leaseOpen -ge 0 -and $preLease -gt $leaseOpen -and $preStage -gt $preLease -and
        $preInclude -gt $preStage -and $stagedPeVerify -gt $preInclude -and
        $postVerifierLease -gt $stagedPeVerify -and $makensisCall -gt $postVerifierLease -and $postLease -gt $makensisCall -and
        $postStage -gt $postLease -and $postInclude -gt $postStage -and $publish -gt $postInclude -and
        [regex]::Matches($installerBuilder,'Test-RimePimeBuildInputLeases @\(\$leases\)').Count -eq 3 -and
        $installerBuilder.Contains('staged_pe_architecture_verified_under_read_leases=$true') -and
        [regex]::Matches($installerBuilder,'Test-RimePimePackageCopyStage').Count -eq 2 -and
        [regex]::Matches($installerBuilder,'Test-RimePimeNsisStageInclude').Count -eq 2 -and
        $combinedBuild.Contains('[IO.FileShare]::Read') -and
        -not $combinedBuild.Contains('[IO.FileShare]::ReadWrite') -and
        $stagedBuildHelper.Contains('$share=[IO.FileShare]::Read -bor [IO.FileShare]::Delete') -and
        $stagedBuildHelper.Contains("Name='receipt-sidecar-commit-marker'") -and
        $stagedBuildHelper.Contains('[IO.File]::Move($target,$backup);$state.OldMoved=$true') -and
        $stagedBuildTest.Contains('third-item-failure-rolls-back-the-original-three-file-bundle')) `
        'The wrapper does not lease and reverify the same stage/include on both sides of makensis before publishing.'
    Assert-True ($packageStaging.Contains('function Get-RimePimeCurrentPackageStageDeclaration') -and
        $nsisStageTest.Contains('definitions-only-module-generates-six-stage-only-macros') -and
        $nsisStageTest.Contains('include-bytes-are-stable-across-distinct-stage-roots') -and
        $nsisStageTest.Contains('changed-stage-after-include-generation-is-rejected')) `
        'The current stage declaration or isolated six-macro regression model is not pinned.'
}
Check 'signing-leaf-sources-and-codeowners-are-in-the-exact-source-snapshot' {
    Assert-True ($signRelease.Contains("Join-Path `$PSScriptRoot 'sign-file.ps1'") -and
        $signFile.Contains('YIME_SIGN_CERT_SHA1') -and
        $signFile.Contains('YIME_SIGNTOOL_EXE') -and
        $importReleaseSigningCertificate.Contains('YIME_SIGN_CERT_BASE64') -and
        $importReleaseSigningCertificate.Contains('Import-PfxCertificate') -and
        $codeOwners.Contains('/tools/sign-*.ps1 @tsaanghwang') -and
        $codeOwners.Contains('/tools/import-release-signing-certificate.ps1 @tsaanghwang')) `
        'A certificate-import/signing leaf or its CODEOWNERS protection escaped the exact source snapshot.'
}
Check 'installer-unsealed-install-uninstall-and-tagged-release-remain-blocked-before-product-mutation' {
    $vacancy = $mainSection.LastIndexOf('Call verifyStagedRegistrationAbsent')
    $closureBlock = $mainSection.IndexOf('This Rime/PIME development package is not installable yet.')
    $firstPayloadWrite = $mainSection.IndexOf('SetOverwrite on')
    $uninstallBlockedAtEntry = $uninstallSection -match
        '(?s)^\s*MessageBox[^\r\n]*development uninstaller is disabled until exact payload ownership, durable recovery and reboot-journal closure[^\r\n]*\r?\n\s*Abort\b'
    $installInitBlockedAtEntry = $installInit -match
        '(?s)^\s*MessageBox[^\r\n]*development installer is disabled until exact payload ownership, durable recovery and reboot-journal closure[^\r\n]*\r?\n\s*Abort\b'
    $uninstallInitBlockedAtEntry = $uninstallInit -match
        '(?s)^\s*MessageBox[^\r\n]*development uninstaller is disabled until exact payload ownership, durable recovery and reboot-journal closure[^\r\n]*\r?\n\s*Abort\b'
    $releaseJob = [regex]::Match($workflow,
        '(?ms)^  release-installer-package:\r?\n.*?(?=^  [A-Za-z0-9_-]+:\r?$|\z)').Value
    $tagBlock = $releaseJob.IndexOf('Block tagged installer until signed-uninstaller and removal closure')
    $packageBuild = $releaseJob.IndexOf('build-rime-pime-installer.ps1')
    Assert-True ($vacancy -ge 0 -and $closureBlock -gt $vacancy -and
        $firstPayloadWrite -gt $closureBlock -and
        $mainSection.IndexOf('Abort',$closureBlock) -lt $firstPayloadWrite -and
        $installInitBlockedAtEntry -and $uninstallInitBlockedAtEntry -and $uninstallBlockedAtEntry -and
        $tagBlock -ge 0 -and $packageBuild -gt $tagBlock -and
        $releaseJob.Contains("run: throw 'Tagged Rime/PIME installer release is disabled")) `
        'An unsealed install, removal, or unsigned embedded uninstaller can reach product mutation or release.'
}
Check 'candidate-annotation-font-is-product-private-and-symmetric' {
    Assert-True ($mainSection.Contains('!insertmacro YimePimeStageMainPayload') -and
        $mainSection -notmatch 'File[^\r\n]*YinYuan-Regular\.ttf' -and
        $installer -notmatch '\$FONTS|CurrentVersion\\Fonts|AddFontResource\(|WM_FONTCHANGE|SendMessage 0xffff 0x001D' -and
        $textService.Contains('AddFontResourceExW(privateFontPath_.c_str(), FR_PRIVATE, nullptr)') -and
        $textService.Contains('RemoveFontResourceExW(privateFontPath_.c_str(), FR_PRIVATE, nullptr)') -and
        $textService.Contains('L"\\go-backend\\input_methods\\yime\\data\\fonts\\YinYuan-Regular.ttf"') -and
        $textServiceHeader.Contains('std::wstring privateFontPath_')) `
        'Candidate annotation font can become a shared system resource or is not released symmetrically.'
}

Check 'native-register-propagates-profile-manager-and-profile-failures' {
    Assert-True ($registerProfiles -match
            'if\s*\(\s*CoCreateInstance\([\s\S]*?IID_ITfInputProcessorProfiles[\s\S]*?\)\s*!=\s*S_OK\s*\)\s*\{?\s*return E_FAIL' -and
        $registerProfiles -match
            'if\s*\(\s*inputProcessProfiles->Register\(textServiceClsid_\)\s*!=\s*S_OK\s*\)\s*\{?\s*return E_FAIL' -and
        $registerProfiles -match 'if\s*\([^\)]*AddLanguageProfile[\s\S]*?!=\s*S_OK\s*\)\s*\{\s*return E_FAIL') `
        'Native profile registration can still return success after a TSF manager, service, or profile failure.'
}
Check 'native-register-propagates-category-manager-failure' {
    Assert-True ($registerServer -match 'CLSID_TF_CategoryMgr[\s\S]*?else\s*\{?\s*result\s*=\s*E_FAIL') `
        'Native registration can still return success when the category manager cannot be created.'
}
Check 'native-register-checks-module-path-and-every-com-value-write' {
    Assert-True ($registerServer.Contains('modulePathLen == 0 || modulePathLen >= MAX_PATH') -and
        [regex]::Matches($registerServer,'RegSetValueExW\(').Count -eq 3 -and
        [regex]::Matches($registerServer,'RegSetValueExW\([\s\S]*?\)\s*!=\s*ERROR_SUCCESS').Count -eq 3) `
        'Native registration can report success after a truncated module path or failed COM value write.'
}
Check 'native-profile-registration-propagates-the-selected-icon-index' {
    Assert-True ($dllEntry.Contains(
            'langProfileFromJson(std::wstring file, std::string& guid, int iconIndex)') -and
        $dllEntry -match 'iconFile\s*,\s*iconIndex\s*\}' -and
        $dllEntry.Contains('langProfileFromJson(imejson, guid, iconIndex)') -and
        $dllEntry.Contains('if(::IsWindows8OrGreater())') -and
        $dllEntry.Contains('iconIndex = 0') -and $dllEntry.Contains('iconIndex = 1')) `
        'DllEntry computes a Windows-version icon index but does not carry it into LangProfileInfo.'
}
Check 'native-com-registration-is-machine-explicit-not-hkcr-merged' {
    Assert-True ($registerServer.Contains('RegCreateKeyExW(HKEY_LOCAL_MACHINE') -and
        $registerServer.Contains('SOFTWARE\\Classes\\CLSID\\') -and
        $unregisterServer.Contains('SHDeleteKey(HKEY_LOCAL_MACHINE') -and
        $registerServer -notmatch 'RegCreateKeyExW\(HKEY_CLASSES_ROOT' -and
        $unregisterServer -notmatch 'SHDeleteKey\(HKEY_CLASSES_ROOT') `
        'Native COM registration still uses the merged HKCR view or does not target HKLM explicitly.'
}
Check 'native-unregister-removes-every-declared-category' {
    foreach ($category in @('GUID_TFCAT_TIP_KEYBOARD','GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER',
            'GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT','GUID_TFCAT_TIPCAP_UIELEMENTENABLED',
            'GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT','GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT')) {
        Assert-True ($unregisterServer.Contains("UnregisterCategory(textServiceClsid_, $category")) `
            "Native unregister does not remove $category."
    }
    Assert-True ($unregisterServer -notmatch '(?<!Un)RegisterCategory\s*\(') `
        'Native unregister still registers a category instead of removing it.'
    Assert-True ($unregisterServer.Contains('HRESULT result = S_OK') -and
        $unregisterServer.Contains('return result;') -and
        [regex]::Matches($unregisterServer,'result\s*=\s*E_FAIL').Count -ge 4) `
        'Native unregister still hides one or more profile/category/registry failures.'
}
Check 'native-and-wow64-dlls-split-one-shared-tsf-owner' {
    Assert-True ($dllEntry.Contains('#if defined(_WIN64)') -and
        $dllEntry.Contains('constexpr bool kOwnsSharedTsfRegistration = true') -and
        $dllEntry.Contains('constexpr bool kOwnsSharedTsfRegistration = false') -and
        $dllEntry.Contains('unregisterServer(kOwnsSharedTsfRegistration)') -and
        $cpp.Contains('if(result == S_OK && ownsSharedTsfRegistration)') -and
        $unregisterServer.Contains('if(ownsSharedTsfRegistration)')) `
        'Both architecture DLLs can still mutate the one shared CTF/TIP registration.'
    Assert-True ($unregisterServer.IndexOf('UnregisterCategory(') -ge 0 -and
        $unregisterServer.IndexOf('UnregisterCategory(') -lt
            $unregisterServer.IndexOf('inputProcessProfiles->Unregister(') -and
        $unregisterServer.IndexOf('inputProcessProfiles->Unregister(') -lt
            $unregisterServer.IndexOf('SHDeleteKey(')) `
        'Native removal does not use Category -> Profile -> per-view COM order.'
}
Check 'read-only-tsf-registration-probe-is-present' {
    $profileNameAnchor = 'kProfileName[] = L"' + [char]0x97F3 + [char]0x5143 + '"'
    foreach ($anchor in @('ITfInputProcessorProfileMgr','EnumProfiles(0, &values)',
            'TF_INPUTPROCESSORPROFILE','GetLanguageProfileDescription',$profileNameAnchor,
            'IsEnabledLanguageProfile','ITfCategoryMgr','EnumCategoriesInItem')) {
        Assert-True ($probe.Contains($anchor)) "Read-only registration probe anchor is missing: $anchor"
    }
}
Check 'probe-is-fixed-to-rime-pime-identity-and-complete-category-set' {
    foreach ($anchor in @('35f67e9d','3f6b5a12','GUID_TFCAT_TIP_KEYBOARD',
            'GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER','GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT',
            'GUID_TFCAT_TIPCAP_UIELEMENTENABLED','GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT',
            'GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT')) {
        Assert-True ($probe.Contains($anchor)) "Registration probe identity/category anchor is missing: $anchor"
    }
}
Check 'probe-enumeration-and-closed-sets-fail-closed' {
    Assert-True ([regex]::Matches($probe,'next == S_FALSE').Count -ge 2 -and
        [regex]::Matches($probe,'fetched == 0 \? S_OK : E_UNEXPECTED').Count -ge 2 -and
        [regex]::Matches($probe,'FAILED\(next\)').Count -ge 2 -and
        [regex]::Matches($probe,'fetched != 1').Count -ge 2 -and
        $probe.Contains('profile.serviceProfileCount == 1') -and
        $probe.Contains('profile.exactProfileCount == 1') -and
        $probe.Contains('state->totalCount == expectedCategoryTotal') -and
        $probe.Contains('state->expectedCount == expectedCategoryTotal') -and
        $probe.Contains('profile.serviceProfileCount == 0') -and
        $probe.Contains('categories.totalCount == 0')) `
        'Profile/category enumeration can still turn an error or extra registration into a passing closed set.'
    Assert-True ($probe.Contains('return IsWindows8OrGreater() ? kCategoryCapacity : 4') -and
        $probe.Contains('categories_expected_count=') -and
        $probe.Contains('expectedCategoryCount()')) `
        'Status probe category count can diverge from the native Windows 8 registration threshold.'
}
Check 'probe-has-fail-closed-registered-present-disabled-and-absent-modes' {
    Assert-True ($probe.Contains('verify-registered') -and $probe.Contains('verify-present') -and $probe.Contains('verify-disabled') -and
        $probe.Contains('verify-absent') -and
        $probe.Contains('mutation_performed=false') -and $probe.Contains('exitCode = registered ? 0') -and
        $probe.Contains('exitCode = present ? 0') -and
        $probe.Contains('exitCode = disabled ? 0') -and
        $probe.Contains('exitCode = absent ? 0')) `
        'Registration probe does not expose all fail-closed read-only lifecycle modes.'
}
Check 'probe-build-target-is-wired-for-each-native-tree' {
    Assert-True ($cmake.Contains('add_executable(PIMERegistrationStatus RegistrationStatus.cpp)') -and
        $cmake.Contains('target_link_libraries(PIMERegistrationStatus ole32 oleaut32)') -and
        $cmake.Contains('MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"') -and
        $rootCmake.Contains('cmake_policy(SET CMP0091 NEW)') -and
        $rootCmake.Contains('CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"')) `
        'PIMERegistrationStatus is not a standalone build target.'
}
Check 'probe-and-dll-architecture-identities-are-explicitly-guarded' {
    Assert-True ($probe.Contains('constexpr wchar_t kArchitecture[] = L"arm64"') -and
        $probe.Contains('constexpr wchar_t kArchitecture[] = L"x64"') -and
        $probe.Contains('constexpr wchar_t kArchitecture[] = L"x86"') -and
        $probe.Contains('L"architecture=" << kArchitecture')) `
        'Registration status cannot distinguish x64, x86 and ARM64 output.'
    foreach($anchor in @('$X86TextService','$X64TextService','$Arm64TextService',
            '$X86RegistrationStatus','$X64RegistrationStatus','$Arm64RegistrationStatus',
            '$RimeDll','$RimeDeployer','$RimeDictManager','$GoBackendRoot',
            '[uint16]0x014C','[uint16]0x8664','[uint16]0xAA64',
            'Get-PeImportedDlls','Read-PeNormalImportNames','Read-PeDelayImportNames',
            '$dataDirectoryOffset + (13 * 8)','VerifyStaticCrt','msvcr.*','api-ms-win-crt',
            'requires both -Arm64TextService and -Arm64RegistrationStatus explicitly')) {
        Assert-True $peGuard.Contains($anchor) "PE architecture guard is missing: $anchor"
    }
}
Check 'pe-import-gate-rejects-normal-and-delay-loaded-dynamic-crt-without-execution' {
    Assert-True ($peImportGateTest.Contains('accepts-safe-normal-import') -and
        $peImportGateTest.Contains('accepts-safe-delay-import') -and
        $peImportGateTest.Contains('default-gate-ignores-unselected-stale-arm64-build-tree') -and
        $peImportGateTest.Contains('accepts-explicit-paired-arm64-inputs') -and
        $peImportGateTest.Contains('rejects-one-sided-arm64-input') -and
        $peImportGateTest.Contains('rejects-msvcr-in-normal-import-directory') -and
        $peImportGateTest.Contains("-ImportKind normal -ImportedDll 'msvcr120.dll'") -and
        $peImportGateTest.Contains('rejects-vcruntime-in-delay-import-directory') -and
        $peImportGateTest.Contains("-ImportKind delay -ImportedDll 'vcruntime140.dll'") -and
        $peImportGateTest.Contains('synthetic_pe_images_executed = $false') -and
        $workflow.Contains('Test normal and delay PE import static CRT rejection') -and
        [regex]::Matches($workflow,'test-pe-import-gate\.ps1').Count -eq 2) `
        'Normal/delay import static-CRT negative coverage can be skipped or execute a fixture.'
}
Check 'ci-runs-complete-rime-pe-gate-only-after-package-build' {
    $nativeJob = [regex]::Match($workflow,
        '(?ms)^  native-build:\r?\n.*?(?=^  [A-Za-z0-9_-]+:\r?$|\z)').Value
    $payloadJob = [regex]::Match($workflow,
        '(?ms)^  installer-payload:\r?\n.*?(?=^  [A-Za-z0-9_-]+:\r?$|\z)').Value
    $goBuild = $payloadJob.IndexOf('cmd /C build.bat')
    $fullPeGate = $payloadJob.IndexOf('.\tools\verify-pe-architectures.ps1')
    Assert-True ($peGuard.Contains('[switch]$SkipPackagedRime') -and
        $nativeJob.Contains('.\tools\test-build-guards.ps1 -SkipPackagedRime') -and
        $goBuild -ge 0 -and $fullPeGate -gt $goBuild) `
        'A clean CI checkout can skip or prematurely run the complete packaged Rime PE/CRT gate.'
}
Check 'registration-probes-enter-build-handoff-signing-and-manifest-closure' {
    Assert-True ($workflow.Contains(
            'cmake --build build64 --config Release --target PIMETextService PIMERpcResponseTests PIMERegistrationStatus')) `
        'The x64 native job does not build PIMERegistrationStatus.'
    foreach($path in @('build\PIMETextService\Release\PIMERegistrationStatus.exe',
            'build64\PIMETextService\Release\PIMERegistrationStatus.exe')) {
        $yamlPath=$path.Replace('\','/')
        Assert-True ($workflow.Contains("Copy-Item $path") -and
            [regex]::Matches($workflow,[regex]::Escape($yamlPath)).Count -ge 2) `
            "CI does not stage and upload both unsigned and signed handoffs for $path."
        $planPath=$path.Replace('\','/')
        Assert-True $packagePlan.Contains("path='$planPath'") "Sealed package plan omits $path."
    }
    Assert-True (-not $packagePlan.Contains("path='build_arm64/") -and
        $packagePlan.Contains('x86/arm64x package-plan profile is reserved but not admitted')) `
        'Stale plain-ARM64 cross-build outputs can enter the current package plan.'
    foreach($path in @('go-backend\build\go-backend\input_methods\yime\rime.dll',
            'go-backend\build\go-backend\input_methods\yime\rime_deployer.exe',
            'go-backend\build\go-backend\input_methods\yime\rime_dict_manager.exe')) {
        $planPath=$path.Replace('\','/')
        Assert-True $packagePlan.Contains("path='$planPath'") "Sealed package plan omits $path."
    }
    Assert-True ($verifyReleaseSignatures -notmatch 'ErrorAction SilentlyContinue' -and
        $buildManifest -notmatch 'ErrorAction SilentlyContinue' -and
        $verifyReleaseSignatures.Contains('Read-RimePimePackagePlan') -and
        $buildManifest.Contains('Read-RimePimePackageBuildReceipt')) `
        'Release signature/manifest closure can silently omit a required exact artifact.'
    Assert-True ($workflow.Contains('test-installer-smoke.ps1 -InstallerPath $installer.FullName -StaticOnly') -and
        $workflow.Contains('without native installation') -and
        [regex]::Matches($workflow,'nsis-version: 3\.12').Count -eq 2 -and
        $workflow.Contains("Join-Path `$env:YIME_TRUSTED_SIGNING_ROOT 'tools\write-build-manifest.ps1') -RepoRoot `$env:GITHUB_WORKSPACE -OutputPath (Join-Path `$env:GITHUB_WORKSPACE 'installer\build-manifest.json')") -and
        [regex]::Matches($workflow,'installer/package-plan\.json\.sha256').Count -ge 3 -and
        [regex]::Matches($workflow,'installer/package-build-receipt\.json\.sha256').Count -ge 3 -and
        -not $workflow.Contains('nsis-version: 3.08')) `
        'Hosted CI still executes the installer without an Explorer same-SID physical target.'
}
Check 'installer-uses-explicit-native-and-wow64-regsvr32-paths' {
    Assert-True ($installer.Contains('$WINDIR\Sysnative\regsvr32.exe') -and
        $installer.Contains('$WINDIR\SysWOW64\regsvr32.exe') -and
        $registerSection.Contains('$RimeNativeRegsvr32') -and $registerSection.Contains('$RimeX86Regsvr32')) `
        'The 32-bit installer does not explicitly separate native and WOW64 regsvr32.'
}
Check 'installer-native-architecture-selection-is-mutually-exclusive' {
    foreach($body in @($installInit,$uninstallInit)) {
        Assert-True ($body.Contains('${If} ${IsNativeARM64}') -and
            $body.Contains('${ElseIf} ${IsNativeAMD64}') -and
            $body.IndexOf('${If} ${IsNativeARM64}') -lt $body.IndexOf('${ElseIf} ${IsNativeAMD64}')) `
            'Installer architecture allowlist is not an ARM64-or-AMD64 exclusive choice.'
    }
    foreach($body in @($registerSection,$uninstallSection)) {
        Assert-True ($body.Contains('$RimeNativeArchitecture == "x64"') -and
            $body.Contains('$RimeNativeArchitecture == "arm64"')) `
            'A product payload branch can still run both x64 and ARM64 paths.'
    }
    foreach($body in @($registerSection,$uninstallOld)) {
        Assert-True (-not $body.Contains('${If} ${RunningX64}') -and
            -not $body.Contains('${If} ${IsNativeARM64}')) `
            'A register or upgrade payload branch still uses overlapping native-platform macros.'
    }
    Assert-True ($uninstallOld -notmatch '(?:/u /s|RMDir|DeleteReg|Call stopRunningBackend)') `
        'The blocked current-family upgrade path still contains a mutation.'
    $uninstallViewBranches = [regex]::Matches($uninstallSection,
        '(?ms)\$\{If\} \$\{(?:RunningX64|IsNativeARM64)\}\s*(.*?)\s*\$\{EndIf\}')
    Assert-True ($uninstallViewBranches.Count -eq 2) `
        'Uninstall must keep exactly two native-view selection compatibility branches.'
    foreach($branch in $uninstallViewBranches) {
        Assert-True ($branch.Groups[1].Value -match '^\s*SetRegView 64\s*;[^\r\n]*\s*$') `
            'A raw native-platform uninstall branch performs product mutation instead of view selection only.'
    }
}
Check 'installer-checked-exec-rejects-launch-errors-and-nonzero-exits' {
    Assert-True ($checkedExecMacro.Contains('ClearErrors') -and
        $checkedExecMacro.Contains('StrCpy $registrationExitCode -1') -and
        $checkedExecMacro.Contains('ExecWait ''${COMMAND}'' $registrationExitCode') -and
        $checkedExecMacro.Contains('${If} ${Errors}') -and
        $checkedExecMacro.Contains('${If} $registrationExitCode != 0') -and
        [regex]::Matches($checkedExecMacro,'\bAbort\b').Count -ge 2) `
        'Registrar/status process launch errors or nonzero exits are not fail-closed.'
    Assert-True ([regex]::Matches($installer,'ExecWait[^\r\n]+\$registrationExitCode').Count -eq 1 -and
        [regex]::Matches($installer,'!insertmacro RunCheckedRegistrationCommand').Count -ge 20) `
        'One or more registration commands bypass the checked execution macro.'
}
Check 'native-components-are-static-crt-and-runtime-process-creation-fail-closed' {
    Assert-True ($launcherConfig.Contains('target-feature=+crt-static') -and
        [regex]::Matches($peGuard,'VerifyStaticCrt\s*=\s*\$true').Count -eq 11 -and
        $peGuard.Contains("Label = 'x64 packaged rime.dll'; VerifyStaticCrt = `$true") -and
        $peGuard.Contains("Label = 'x64 packaged rime_deployer.exe'; VerifyStaticCrt = `$true") -and
        $peGuard.Contains("Label = 'x64 packaged rime_dict_manager.exe'; VerifyStaticCrt = `$true") -and
        $peGuard.Contains('Label = "x64 packaged Go $name"') -and
        @('server.exe','tool-hub.exe','yime-trainer.exe','input-toolbar.exe','settings-tool.exe',
            'diagnostics-tool.exe','yime-layout-designer.exe','lexicon-manager.exe','reverse-lookup.exe',
            'system-lexicon-audit.exe','lexicon-promotion-scan.exe','blocklist-manager.exe' | Where-Object {
                -not $peGuard.Contains("'$_'")
            }).Count -eq 0) `
        'One or more packaged native components can regain a dynamic CRT dependency.'
    Assert-True ($installer -notmatch 'DownloadVerifiedVCRedist|ensureVCRedist|vc_redist\.|inetc::get') `
        'Installer runtime download returned despite complete static-CRT packaging.'
    $launch=$registerSection.IndexOf('Exec ''"$INSTDIR\PIMELauncher.exe"''')
    Assert-True ($launch -ge 0 -and
        $registerSection.LastIndexOf('ClearErrors',$launch) -lt $launch -and
        $registerSection.IndexOf('${If} ${Errors}',$launch) -gt $launch -and
        $registerSection.IndexOf('Abort',$launch) -gt $launch) `
        'PIMELauncher process-creation failure can still complete installation successfully.'
}
Check 'installer-checks-install-layout-or-tip-return' {
    $installFunction = [regex]::Match($installer,
        '(?ms)^Function InstallLayoutOrTipForUser\s+(.*?)^FunctionEnd').Groups[1].Value
    $uninstallFunction = [regex]::Match($installer,
        '(?ms)^Function un\.InstallLayoutOrTipForUser\s+(.*?)^FunctionEnd').Groups[1].Value
    Assert-True ($installFunction.Contains('InstallLayoutOrTip') -and
        $installFunction.Contains('${If} $0 == 0') -and $installFunction.Contains('Abort')) `
        'InstallLayoutOrTip enable FALSE is not fail-closed.'
    Assert-True ($uninstallFunction.Contains('InstallLayoutOrTip') -and
        $uninstallFunction.Contains('${If} $0 == 0') -and
        $uninstallFunction.Contains('exact disabled-state verification is still required') -and
        -not $uninstallFunction.Contains('Abort')) `
        'Uninstall FALSE is either trusted as success or prevents an already-disabled profile from removal.'
}
Check 'installer-packages-and-runs-profile-category-probes-before-runtime' {
    Assert-True ($registerSection.Contains('$PLUGINSDIR\PIMERegistrationStatus_x86.exe') -and
        $registerSection.Contains('$PLUGINSDIR\PIMERegistrationStatus_x64.exe') -and
        $registerSection -notmatch 'RunCheckedRegistrationCommand[^\r\n]+\$INSTDIR\\[^\r\n]*PIMERegistrationStatus' -and
        $registerSection.Contains('verify-present') -and
        $registerSection.IndexOf('verify-present') -lt $registerSection.IndexOf('Exec ')) `
        'Profile/category verification is absent, mutable, or occurs after runtime startup.'
}
Check 'removal-validates-complete-registration-before-stop-or-mutation' {
    Assert-True ($uninstallSection.IndexOf('Call un.verifyRegistrationOwnershipForRemoval') -ge 0 -and
        $uninstallSection.IndexOf('Call un.verifyInstalledRegistrationForRemoval') -gt
            $uninstallSection.IndexOf('Call un.verifyRegistrationOwnershipForRemoval') -and
        $uninstallSection.IndexOf('Call un.verifyInstalledRegistrationForRemoval') -lt
            $uninstallSection.IndexOf('Call un.stopOwnedPime')) `
        'Uninstall can mutate or stop before the exact registered state is proven.'
    Assert-True ($uninstallOld.Contains('In-place upgrade is not enabled') -and
        $uninstallOld.Contains('existing installation was not stopped, unregistered, overwritten or deleted') -and
        $uninstallOld -notmatch '(?:/u /s|RMDir|DeleteReg|Call stopRunningBackend)') `
        'Current-family upgrade is not an explicit read-only fail-closed path.'
    Assert-True ($installer.Contains('Function un.stageTrustedRegistrationTools') -and
        $uninstallSection -notmatch 'RunCheckedRegistrationCommand[^\r\n]+\$INSTDIR\\' -and
        $uninstallSection.Contains('$PLUGINSDIR\PIMETextService_x86.dll') -and
        $uninstallSection.Contains('$PLUGINSDIR\PIMERegistrationStatus_x86.exe')) `
        'Privileged uninstall still executes replaceable installed registration helpers.'
}
Check 'uninstall-proves-disabled-then-absent-before-raw-user-cleanup' {
    $disabled=$uninstallSection.IndexOf('verify-disabled')
    $unregister=$uninstallSection.IndexOf('/u /s')
    $lastAbsent=$uninstallSection.LastIndexOf('verify-absent')
    $cleanup=$uninstallSection.IndexOf('Call un.cleanupTargetUserProfile')
    Assert-True ($disabled -ge 0 -and $disabled -lt $unregister -and
        $lastAbsent -gt $unregister -and $cleanup -gt $lastAbsent -and
        $cleanup -lt $uninstallSection.IndexOf('DeleteRegKey')) `
        'Uninstall does not preserve the required disabled -> native absent -> raw cleanup order.'
}
Check 'uninstaller-verifies-profile-category-absence-before-deletion' {
    $nativeAbsent = $uninstallSection.IndexOf('Call un.verifyNativeRegistrationAbsent')
    $verify = $uninstallSection.IndexOf('verify-absent')
    Assert-True ($nativeAbsent -ge 0 -and $verify -gt $nativeAbsent -and
        $verify -lt $uninstallSection.IndexOf('DeleteRegKey') -and
        $verify -lt $uninstallSection.IndexOf('RMDir /REBOOTOK /r "$INSTDIR\x86"')) `
        'Uninstall deletes registration or payload before COM/Profile/category absence is verified.'
}
Check 'fresh-install-rejects-orphan-registration-before-stop-or-register' {
    Assert-True ($uninstallOld.Contains('Call verifyStagedRegistrationAbsent') -and
        $uninstallOld.Contains('StrCpy $RimeInstallMode "fresh"') -and
        $installInit -notmatch 'Call (?:uninstallOldVersion|stopRunningBackend)' -and
        $mainSection.IndexOf('Call uninstallOldVersion') -ge 0 -and
        [regex]::Matches($mainSection,'Call verifyStagedRegistrationAbsent').Count -ge 1 -and
        $mainSection.LastIndexOf('Call verifyStagedRegistrationAbsent') -lt
            $mainSection.IndexOf('SetOverwrite on') -and
        $uninstallOld -notmatch '(?:/u /s|RMDir|DeleteReg|Call stopRunningBackend)') `
        'Fresh/orphan state can reach a payload write without post-license final vacancy admission.'
}
Check 'legacy-registration-is-not-deleted-without-an-exact-owner-snapshot' {
    Assert-True ($installer -notmatch 'DeleteRegKey\s+HKLM\s+"\$\{LEGACY_PRODUCT_(?:UNINST|INSTALL)_KEY\}"') `
        'Legacy product keys are still deleted without a matching owner snapshot.'
}
Check 'payload-and-static-artifact-verifiers-are-pinned-with-release-blocked' {
    Assert-True ($payloadClosure.Contains('NumberOfLinks') -and
        $payloadClosure.Contains('FindFirstStreamW') -and
        $payloadClosure.Contains('Uninstall.exe requires a separately sealed self-identity contract') -and
        $payloadClosure.Contains('actual_install_or_removal_executed=$false') -and
        $payloadClosureTest.Contains("New-Item -ItemType HardLink") -and
        $payloadClosureTest.Contains("':private'") -and
        $payloadClosureTest.Contains('closure-rejects-second-pass-insertion') -and
        $staticVerifier.Contains('declared product-PE evidence manifest match') -and
        $staticVerifier.Contains('Read-RimePimePackagePlan') -and
        $staticVerifier.Contains('Read-RimePimePackageBuildReceipt') -and
        $buildManifest.Contains('receiptSha256=$receipt.Digest') -and
        $installerStaticTest.Contains('foreign-installer-basename-collision') -and
        $installerStaticTest.Contains('manifest-package-plan-digest-mismatch') -and
        $buildGuards.Contains('Go payload architecture mismatch rejection test passed.') -and
        $workflow.Contains('Test exact payload-closure rejection model') -and
        $workflow.Contains('Test static installer artifact verifier') -and
        $mainSection.Contains('This Rime/PIME development package is not installable yet.') -and
        $uninstallSection.Contains('development uninstaller is disabled until exact payload ownership') -and
        $workflow.Contains('Block tagged installer until signed-uninstaller and removal closure')) `
        'Payload/static verifier coverage drifted or an unsealed install/removal/release path reopened.'
}
Check 'source-snapshot-unchanged-during-run' {
    foreach ($relative in $sourceFiles) {
        $path = Join-Path $repo $relative
        if ([string]$beforeHashes[$relative] -ceq 'missing') {
            Assert-True (-not (Test-Path -LiteralPath $path)) "Missing source appeared during run: $relative"
        } else {
            $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            Assert-True ($actual -ceq [string]$beforeHashes[$relative]) "Source changed during run: $relative"
        }
    }
}

$failed = @($checks | Where-Object {-not $_.passed})
$receipt = [ordered]@{
    schema_version='yime-rime-pime-registration-completeness-test-v1'
    test_level='source-and-build-wiring-only-no-native-status-execution'
    source_sha256=$beforeHashes
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    powershell_edition=$PSVersionTable.PSEdition
    powershell_version=$PSVersionTable.PSVersion.ToString()
    check_count=$checks.Count
    passed_count=$checks.Count-$failed.Count
    failed_count=$failed.Count
    passed=$failed.Count -eq 0
    checks=$checks
    actual_registration_probe_executed=$false
    actual_installer_or_uninstaller_executed=$false
    actual_registry_profile_or_category_read_or_mutation_executed=$false
    default_input_method_changed=$false
    production_rime_pime_touched=$false
    dp1_full_implementation_passed=$false
    dp2_physical_acceptance_passed=$false
}
$receiptPath=Join-Path $output 'result.json'
[IO.File]::WriteAllText($receiptPath,($receipt|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
if($failed.Count) {
    Write-Host "FAIL: $($failed.Count) of $($checks.Count) registration-completeness source checks failed. Evidence: $receiptPath"
    foreach($item in $failed){Write-Host " - $($item.name): $($item.reason)"}
    exit 1
}
Write-Host "PASS: $($checks.Count) registration-completeness source checks passed without native execution. Evidence: $receiptPath"
