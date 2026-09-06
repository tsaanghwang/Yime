//go:build windows

package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// All tests are pure source contracts or disposable filesystem fixtures.
// No executable, pipe server, Runtime, auditor or recovery process is started.
func fixturePackage(t *testing.T) (string, string, manifest) {
	t.Helper()
	root := filepath.Join(t.TempDir(), ".tmp", "yimecore-local-product", "new-build-fixture", "package")
	if err := os.MkdirAll(root, 0700); err != nil {
		t.Fatal(err)
	}
	m := manifest{Contract: "yimecore-local-product-package-v1", Tool: "yimecore-local-builder-v1"}
	for _, rel := range []string{"bin/YimeCoreIndependenceAudit.exe", "bin/YimeCoreTrialRuntime.exe", "bin/YimeBroker.exe", "bin/YimeCoreRecoveryProbe.exe", "speech-capability.json", "speech/product.json", "speech/admitted-records.json", "indexes/full.yidx", "indexes/variable.yidx", "indexes/shorthand.yidx"} {
		path := filepath.Join(root, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		data := []byte("NONEXECUTABLE SYNTHETIC FIXTURE " + rel)
		if err := os.WriteFile(path, data, 0600); err != nil {
			t.Fatal(err)
		}
		hash, err := hashFile(path)
		if err != nil {
			t.Fatal(err)
		}
		m.Files = append(m.Files, fileRecord{rel, int64(len(data)), hash})
	}
	if err := writeNewJSON(filepath.Join(root, "package-manifest.json"), m); err != nil {
		t.Fatal(err)
	}
	sha, err := hashFile(filepath.Join(root, "package-manifest.json"))
	if err != nil {
		t.Fatal(err)
	}
	return root, sha, m
}
func TestNormalProductFixtureExplicitRuntimeArguments(t *testing.T) {
	pipe, err := newPipeName()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(pipe, `\\.\pipe\YimeBroker.SR4B2.`) || len(pipe) != len(`\\.\pipe\YimeBroker.SR4B2.`)+32 {
		t.Fatal("private pipe shape")
	}
	for _, stop := range []bool{false, true} {
		args := runtimeArguments(`C:\fixture\package`, `C:\fixture\state`, pipe, stop)
		joined := strings.Join(args, " ")
		for _, want := range []string{"-install-root C:\\fixture\\package", "-broker C:\\fixture\\package\\bin\\YimeBroker.exe", "-state-root C:\\fixture\\state", "-pipe " + pipe, "-no-toolbar"} {
			if !strings.Contains(joined, want) {
				t.Fatal("explicit normal argument missing")
			}
		}
		if strings.Contains(joined, "trusted-client-id") || strings.Contains(joined, "speech-experiment") || strings.Contains(joined, "YimeCoreTrial.v1") {
			t.Fatal("fixture used experiment/default endpoint")
		}
		if strings.Contains(joined, "-stop") != stop {
			t.Fatal("stop argument mismatch")
		}
	}
}
func TestNormalProductFixturePinnedFilesAndCopy(t *testing.T) {
	root, sha, m := fixturePackage(t)
	if _, err := readManifest(root, sha); err != nil {
		t.Fatal(err)
	}
	copyRoot := filepath.Join(t.TempDir(), "package-copy")
	if err := copyPackage(root, copyRoot, m); err != nil {
		t.Fatal(err)
	}
	if _, err := readManifest(copyRoot, sha); err != nil {
		t.Fatal(err)
	}
	if err := copyPackage(root, copyRoot, m); err == nil {
		t.Fatal("existing package overwritten")
	}
	if _, err := readManifest(root, strings.Repeat("0", 64)); err == nil {
		t.Fatal("unfixed source accepted")
	}
}
func TestNormalProductFixtureIncompleteExtraAndChangedPayloadRejected(t *testing.T) {
	for _, scenario := range []string{"missing", "extra", "changed", "installed-marker", "duplicate"} {
		t.Run(scenario, func(t *testing.T) {
			root, _, m := fixturePackage(t)
			switch scenario {
			case "missing":
				if err := os.Remove(filepath.Join(root, "speech-capability.json")); err != nil {
					t.Fatal(err)
				}
			case "extra":
				if err := os.WriteFile(filepath.Join(root, "extra.txt"), []byte("fixture"), 0600); err != nil {
					t.Fatal(err)
				}
			case "changed":
				if err := os.WriteFile(filepath.Join(root, "speech-capability.json"), []byte("changed"), 0600); err != nil {
					t.Fatal(err)
				}
			case "installed-marker":
				if err := os.WriteFile(filepath.Join(root, "install-metadata.json"), []byte("fixture"), 0600); err != nil {
					t.Fatal(err)
				}
			case "duplicate":
				m.Files = append(m.Files, m.Files[0])
			}
			if err := verifyFiles(root, m); err == nil {
				t.Fatal("invalid synthetic package accepted")
			}
		})
	}
}
func TestNormalProductFixtureRejectsForeignOrExistingOutput(t *testing.T) {
	root, _, _ := fixturePackage(t)
	profile := filepath.Join(t.TempDir(), "synthetic-profile")
	good := filepath.Join(profile, "YimeCore Isolated Fixtures", "SR4B2", "speech-product-test-12345678")
	if err := validateRoots(root, good, profile); err != nil {
		t.Fatal(err)
	}
	for _, bad := range []string{filepath.Join(profile, "YimeCore Experimental Trial"), filepath.Join(profile, "YimeCore Isolated Fixtures", "SR4B2-other", "speech-product-test-12345678"), filepath.Join(profile, "YimeCore Isolated Fixtures", "SR4B2", "speech-product-test-x", "nested")} {
		if err := validateRoots(root, bad, profile); err == nil {
			t.Fatal("foreign/broad output accepted")
		}
	}
	if err := os.MkdirAll(good, 0700); err != nil {
		t.Fatal(err)
	}
	if err := validateRoots(root, good, profile); err == nil {
		t.Fatal("output reuse accepted")
	}
	if err := validateRoots(filepath.Join(profile, "installed-package"), good+"new", profile); err == nil {
		t.Fatal("non-build source accepted")
	}
}
func TestNormalProductFixturePlainPathsRejectAliases(t *testing.T) {
	root := t.TempDir()
	for _, bad := range []string{root + `\..\other`, root + `\file:ads`, root + `\file.`, root + `\NUL`, root + `\COM1.txt`, root + `\*`, `\\?\` + root, "C:\\", root + `\\double`, strings.ReplaceAll(root, `\`, "/")} {
		if err := plainPath(bad); err == nil {
			t.Fatal("ambiguous path accepted")
		}
	}
}
func TestNormalProductFixtureRelativePathsRejectEscapes(t *testing.T) {
	root := t.TempDir()
	for _, bad := range []string{"../other", "/outside", "a\\b", "file:ads", "a//b", "a/./b", "a/file.", "a/../b"} {
		if _, err := safeChild(root, bad); err == nil {
			t.Fatal("package path escaped")
		}
	}
}
func TestNormalProductFixtureEnvironmentDoesNotInheritSecretsOrOptIns(t *testing.T) {
	t.Setenv("YIME_RUN_REAL_RIME_TESTS", "1")
	t.Setenv("SYNTHETIC_SECRET", "not-a-user-secret")
	root := t.TempDir()
	env, err := environment(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(env) != 8 {
		t.Fatal("environment whitelist changed")
	}
	for _, line := range env {
		if strings.Contains(line, "YIME_") || strings.Contains(line, "SECRET") {
			t.Fatal("inherited opt-in or secret")
		}
	}
	if os.Getenv("YIME_RUN_REAL_RIME_TESTS") != "1" {
		t.Fatal("parent environment mutated")
	}
	if _, err := environment(root); err == nil {
		t.Fatal("private environment reused")
	}
}
func TestNormalProductFixtureReadOnlyModelHashingDoesNotRepair(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "user-model.journal")
	data := []byte("synthetic deliberately invalid journal tail")
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	a, err := stateHashes(root)
	if err != nil {
		t.Fatal(err)
	}
	b, err := stateHashes(root)
	if err != nil {
		t.Fatal(err)
	}
	if !sameRecords(a, b) || len(a) != 1 {
		t.Fatal("read-only inventory changed invalid journal")
	}
	actual, err := os.ReadFile(path)
	if err != nil || string(actual) != string(data) {
		t.Fatal("model reader repaired origin")
	}
}
func TestNormalProductFixtureJSONAndConsoleBounded(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "result.json")
	if err := writeNewJSON(path, map[string]bool{"synthetic": true}); err != nil {
		t.Fatal(err)
	}
	if err := writeNewJSON(path, map[string]bool{}); err == nil {
		t.Fatal("old evidence replaced")
	}
	var v any
	if err := readJSON(path, 1, &v); err == nil {
		t.Fatal("JSON read limit ignored")
	}
	var buffer limitedBuffer
	n, err := buffer.Write(make([]byte, 100000))
	if err != nil || n != 100000 || buffer.Len() != 65536 {
		t.Fatal("console bound ignored")
	}
}
func TestNormalProductFixtureOutcomeCannotClaimInstalledAcceptance(t *testing.T) {
	r := report{Schema: "yimecore-speech-normal-process-v1"}
	data, err := json.Marshal(r)
	if err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{"installed_runtime_connected", "installation_or_registered_host_tested", "windows_reboot_tested", "rime_executed", "user_data_read"} {
		if !strings.Contains(string(data), `"`+field+`":false`) {
			t.Fatal("scope false flag missing")
		}
	}
}

func TestNormalProductFixtureCanonicalAnnotationUsesHashedInventory(t *testing.T) {
	normalized := map[string]string{"jia3": "jiǎ", "yi3": "yǐ"}
	actual, err := markedCanonical("jia3 yi3", normalized)
	if err != nil || actual != "jiǎ yǐ" {
		t.Fatal("numeric canonical spelling treated as rendered annotation")
	}
	if _, err := markedCanonical("missing3", normalized); err == nil {
		t.Fatal("missing source annotation guessed")
	}
}

func TestNormalProductFixtureRestartReadsSettingWithoutRewrite(t *testing.T) {
	for _, stage := range []string{"disabled-before", "enabled-restart", "valid-generation-recovered"} {
		if changesSetting(stage) {
			t.Fatal("readback stage rewrote prior speech setting")
		}
	}
	for _, stage := range []string{"enabled-train", "disabled-after", "reenabled"} {
		if !changesSetting(stage) {
			t.Fatal("explicit toggle stage did not write setting")
		}
	}
}

func TestNormalProductFixtureCapabilityHashRejectionIsSpecific(t *testing.T) {
	expected := "load speech capability: product evidence hash mismatch\r\n"
	processErr := errors.New("synthetic exit status 1")
	for _, tc := range []struct {
		name                   string
		exit                   int
		contextErr, processErr error
		diagnostic             string
		want                   bool
	}{
		{"expected-capability-hash", 1, nil, processErr, expected, true},
		{"unknown-error", 1, nil, processErr, "load speech capability: permission denied", false},
		{"wrong-validation-stage", 1, nil, processErr, "validate speech product: product evidence hash mismatch", false},
		{"extra-diagnostic", 1, nil, processErr, expected + "another failure", false},
		{"timeout", 1, context.DeadlineExceeded, processErr, expected, false},
		{"cancelled", 1, context.Canceled, processErr, expected, false},
		{"zero-exit", 0, nil, nil, expected, false},
		{"other-exit", 42, nil, processErr, expected, false},
		{"missing-process-error", 1, nil, nil, expected, false},
		{"no-process-exit", -1, nil, processErr, expected, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := confirmedCapabilityHashRejection(tc.exit, tc.contextErr, tc.processErr, tc.diagnostic); got != tc.want {
				t.Fatal("pre-state diagnostic classifier accepted the wrong outcome")
			}
		})
	}
}
