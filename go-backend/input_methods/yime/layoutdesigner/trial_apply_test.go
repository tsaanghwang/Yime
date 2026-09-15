package layoutdesigner

import (
	"os"
	"path/filepath"
	"testing"
)

func TestBuildTrialLayoutGenerationPublishesThreeVerifiedIndexes(t *testing.T) {
	sharedDir := filepath.Join("..", "data")
	stateRoot := t.TempDir()
	source, err := LoadProfile(filepath.Join(sharedDir, ProfileFileName))
	if err != nil {
		t.Fatal(err)
	}
	target := source
	target.Projection = cloneProjection(source.Projection)
	target.BasedOnDigest, _ = source.Digest()
	if err := target.Assign("M16", source.Projection["N06"]); err != nil {
		t.Fatal(err)
	}
	result, err := BuildTrialLayoutGeneration(sharedDir, stateRoot, target)
	if err != nil {
		t.Fatal(err)
	}
	if result.Plan.TargetDigest == "" || len(result.Indexes) != 3 {
		t.Fatalf("Trial generation=%#v", result)
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		spec, ok := result.Indexes[mode]
		if !ok || spec.Mode != mode || len(spec.SHA256) != 64 {
			t.Fatalf("%s index spec=%#v", mode, spec)
		}
		if info, statErr := os.Stat(spec.Path); statErr != nil || info.IsDir() || info.Size() == 0 {
			t.Fatalf("%s index unavailable: %v", mode, statErr)
		}
	}
	if _, err := os.Stat(filepath.Join(result.DataDir, ProfileFileName)); err != nil {
		t.Fatalf("Trial layout data missing: %v", err)
	}
	loaded, err := LoadTrialLayoutGeneration(stateRoot)
	if err != nil {
		t.Fatalf("published Trial generation cannot be loaded: %v", err)
	}
	if loaded.Version != result.Version || loaded.DataDir != result.DataDir || len(loaded.Indexes) != 3 {
		t.Fatalf("Trial generation round trip mismatch: got %#v want %#v", loaded, result)
	}
}
