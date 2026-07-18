package yime

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSchemasIsolateLearnedCandidatesByLayoutProjection(t *testing.T) {
	const layoutID = "6d00e609f689"
	for _, mode := range []string{"full", "variable", "shorthand"} {
		mode := mode
		t.Run(mode, func(t *testing.T) {
			payload, err := os.ReadFile(filepath.Join("data", "yime_"+mode+".schema.yaml"))
			if err != nil {
				t.Fatal(err)
			}
			schema := string(payload)
			wantVersion := `version: "2026-07-18-layout-` + layoutID + `"`
			wantUserDict := "user_dict: yime_" + mode + "_layout_" + layoutID
			if !strings.Contains(schema, wantVersion) {
				t.Fatalf("schema does not identify current layout: want %q", wantVersion)
			}
			if !strings.Contains(schema, wantUserDict) {
				t.Fatalf("schema reuses another layout's learned candidates: want %q", wantUserDict)
			}
			stableCustomPhrase := "user_dict: custom_phrase_" + mode
			if !strings.Contains(schema, stableCustomPhrase) {
				t.Fatalf("layout isolation must keep regenerated user lexicon: want %q", stableCustomPhrase)
			}
		})
	}
}
