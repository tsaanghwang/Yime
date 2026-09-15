package main

import (
	"crypto/sha256"
	"debug/pe"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestSafeManifestPathRejectsEscape(t *testing.T) {
	for _, path := range []string{"", "../outside", "C:/outside", "/outside"} {
		if _, err := safeManifestPath(path); err == nil {
			t.Fatalf("safeManifestPath(%q) accepted an unsafe path", path)
		}
	}
	if got, err := safeManifestPath("bin/YimeBroker.exe"); err != nil || got != "bin/YimeBroker.exe" {
		t.Fatalf("safe path = %q, %v", got, err)
	}
}

func TestAuditRejectsForbiddenArtifact(t *testing.T) {
	root := t.TempDir()
	writeTestManifest(t, root, []testFile{{path: "bin/rime.dll", data: []byte("not a PE")}})
	report, err := auditPackage(root)
	if err == nil || report.ForbiddenArtifactsAbsent || report.Passed {
		t.Fatalf("forbidden artifact report = %+v, err=%v", report, err)
	}
}

func TestAuditRejectsUnlistedPackageFile(t *testing.T) {
	root := t.TempDir()
	writeTestManifest(t, root, nil)
	if err := os.WriteFile(filepath.Join(root, "unexpected.bin"), []byte("extra"), 0o644); err != nil {
		t.Fatal(err)
	}
	report, err := auditPackage(root)
	if err == nil || report.ManifestIntegrityPassed || report.Passed {
		t.Fatalf("unlisted file report = %+v, err=%v", report, err)
	}
}

func TestValidateInstallMetadata(t *testing.T) {
	root := t.TempDir()
	metadata := installMetadata{
		SchemaVersion:         "yimecore-trial-install-v1",
		ProductKey:            "YimeCoreExperimentalTrial",
		InstallRoot:           root,
		PackageManifestSHA256: "manifest-hash",
		GitCommit:             "commit",
	}
	data, err := json.Marshal(metadata)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "install-metadata.json")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := validateInstallMetadata(path, root, "manifest-hash", "commit"); err != nil {
		t.Fatal(err)
	}
	if err := validateInstallMetadata(path, root, "changed", "commit"); err == nil {
		t.Fatal("metadata with a changed manifest hash was accepted")
	}
}

func TestAuditAcceptsPowerShellUTF8BOM(t *testing.T) {
	root := t.TempDir()
	writeTestManifest(t, root, nil)
	path := filepath.Join(root, "package-manifest.json")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, append([]byte{0xef, 0xbb, 0xbf}, data...), 0o644); err != nil {
		t.Fatal(err)
	}
	report, err := auditPackage(root)
	if err == nil || report.ManifestToolVersion != "test-package-v1" {
		t.Fatalf("BOM manifest was not decoded before normal gate failures: %+v, err=%v", report, err)
	}
}

func TestAuditAcceptsCompleteIndependentPackage(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("uses the Windows test executable as a valid PE fixture")
	}
	fixture, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(fixture)
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	files := make([]testFile, 0, len(requiredPackageFiles))
	for _, path := range requiredPackageFiles {
		machine := uint16(pe.IMAGE_FILE_MACHINE_AMD64)
		switch expectedMachine(path) {
		case "i386":
			machine = pe.IMAGE_FILE_MACHINE_I386
		case "arm64":
			machine = pe.IMAGE_FILE_MACHINE_ARM64
		}
		files = append(files, testFile{path: path, data: peFixtureForMachine(t, data, machine)})
	}
	writeTestManifest(t, root, files)
	report, err := auditPackage(root)
	if err != nil || !report.Passed || !report.ManifestIntegrityPassed || !report.RequiredComponentsPassed ||
		!report.PEArchitecturePassed || !report.ForbiddenArtifactsAbsent || !report.ForbiddenPEImportsAbsent {
		t.Fatalf("complete package report = %+v, err=%v", report, err)
	}
	if len(report.PEFiles) != len(requiredPackageFiles) || len(report.PEFiles[0].Libraries) == 0 {
		t.Fatalf("PE import evidence is incomplete: %+v", report.PEFiles)
	}
}

func peFixtureForMachine(t *testing.T, source []byte, machine uint16) []byte {
	t.Helper()
	fixture := append([]byte(nil), source...)
	if len(fixture) < 0x40 {
		t.Fatal("test executable has no DOS header")
	}
	peOffset := int(binary.LittleEndian.Uint32(fixture[0x3c:0x40]))
	if peOffset < 0 || peOffset+6 > len(fixture) {
		t.Fatal("test executable has no PE header")
	}
	binary.LittleEndian.PutUint16(fixture[peOffset+4:peOffset+6], machine)
	return fixture
}

type testFile struct {
	path string
	data []byte
}

func writeTestManifest(t *testing.T, root string, files []testFile) {
	t.Helper()
	manifest := packageManifest{ToolVersion: "test-package-v1", GitCommit: "test-commit", Scope: "independent test"}
	for _, item := range files {
		path := filepath.Join(root, filepath.FromSlash(item.path))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, item.data, 0o644); err != nil {
			t.Fatal(err)
		}
		digest := sha256.Sum256(item.data)
		manifest.Files = append(manifest.Files, manifestFile{
			Path: item.path, Bytes: int64(len(item.data)), SHA256: hex.EncodeToString(digest[:]),
		})
	}
	data, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "package-manifest.json"), data, 0o644); err != nil {
		t.Fatal(err)
	}
}
