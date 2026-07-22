package runtimechange

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReleasePipelineSignsPayloadInstallerAndUninstaller(t *testing.T) {
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
	installer := read(filepath.Join(root, "installer", "installer.nsi"))
	installer = strings.ReplaceAll(installer, "\r\n", "\n")
	devUninstaller := read(filepath.Join(root, "tools", "dev-uninstall.ps1"))
	signer := read(filepath.Join(root, "tools", "sign-release.ps1"))
	verifier := read(filepath.Join(root, "tools", "verify-release-signatures.ps1"))
	signFile := read(filepath.Join(root, "tools", "sign-file.ps1"))

	for _, fragment := range []string{"tags: ['v*']", "Import release signing certificate", "sign-release.ps1 -RequireComplete", "verify-release-signatures.ps1 -IncludeInstaller", "YIME-unsigned-test-installer", "installer/YIME-*-setup.exe"} {
		if !strings.Contains(ci, fragment) {
			t.Fatalf("CI release signing chain is missing %q", fragment)
		}
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
	for _, fragment := range []string{"!finalize", "!uninstfinalize", "sign-file.ps1"} {
		if !strings.Contains(installer, fragment) {
			t.Fatalf("NSIS signing hooks are missing %q", fragment)
		}
	}
	for _, fragment := range []string{
		`InstallDir "$PROGRAMFILES32\YIME"`,
		`ReadRegStr $R1 HKLM "${PRODUCT_INSTALL_KEY}" ""`,
		`StrCpy $INSTDIR $R1`,
		`StrCpy $INSTDIR "$PROGRAMFILES32\YIME"`,
		`File /r "..\go-backend\build\go-backend\*.*"`,
		`SetOutPath "$INSTDIR\licenses"`,
		`File "..\LICENSE.txt"`,
		`File "..\NOTICE.md"`,
		`File "..\THIRD_PARTY_NOTICES.md"`,
		`File "..\LICENSES\PIME-UPSTREAM-LICENSE.txt"`,
		`File "..\LICENSES\RIME-FROST-GPL-3.0.txt"`,
		`File "..\LICENSES\RUST-DEPENDENCIES.md"`,
		`WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"`,
		`RMDir /REBOOTOK /r "$INSTDIR\licenses"`,
		`RMDir "$INSTDIR\go-backend\input_methods\fcitx5"`,
		`RMDir "$INSTDIR\go-backend\input_methods\meow"`,
		`RMDir "$INSTDIR\go-backend\input_methods\simple_pinyin"`,
		`File /oname=YinYuan-Regular.ttf "..\go-backend\input_methods\yime\data\fonts\YinYuan-Regular.ttf"`,
		`AddFontResource`,
		`YinYuan Regular (TrueType)`,
		`Function stopRunningBackend`,
		`Call stopRunningBackend`,
		`ExecWait '"$INSTDIR\PIMELauncher.exe" /quit'`,
		`taskkill.exe" /F /T /IM PIMELauncher.exe`,
		`input.dll::InstallLayoutOrTip`,
		`0x0804:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}`,
	} {
		if !strings.Contains(installer, fragment) {
			t.Fatalf("NSIS installer is missing install-path or Yime payload guard %q", fragment)
		}
	}
	for _, path := range []string{
		filepath.Join(root, "go-backend", "input_methods", "yime", "data", "yime_pua_pinyin.json"),
		filepath.Join(root, "go-backend", "input_methods", "yime", "data", "fonts", "YinYuan-Regular.ttf"),
	} {
		if info, err := os.Stat(path); err != nil || info.Size() == 0 {
			t.Fatalf("PUA annotation release asset is missing or empty: %s (%v)", path, err)
		}
	}
	if strings.Contains(installer, `ReadRegStr $INSTDIR`) {
		t.Fatal("NSIS registry probing must not clear the default installation directory")
	}
	if strings.Contains(installer, "Section $(CHEWING) chewing\n\t\t\tSectionIn 1 2") {
		t.Fatal("standard Yime installation must not select the legacy Python Chewing backend")
	}
	for _, fragment := range []string{
		`Microsoft\Windows\CurrentVersion\Uninstall\YIME`,
		`Microsoft\Windows\CurrentVersion\Uninstall\PIME`,
	} {
		if !strings.Contains(devUninstaller, fragment) {
			t.Fatalf("developer uninstall must remove stale uninstall registration %q", fragment)
		}
	}
	for _, fragment := range []string{"PIMELauncher.exe", "PIMETextService.dll", "rime_deployer.exe", "rime_dict_manager.exe", "rime.dll"} {
		if !strings.Contains(signer, fragment) {
			t.Fatalf("release payload signer is missing %q", fragment)
		}
	}
	if !strings.Contains(signer, "yime-layout-designer.exe") {
		t.Fatal("release payload signer is missing yime-layout-designer.exe")
	}
	if !strings.Contains(verifier, "Get-AuthenticodeSignature") || !strings.Contains(verifier, "Valid") {
		t.Fatal("release signature verifier must reject non-valid signatures")
	}
	for _, fragment := range []string{"SignerCertificate.Thumbprint", "TimeStamperCertificate", "YIME_SIGN_CERT_SHA1"} {
		if !strings.Contains(verifier, fragment) {
			t.Fatalf("release signature verifier is missing %q", fragment)
		}
	}
	if count := strings.Count(buildScript, "--icon input_methods\\yime\\icon.ico"); count != 9 {
		t.Fatalf("expected all 9 Go executables to embed the Yime icon, got %d", count)
	}
	if count := strings.Count(buildScript, `--copyright "Copyright (C) 2026 Yime contributors"`); count != 9 {
		t.Fatalf("expected all 9 Go executables to embed Yime copyright metadata, got %d", count)
	}
	for _, fragment := range []string{
		`set "WIN32_CMAKE_PLATFORM=-A Win32"`,
		`/c:"CMAKE_GENERATOR_PLATFORM:INTERNAL="`,
		`%WIN32_CMAKE_PLATFORM% -DCMAKE_POLICY_VERSION_MINIMUM=3.5`,
	} {
		if !strings.Contains(rootBuildScript, fragment) {
			t.Fatalf("root build script is missing legacy Win32 CMake-cache compatibility %q", fragment)
		}
	}
	if !strings.Contains(buildScript, `for /r "%PACKAGE_DIR%\input_methods" %%F in (*.go)`) {
		t.Fatal("package build must recursively remove copied Go source files")
	}
	for _, fragment := range []string{
		`if exist "%PACKAGE_RIME_DATA_DIR%\preview" rmdir /s /q "%PACKAGE_RIME_DATA_DIR%\preview"`,
		`if exist "%PACKAGE_RIME_DATA_DIR%\weasel.yaml" del /q "%PACKAGE_RIME_DATA_DIR%\weasel.yaml"`,
	} {
		if !strings.Contains(buildScript, fragment) {
			t.Fatalf("package build must remove Weasel-only runtime asset: %q", fragment)
		}
	}
	for _, fragment := range []string{`if not defined GOCACHE set "GOCACHE=%PIME_ROOT%\.tmp\go-cache"`, `if not defined GOTMPDIR set "GOTMPDIR=%PIME_ROOT%\.tmp\go-tmp"`} {
		if !strings.Contains(buildScript, fragment) {
			t.Fatalf("build.bat is missing workspace-local Go cache default %q", fragment)
		}
	}
	if !strings.Contains(ci, "Remove-Item -LiteralPath $pfxPath") {
		t.Fatal("release CI must remove the temporary PFX after import")
	}
	for _, fragment := range []string{"1.2.840.113549.1.1.1", "1.3.6.1.5.5.7.3.3", "HasPrivateKey", "NotAfter"} {
		if !strings.Contains(signFile, fragment) {
			t.Fatalf("sign-file.ps1 is missing certificate validation %q", fragment)
		}
	}
}
