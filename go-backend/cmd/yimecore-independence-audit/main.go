package main

import (
	"bytes"
	"crypto/sha256"
	"debug/pe"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const reportSchema = "yimecore-independence-audit-v1"

var requiredPackageFiles = []string{
	"bin/YimeBroker.exe",
	"bin/YimeCoreTrialRuntime.exe",
	"x64/YimeTextServiceExperiment.dll",
	"x64/YimeTextServiceRegistration.exe",
	"x86/YimeTextServiceExperiment.dll",
	"x86/YimeTextServiceRegistration.exe",
	"arm64/YimeTextServiceExperiment.dll",
	"arm64/YimeTextServiceRegistration.exe",
}

var forbiddenDependencyPrefixes = []string{"librime", "pime", "weasel"}

type packageManifest struct {
	PackageContract string         `json:"package_contract,omitempty"`
	ToolVersion     string         `json:"tool_version"`
	GitCommit       string         `json:"git_commit"`
	Scope           string         `json:"scope"`
	Files           []manifestFile `json:"files"`
}

type manifestFile struct {
	Path   string `json:"path"`
	Bytes  int64  `json:"bytes"`
	SHA256 string `json:"sha256"`
}

type installMetadata struct {
	SchemaVersion         string `json:"schema_version"`
	ProductKey            string `json:"product_key"`
	InstallRoot           string `json:"install_root"`
	PackageManifestSHA256 string `json:"package_manifest_sha256"`
	GitCommit             string `json:"git_commit"`
}

type peEvidence struct {
	Path      string   `json:"path"`
	Machine   string   `json:"machine"`
	Libraries []string `json:"imported_libraries"`
}

type auditReport struct {
	SchemaVersion            string       `json:"schema_version"`
	GeneratedAt              string       `json:"generated_at"`
	PackageRoot              string       `json:"package_root"`
	ManifestSHA256           string       `json:"manifest_sha256"`
	ManifestToolVersion      string       `json:"manifest_tool_version"`
	ManifestGitCommit        string       `json:"manifest_git_commit"`
	ManifestScope            string       `json:"manifest_scope"`
	ManifestFileCount        int          `json:"manifest_file_count"`
	ManifestIntegrityPassed  bool         `json:"manifest_integrity_passed"`
	InstallMetadataPassed    bool         `json:"install_metadata_passed"`
	RequiredComponentsPassed bool         `json:"required_components_passed"`
	PEArchitecturePassed     bool         `json:"pe_architecture_passed"`
	ForbiddenArtifactsAbsent bool         `json:"forbidden_artifacts_absent"`
	ForbiddenPEImportsAbsent bool         `json:"forbidden_pe_imports_absent"`
	PEFiles                  []peEvidence `json:"pe_files"`
	Failures                 []string     `json:"failures"`
	Passed                   bool         `json:"passed"`
}

func main() {
	packageRoot := flag.String("package", "", "installed or staged YimeCore package root")
	output := flag.String("output", "", "evidence JSON path, or - for read-only stdout")
	flag.Parse()
	if *packageRoot == "" || *output == "" {
		fmt.Fprintln(os.Stderr, "-package and -output are required")
		os.Exit(2)
	}
	report, err := auditPackage(*packageRoot)
	var writeErr error
	if *output == "-" {
		writeErr = json.NewEncoder(os.Stdout).Encode(report)
	} else {
		writeErr = writeReport(*output, report)
	}
	if writeErr != nil {
		fmt.Fprintln(os.Stderr, writeErr)
		os.Exit(1)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if *output != "-" {
		fmt.Printf("YimeCore independence audit passed: %s\n", *output)
	}
}

func auditPackage(root string) (auditReport, error) {
	absoluteRoot, err := filepath.Abs(root)
	if err != nil {
		return auditReport{}, err
	}
	absoluteRoot = filepath.Clean(absoluteRoot)
	report := auditReport{
		SchemaVersion:            reportSchema,
		GeneratedAt:              time.Now().UTC().Format(time.RFC3339Nano),
		PackageRoot:              absoluteRoot,
		ManifestIntegrityPassed:  true,
		InstallMetadataPassed:    true,
		RequiredComponentsPassed: true,
		PEArchitecturePassed:     true,
		ForbiddenArtifactsAbsent: true,
		ForbiddenPEImportsAbsent: true,
	}
	manifestPath := filepath.Join(absoluteRoot, "package-manifest.json")
	manifestBytes, err := os.ReadFile(manifestPath)
	if err != nil {
		report.fail("read package manifest: %v", err)
		return report, errors.New("YimeCore independence audit failed")
	}
	manifestDigest := sha256.Sum256(manifestBytes)
	report.ManifestSHA256 = hex.EncodeToString(manifestDigest[:])
	var manifest packageManifest
	manifestJSON := bytes.TrimPrefix(manifestBytes, []byte{0xef, 0xbb, 0xbf})
	if err := json.Unmarshal(manifestJSON, &manifest); err != nil {
		report.fail("decode package manifest: %v", err)
		return report, errors.New("YimeCore independence audit failed")
	}
	report.ManifestToolVersion = manifest.ToolVersion
	report.ManifestGitCommit = manifest.GitCommit
	report.ManifestScope = manifest.Scope
	report.ManifestFileCount = len(manifest.Files)
	if manifest.ToolVersion == "" || manifest.GitCommit == "" || len(manifest.Files) == 0 {
		report.ManifestIntegrityPassed = false
		report.fail("manifest identity or file list is incomplete")
	}
	required, contractErr := requiredFilesForContract(manifest)
	if contractErr != nil {
		report.RequiredComponentsPassed = false
		report.fail("package contract: %v", contractErr)
	}

	entries := make(map[string]manifestFile, len(manifest.Files))
	for _, item := range manifest.Files {
		relative, pathErr := safeManifestPath(item.Path)
		if pathErr != nil {
			report.ManifestIntegrityPassed = false
			report.fail("invalid manifest path %q: %v", item.Path, pathErr)
			continue
		}
		key := strings.ToLower(relative)
		if _, exists := entries[key]; exists {
			report.ManifestIntegrityPassed = false
			report.fail("duplicate manifest path: %s", relative)
			continue
		}
		entries[key] = item
		if containsForbiddenToken(relative) {
			report.ForbiddenArtifactsAbsent = false
			report.fail("forbidden compatibility artifact in package: %s", relative)
		}
		fullPath := filepath.Join(absoluteRoot, filepath.FromSlash(relative))
		if err := rejectIndirectPath(absoluteRoot, relative); err != nil {
			report.ManifestIntegrityPassed = false
			report.fail("indirect package path %s: %v", relative, err)
			continue
		}
		info, statErr := os.Stat(fullPath)
		if statErr != nil || !info.Mode().IsRegular() {
			report.ManifestIntegrityPassed = false
			report.fail("manifest file missing or not regular: %s", relative)
			continue
		}
		if info.Size() != item.Bytes {
			report.ManifestIntegrityPassed = false
			report.fail("manifest size mismatch for %s", relative)
		}
		digest, hashErr := hashFile(fullPath)
		if hashErr != nil || !strings.EqualFold(digest, item.SHA256) {
			report.ManifestIntegrityPassed = false
			report.fail("manifest hash mismatch for %s", relative)
		}
		if extension := strings.ToLower(filepath.Ext(relative)); extension == ".exe" || extension == ".dll" {
			peItem, peErr := inspectPE(fullPath, relative)
			if peErr != nil {
				report.PEArchitecturePassed = false
				report.fail("inspect PE %s: %v", relative, peErr)
				continue
			}
			expected := expectedMachine(relative)
			if manifest.PackageContract == localRuntimeContract || manifest.PackageContract == localInstallableContract {
				// Runtime/tooling remains native x64. Only the explicitly scoped x86/
				// TSF surface is Win32 for WOW64 desktop hosts on this machine.
				if strings.HasPrefix(strings.ToLower(filepath.ToSlash(relative)), "x86/") {
					expected = "i386"
				} else {
					expected = "amd64"
				}
			}
			if expected != "" && peItem.Machine != expected {
				report.PEArchitecturePassed = false
				report.fail("PE architecture mismatch for %s: got %s, want %s", relative, peItem.Machine, expected)
			}
			for _, library := range peItem.Libraries {
				if containsForbiddenToken(library) {
					report.ForbiddenPEImportsAbsent = false
					report.fail("forbidden PE import in %s: %s", relative, library)
				}
			}
			report.PEFiles = append(report.PEFiles, peItem)
		}
	}
	for _, required := range required {
		if _, found := entries[strings.ToLower(required)]; !found {
			report.RequiredComponentsPassed = false
			report.fail("required independent component missing: %s", required)
		}
	}
	if manifest.PackageContract == localRuntimeContract || manifest.PackageContract == localInstallableContract {
		if err := validateLocalContract(absoluteRoot, entries, manifest.PackageContract); err != nil {
			report.RequiredComponentsPassed = false
			report.fail("local runtime contract: %v", err)
		}
	}
	if walkErr := filepath.WalkDir(absoluteRoot, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("indirect package entry: %s", path)
		}
		if entry.IsDir() {
			return nil
		}
		relative, err := filepath.Rel(absoluteRoot, path)
		if err != nil {
			return err
		}
		relative = filepath.ToSlash(relative)
		if strings.EqualFold(relative, "package-manifest.json") {
			return nil
		}
		if strings.EqualFold(relative, "install-metadata.json") {
			if err := validateInstallMetadata(path, absoluteRoot, report.ManifestSHA256, manifest.GitCommit); err != nil {
				report.InstallMetadataPassed = false
				report.fail("invalid install metadata: %v", err)
			}
			return nil
		}
		if _, found := entries[strings.ToLower(relative)]; !found {
			report.ManifestIntegrityPassed = false
			report.fail("unlisted package file: %s", relative)
		}
		return nil
	}); walkErr != nil {
		report.ManifestIntegrityPassed = false
		report.fail("enumerate package files: %v", walkErr)
	}
	sort.Slice(report.PEFiles, func(i, j int) bool { return report.PEFiles[i].Path < report.PEFiles[j].Path })
	report.Passed = report.ManifestIntegrityPassed && report.InstallMetadataPassed && report.RequiredComponentsPassed &&
		report.PEArchitecturePassed && report.ForbiddenArtifactsAbsent && report.ForbiddenPEImportsAbsent
	if !report.Passed {
		return report, errors.New("YimeCore independence audit failed")
	}
	return report, nil
}

func validateInstallMetadata(path, packageRoot, manifestSHA256, gitCommit string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var metadata installMetadata
	if err := json.Unmarshal(bytes.TrimPrefix(data, []byte{0xef, 0xbb, 0xbf}), &metadata); err != nil {
		return err
	}
	if metadata.SchemaVersion != "yimecore-trial-install-v1" || metadata.ProductKey != "YimeCoreExperimentalTrial" {
		return errors.New("schema version or product key is incorrect")
	}
	metadataRoot, err := filepath.Abs(metadata.InstallRoot)
	if err != nil || !strings.EqualFold(filepath.Clean(metadataRoot), filepath.Clean(packageRoot)) {
		return errors.New("install root does not match the audited package")
	}
	if !strings.EqualFold(metadata.PackageManifestSHA256, manifestSHA256) {
		return errors.New("package manifest hash does not match")
	}
	if metadata.GitCommit != gitCommit {
		return errors.New("git commit does not match the package manifest")
	}
	return nil
}

func (r *auditReport) fail(format string, values ...any) {
	r.Failures = append(r.Failures, fmt.Sprintf(format, values...))
}

func safeManifestPath(path string) (string, error) {
	if path == "" || filepath.IsAbs(path) || strings.HasPrefix(path, "/") || strings.HasPrefix(path, `\`) {
		return "", errors.New("path must be non-empty and relative")
	}
	cleaned := filepath.ToSlash(filepath.Clean(filepath.FromSlash(path)))
	if cleaned == "." || cleaned == ".." || strings.HasPrefix(cleaned, "../") || strings.Contains(cleaned, ":") {
		return "", errors.New("path escapes package root")
	}
	for _, part := range strings.Split(strings.ReplaceAll(path, `\`, "/"), "/") {
		if part == "" || part == "." || part == ".." || strings.TrimRight(part, ". ") != part {
			return "", errors.New("path is not canonical")
		}
	}
	return cleaned, nil
}

func rejectIndirectPath(root, relative string) error {
	path := root
	for _, part := range strings.Split(filepath.ToSlash(relative), "/") {
		path = filepath.Join(path, part)
		info, err := os.Lstat(path)
		if err != nil {
			return err
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return errors.New("symlinks and junctions are not package payloads")
		}
	}
	return nil
}

func containsForbiddenToken(value string) bool {
	lower := strings.ToLower(filepath.ToSlash(value))
	base := filepath.Base(filepath.FromSlash(lower))
	if base == "rime.dll" || base == "rime.exe" {
		return true
	}
	for _, prefix := range forbiddenDependencyPrefixes {
		if strings.HasPrefix(base, prefix) {
			return true
		}
	}
	for _, part := range strings.Split(lower, "/") {
		if part == "rime" || part == "pime" || part == "weasel" {
			return true
		}
	}
	return false
}

func hashFile(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func inspectPE(path, relative string) (peEvidence, error) {
	file, err := pe.Open(path)
	if err != nil {
		return peEvidence{}, err
	}
	defer file.Close()
	libraries, err := importedLibraries(file)
	if err != nil {
		return peEvidence{}, err
	}
	for index := range libraries {
		libraries[index] = strings.ToLower(libraries[index])
	}
	sort.Strings(libraries)
	return peEvidence{Path: filepath.ToSlash(relative), Machine: machineName(file.Machine), Libraries: libraries}, nil
}

func importedLibraries(file *pe.File) ([]string, error) {
	var directory pe.DataDirectory
	switch header := file.OptionalHeader.(type) {
	case *pe.OptionalHeader32:
		if header.NumberOfRvaAndSizes <= pe.IMAGE_DIRECTORY_ENTRY_IMPORT {
			return nil, nil
		}
		directory = header.DataDirectory[pe.IMAGE_DIRECTORY_ENTRY_IMPORT]
	case *pe.OptionalHeader64:
		if header.NumberOfRvaAndSizes <= pe.IMAGE_DIRECTORY_ENTRY_IMPORT {
			return nil, nil
		}
		directory = header.DataDirectory[pe.IMAGE_DIRECTORY_ENTRY_IMPORT]
	default:
		return nil, errors.New("PE optional header is missing or unsupported")
	}
	if directory.VirtualAddress == 0 || directory.Size == 0 {
		return nil, nil
	}
	data, offset, err := dataAtRVA(file, directory.VirtualAddress)
	if err != nil {
		return nil, err
	}
	data = data[offset:]
	libraries := make([]string, 0, 8)
	for len(data) >= 20 {
		originalThunk := binary.LittleEndian.Uint32(data[0:4])
		timestamp := binary.LittleEndian.Uint32(data[4:8])
		forwarder := binary.LittleEndian.Uint32(data[8:12])
		nameRVA := binary.LittleEndian.Uint32(data[12:16])
		firstThunk := binary.LittleEndian.Uint32(data[16:20])
		data = data[20:]
		if originalThunk == 0 && timestamp == 0 && forwarder == 0 && nameRVA == 0 && firstThunk == 0 {
			break
		}
		if nameRVA == 0 {
			return nil, errors.New("PE import descriptor has no library name")
		}
		name, err := stringAtRVA(file, nameRVA)
		if err != nil {
			return nil, err
		}
		libraries = append(libraries, name)
	}
	return libraries, nil
}

func stringAtRVA(file *pe.File, rva uint32) (string, error) {
	data, offset, err := dataAtRVA(file, rva)
	if err != nil {
		return "", err
	}
	data = data[offset:]
	for index, value := range data {
		if value == 0 {
			if index == 0 {
				return "", errors.New("PE import library name is empty")
			}
			return string(data[:index]), nil
		}
	}
	return "", errors.New("PE import library name is not terminated")
}

func dataAtRVA(file *pe.File, rva uint32) ([]byte, int, error) {
	for _, section := range file.Sections {
		if section.Offset == 0 || rva < section.VirtualAddress {
			continue
		}
		data, err := section.Data()
		if err != nil {
			return nil, 0, err
		}
		offset := uint64(rva - section.VirtualAddress)
		if offset < uint64(len(data)) {
			return data, int(offset), nil
		}
	}
	return nil, 0, fmt.Errorf("PE RVA 0x%x is outside file sections", rva)
}

func expectedMachine(relative string) string {
	lower := strings.ToLower(filepath.ToSlash(relative))
	switch {
	case strings.HasPrefix(lower, "x64/"):
		return "amd64"
	case strings.HasPrefix(lower, "x86/"):
		return "i386"
	case strings.HasPrefix(lower, "arm64/"):
		return "arm64"
	default:
		return ""
	}
}

func machineName(machine uint16) string {
	switch machine {
	case pe.IMAGE_FILE_MACHINE_AMD64:
		return "amd64"
	case pe.IMAGE_FILE_MACHINE_I386:
		return "i386"
	case pe.IMAGE_FILE_MACHINE_ARM64:
		return "arm64"
	default:
		return fmt.Sprintf("0x%04x", machine)
	}
}

func writeReport(path string, report auditReport) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	encodeErr := encoder.Encode(report)
	closeErr := file.Close()
	if encodeErr != nil {
		return encodeErr
	}
	return closeErr
}
