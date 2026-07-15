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
		"$requiredYimeTests = @(",
		"TestDeployCommandQueuesConfirmedExternalBuildWithoutNativeRedeploy",
		"go test ./input_methods/yime -list '^Test'",
		"$listedYimeTests -notcontains $testName",
	} {
		if !strings.Contains(ci, fragment) {
			t.Fatalf("CI required-test guard is missing %q", fragment)
		}
	}
	if strings.Contains(ci, "TestDeployCommandRedeploysCurrentSchema") {
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
	for _, fragment := range []string{"PIMELauncher.exe", "PIMETextService.dll", "rime_deployer.exe", "rime.dll"} {
		if !strings.Contains(signer, fragment) {
			t.Fatalf("release payload signer is missing %q", fragment)
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
	if count := strings.Count(buildScript, "--icon input_methods\\yime\\icon.ico"); count != 8 {
		t.Fatalf("expected all 8 Go executables to embed the Yime icon, got %d", count)
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
