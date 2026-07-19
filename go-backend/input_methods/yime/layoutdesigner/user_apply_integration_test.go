package layoutdesigner

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestApplyUserEndToEnd(t *testing.T) {
	sharedDir := os.Getenv("YIME_LAYOUT_E2E_SHARED")
	if sharedDir == "" {
		t.Skip("set YIME_LAYOUT_E2E_SHARED to packaged Rime data")
	}
	userDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(userDir, "yime_user_phrases.txt"), []byte("# test\n中国\tzhong1 guo2\t1000000\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	source, err := LoadProfile(filepath.Join(sharedDir, ProfileFileName))
	if err != nil {
		t.Fatal(err)
	}
	target := source
	target.Projection = cloneProjection(source.Projection)
	digest, err := source.Digest()
	if err != nil {
		t.Fatal(err)
	}
	target.BasedOnDigest = digest
	if err := target.Assign("M16", source.Projection["N06"]); err != nil {
		t.Fatal(err)
	}
	result, err := ApplyUser(sharedDir, userDir, target)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Plan.ChangedIDs) != 2 {
		t.Fatalf("expected one swapped pair, got %#v", result.Plan.ChangedIDs)
	}
	active, err := EffectiveDataDir(sharedDir, userDir)
	if err != nil || filepath.Clean(active) != filepath.Clean(userDir) {
		t.Fatalf("expected user override, got %q err=%v", active, err)
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		if info, statErr := os.Stat(filepath.Join(userDir, "build", "yime_"+mode+".schema.yaml")); statErr != nil || info.Size() == 0 {
			t.Fatalf("missing compiled %s schema: %v", mode, statErr)
		}
		userLexicon, readErr := os.ReadFile(filepath.Join(userDir, "custom_phrase_"+mode+".txt"))
		if readErr != nil || !strings.Contains(string(userLexicon), "中国\t") {
			t.Fatalf("%s user lexicon was not rebuilt: %v %q", mode, readErr, userLexicon)
		}
	}
	if _, err := os.Stat(filepath.Join(userDir, "yime_runtime_change.json")); err != nil {
		t.Fatalf("runtime notification missing: %v", err)
	}
}
