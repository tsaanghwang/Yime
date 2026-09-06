package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSpeechExperimentRejectsBeforeStateCreation(t *testing.T) {
	root := filepath.Join(t.TempDir(), "speech-admission-rejected-1234")
	if err := os.Mkdir(root, 0700); err != nil {
		t.Fatal(err)
	}
	err := runSpeechExperiment(root, "missing.json", strings.Repeat("a", 64), "speech-isolated-fixture")
	if !errors.Is(err, errSpeechAdmissionRejected) {
		t.Fatal("pre-state rejection was not classified")
	}
	if _, err := os.Stat(filepath.Join(root, "state")); !os.IsNotExist(err) {
		t.Fatal("admission rejection opened durable state")
	}
}

func TestSpeechExperimentRequiresExplicitIsolatedFlags(t *testing.T) {
	if speechExperimentRequested(nil) || !speechExperimentRequested([]string{"speech-experiment-root"}) {
		t.Fatal("explicit empty speech flag must not fall through to default path")
	}
	flags := []string{"speech-experiment-root", "speech-experiment-manifest", "speech-experiment-sha256", "trusted-client-id"}
	check := func(names []string, root, manifest, hash, client string) error {
		return validateSpeechExperimentFlags(names, root, manifest, hash, client)
	}
	if err := check(flags, "fixture", "bundle.json", strings.Repeat("a", 64), "speech-isolated-fixture"); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"named-pipe", "index-root", "index", "mode", "index-version", "index-control-manifest", "user-model-snapshot", "user-model-journal", "annotation-data-dir", "professional-root", "professional-state", "user-lexicon-dir", "user-blocklist", "learning-config", "experiment-exit-after-request"} {
		if err := check(append(append([]string(nil), flags...), name), "fixture", "bundle.json", strings.Repeat("a", 64), "speech-isolated-fixture"); err == nil {
			t.Fatalf("mixed %s was accepted", name)
		}
	}
	for _, args := range [][4]string{{"", "bundle.json", strings.Repeat("a", 64), "speech-isolated-fixture"}, {"fixture", "", strings.Repeat("a", 64), "speech-isolated-fixture"}, {"fixture", "bundle.json", "", "speech-isolated-fixture"}, {"fixture", "bundle.json", strings.Repeat("a", 64), "arbitrary"}} {
		if check(flags, args[0], args[1], args[2], args[3]) == nil {
			t.Fatal("incomplete experiment flags accepted")
		}
	}
}
