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

func TestBundledSystemCandidateExclusionGateIsComplete(t *testing.T) {
	path := filepath.Join("data", systemCandidateExclusionsFileName)
	set, err := loadSystemCandidateExclusions(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(set) != 42 {
		t.Fatalf("system candidate exclusions=%d, want 42", len(set))
	}
	for _, text := range []string{"你啊我", "我啊他", "说啊你", "好啊亲", "是啊那", "对啊网"} {
		if _, ok := set[text]; !ok {
			t.Fatalf("system candidate exclusion gate lacks %s", text)
		}
	}
	for _, retained := range []string{"等啊等", "走啊走"} {
		if _, blocked := set[retained]; blocked {
			t.Fatalf("attested reduplicative construction must remain available: %s", retained)
		}
	}
}

func TestSystemAndUserCandidateExclusionsAreMerged(t *testing.T) {
	userRoot := t.TempDir()
	t.Setenv("APPDATA", userRoot)
	userDir := filepath.Join(userRoot, APP, "Rime")
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := userblocklist.WritePhrases(userblocklist.SourcePath(userDir), []string{"用户屏蔽"}); err != nil {
		t.Fatal(err)
	}
	systemPath := filepath.Join(t.TempDir(), systemCandidateExclusionsFileName)
	payload, err := os.ReadFile(filepath.Join("data", systemCandidateExclusionsFileName))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(systemPath, payload, 0o644); err != nil {
		t.Fatal(err)
	}
	previousResolver := resolveSystemCandidateExclusionsPath
	resolveSystemCandidateExclusionsPath = func(*IME) string { return systemPath }
	t.Cleanup(func() { resolveSystemCandidateExclusionsPath = previousResolver })
	imeBlocklistCache = blocklistCache{}
	imeSystemExclusionCache = blocklistCache{}
	set := newTestIME().blockedCandidateSet()
	for _, text := range []string{"用户屏蔽", "你啊我", "对啊网"} {
		if _, ok := set[text]; !ok {
			t.Fatalf("merged candidate exclusion set lacks %s", text)
		}
	}
}

func TestSystemCandidateGateHidesUnverifiableParticleAFragmentsInEverySchema(t *testing.T) {
	previousResolver := resolveSystemCandidateExclusionsPath
	resolveSystemCandidateExclusionsPath = func(*IME) string {
		return filepath.Join("data", systemCandidateExclusionsFileName)
	}
	t.Cleanup(func() { resolveSystemCandidateExclusionsPath = previousResolver })
	imeSystemExclusionCache = blocklistCache{}

	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	for _, schemaID := range []string{"yime_variable", "yime_full", "yime_shorthand"} {
		t.Run(schemaID, func(t *testing.T) {
			backend.schemaID = schemaID
			backend.composition = "particle-a-fragment"
			backend.candidates = []candidateItem{
				{Text: "你啊我"},
				{Text: "等啊等"},
				{Text: "对啊网"},
			}

			resp := &pime.Response{}
			ime.applyStateToResponse(resp, backend.State())
			if len(resp.CandidateList) != 1 || resp.CandidateList[0] != "等啊等" {
				t.Fatalf("unexpected candidate list %#v", resp.CandidateList)
			}
			backendIndex, ok := ime.mapCandidateSelectionIndex(0)
			if !ok || backendIndex != 1 {
				t.Fatalf("expected retained candidate to map to backend 1, got %d ok=%v", backendIndex, ok)
			}
		})
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

func TestMapCandidateSelectionIndexRejectsSelectionWhenEveryCandidateIsExcluded(t *testing.T) {
	ime := &IME{candidateBackendIndexMap: []int{}}
	if backendIndex, ok := ime.mapCandidateSelectionIndex(0); ok {
		t.Fatalf("fully excluded candidate bucket mapped to backend %d", backendIndex)
	}
}

func TestBlockedCandidatesHiddenFromResponseInEveryInputSchema(t *testing.T) {
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

	for _, schemaID := range []string{"yime_variable", "yime_full", "yime_shorthand"} {
		t.Run(schemaID, func(t *testing.T) {
			backend.schemaID = schemaID
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
		})
	}
}
