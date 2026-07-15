package yime

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userblocklist"
	"github.com/tsaanghwang/Yime/go-backend/pime"
)

func TestFilterBlockedCandidatesRemovesBlockedText(t *testing.T) {
	blocked := map[string]struct{}{"呢": {}, "泥": {}}
	candidates := []candidateItem{
		{Text: "你"},
		{Text: "呢"},
		{Text: "泥"},
	}
	filtered, mapping := filterBlockedCandidates(candidates, blocked)
	if len(filtered) != 1 || filtered[0].Text != "你" {
		t.Fatalf("unexpected filtered %#v", filtered)
	}
	if len(mapping) != 1 || mapping[0] != 0 {
		t.Fatalf("unexpected mapping %#v", mapping)
	}
}

func TestMapCandidateSelectionIndexUsesBackendMapping(t *testing.T) {
	ime := &IME{
		candidateBackendIndexMap: []int{0, 2},
	}
	backendIndex, ok := ime.mapCandidateSelectionIndex(1)
	if !ok || backendIndex != 2 {
		t.Fatalf("expected backend index 2, got %d ok=%v", backendIndex, ok)
	}
}

func TestBlockedCandidatesHiddenFromResponse(t *testing.T) {
	userRoot := t.TempDir()
	t.Setenv("APPDATA", userRoot)
	userDir := filepath.Join(userRoot, APP, "Rime")
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := userblocklist.WritePhrases(userblocklist.SourcePath(userDir), []string{"呢"}); err != nil {
		t.Fatal(err)
	}

	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "n"
	backend.candidates = []candidateItem{{Text: "你"}, {Text: "呢"}, {Text: "泥"}}

	resp := &pime.Response{}
	ime.applyStateToResponse(resp, backend.State())
	if len(resp.CandidateList) != 2 {
		t.Fatalf("expected 2 visible candidates, got %#v", resp.CandidateList)
	}
	if resp.CandidateList[0] != "你" || resp.CandidateList[1] != "泥" {
		t.Fatalf("unexpected candidate list %#v", resp.CandidateList)
	}

	backendIndex, ok := ime.mapCandidateSelectionIndex(1)
	if !ok || backendIndex != 2 {
		t.Fatalf("expected visible index 1 to map to backend 2, got %d ok=%v", backendIndex, ok)
	}
}
