package main

import (
	"bytes"
	"crypto/sha256"
	"debug/pe"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const candidatePackageSchema = "yimecore-speech-candidate-package-v1"
const candidatePackageManifest = "package-manifest.json"
const candidatePackageFiles = 69

type packageFile struct {
	Role   string `json:"role"`
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

// This is deliberately not a local-product descriptor. The two bool pointers
// distinguish an explicitly false policy from a missing/null JSON field.
type candidatePackage struct {
	SchemaVersion  string        `json:"schema_version"`
	Architecture   string        `json:"architecture"`
	Installable    *bool         `json:"installable"`
	DefaultEnabled *bool         `json:"default_enabled"`
	DefaultBundle  string        `json:"default_bundle"`
	Files          []packageFile `json:"files"`
}

var packageRuntimeFiles = map[string]string{
	"broker":              "bin/YimeBroker-speech.exe",
	"tool":                "bin/YimeSpeechAdmission.exe",
	"disabled_bundle":     "bundle-off.json",
	"enabled_test_bundle": "bundle-on.json",
	"admission":           "admission.json",
	"forward_source":      "forward-source.json",
	"admitted_records":    "admitted-records.json",
	"full_core":           "indexes/full-core.yidx",
	"full_module":         "indexes/full-stage5c.yidx",
	"variable_core":       "indexes/variable-core.yidx",
	"variable_module":     "indexes/variable-stage5c.yidx",
	"shorthand_core":      "indexes/shorthand-core.yidx",
	"shorthand_module":    "indexes/shorthand-stage5c.yidx",
}

func packageDigest(value string) bool {
	if len(value) != 64 || value != strings.ToLower(value) {
		return false
	}
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == 32
}

func packageChild(root, relative string) (string, error) {
	path, err := speechruntime.Child(root, relative)
	if err != nil {
		return "", err
	}
	if err = packagePlainPath(path); err != nil {
		return "", err
	}
	return path, nil
}

func packageRoot(root, prefix string) error {
	if !filepath.IsAbs(root) || !strings.HasPrefix(filepath.Base(filepath.Clean(root)), prefix) || len(filepath.Base(filepath.Clean(root))) <= len(prefix) {
		return errors.New("explicit absolute, uniquely named speech package/exercise root required")
	}
	return packagePlainPath(root)
}

func rootsOverlap(a, b string) bool {
	// Windows names are case insensitive; conservatively keep that policy on
	// other hosts as well, so an offline verification cannot weaken the format.
	a, b = strings.ToLower(filepath.Clean(a)), strings.ToLower(filepath.Clean(b))
	return a == b || strings.HasPrefix(a, b+string(filepath.Separator)) || strings.HasPrefix(b, a+string(filepath.Separator))
}

func packageNewRoot(root, prefix string, protected ...string) error {
	if err := packageRoot(root, prefix); err != nil {
		return err
	}
	for _, other := range protected {
		if rootsOverlap(root, other) {
			return errors.New("package input and output roots must not overlap")
		}
	}
	if _, err := os.Lstat(root); !os.IsNotExist(err) {
		return errors.New("package output root must be absent")
	}
	return nil
}

func packageRegular(path string) (fs.FileInfo, error) {
	if err := packagePlainPath(path); err != nil {
		return nil, err
	}
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, errors.New("package payload must be an ordinary file")
	}
	return info, nil
}

func describePackageFile(role, relative, source string) (packageFile, error) {
	info, err := packageRegular(source)
	if err != nil {
		return packageFile{}, err
	}
	hash, err := speechruntime.HashFile(source)
	return packageFile{Role: role, Path: relative, SHA256: hash, Size: info.Size()}, err
}

func copyPackageFile(source, root string, item packageFile) error {
	info, err := packageRegular(source)
	if err != nil || info.Size() != item.Size || !packageDigest(item.SHA256) {
		return errors.New("package source size/type/digest mismatch")
	}
	target, err := packageChild(root, item.Path)
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(target), 0700); err != nil {
		return err
	}
	if err = packagePlainPath(target); err != nil {
		return err
	}
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(target, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	hash := sha256.New()
	size, copyErr := io.Copy(io.MultiWriter(out, hash), in)
	if err = errors.Join(copyErr, out.Close()); err != nil {
		return err
	}
	if size != item.Size || hex.EncodeToString(hash.Sum(nil)) != item.SHA256 {
		return errors.New("package input changed during copy")
	}
	return nil
}

func requireAMD64Executable(path string) error {
	if _, err := packageRegular(path); err != nil {
		return err
	}
	file, err := pe.Open(path)
	if err != nil {
		return errors.New("candidate executable is not a valid Windows PE")
	}
	defer file.Close()
	if file.Machine != pe.IMAGE_FILE_MACHINE_AMD64 || file.Characteristics&pe.IMAGE_FILE_EXECUTABLE_IMAGE == 0 || file.Characteristics&pe.IMAGE_FILE_DLL != 0 {
		return errors.New("candidate package requires native Windows AMD64 executables")
	}
	header, ok := file.OptionalHeader.(*pe.OptionalHeader64)
	if !ok {
		return errors.New("candidate executable requires PE32+ header")
	}
	imports, err := packagePEImports(file, header)
	if err != nil {
		return errors.New("candidate executable import table is invalid")
	}
	for _, name := range imports {
		lower := strings.ToLower(name)
		if strings.Contains(lower, "rime") || strings.Contains(lower, "pime") {
			return errors.New("candidate executable imports another input product")
		}
	}
	return nil
}

// debug/pe.ImportedLibraries is currently a no-op, and ImportedSymbols omits
// ordinal-only imports. Read DLL names from the bounded import descriptors.
func packagePEImports(file *pe.File, header *pe.OptionalHeader64) ([]string, error) {
	if header.NumberOfRvaAndSizes > 16 {
		return nil, errors.New("unsupported PE directories")
	}
	for _, index := range []int{pe.IMAGE_DIRECTORY_ENTRY_BOUND_IMPORT, pe.IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT} {
		if header.NumberOfRvaAndSizes > uint32(index) && (header.DataDirectory[index].VirtualAddress != 0 || header.DataDirectory[index].Size != 0) {
			return nil, errors.New("unsupported indirect PE imports")
		}
	}
	if header.NumberOfRvaAndSizes <= pe.IMAGE_DIRECTORY_ENTRY_IMPORT {
		return nil, nil
	}
	directory := header.DataDirectory[pe.IMAGE_DIRECTORY_ENTRY_IMPORT]
	if directory.VirtualAddress == 0 && directory.Size == 0 {
		return nil, nil
	}
	if directory.VirtualAddress == 0 || directory.Size < 20 || directory.Size > 128*1024 {
		return nil, errors.New("invalid PE import directory")
	}
	readRVA := func(address uint32, maximum int) ([]byte, error) {
		for _, section := range file.Sections {
			if address < section.VirtualAddress {
				continue
			}
			delta := uint64(address) - uint64(section.VirtualAddress)
			if delta >= uint64(section.Size) {
				continue
			}
			count := uint64(maximum)
			if count > uint64(section.Size)-delta {
				count = uint64(section.Size) - delta
			}
			data := make([]byte, int(count))
			_, err := section.ReadAt(data, int64(delta))
			return data, err
		}
		return nil, errors.New("PE import address is not file-backed")
	}
	data, err := readRVA(directory.VirtualAddress, int(directory.Size))
	if err != nil {
		return nil, err
	}
	var imports []string
	for len(data) >= 20 {
		descriptor := data[:20]
		data = data[20:]
		if bytes.Equal(descriptor, make([]byte, 20)) {
			return imports, nil
		}
		nameRVA := binary.LittleEndian.Uint32(descriptor[12:16])
		if nameRVA == 0 {
			return nil, errors.New("missing PE imported DLL name")
		}
		name, err := readRVA(nameRVA, 261)
		if err != nil {
			return nil, err
		}
		end := bytes.IndexByte(name, 0)
		if end < 1 || end > 260 {
			return nil, errors.New("invalid PE imported DLL name")
		}
		for _, value := range name[:end] {
			if value < 33 || value > 126 {
				return nil, errors.New("non-ASCII PE imported DLL name")
			}
		}
		imports = append(imports, string(name[:end]))
	}
	return nil, errors.New("unterminated PE import directory")
}

func packageCandidate(repo, root, output, broker, expectedBroker string) error {
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	return packageCandidateWithTool(repo, root, output, broker, expectedBroker, executable)
}

// An explicit tool path is internal testability only; the CLI always packages
// its own executable, never an arbitrary tool nominated by the caller.
func packageCandidateWithTool(repo, root, output, broker, expectedBroker, tool string) error {
	if !filepath.IsAbs(repo) || !filepath.IsAbs(broker) || !filepath.IsAbs(tool) || !packageDigest(expectedBroker) {
		return errors.New("explicit source root and pinned absolute executable inputs required")
	}
	if err := packageRoot(root, "speech-admission-"); err != nil {
		return err
	}
	if err := packageNewRoot(output, "speech-admission-package-", root); err != nil {
		return err
	}
	if rootsOverlap(output, filepath.Dir(broker)) || rootsOverlap(output, filepath.Dir(tool)) {
		return errors.New("output overlaps executable input directory")
	}
	forwardPath, err := packageChild(root, "forward-source.json")
	if err != nil {
		return err
	}
	forward, err := speechruntime.ReadForward(forwardPath)
	if err != nil {
		return err
	}
	if err = verifyPackageRuntime(root); err != nil {
		return err
	}
	for _, path := range []string{broker, tool} {
		if err = requireAMD64Executable(path); err != nil {
			return err
		}
	}
	falseValue := false
	manifest := candidatePackage{SchemaVersion: candidatePackageSchema, Architecture: "windows-amd64", Installable: &falseValue, DefaultEnabled: &falseValue, DefaultBundle: "bundle-off.json"}
	sources := map[string]string{}
	for role, relative := range packageRuntimeFiles {
		source, err := packageChild(root, relative)
		if err != nil {
			return err
		}
		if role == "broker" {
			source = broker
		}
		if role == "tool" {
			source = tool
		}
		item, err := describePackageFile(role, relative, source)
		if err != nil {
			return err
		}
		if role == "broker" && item.SHA256 != expectedBroker {
			return errors.New("new Broker hash mismatch")
		}
		manifest.Files = append(manifest.Files, item)
		sources[relative] = source
	}
	for _, input := range forward.Inputs {
		source, err := packageChild(repo, input.Path)
		if err != nil {
			return err
		}
		item, err := describePackageFile("forward:"+input.Role, "sources/"+input.Path, source)
		if err != nil {
			return err
		}
		if item.SHA256 != input.SHA256 {
			return errors.New("forward source changed before packaging")
		}
		manifest.Files = append(manifest.Files, item)
		sources[item.Path] = source
	}
	sort.Slice(manifest.Files, func(i, j int) bool { return manifest.Files[i].Path < manifest.Files[j].Path })
	if err = os.Mkdir(output, 0700); err != nil {
		return err
	}
	for _, item := range manifest.Files {
		if err = copyPackageFile(sources[item.Path], output, item); err != nil {
			return err
		}
	}
	if err = writeNew(filepath.Join(output, candidatePackageManifest), manifest); err != nil {
		return err
	}
	hash, err := speechruntime.HashFile(filepath.Join(output, candidatePackageManifest))
	if err != nil {
		return err
	}
	_, err = verifyPackage(output, hash)
	return err
}

func strictPackageJSON(data []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	var walk func() error
	walk = func() error {
		token, err := decoder.Token()
		if err != nil {
			return err
		}
		if delim, ok := token.(json.Delim); ok {
			switch delim {
			case '{':
				seen := map[string]bool{}
				for decoder.More() {
					key, err := decoder.Token()
					if err != nil {
						return err
					}
					name, ok := key.(string)
					if !ok || seen[name] {
						return errors.New("duplicate package JSON key")
					}
					seen[name] = true
					if err = walk(); err != nil {
						return err
					}
				}
			case '[':
				for decoder.More() {
					if err = walk(); err != nil {
						return err
					}
				}
			default:
				return errors.New("invalid package JSON delimiter")
			}
			_, err = decoder.Token()
			return err
		}
		return nil
	}
	if err := walk(); err != nil {
		return err
	}
	if _, err := decoder.Token(); err != io.EOF {
		return errors.New("trailing package JSON")
	}
	decoder = json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	return decoder.Decode(target)
}

func readPackageManifest(root, expected string) (candidatePackage, error) {
	var manifest candidatePackage
	if !packageDigest(expected) {
		return manifest, errors.New("pinned lowercase package SHA-256 required")
	}
	path, err := packageChild(root, candidatePackageManifest)
	if err != nil {
		return manifest, err
	}
	info, err := packageRegular(path)
	if err != nil || info.Size() > 128*1024 {
		return manifest, errors.New("package manifest missing or oversized")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return manifest, err
	}
	sum := sha256.Sum256(data)
	if hex.EncodeToString(sum[:]) != expected {
		return manifest, errors.New("sealed package manifest hash mismatch")
	}
	if err = strictPackageJSON(data, &manifest); err != nil {
		return manifest, err
	}
	if manifest.SchemaVersion != candidatePackageSchema || manifest.Architecture != "windows-amd64" || manifest.Installable == nil || *manifest.Installable || manifest.DefaultEnabled == nil || *manifest.DefaultEnabled || manifest.DefaultBundle != "bundle-off.json" || len(manifest.Files) != candidatePackageFiles {
		return manifest, errors.New("unsupported or incomplete non-installable default-off package policy")
	}
	// json.Unmarshal accepts omitted numeric fields as zero; require each exact
	// file field even for intentionally empty source __init__.py files.
	var fields map[string]json.RawMessage
	if err = json.Unmarshal(data, &fields); err != nil {
		return manifest, err
	}
	if len(fields) != 6 {
		return manifest, errors.New("package top-level field set mismatch")
	}
	for _, key := range []string{"schema_version", "architecture", "installable", "default_enabled", "default_bundle", "files"} {
		if len(fields[key]) == 0 || string(fields[key]) == "null" {
			return manifest, errors.New("noncanonical package top-level field")
		}
	}
	var raw struct {
		Files []map[string]json.RawMessage `json:"files"`
	}
	if err = json.Unmarshal(data, &raw); err != nil {
		return manifest, err
	}
	for _, item := range raw.Files {
		if len(item) != 4 {
			return manifest, errors.New("incomplete package file fields")
		}
		for _, key := range []string{"role", "path", "sha256", "size"} {
			if len(item[key]) == 0 || string(item[key]) == "null" {
				return manifest, errors.New("missing package file field")
			}
		}
	}
	return manifest, nil
}

func verifyPackage(root, expected string) (candidatePackage, error) {
	var empty candidatePackage
	if err := packageRoot(root, "speech-admission-package-"); err != nil {
		return empty, err
	}
	manifest, err := readPackageManifest(root, expected)
	if err != nil {
		return empty, err
	}
	forwardPath, err := packageChild(root, "forward-source.json")
	if err != nil {
		return empty, err
	}
	forward, err := speechruntime.ReadForward(forwardPath)
	if err != nil {
		return empty, err
	}
	wanted := make(map[string]string, candidatePackageFiles)
	for role, path := range packageRuntimeFiles {
		wanted[role] = path
	}
	for _, input := range forward.Inputs {
		wanted["forward:"+input.Role] = "sources/" + input.Path
	}
	seenRoles, seenPaths := map[string]bool{}, map[string]bool{}
	directories := map[string]bool{".": true}
	for _, item := range manifest.Files {
		if wanted[item.Role] != item.Path || item.Path == "" || seenRoles[item.Role] || seenPaths[item.Path] || !packageDigest(item.SHA256) || item.Size < 0 {
			return empty, errors.New("package required role/path/digest set mismatch")
		}
		seenRoles[item.Role], seenPaths[item.Path] = true, true
		for dir := filepath.ToSlash(filepath.Dir(filepath.FromSlash(item.Path))); dir != "."; dir = filepath.ToSlash(filepath.Dir(filepath.FromSlash(dir))) {
			directories[dir] = true
		}
		path, err := packageChild(root, item.Path)
		if err != nil {
			return empty, err
		}
		actual, err := describePackageFile(item.Role, item.Path, path)
		if err != nil || actual != item {
			return empty, errors.New("package payload size/hash mismatch")
		}
		if strings.HasPrefix(item.Role, "forward:") && forward.InputSHA256[strings.TrimPrefix(item.Path, "sources/")] != item.SHA256 {
			return empty, errors.New("package source copy differs from forward receipt")
		}
	}
	seenPaths[candidatePackageManifest] = true
	if err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := packagePlainPath(path); err != nil {
			return err
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		relative = filepath.ToSlash(relative)
		if entry.IsDir() {
			if !directories[relative] {
				return errors.New("unknown directory in sealed package")
			}
			return nil
		}
		if !seenPaths[relative] {
			return errors.New("unknown file in sealed package")
		}
		return nil
	}); err != nil {
		return empty, err
	}
	for _, relative := range []string{packageRuntimeFiles["broker"], packageRuntimeFiles["tool"]} {
		if err = requireAMD64Executable(filepath.Join(root, filepath.FromSlash(relative))); err != nil {
			return empty, err
		}
	}
	if err = verifyPackageRuntime(root); err != nil {
		return empty, err
	}
	return manifest, nil
}

func verifyPackageRuntime(root string) error {
	var off speechruntime.Manifest
	for _, enabled := range []bool{false, true} {
		name := "bundle-off.json"
		if enabled {
			name = "bundle-on.json"
		}
		path, err := packageChild(root, name)
		if err != nil {
			return err
		}
		hash, err := speechruntime.HashFile(path)
		if err != nil {
			return err
		}
		bundle, err := speechruntime.Load(root, name, hash)
		if err != nil {
			return err
		}
		if bundle.Enabled != enabled || bundle.Admission.Path != "admission.json" || bundle.ForwardSource.Path != "forward-source.json" {
			return errors.New("package bundle has noncanonical policy or evidence paths")
		}
		if enabled {
			bundle.Enabled = false
			if !reflect.DeepEqual(off, bundle) {
				return errors.New("test enabled bundle changes more than module switch")
			}
		} else {
			off = bundle
		}
	}
	var receipt speechruntime.AdmissionReceipt
	data, err := os.ReadFile(filepath.Join(root, "admission.json"))
	if err != nil {
		return err
	}
	if err = strictPackageJSON(data, &receipt); err != nil {
		return err
	}
	if receipt.Records.Path != "admitted-records.json" {
		return errors.New("noncanonical record receipt path")
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		item := off.Generation.Modes[mode]
		for _, module := range []bool{false, true} {
			spec, suffix := item.Core, "-core.yidx"
			if module {
				spec, suffix = item.Modules[0].Index, "-stage5c.yidx"
			}
			path, err := packageChild(root, "indexes/"+mode+suffix)
			if err != nil {
				return err
			}
			if spec.Path != path {
				return errors.New("noncanonical package index path")
			}
			hash, err := speechruntime.HashFile(path)
			if err != nil || hash != spec.ExpectedSHA256 {
				return errors.New("package index is not receipt-bound")
			}
			index, err := yimecore.OpenFileIndex(path)
			if err != nil {
				return err
			}
			valid := index.Mode() == mode && index.RecordCount() >= 24
			if module {
				valid = valid && index.RecordCount() == 24
			}
			if err = index.Close(); err != nil {
				return err
			}
			if !valid {
				return errors.New("package index mode or admission count mismatch")
			}
		}
	}
	return nil
}

func packageChildLaunch(root string, inherited []string) (childLaunch, error) {
	launch := childLaunch{directory: root, environment: []string{}}
	// Only OS loader necessities survive. No YIME_*, RIME_*, PIME_*, smoke
	// flags, source paths, user AppData or executable search path is inherited.
	for _, item := range inherited {
		key, _, ok := strings.Cut(item, "=")
		if !ok {
			continue
		}
		switch strings.ToUpper(key) {
		case "SYSTEMROOT", "WINDIR", "COMSPEC", "PROCESSOR_ARCHITECTURE", "NUMBER_OF_PROCESSORS":
			launch.environment = append(launch.environment, item)
		}
	}
	for _, key := range []string{"APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "USERPROFILE"} {
		path, err := packageChild(root, "private-environment/"+strings.ToLower(key))
		if err != nil {
			return launch, err
		}
		if err = os.MkdirAll(path, 0700); err != nil {
			return launch, err
		}
		launch.environment = append(launch.environment, key+"="+path)
	}
	return launch, nil
}

func exercisePackage(root, expected, output string) (resultErr error) {
	manifest, err := verifyPackage(root, expected)
	if err != nil {
		return err
	}
	if err = packageNewRoot(output, "speech-admission-exercise-", root); err != nil {
		return err
	}
	if err = os.Mkdir(output, 0700); err != nil {
		return err
	}
	outcome := map[string]any{"schema_version": "yimecore-speech-package-exercise-v1", "passed": false, "package_manifest_sha256": expected, "package_unchanged": false, "payload_files": candidatePackageFiles, "forward_source_files": 56, "process_outcome": "process-outcome.json", "installable": false, "source_repository_required": false, "rime_executed": false, "registered_or_live_host_tested": false}
	defer func() {
		_, verifyErr := verifyPackage(root, expected)
		outcome["package_unchanged"] = verifyErr == nil
		outcome["passed"] = resultErr == nil && verifyErr == nil
		resultErr = errors.Join(resultErr, verifyErr, writeNew(filepath.Join(output, "package-exercise-outcome.json"), outcome))
	}()
	launch, brokerSHA, err := clonePackageRuntime(root, output, manifest, os.Environ())
	if err != nil {
		return err
	}
	if err = exerciseWithLaunch(output, filepath.Join(output, filepath.FromSlash(packageRuntimeFiles["broker"])), brokerSHA, launch); err != nil {
		return fmt.Errorf("private package exercise failed: %w", err)
	}
	return nil
}

// The caller has verified the immutable package and exclusively created output.
// The fresh clone has no copied model, journal, receipt outcomes or source code.
func clonePackageRuntime(root, output string, manifest candidatePackage, inherited []string) (childLaunch, string, error) {
	var brokerSHA string
	for _, item := range manifest.Files {
		if strings.HasPrefix(item.Role, "forward:") || item.Role == "tool" {
			continue
		}
		source, err := packageChild(root, item.Path)
		if err != nil {
			return childLaunch{}, "", err
		}
		if err = copyPackageFile(source, output, item); err != nil {
			return childLaunch{}, "", err
		}
		if item.Role == "broker" {
			brokerSHA = item.SHA256
		}
	}
	launch, err := packageChildLaunch(output, inherited)
	return launch, brokerSHA, err
}
