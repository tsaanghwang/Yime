//go:build windows

package yime

import (
	"encoding/json"
	"os"
	"testing"
)

func TestRimeMigrationCandidateSnapshot(t *testing.T) {
	if os.Getenv("YIME_RUN_RIME_MIGRATION_PROBE") != "1" {
		t.Skip("set YIME_RUN_RIME_MIGRATION_PROBE=1 to capture candidate snapshots")
	}

	session := newRealRimeSession(t)
	cases := []struct {
		schemaID string
		input    string
	}{
		{"yime_variable", "bj"},
		{"yime_variable", "bjbj"},
		{"yime_full", "bjjjbjjj"},
		{"yime_shorthand", "bjbj"},
		{"yime_variable", `\lda1m,.]e`},
		{"yime_variable", `\lda1m,.]eguew8we;`},
		{"yime_variable", `]s8u\e4fa7J9wo`},
	}

	for _, test := range cases {
		ClearComposition(session.sessionID)
		if !SelectSchema(session.sessionID, test.schemaID) {
			t.Fatalf("could not select schema %s", test.schemaID)
		}
		typeASCII(t, session.sessionID, test.input)
		menu, ok := GetMenu(session.sessionID)
		if !ok {
			t.Fatalf("no menu for %s input %q", test.schemaID, test.input)
		}
		payload, err := json.Marshal(struct {
			Schema     string          `json:"schema"`
			Input      string          `json:"input"`
			PageSize   int             `json:"page_size"`
			Candidates []RimeCandidate `json:"candidates"`
		}{
			Schema:     test.schemaID,
			Input:      test.input,
			PageSize:   menu.PageSize,
			Candidates: menu.Candidates,
		})
		if err != nil {
			t.Fatal(err)
		}
		t.Logf("SNAPSHOT %s", payload)
	}
}
