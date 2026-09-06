// Build-only normal-product process acceptance. Never shipped in go_binaries.
// Only a pinned new build package and a fresh, OS-profile-owned fixture may run.
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
)

const normalNamespace = "yimecore-e6c-three-mode-trial-v1:installed-v1"

var hashPattern = regexp.MustCompile(`^[a-f0-9]{64}$`)
var outputPattern = regexp.MustCompile(`^speech-product-test-[a-zA-Z0-9-]{8,100}$`)

type fileRecord struct {
	Path   string `json:"path"`
	Bytes  int64  `json:"bytes"`
	SHA256 string `json:"sha256"`
}
type manifest struct {
	Contract string       `json:"package_contract"`
	Tool     string       `json:"tool_version"`
	Files    []fileRecord `json:"files"`
}
type processEvidence struct {
	PID       uint32 `json:"pid"`
	ParentPID uint32 `json:"parent_pid"`
	Image     string `json:"image"`
	Created   uint64 `json:"creation_filetime"`
	SID       string `json:"sid"`
}
type runtimeState struct {
	State       string `json:"state"`
	RuntimePID  uint32 `json:"runtime_pid"`
	BrokerPID   uint32 `json:"broker_pid"`
	InstallRoot string `json:"install_root"`
	BrokerPath  string `json:"broker_path"`
	StateRoot   string `json:"state_root"`
	Pipe        string `json:"pipe_name"`
}
type stageEvidence struct {
	Name                      string          `json:"name"`
	Passed                    bool            `json:"passed"`
	Enabled                   bool            `json:"enabled"`
	Runtime                   processEvidence `json:"runtime"`
	Broker                    processEvidence `json:"broker"`
	Pipe                      string          `json:"pipe"`
	Modes                     int             `json:"modes_passed"`
	CanonicalChecks           int             `json:"canonical_checks"`
	AliasChecks               int             `json:"alias_or_disabled_checks"`
	Generation                uint64          `json:"learning_generation"`
	RuntimeStopped            bool            `json:"runtime_stopped"`
	BrokerStopped             bool            `json:"broker_stopped"`
	RejectionExit             int             `json:"rejection_exit_code,omitempty"`
	RejectionDiagnostic       string          `json:"rejection_diagnostic,omitempty"`
	RejectionDiagnosticSHA256 string          `json:"rejection_diagnostic_sha256,omitempty"`
	StateUnchanged            bool            `json:"state_unchanged,omitempty"`
}
type report struct {
	Schema                    string          `json:"schema_version"`
	Passed                    bool            `json:"passed"`
	Failure                   string          `json:"failure,omitempty"`
	PackageSHA                string          `json:"package_manifest_sha256"`
	Source                    string          `json:"source_package"`
	PrivatePackage            string          `json:"private_package"`
	Output                    string          `json:"output_root"`
	SID                       string          `json:"initiating_sid"`
	Stages                    []stageEvidence `json:"stages"`
	SourceUnchanged           bool            `json:"source_package_unchanged"`
	CopyUnchanged             bool            `json:"private_package_unchanged"`
	Environment               string          `json:"child_environment"`
	Transport                 string          `json:"transport"`
	Recovery                  string          `json:"recovery_scope"`
	InstalledRuntimeConnected bool            `json:"installed_runtime_connected"`
	InstallOrRegisteredHost   bool            `json:"installation_or_registered_host_tested"`
	WindowsReboot             bool            `json:"windows_reboot_tested"`
	RimeExecuted              bool            `json:"rime_executed"`
	UserDataRead              bool            `json:"user_data_read"`
}

func main() {
	root := flag.String("package", "", "new .tmp/yimecore-local-product/<id>/package")
	sha := flag.String("package-sha256", "", "pinned new package manifest SHA256")
	out := flag.String("output-root", "", "new actual-profile/YimeCore Isolated Fixtures/SR4B2/speech-product-test-<id>")
	flag.Parse()
	if flag.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "unexpected positional arguments")
		os.Exit(2)
	}
	if err := exercise(*root, *sha, *out); err != nil {
		fmt.Fprintln(os.Stderr, "normal-product private acceptance failed; retain the fixture result")
		os.Exit(1)
	}
	fmt.Println("PASS: normal Runtime private seven-stage fixture; no install, registered host or reboot acceptance inferred.")
}

func readJSON(path string, limit int64, value any) error {
	if err := plainPath(path); err != nil {
		return err
	}
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, limit+1))
	if err != nil {
		return err
	}
	if int64(len(data)) > limit {
		return errors.New("fixture JSON exceeds limit")
	}
	return json.Unmarshal(data, value)
}
func writeNewJSON(path string, value any) error {
	if err := plainPath(path); err != nil {
		return err
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	_, err = f.Write(append(data, '\n'))
	return errors.Join(err, f.Close())
}
func hashFile(path string) (string, error) {
	if err := plainPath(path); err != nil {
		return "", err
	}
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err = io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
func safeChild(root, relative string) (string, error) {
	if relative == "" || filepath.IsAbs(relative) || strings.ContainsAny(relative, `\:`) {
		return "", errors.New("noncanonical package path")
	}
	for _, part := range strings.Split(relative, "/") {
		if part == "" || part == "." || part == ".." || strings.TrimRight(part, ". ") != part {
			return "", errors.New("ambiguous package path")
		}
	}
	path := filepath.Join(root, filepath.FromSlash(relative))
	return path, plainPath(path)
}
func newDirectory(path string) error {
	if err := plainPath(path); err != nil {
		return err
	}
	return os.Mkdir(path, 0700)
}
func copyNew(source, destination string) error {
	if err := plainPath(source); err != nil {
		return err
	}
	if err := plainPath(destination); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0700); err != nil {
		return err
	}
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(destination, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	_, err = io.Copy(out, in)
	return errors.Join(err, out.Close())
}
func readManifest(root, expected string) (manifest, error) {
	var m manifest
	if !hashPattern.MatchString(expected) {
		return m, errors.New("explicit lowercase manifest SHA256 required")
	}
	actual, err := hashFile(filepath.Join(root, "package-manifest.json"))
	if err != nil || actual != expected {
		return m, errors.New("package pin mismatch")
	}
	if err = readJSON(filepath.Join(root, "package-manifest.json"), 4<<20, &m); err != nil {
		return m, err
	}
	if m.Contract != "yimecore-local-product-package-v1" || m.Tool != "yimecore-local-builder-v1" || len(m.Files) < 10 || len(m.Files) > 512 {
		return m, errors.New("not a bounded normal product package")
	}
	if err = verifyFiles(root, m); err != nil {
		return m, err
	}
	return m, nil
}
func verifyFiles(root string, m manifest) error {
	expected := map[string]fileRecord{}
	for _, r := range m.Files {
		if _, err := safeChild(root, r.Path); err != nil {
			return err
		}
		key := strings.ToLower(r.Path)
		if _, ok := expected[key]; ok || key == "package-manifest.json" || key == "install-metadata.json" || !hashPattern.MatchString(r.SHA256) || r.Bytes < 0 {
			return errors.New("invalid package inventory")
		}
		expected[key] = r
	}
	for _, required := range []string{"bin/YimeCoreIndependenceAudit.exe", "bin/YimeCoreTrialRuntime.exe", "bin/YimeBroker.exe", "bin/YimeCoreRecoveryProbe.exe", "speech-capability.json", "speech/product.json", "speech/admitted-records.json"} {
		if _, ok := expected[strings.ToLower(required)]; !ok {
			return errors.New("normal speech package missing required file")
		}
	}
	count := 0
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := plainPath(path); err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		if rel == "package-manifest.json" {
			return nil
		}
		r, ok := expected[strings.ToLower(rel)]
		if !ok || r.Path != rel {
			return errors.New("unexpected or ambiguous package file")
		}
		info, err := d.Info()
		if err != nil || !info.Mode().IsRegular() || info.Size() != r.Bytes {
			return errors.New("package size/type differs")
		}
		hash, err := hashFile(path)
		if err != nil || hash != r.SHA256 {
			return errors.New("package content differs")
		}
		count++
		return nil
	})
	if err != nil {
		return err
	}
	if count != len(expected) {
		return errors.New("package inventory incomplete")
	}
	return nil
}
func copyPackage(root, destination string, m manifest) error {
	if err := newDirectory(destination); err != nil {
		return err
	}
	for _, r := range append(append([]fileRecord(nil), m.Files...), fileRecord{Path: "package-manifest.json"}) {
		src, err := safeChild(root, r.Path)
		if err != nil {
			return err
		}
		dst, err := safeChild(destination, r.Path)
		if err != nil {
			return err
		}
		if err = copyNew(src, dst); err != nil {
			return err
		}
	}
	return verifyFiles(destination, m)
}
func validateRoots(root, out, profile string) error {
	if err := plainPath(root); err != nil {
		return err
	}
	if err := plainPath(out); err != nil {
		return err
	}
	parent := filepath.Dir(root)
	lane := filepath.Dir(parent)
	if filepath.Base(root) != "package" || filepath.Base(lane) != "yimecore-local-product" || filepath.Base(filepath.Dir(lane)) != ".tmp" || filepath.Base(parent) == "" {
		return errors.New("package must be the explicit new build output")
	}
	allowed := filepath.Join(profile, "YimeCore Isolated Fixtures", "SR4B2")
	if !strings.EqualFold(filepath.Dir(out), allowed) || !outputPattern.MatchString(filepath.Base(out)) {
		return errors.New("fresh OS-profile-owned SR4B2 output required")
	}
	for _, a := range []string{root, out} {
		for _, part := range strings.Split(filepath.ToSlash(a), "/") {
			if strings.EqualFold(part, "YimeCore Experimental Trial") {
				return errors.New("installed state is outside fixture scope")
			}
		}
	}
	if _, err := os.Lstat(out); !os.IsNotExist(err) {
		return errors.New("existing output must be retained, not reused")
	}
	return nil
}
func environment(root string) ([]string, error) {
	windows, err := windowsDirectory()
	if err != nil {
		return nil, err
	}
	values := map[string]string{"SystemRoot": windows, "WINDIR": windows, "PATH": filepath.Join(windows, "System32")}
	for name, relative := range map[string]string{"APPDATA": "roaming", "LOCALAPPDATA": "local", "TEMP": "temp", "TMP": "tmp", "USERPROFILE": "profile"} {
		path := filepath.Join(root, relative)
		if err := newDirectory(path); err != nil {
			return nil, err
		}
		values[name] = path
	}
	var names []string
	for name := range values {
		names = append(names, name)
	}
	sort.Strings(names)
	result := make([]string, 0, len(names))
	for _, name := range names {
		result = append(result, name+"="+values[name])
	}
	return result, nil
}
func command(ctx context.Context, image, dir string, env []string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, image, args...)
	cmd.Dir = dir
	cmd.Env = append([]string(nil), env...)
	hideProcess(cmd)
	return cmd
}
func runTool(image, dir string, env []string, args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	cmd := command(ctx, image, dir, env, args...)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	if err := cmd.Run(); err != nil {
		return errors.New("owned packaged validation tool failed")
	}
	return nil
}
func audit(root, out, expected string, env []string) error {
	if err := runTool(filepath.Join(root, "bin", "YimeCoreIndependenceAudit.exe"), out, env, "-package", root, "-output", filepath.Join(out, "audit.json")); err != nil {
		return err
	}
	var r struct {
		Schema string `json:"schema_version"`
		Passed bool   `json:"passed"`
		SHA    string `json:"manifest_sha256"`
	}
	if err := readJSON(filepath.Join(out, "audit.json"), 4<<20, &r); err != nil {
		return err
	}
	if r.Schema != "yimecore-independence-audit-v1" || !r.Passed || r.SHA != expected {
		return errors.New("independent package audit did not converge")
	}
	return nil
}

func exercise(root, expected, out string) (resultErr error) {
	profile, sid, err := actualProfile()
	if err != nil {
		return err
	}
	root, err = filepath.Abs(root)
	if err != nil {
		return err
	}
	out, err = filepath.Abs(out)
	if err != nil {
		return err
	}
	if err = validateRoots(root, out, profile); err != nil {
		return err
	}
	m, err := readManifest(root, expected)
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(out), 0700); err != nil {
		return err
	}
	if err = newDirectory(out); err != nil {
		return err
	}
	r := report{Schema: "yimecore-speech-normal-process-v1", PackageSHA: expected, Source: root, Output: out, SID: sid,
		PrivatePackage: filepath.Join(out, "package"), Environment: "explicit Windows paths plus fresh private APPDATA/LOCALAPPDATA/TEMP/TMP/USERPROFILE; no inherited secrets or opt-ins",
		Transport: "normal Runtime/Broker; unique authenticated named pipe; server PID checked", Recovery: "offline fresh-clone probe only; runtime stop is not claimed graceful; no installed backup/restore"}
	defer func() {
		_, sourceErr := readManifest(root, expected)
		r.SourceUnchanged = sourceErr == nil
		_, copyErr := readManifest(r.PrivatePackage, expected)
		r.CopyUnchanged = copyErr == nil
		resultErr = errors.Join(resultErr, sourceErr, copyErr)
		r.Passed = resultErr == nil && len(r.Stages) == 7
		if resultErr != nil {
			r.Failure = resultErr.Error()
		}
		resultErr = errors.Join(resultErr, writeNewJSON(filepath.Join(out, "summary.json"), r))
	}()
	envRoot := filepath.Join(out, "environment")
	if err = newDirectory(envRoot); err != nil {
		return err
	}
	env, err := environment(envRoot)
	if err != nil {
		return err
	}
	pre := filepath.Join(out, "source-audit")
	if err = newDirectory(pre); err != nil {
		return err
	}
	if err = audit(root, pre, expected, env); err != nil {
		return err
	}
	if err = copyPackage(root, r.PrivatePackage, m); err != nil {
		return err
	}
	post := filepath.Join(out, "copy-audit")
	if err = newDirectory(post); err != nil {
		return err
	}
	if err = audit(r.PrivatePackage, post, expected, env); err != nil {
		return err
	}
	capability, err := speechruntime.LoadCapability(r.PrivatePackage)
	if err != nil || capability == nil {
		return errors.New("validated speech capability required")
	}
	product, err := speechruntime.OpenProduct(r.PrivatePackage, capability.Product.Path, capability.Product.SHA256)
	if err != nil {
		return err
	}
	product.Close()
	var records connectedspeech.AdmissionResult
	if err = readJSON(filepath.Join(r.PrivatePackage, "speech", "admitted-records.json"), 512<<10, &records); err != nil {
		return err
	}
	if records.ModuleID != speechruntime.ModuleID || len(records.Records) != 24 {
		return errors.New("fixed 24-record product scope required")
	}
	stateRoot := filepath.Join(out, "state")
	if err = newDirectory(stateRoot); err != nil {
		return err
	}
	for _, stage := range []struct {
		name                    string
		enabled, train, learned bool
		generation              uint64
	}{
		{"disabled-before", false, false, false, 0}, {"enabled-train", true, true, false, 6}, {"enabled-restart", true, false, true, 6},
		{"disabled-after", false, false, true, 6}, {"reenabled", true, false, true, 6},
	} {
		entry, e := normalStage(r.PrivatePackage, stateRoot, out, env, sid, records.Records, stage.name, stage.enabled, stage.train, stage.learned, stage.generation)
		r.Stages = append(r.Stages, entry)
		if e != nil {
			return fmt.Errorf("%s: %w", stage.name, e)
		}
	}
	bad := filepath.Join(out, "bad-package")
	if err = copyPackage(r.PrivatePackage, bad, m); err != nil {
		return err
	}
	before, err := stateHashes(stateRoot)
	if err != nil {
		return err
	}
	// Negative fixture only: corrupt a separate copy's capability binding. Keep
	// the sealed source/copy unchanged; do not repair or reseal this bad package.
	capability.Product.SHA256 = strings.Repeat("0", 64)
	badBytes, err := json.Marshal(capability)
	if err != nil {
		return err
	}
	if err = os.WriteFile(filepath.Join(bad, "speech-capability.json"), badBytes, 0600); err != nil {
		return err
	}
	entry := stageEvidence{Name: "invalid-generation-rejected", Enabled: true}
	stageDir := filepath.Join(out, entry.Name)
	if err = newDirectory(stageDir); err != nil {
		return err
	}
	pipe, err := newPipeName()
	if err != nil {
		return err
	}
	entry.Pipe = pipe
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	cmd := command(ctx, filepath.Join(bad, "bin", "YimeCoreTrialRuntime.exe"), stageDir, env, runtimeArguments(bad, stateRoot, pipe, false)...)
	var stderr limitedBuffer
	cmd.Stderr = &stderr
	cmd.Stdout = io.Discard
	err = cmd.Run()
	contextErr := ctx.Err()
	cancel()
	if cmd.ProcessState != nil {
		entry.RejectionExit = cmd.ProcessState.ExitCode()
	}
	// LoadCapability validates its product-file binding before OpenProduct.
	// Accept only this deliberately corrupted binding's exact pre-state error,
	// never an arbitrary startup failure, crash or timeout.
	confirmed := confirmedCapabilityHashRejection(entry.RejectionExit, contextErr, err, stderr.String())
	entry.RejectionDiagnostic = "unrecognized_startup_failure"
	if confirmed {
		entry.RejectionDiagnostic = "capability_product_hash_mismatch"
	}
	diagnosticDigest := sha256.Sum256(stderr.Bytes())
	entry.RejectionDiagnosticSHA256 = hex.EncodeToString(diagnosticDigest[:])
	after, e := stateHashes(stateRoot)
	entry.StateUnchanged = e == nil && sameRecords(before, after)
	entry.Passed = confirmed && entry.StateUnchanged
	r.Stages = append(r.Stages, entry)
	if e = writeNewJSON(filepath.Join(stageDir, "result.json"), entry); e != nil {
		return e
	}
	if !entry.Passed {
		return errors.New("bad resource did not produce confirmed pre-state rejection")
	}
	entry, e = normalStage(r.PrivatePackage, stateRoot, out, env, sid, records.Records, "valid-generation-recovered", true, false, true, 6)
	r.Stages = append(r.Stages, entry)
	return e
}

func confirmedCapabilityHashRejection(exitCode int, contextErr, processErr error, diagnostic string) bool {
	return exitCode == 1 && contextErr == nil && processErr != nil &&
		strings.TrimSpace(diagnostic) == "load speech capability: product evidence hash mismatch"
}

func newPipeName() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return `\\.\pipe\YimeBroker.SR4B2.` + hex.EncodeToString(b[:]), nil
}
func runtimeArguments(root, state, pipe string, stop bool) []string {
	a := []string{"-install-root", root, "-broker", filepath.Join(root, "bin", "YimeBroker.exe"), "-state-root", state, "-pipe", pipe, "-no-toolbar"}
	if stop {
		a = append(a, "-stop")
	}
	return a
}
func stateHashes(root string) ([]fileRecord, error) {
	var records []fileRecord
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if err = plainPath(path); err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		hash, err := hashFile(path)
		if err != nil {
			return err
		}
		records = append(records, fileRecord{filepath.ToSlash(rel), info.Size(), hash})
		return nil
	})
	sort.Slice(records, func(i, j int) bool { return records[i].Path < records[j].Path })
	return records, err
}
func sameRecords(a, b []fileRecord) bool {
	aa, _ := json.Marshal(a)
	bb, _ := json.Marshal(b)
	return bytes.Equal(aa, bb)
}
func generationClone(root, state, stage string, env []string) (uint64, error) {
	model := filepath.Join(state, "user-model", "installed-v1")
	before, err := stateHashes(model)
	if err != nil {
		return 0, err
	}
	clone := filepath.Join(stage, "model-clone")
	if err = newDirectory(clone); err != nil {
		return 0, err
	}
	for _, name := range []string{"user-model.json", "user-model.journal"} {
		src := filepath.Join(model, name)
		if _, err = os.Stat(src); os.IsNotExist(err) && name == "user-model.json" {
			continue
		} else if err != nil {
			return 0, err
		}
		if err = copyNew(src, filepath.Join(clone, name)); err != nil {
			return 0, err
		}
	}
	marker, err := os.OpenFile(filepath.Join(clone, ".yime-recovery-clone"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return 0, err
	}
	marker.Close()
	result := filepath.Join(stage, "recovery.json")
	if err = runTool(filepath.Join(root, "bin", "YimeCoreRecoveryProbe.exe"), stage, env, "-clone", clone, "-source-id", normalNamespace, "-output", result); err != nil {
		return 0, err
	}
	var recovered struct {
		Passed     bool   `json:"passed"`
		Generation uint64 `json:"generation"`
		Source     string `json:"source_id"`
	}
	if err = readJSON(result, 128<<10, &recovered); err != nil {
		return 0, err
	}
	after, err := stateHashes(model)
	if err != nil {
		return 0, err
	}
	if !recovered.Passed || recovered.Source != normalNamespace || !sameRecords(before, after) {
		return 0, errors.New("clone recovery changed origin or namespace")
	}
	return recovered.Generation, nil
}

type runningRuntime struct {
	cmd             *exec.Cmd
	done            chan error
	runtime, broker *processHandle
	pipe            string
}

func changesSetting(stage string) bool {
	return stage == "enabled-train" || stage == "disabled-after" || stage == "reenabled"
}

func normalStage(root, state, out string, env []string, sid string, records []connectedspeech.AdmissionRecord, name string, enabled, train, learned bool, want uint64) (entry stageEvidence, resultErr error) {
	entry = stageEvidence{Name: name, Enabled: enabled}
	dir := filepath.Join(out, name)
	if err := newDirectory(dir); err != nil {
		return entry, err
	}
	defer func() {
		entry.Passed = resultErr == nil
		resultErr = errors.Join(resultErr, writeNewJSON(filepath.Join(dir, "result.json"), entry))
	}()
	if changesSetting(name) {
		if err := speechruntime.SaveSettings(filepath.Join(state, "speech.json"), enabled, true); err != nil {
			return entry, err
		}
	}
	setting, err := speechruntime.LoadSettings(filepath.Join(state, "speech.json"))
	if err != nil || setting.Enabled != enabled {
		return entry, errors.New("explicit speech setting did not persist")
	}
	pipe, err := newPipeName()
	if err != nil {
		return entry, err
	}
	entry.Pipe = pipe
	run, err := startRuntime(root, state, dir, env, sid, pipe)
	if err != nil {
		return entry, err
	}
	entry.Runtime = run.runtime.evidence
	entry.Broker = run.broker.evidence
	defer func() {
		if run != nil {
			stopErr := stopRuntime(run, root, state, dir, env)
			entry.RuntimeStopped = !run.runtime.alive()
			entry.BrokerStopped = !run.broker.alive()
			run.runtime.close()
			run.broker.close()
			resultErr = errors.Join(resultErr, stopErr)
		}
	}()
	client, err := connectClient(pipe, run.broker)
	if err != nil {
		return entry, err
	}
	var normalized map[string]string
	if err = readJSON(filepath.Join(root, "data", "pinyin_normalized.json"), 4<<20, &normalized); err != nil {
		client.close()
		return entry, err
	}
	err = exerciseModes(client, records, normalized, enabled, train, learned)
	client.close()
	if err != nil {
		return entry, err
	}
	entry.Modes = 3
	entry.CanonicalChecks = 72
	entry.AliasChecks = 72
	if err = stopRuntime(run, root, state, dir, env); err != nil {
		return entry, err
	}
	entry.RuntimeStopped = !run.runtime.alive()
	entry.BrokerStopped = !run.broker.alive()
	run.runtime.close()
	run.broker.close()
	run = nil
	entry.Generation, err = generationClone(root, state, dir, env)
	if err != nil {
		return entry, err
	}
	if entry.Generation != want {
		return entry, errors.New("unexpected normal-model mutation generation")
	}
	return entry, nil
}

func startRuntime(root, state, dir string, env []string, sid, pipe string) (run *runningRuntime, resultErr error) {
	cmd := command(context.Background(), filepath.Join(root, "bin", "YimeCoreTrialRuntime.exe"), dir, env, runtimeArguments(root, state, pipe, false)...)
	log, err := os.OpenFile(filepath.Join(dir, "runtime-console.log"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return nil, err
	}
	cmd.Stdout = log
	cmd.Stderr = log
	if err = cmd.Start(); err != nil {
		log.Close()
		return nil, err
	}
	run = &runningRuntime{cmd: cmd, done: make(chan error, 1), pipe: pipe}
	go func() { run.done <- cmd.Wait(); log.Close() }()
	defer func() {
		if resultErr != nil {
			_ = cmd.Process.Kill()
			select {
			case <-run.done:
			case <-time.After(10 * time.Second):
			}
			if run.runtime != nil {
				run.runtime.close()
			}
			if run.broker != nil {
				run.broker.close()
			}
		}
	}()
	run.runtime, err = bindProcess(uint32(cmd.Process.Pid), filepath.Join(root, "bin", "YimeCoreTrialRuntime.exe"), uint32(os.Getpid()), 0, sid)
	if err != nil {
		return run, err
	}
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		if !run.runtime.alive() {
			return run, errors.New("normal Runtime exited before readiness")
		}
		var status runtimeState
		if readJSON(filepath.Join(state, "runtime-status.json"), 128<<10, &status) == nil && status.State == "running" && status.RuntimePID == uint32(cmd.Process.Pid) &&
			strings.EqualFold(status.InstallRoot, root) && strings.EqualFold(status.BrokerPath, filepath.Join(root, "bin", "YimeBroker.exe")) && strings.EqualFold(status.StateRoot, state) && status.Pipe == pipe {
			child, e := bindProcess(status.BrokerPID, filepath.Join(root, "bin", "YimeBroker.exe"), uint32(cmd.Process.Pid), run.runtime.evidence.Created, sid)
			if e == nil {
				run.broker = child
				return run, nil
			}
		}
		time.Sleep(50 * time.Millisecond)
	}
	return run, errors.New("normal Runtime child identity did not converge")
}
func stopRuntime(run *runningRuntime, root, state, dir string, env []string) error {
	if !run.runtime.alive() {
		if run.broker.alive() {
			return errors.New("private runtime stopped but owned Broker remains")
		}
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	cmd := command(ctx, filepath.Join(root, "bin", "YimeCoreTrialRuntime.exe"), dir, env, runtimeArguments(root, state, run.pipe, true)...)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	err := cmd.Run()
	if err == nil {
		select {
		case waitErr := <-run.done:
			err = waitErr
		case <-time.After(10 * time.Second):
			err = errors.New("private Runtime stop wait timed out")
		}
	}
	if err != nil {
		_ = run.cmd.Process.Kill()
		select {
		case <-run.done:
		case <-time.After(10 * time.Second):
		}
		return errors.New("private normal stop failed; only owned Runtime cleanup attempted")
	}
	if run.runtime.alive() || run.broker.alive() {
		return errors.New("owned Runtime/Broker still alive after stop")
	}
	return nil
}

type limitedBuffer struct{ bytes.Buffer }

func (b *limitedBuffer) Write(p []byte) (int, error) {
	n := len(p)
	if b.Len() < 65536 {
		keep := 65536 - b.Len()
		if len(p) > keep {
			p = p[:keep]
		}
		_, _ = b.Buffer.Write(p)
	}
	return n, nil
}
