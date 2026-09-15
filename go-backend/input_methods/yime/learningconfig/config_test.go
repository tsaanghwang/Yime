package learningconfig

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLearningConfigDefaultsEnabledAndRoundTrips(t *testing.T) {
	path := filepath.Join(t.TempDir(), "learning.json")
	config, err := Load(path)
	if err != nil || !config.Enabled {
		t.Fatalf("default config=%#v err=%v", config, err)
	}
	if err := Save(path, false); err != nil {
		t.Fatal(err)
	}
	config, err = Load(path)
	if err != nil || config.Enabled {
		t.Fatalf("saved config=%#v err=%v", config, err)
	}
	if err := os.WriteFile(path, []byte(`{"schema_version":"wrong","enabled":true}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(path); err == nil {
		t.Fatal("unsupported schema was accepted")
	}
}
