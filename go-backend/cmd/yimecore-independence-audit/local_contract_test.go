package main

import (
	"crypto/sha256"
	"debug/pe"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"sort"
	"strings"
	"testing"
)

func localDescriptorFixture(t *testing.T) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "..", "..", "tools", "yimecore", "local-product.json"))
	if err != nil {
		t.Fatal(err)
	}
	// Preserve the L2 runtime-only fixture independently of the current builder.
	var descriptor map[string]any
	if err := json.Unmarshal(data, &descriptor); err != nil {
		t.Fatal(err)
	}
	descriptor["package_contract"] = localRuntimeContract
	descriptor["installable"] = false
	data, err = json.Marshal(descriptor)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func TestLocalContractDoesNotWeakenLegacy(t *testing.T) {
	legacy, err := requiredFilesForContract(packageManifest{ToolVersion: "yimecore-e6c-staged-package-v1"})
	if err != nil || !reflect.DeepEqual(legacy, requiredPackageFiles) {
		t.Fatalf("legacy requirements changed: %v", err)
	}
	for _, path := range []string{"x86/YimeTextServiceExperiment.dll", "arm64/YimeTextServiceRegistration.exe"} {
		found := false
		for _, required := range legacy {
			found = found || path == required
		}
		if !found {
			t.Fatalf("legacy required file removed: %s", path)
		}
	}
	for _, manifest := range []packageManifest{
		{ToolVersion: "yimecore-local-builder-v1"},
		{ToolVersion: "yimecore-local-builder-v1", PackageContract: "future-or-misspelled"},
		{ToolVersion: "legacy", PackageContract: localRuntimeContract},
	} {
		if _, err := requiredFilesForContract(manifest); err == nil {
			t.Fatalf("accepted invalid contract: %+v", manifest)
		}
	}
}

func TestLocalRequiredFilesMatchCanonicalBuildCatalog(t *testing.T) {
	var descriptor struct {
		GoBinaries     []struct{ Path string } `json:"go_binaries"`
		NativeBinaries []string                `json:"native_binaries"`
		Assets         []struct{ Path string } `json:"assets"`
		Maintenance    []struct{ Path string } `json:"maintenance_assets"`
	}
	if err := json.Unmarshal(localDescriptorFixture(t), &descriptor); err != nil {
		t.Fatal(err)
	}
	want := []string{"indexes/full.yidx", "indexes/variable.yidx", "indexes/shorthand.yidx", "local-product.json",
		"build/source-manifest.json", "build/build-inputs.json", "build/go-runtime-dependencies.txt"}
	for _, item := range descriptor.GoBinaries {
		want = append(want, item.Path)
	}
	for _, item := range descriptor.NativeBinaries {
		want = append(want, "x64/"+item)
	}
	for _, item := range descriptor.Assets {
		want = append(want, item.Path)
	}
	got := append([]string(nil), requiredLocalRuntimeFiles...)
	sort.Strings(want)
	sort.Strings(got)
	if !reflect.DeepEqual(want, got) {
		t.Fatalf("auditor/build catalog drift:\nwant=%v\ngot=%v", want, got)
	}
	want = nil
	for _, item := range descriptor.Maintenance {
		want = append(want, item.Path)
	}
	got = append([]string(nil), requiredLocalMaintenanceFiles...)
	sort.Strings(want)
	sort.Strings(got)
	if !reflect.DeepEqual(want, got) {
		t.Fatalf("maintenance catalog drift: want=%v got=%v", want, got)
	}
}

func TestInstallableContractRequiredMaintenanceAndIdentity(t *testing.T) {
	root := writeLocalFixture(t)
	// Reconstruct the static fixture as the new contract, retaining complete
	// mandatory runtime and maintenance sets. No maintenance scripts are run.
	for _, path := range requiredLocalMaintenanceFiles {
		full := filepath.Join(root, filepath.FromSlash(path))
		if err := os.MkdirAll(filepath.Dir(full), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("fixture"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	data, err := os.ReadFile(filepath.Join("..", "..", "..", "tools", "yimecore", "local-product.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "local-product.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	mutateLocalManifest(t, root, func(m *packageManifest) {
		m.PackageContract = localInstallableContract
		m.Files = nil
		for _, path := range append(append([]string(nil), requiredLocalRuntimeFiles...), requiredLocalMaintenanceFiles...) {
			data, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(path)))
			if err != nil {
				t.Fatal(err)
			}
			hash := sha256.Sum256(data)
			m.Files = append(m.Files, manifestFile{Path: path, Bytes: int64(len(data)), SHA256: hex.EncodeToString(hash[:])})
		}
	})
	if report, err := auditPackage(root); err != nil || !report.Passed {
		t.Fatalf("installable candidate rejected: %+v %v", report, err)
	}
	mutateLocalManifest(t, root, func(m *packageManifest) {
		for i, item := range m.Files {
			if item.Path == "maintenance/local-runtime-launcher.cs" {
				m.Files = append(m.Files[:i], m.Files[i+1:]...)
				break
			}
		}
	})
	if err := os.Remove(filepath.Join(root, "maintenance", "local-runtime-launcher.cs")); err != nil {
		t.Fatal(err)
	}
	if report, err := auditPackage(root); err == nil || report.RequiredComponentsPassed {
		t.Fatalf("missing privilege helper passed: %+v", report)
	}
}

func writeLocalFixture(t *testing.T) string {
	t.Helper()
	if runtime.GOOS != "windows" || runtime.GOARCH != "amd64" {
		t.Skip("native x64 static PE fixtures only")
	}
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	peBytes, err := os.ReadFile(exe)
	if err != nil {
		t.Fatal(err)
	}
	files := []testFile{}
	for _, path := range requiredLocalRuntimeFiles {
		data := []byte("fixture")
		if strings.HasSuffix(path, ".exe") || strings.HasSuffix(path, ".dll") {
			data = peBytes
		}
		if path == "local-product.json" {
			data = localDescriptorFixture(t)
		}
		files = append(files, testFile{path: path, data: data})
	}
	root := t.TempDir()
	writeTestManifest(t, root, files)
	mutateLocalManifest(t, root, func(m *packageManifest) {
		m.ToolVersion = "yimecore-local-builder-v1"
		m.PackageContract = localRuntimeContract
	})
	return root
}

func mutateLocalManifest(t *testing.T, root string, mutate func(*packageManifest)) {
	t.Helper()
	path := filepath.Join(root, "package-manifest.json")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var manifest packageManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		t.Fatal(err)
	}
	mutate(&manifest)
	data, err = json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
}

func TestLocalAuditCompleteAndMissingComponent(t *testing.T) {
	root := writeLocalFixture(t)
	if report, err := auditPackage(root); err != nil || !report.Passed {
		t.Fatalf("valid x64 bundle rejected: %+v %v", report, err)
	}
	path := "indexes/shorthand.yidx"
	if err := os.Remove(filepath.Join(root, filepath.FromSlash(path))); err != nil {
		t.Fatal(err)
	}
	mutateLocalManifest(t, root, func(m *packageManifest) {
		for i, item := range m.Files {
			if item.Path == path {
				m.Files = append(m.Files[:i], m.Files[i+1:]...)
				break
			}
		}
	})
	if report, err := auditPackage(root); err == nil || report.RequiredComponentsPassed {
		t.Fatalf("missing index passed: %+v", report)
	}
}

func TestLocalAuditRejectsWrongArchitectureInBin(t *testing.T) {
	root := writeLocalFixture(t)
	path := "bin/YimeBroker.exe"
	full := filepath.Join(root, filepath.FromSlash(path))
	data, err := os.ReadFile(full)
	if err != nil {
		t.Fatal(err)
	}
	// A static header fixture, never an x86 executable build or test execution.
	data = peFixtureForMachine(t, data, pe.IMAGE_FILE_MACHINE_I386)
	if err := os.WriteFile(full, data, 0600); err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(data)
	mutateLocalManifest(t, root, func(m *packageManifest) {
		for i := range m.Files {
			if m.Files[i].Path == path {
				m.Files[i].SHA256 = hex.EncodeToString(digest[:])
			}
		}
	})
	if report, err := auditPackage(root); err == nil || report.PEArchitecturePassed {
		t.Fatalf("non-x64 bin passed: %+v", report)
	}
}

func TestLocalDescriptorRejectsInstallabilityAndIdentityChanges(t *testing.T) {
	root := t.TempDir()
	var original map[string]any
	if err := json.Unmarshal(localDescriptorFixture(t), &original); err != nil {
		t.Fatal(err)
	}
	for _, scenario := range []string{"installable", "missing-installable", "clsid", "scope", "frozen-payload", "installer"} {
		t.Run(scenario, func(t *testing.T) {
			data, _ := json.Marshal(original)
			var current map[string]any
			if err := json.Unmarshal(data, &current); err != nil {
				t.Fatal(err)
			}
			entries := map[string]manifestFile{}
			switch scenario {
			case "installable":
				current["installable"] = true
			case "missing-installable":
				delete(current, "installable")
			case "clsid":
				current["identity"].(map[string]any)["clsid"] = "{new-identity}"
			case "scope":
				current["scope"].(map[string]any)["active_architectures"] = []string{"x64", "arm64"}
			case "frozen-payload":
				entries["x86/retained.bin"] = manifestFile{}
			case "installer":
				entries["install.cmd"] = manifestFile{}
			}
			data, _ = json.Marshal(current)
			if err := os.WriteFile(filepath.Join(root, "local-product.json"), data, 0600); err != nil {
				t.Fatal(err)
			}
			if err := validateLocalRuntimeContract(root, entries); err == nil {
				t.Fatal("invalid local contract passed")
			}
		})
	}
}

func TestManifestRejectsAmbiguousWindowsPaths(t *testing.T) {
	for _, path := range []string{"bin/../outside", "bin//tool", "bin/./tool", "bin/tool.", "bin/tool ", "bin/tool:stream"} {
		if _, err := safeManifestPath(path); err == nil {
			t.Fatalf("accepted %q", path)
		}
	}
}
