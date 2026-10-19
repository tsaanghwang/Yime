package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestProfilesRejectTyposAndUnreviewed17U(t *testing.T) {
	root, e := filepath.Abs(filepath.Join("..", "..", ".."))
	if e != nil {
		t.Fatal(e)
	}
	for _, raw := range []string{`{"numericZones":"none","unknown":1}`, `{"numericZones":"none","mainWidthU":17}`, `{"numericZones":"none"} {}`} {
		p := filepath.Join(t.TempDir(), "profile.json")
		if e := os.WriteFile(p, []byte(raw), 0600); e != nil {
			t.Fatal(e)
		}
		if _, e := load(options{Root: root, Profile: p}); e == nil {
			t.Fatalf("unsafe/mistyped profile accepted: %s", raw)
		}
	}
	if _, e := load(options{Root: root, Zones: "none", Gutters: true}); e != nil {
		t.Fatal(e)
	}
}
