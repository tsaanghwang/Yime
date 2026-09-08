package runtimechange

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestReleasePipelineKeepsSigningHooksAndBlocksUnsealedRelease(t *testing.T) {
	read := func(path string) string {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		return string(data)
	}
	root := filepath.Clean(filepath.Join("..", "..", "..", ".."))
	ci := read(filepath.Join(root, ".github", "workflows", "ci.yaml"))
	goTestScript := read(filepath.Join(root, "tools", "test-go.ps1"))
	rootBuildScript := read(filepath.Join(root, "build.bat"))
	buildScript := read(filepath.Join(root, "go-backend", "build.bat"))
	runtimeSources := []string{
		read(filepath.Join(root, "go-backend", "input_methods", "yime", "yime.go")),
		read(filepath.Join(root, "go-backend", "input_methods", "yime", "settings", "rime.go")),
		read(filepath.Join(root, "go-backend", "input_methods", "yime", "diagnostics", "collect.go")),
		read(filepath.Join(root, "go-backend", "input_methods", "yime", "learningmigration", "migration.go")),
	}
	installer := read(filepath.Join(root, "installer", "installer.nsi"))
	installer = strings.ReplaceAll(installer, "\r\n", "\n")
	textService := read(filepath.Join(root, "PIMETextService", "PIMETextService.cpp"))
	devUninstaller := read(filepath.Join(root, "tools", "dev-uninstall.ps1"))
	devStop := read(filepath.Join(root, "tools", "dev-stop-pime.ps1"))
	signer := read(filepath.Join(root, "tools", "sign-release.ps1"))
	verifier := read(filepath.Join(root, "tools", "verify-release-signatures.ps1"))
	packagePlan := read(filepath.Join(root, "tools", "dual-product", "rime-pime-package-plan.ps1"))
	installerBuilder := read(filepath.Join(root, "tools", "build-rime-pime-installer.ps1"))
	buildManifest := read(filepath.Join(root, "tools", "write-build-manifest.ps1"))
	signFile := read(filepath.Join(root, "tools", "sign-file.ps1"))
	certificateImporter := read(filepath.Join(root, "tools", "import-release-signing-certificate.ps1"))

	for _, fragment := range []string{
		"tags: ['v*']", "environment: release-signing", "Checkout trusted signing implementation",
		".trusted-signing", "Move trusted signing implementation outside source checkout",
		"YIME_TRUSTED_SIGNING_ROOT=$trustedRoot",
		"Join-Path $env:YIME_TRUSTED_SIGNING_ROOT 'tools\\sign-release.ps1'",
		"Join-Path $env:YIME_TRUSTED_SIGNING_ROOT 'tools\\verify-release-signatures.ps1'",
		"YIME-unsigned-test-installer", "installer/YIME-*-setup.exe",
	} {
		if !strings.Contains(ci, fragment) {
			t.Fatalf("CI release signing chain is missing %q", fragment)
		}
	}
	for _, fragment := range []string{
		"Block tagged installer until signed-uninstaller and removal closure",
		"Tagged Rime/PIME installer release is disabled until the embedded uninstaller is trusted",
	} {
		if !strings.Contains(ci, fragment) {
			t.Fatalf("CI unsealed-release block is missing %q", fragment)
		}
	}
	block := strings.Index(ci, "Block tagged installer until signed-uninstaller and removal closure")
	outerBuild := strings.Index(ci[block:], "build-rime-pime-installer.ps1")
	if block < 0 || outerBuild < 0 {
		t.Fatal("tagged release must fail before building the outer installer")
	}
	for _, fragment := range []string{
		"actions/setup-go@v6",
		"go-version: '1.26.4'",
		`.\tools\test-go.ps1`,
	} {
		if !strings.Contains(ci, fragment) {
			t.Fatalf("CI Go-test entry point is missing %q", fragment)
		}
	}
	for _, fragment := range []string{
		"$requiredYimeTests = @(",
		"TestDeployCommandQueuesConfirmedExternalBuildWithoutNativeRedeploy",
		"go test ./input_methods/yime -list '^Test'",
		"$listedYimeTests -notcontains $testName",
	} {
		if !strings.Contains(goTestScript, fragment) {
			t.Fatalf("Go required-test guard is missing %q", fragment)
		}
	}
	if strings.Contains(ci, "TestDeployCommandRedeploysCurrentSchema") || strings.Contains(goTestScript, "TestDeployCommandRedeploysCurrentSchema") {
		t.Fatal("CI must not retain the removed synchronous native-redeploy test name")
	}
	for _, fragment := range []string{"!finalize", "!uninstfinalize", "PACKAGE_SIGN_FILE_PATH"} {
		if !strings.Contains(installer, fragment) {
			t.Fatalf("NSIS signing hooks are missing %q", fragment)
		}
	}
	for _, fragment := range []string{
		`InstallDir "$PROGRAMFILES32\YIME"`,
		`ReadRegStr $R1 HKLM "${PRODUCT_INSTALL_KEY}" ""`,
		`StrCpy $INSTDIR $R1`,
		`StrCpy $INSTDIR "$PROGRAMFILES32\YIME"`,
		`Call enforceInstallRootPolicy`,
		`Command-line /D overrides and user-writable roots are not admitted.`,
		`WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"`,
		`RMDir /REBOOTOK /r "$INSTDIR\licenses"`,
		`RMDir "$INSTDIR\go-backend\input_methods\fcitx5"`,
		`RMDir "$INSTDIR\go-backend\input_methods\meow"`,
		`RMDir "$INSTDIR\go-backend\input_methods\simple_pinyin"`,
		`input.dll::InstallLayoutOrTip`,
		`0x0804:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}`,
	} {
		if !strings.Contains(installer, fragment) {
			t.Fatalf("NSIS installer is missing install-path or Yime payload guard %q", fragment)
		}
	}
	// Direct File/SetOutPath payload directives were sealed into a
	// content-hash-verified generated include; see rime-pime-nsis-stage.ps1.
	for _, fragment := range []string{
		"!ifndef PACKAGE_PAYLOAD_NSH_PATH",
		"!ifndef PACKAGE_PAYLOAD_NSH_SHA256",
		`!include "${PACKAGE_PAYLOAD_NSH_PATH}"`,
	} {
		if !strings.Contains(installer, fragment) {
			t.Fatalf("NSIS installer is missing sealed payload-stage include %q", fragment)
		}
	}
	if regexp.MustCompile(`(?mi)^[ \t]*File(?:[ \t]|$)`).MatchString(installer) {
		t.Fatal("NSIS installer must not read product payload directly through File; use the sealed stage include")
	}
	for _, forbidden := range []string{`$FONTS`, `CurrentVersion\Fonts`, `AddFontResource(`, `YinYuan Regular (TrueType)`} {
		if strings.Contains(installer, forbidden) {
			t.Fatalf("NSIS installer retains forbidden system-font mutation %q", forbidden)
		}
	}
	if strings.Contains(installer, `File /oname=YinYuan-Regular.ttf`) {
		t.Fatal("NSIS installer must not duplicate the font already present in the staged backend tree")
	}
	for _, fragment := range []string{
		`\\go-backend\\input_methods\\yime\\data\\fonts\\YinYuan-Regular.ttf`,
		`AddFontResourceExW(privateFontPath_.c_str(), FR_PRIVATE, nullptr)`,
		`RemoveFontResourceExW(privateFontPath_.c_str(), FR_PRIVATE, nullptr)`,
	} {
		if !strings.Contains(textService, fragment) {
			t.Fatalf("text service private-font lifecycle is missing %q", fragment)
		}
	}
	for _, forbidden := range []string{
		`ExecWait '"$INSTDIR\PIMELauncher.exe" /quit'`,
		`taskkill.exe" /F /T /IM PIMELauncher.exe`,
	} {
		if strings.Contains(installer, forbidden) {
			t.Fatalf("NSIS installer retains forbidden global Rime/PIME stop primitive %q", forbidden)
		}
	}
	for _, path := range []string{
		filepath.Join(root, "go-backend", "input_methods", "yime", "data", "yime_pua_pinyin.json"),
		filepath.Join(root, "go-backend", "input_methods", "yime", "data", "fonts", "YinYuan-Regular.ttf"),
		filepath.Join(root, "go-backend", "input_methods", "yime", "data", "default.yaml"),
		filepath.Join(root, "go-backend", "input_methods", "yime", "data", "symbols.yaml"),
		filepath.Join(root, "go-backend", "input_methods", "yime", "data", "essay.txt"),
		filepath.Join(root, "go-backend", "input_methods", "yime", "data", "opencc", "t2s.json"),
		filepath.Join(root, "go-backend", "input_methods", "yime", "data", "opencc", "TSCharacters.ocd2"),
		filepath.Join(root, "go-backend", "input_methods", "yime", "rime_runtime.lock.json"),
		filepath.Join(root, "go-backend", "input_methods", "yime", "rime_deployer.exe"),
		filepath.Join(root, "go-backend", "input_methods", "yime", "rime_dict_manager.exe"),
	} {
		if info, err := os.Stat(path); err != nil || info.Size() == 0 {
			t.Fatalf("required release asset is missing or empty: %s (%v)", path, err)
		}
	}
	if strings.Contains(installer, `ReadRegStr $INSTDIR`) {
		t.Fatal("NSIS registry probing must not clear the default installation directory")
	}
	if strings.Contains(installer, "Section $(CHEWING) chewing\n\t\t\tSectionIn 1 2") {
		t.Fatal("standard Yime installation must not select the legacy Python Chewing backend")
	}
	if !strings.Contains(devUninstaller, `Microsoft\Windows\CurrentVersion\Uninstall\YIME`) {
		t.Fatal("developer uninstall must remove its owned YIME uninstall registration")
	}
	if strings.Contains(devUninstaller, `Remove-RegistryTree -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PIME"`) {
		t.Fatal("developer uninstall must not clean the independent legacy PIME uninstall registration")
	}
	for _, fragment := range []string{"PIMELauncher.exe", "PIMETextService.dll", "rime_deployer.exe", "rime_dict_manager.exe", "rime.dll", "input-toolbar.exe", "yime-trainer.exe", "yime-layout-designer.exe"} {
		if !strings.Contains(packagePlan, fragment) {
			t.Fatalf("sealed release package plan is missing %q", fragment)
		}
	}
	for _, fragment := range []string{"Read-RimePimePackagePlan", "Write-RimePimePackagePlan"} {
		if !strings.Contains(signer, fragment) {
			t.Fatalf("release payload signer is not bound to the sealed plan lifecycle %q", fragment)
		}
	}
	for _, fragment := range []string{"PACKAGE_PLAN_SHA256", "PACKAGE_PLAN_X86_X64", "New-RimePimePreparedPublication"} {
		if !strings.Contains(installerBuilder, fragment) {
			t.Fatalf("installer builder is missing package-plan binding %q", fragment)
		}
	}
	if !strings.Contains(buildManifest, "Read-RimePimePackageBuildReceipt") || !strings.Contains(buildManifest, "receiptSha256") {
		t.Fatal("build manifest is not bound to the sealed package plan and receipt")
	}
	for _, fragment := range []string{
		`dual-product\rime-pime-ownership.ps1`,
		`Stop-YimePimeOwnedProcesses`,
		`TargetUserSid`,
	} {
		if !strings.Contains(devStop, fragment) {
			t.Fatalf("developer stop flow is missing directed ownership contract %q", fragment)
		}
	}
	for _, forbidden := range []string{`Stop-ProcessByName`, `Stop-ProcessByPathPrefix`, `PIMELauncher.exe" /quit`, `taskkill.exe`} {
		if strings.Contains(devStop, forbidden) {
			t.Fatalf("developer stop flow retains forbidden global/name stop primitive %q", forbidden)
		}
	}
	if !strings.Contains(verifier, "Get-AuthenticodeSignature") || !strings.Contains(verifier, "Valid") {
		t.Fatal("release signature verifier must reject non-valid signatures")
	}
	for _, fragment := range []string{"SignerCertificate.Thumbprint", "TimeStamperCertificate", "YIME_SIGN_CERT_SHA1"} {
		if !strings.Contains(verifier, fragment) {
			t.Fatalf("release signature verifier is missing %q", fragment)
		}
	}
	if count := strings.Count(buildScript, "--icon input_methods\\yime\\icon.ico"); count != 11 {
		t.Fatalf("expected all 11 Go executables to embed the Yime icon, got %d", count)
	}
	if count := strings.Count(buildScript, `--copyright "Copyright (C) 2026 Yime contributors"`); count != 11 {
		t.Fatalf("expected all 11 Go executables to embed Yime copyright metadata, got %d", count)
	}
	for _, fragment := range []string{
		`set "WIN32_CMAKE_PLATFORM=-A Win32"`,
		`/c:"CMAKE_GENERATOR_PLATFORM:INTERNAL="`,
		`%WIN32_CMAKE_PLATFORM% -DCMAKE_POLICY_VERSION_MINIMUM=3.5`,
		`--build build --config Release --target PIMETextService PIMERegistrationStatus`,
		`--build build64 --config Release --target PIMETextService PIMERegistrationStatus`,
		`--build build_arm64 --config Release --target PIMETextService PIMERegistrationStatus`,
		`set "ARM64_PE_ARGS="`,
		`set "ARM64_PE_ARGS=-Arm64TextService "%ROOT_DIR%\build_arm64\PIMETextService\Release\PIMETextService.dll" -Arm64RegistrationStatus "%ROOT_DIR%\build_arm64\PIMETextService\Release\PIMERegistrationStatus.exe""`,
		`verify-pe-architectures.ps1" -RepoRoot "%ROOT_DIR%" -SkipPackagedRime`,
	} {
		if !strings.Contains(rootBuildScript, fragment) {
			t.Fatalf("root build script is missing legacy Win32 CMake-cache compatibility %q", fragment)
		}
	}
	goPackageBuild := strings.Index(rootBuildScript, "cmd /C build.bat")
	fullPayloadGate := strings.LastIndex(rootBuildScript, `verify-pe-architectures.ps1" -RepoRoot "%ROOT_DIR%" %ARM64_PE_ARGS% || exit /b 1`)
	armBuild := strings.Index(rootBuildScript, `--build build_arm64 --config Release --target PIMETextService PIMERegistrationStatus`)
	armArgs := strings.Index(rootBuildScript, `set "ARM64_PE_ARGS=-Arm64TextService`)
	if goPackageBuild < 0 || fullPayloadGate <= goPackageBuild || armBuild < 0 || armArgs <= armBuild ||
		strings.Count(rootBuildScript, "%ARM64_PE_ARGS%") != 2 || strings.Count(rootBuildScript, "verify-pe-architectures.ps1") != 2 {
		t.Fatal("root build must run the complete PE gate only after the Go package exists")
	}
	if !strings.Contains(buildScript, `for /r "%PACKAGE_DIR%\input_methods" %%F in (*.go)`) {
		t.Fatal("package build must recursively remove copied Go source files")
	}
	for _, fragment := range []string{
		`verify-rime-runtime.ps1`,
		`rime_runtime.lock.json`,
		`Missing pinned Rime shared data`,
		`Missing pinned OpenCC shared data`,
		`Copying pinned bundled Rime shared data`,
	} {
		if !strings.Contains(buildScript, fragment) {
			t.Fatalf("package build is missing pinned Rime runtime/data guard: %q", fragment)
		}
	}
	for _, fragment := range []string{`LIBRIME_BUILD_DIR`, `merge_weasel_shared_data`, `find_weasel_data_dir`, `run_plum_install`, `C:\dev\librime`} {
		if strings.Contains(buildScript, fragment) {
			t.Fatalf("package build must not use a machine-local Rime fallback: %q", fragment)
		}
	}
	for _, source := range runtimeSources {
		for _, fragment := range []string{`C:\dev\librime`, `librime\build\bin\Release`} {
			if strings.Contains(source, fragment) {
				t.Fatalf("runtime source must not use a machine-local Rime fallback: %q", fragment)
			}
		}
	}
	for _, fragment := range []string{`rime-frost`, `Fetch Rime shared data`} {
		if strings.Contains(ci, fragment) {
			t.Fatalf("CI must use the committed pinned Rime shared data, not fetch %q", fragment)
		}
	}
	for _, fragment := range []string{`if not defined GOCACHE set "GOCACHE=%PIME_ROOT%\.tmp\go-cache"`, `if not defined GOTMPDIR set "GOTMPDIR=%PIME_ROOT%\.tmp\go-tmp"`} {
		if !strings.Contains(buildScript, fragment) {
			t.Fatalf("build.bat is missing workspace-local Go cache default %q", fragment)
		}
	}
	if !strings.Contains(certificateImporter, "Remove-Item -LiteralPath $pfxPath") {
		t.Fatal("release CI must remove the temporary PFX after import")
	}
	for _, fragment := range []string{"1.2.840.113549.1.1.1", "1.3.6.1.5.5.7.3.3", "HasPrivateKey", "NotAfter"} {
		if !strings.Contains(signFile, fragment) {
			t.Fatalf("sign-file.ps1 is missing certificate validation %q", fragment)
		}
	}
}
