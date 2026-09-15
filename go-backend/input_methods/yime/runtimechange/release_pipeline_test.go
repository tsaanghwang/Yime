package runtimechange

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSourceBuildKeepsRuntimeAssetsAndArchitectures(t *testing.T) {
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
	textService := read(filepath.Join(root, "PIMETextService", "PIMETextService.cpp"))
	signFile := read(filepath.Join(root, "tools", "sign-file.ps1"))
	certificateImporter := read(filepath.Join(root, "tools", "import-release-signing-certificate.ps1"))
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
	for _, fragment := range []string{
		`\\go-backend\\input_methods\\yime\\data\\fonts\\YinYuan-Regular.ttf`,
		`AddFontResourceExW(privateFontPath_.c_str(), FR_PRIVATE, nullptr)`,
		`RemoveFontResourceExW(privateFontPath_.c_str(), FR_PRIVATE, nullptr)`,
	} {
		if !strings.Contains(textService, fragment) {
			t.Fatalf("text service private-font lifecycle is missing %q", fragment)
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
