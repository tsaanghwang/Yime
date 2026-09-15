package yimecore

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

func TestBundleIndexAddsAuditableModuleAndRollsBackIndependently(t *testing.T) {
	core := buildTestFileIndex(t, "full", "core", "规范\tab\t100\n工作\tcd\t90\n")
	alias := buildTestFileIndex(t, "full", "alias", "规范\txy\t1\n")
	defer core.Close()
	defer alias.Close()

	bundle, err := NewBundleIndex(core, []BundleModule{{ID: "reviewed-alias", Index: alias}})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewBundleEngine(bundle, 9)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "xy")
	candidate := findBundleCandidate(state.Candidates, "规范")
	if candidate == nil || !strings.HasPrefix(candidate.SourceID, "reviewed-alias@yime-index-v1:full:") {
		t.Fatalf("alias provenance missing: %#v", candidate)
	}

	withoutAlias, err := NewBundleIndex(core, nil)
	if err != nil {
		t.Fatal(err)
	}
	rollbackEngine, err := NewBundleEngine(withoutAlias, 9)
	if err != nil {
		t.Fatal(err)
	}
	if candidate := findBundleCandidate(applyBundleCode(t, rollbackEngine, "xy").Candidates, "规范"); candidate != nil {
		t.Fatalf("disabled alias remained visible: %#v", candidate)
	}
	canonical := findBundleCandidate(applyBundleCode(t, rollbackEngine, "ab").Candidates, "规范")
	if canonical == nil || !strings.HasPrefix(canonical.SourceID, "core@yime-index-v1:full:") {
		t.Fatalf("canonical route did not survive rollback: %#v", canonical)
	}
}

func TestBundleSentenceSegmentsRetainPerModuleSource(t *testing.T) {
	core := buildTestFileIndex(t, "full", "core", "工作\tcd\t100\n")
	alias := buildTestFileIndex(t, "full", "alias", "大婶儿\txy\t1\n")
	defer core.Close()
	defer alias.Close()
	bundle, err := NewBundleIndex(core, []BundleModule{{ID: "explicit-erhua", Index: alias}})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewBundleEngine(bundle, 9)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "xycd")
	candidate := state.Sentence
	if candidate != nil && candidate.Text != "大婶儿工作" {
		candidate = nil
	}
	if candidate == nil || len(candidate.Segments) != 2 {
		t.Fatalf("mixed sentence missing: %#v", candidate)
	}
	if !strings.HasPrefix(candidate.Segments[0].SourceID, "explicit-erhua@") ||
		!strings.HasPrefix(candidate.Segments[1].SourceID, "core@") {
		t.Fatalf("segment provenance mismatch: %#v", candidate.Segments)
	}
}

func TestBundleRejectsModeMismatchAndDuplicateIDs(t *testing.T) {
	core := buildTestFileIndex(t, "full", "core", "甲\ta\t1\n")
	other := buildTestFileIndex(t, "variable", "other", "乙\tb\t1\n")
	defer core.Close()
	defer other.Close()
	if _, err := NewBundleIndex(core, []BundleModule{{ID: "x", Index: other}}); err == nil {
		t.Fatal("mode mismatch was accepted")
	}
	if _, err := NewBundleIndex(core, []BundleModule{{ID: "x", Index: core}, {ID: "x", Index: core}}); err == nil {
		t.Fatal("duplicate module ID was accepted")
	}
}

func TestBundleSupportsUserLexiconAndLearningLayers(t *testing.T) {
	core := buildTestFileIndex(t, "variable", "core", "系统\taa\t10\n")
	module := buildTestFileIndex(t, "variable", "module", "专业\tbb\t20\n")
	defer core.Close()
	defer module.Close()
	bundle, err := NewBundleIndex(core, []BundleModule{{ID: "approved-pack", Index: module}})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel("bundle-layer-test")
	if err != nil {
		t.Fatal(err)
	}
	userPath := filepath.Join(t.TempDir(), "custom_phrase_variable.txt")
	if err := os.WriteFile(userPath, []byte("用户\tcc\t30\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	engine, err := NewBundleEngineWithUserLexicon(bundle, 9, userPath, model)
	if err != nil {
		t.Fatal(err)
	}
	for code, text := range map[string]string{"aa": "系统", "bb": "专业", "cc": "用户"} {
		state := applyBundleCode(t, engine, code)
		if len(state.Candidates) != 1 || state.Candidates[0].Text != text {
			t.Fatalf("%s candidates=%#v", code, state.Candidates)
		}
	}
}

func TestBundlePagingReachesLowWeightReviewedAlias(t *testing.T) {
	var coreBody strings.Builder
	for i := 0; i < 10; i++ {
		coreBody.WriteString(string(rune('甲' + i)))
		coreBody.WriteString("\tab\t")
		coreBody.WriteString(fmt.Sprintf("%d\n", 100-i))
	}
	core := buildTestFileIndex(t, "full", "core", coreBody.String())
	alias := buildTestFileIndex(t, "full", "alias", "审\tab\t1\n")
	defer core.Close()
	defer alias.Close()
	bundle, err := NewBundleIndex(core, []BundleModule{{ID: "reviewed", Index: alias}})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewBundleEngine(bundle, 9)
	if err != nil {
		t.Fatal(err)
	}
	first := applyBundleCode(t, engine, "ab")
	if !first.HasNext || first.PageNumber != 0 || findBundleCandidate(first.Candidates, "审") != nil {
		t.Fatalf("unexpected first page: %#v", first)
	}
	second, err := engine.Apply(engineapi.Event{Operation: engineapi.PageNext})
	if err != nil {
		t.Fatal(err)
	}
	if second.State.PageNumber != 1 || !second.State.HasPrevious || findBundleCandidate(second.State.Candidates, "审") == nil {
		t.Fatalf("reviewed alias was not reachable on page 2: %#v", second.State)
	}
	previous, err := engine.Apply(engineapi.Event{Operation: engineapi.PagePrevious})
	if err != nil || previous.State.PageNumber != 0 {
		t.Fatalf("previous page failed: state=%#v err=%v", previous.State, err)
	}
	coverage, err := bundle.AuditModuleCoverage("reviewed", 9)
	if err != nil {
		t.Fatal(err)
	}
	if !coverage.Passed || coverage.IndexedRecords != 1 || coverage.ReachableRecords != 1 ||
		coverage.DirectFirstPageRecords != 0 || coverage.DirectLaterPageRecords != 1 || coverage.MaximumDirectPageNumber != 1 ||
		coverage.ExactTextRetainedAfterDisable != 0 {
		t.Fatalf("unexpected exhaustive coverage: %#v", coverage)
	}
}

func buildTestFileIndex(t *testing.T, mode, name, body string) *FileIndex {
	t.Helper()
	dir := t.TempDir()
	source := filepath.Join(dir, name+".dict.yaml")
	content := "# Rime dictionary\n---\nname: " + name + "\n...\n" + body
	if err := os.WriteFile(source, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, name+".yidx")
	if _, err := BuildIndexFile(mode, source, path); err != nil {
		t.Fatal(err)
	}
	index, err := OpenFileIndex(path)
	if err != nil {
		t.Fatal(err)
	}
	return index
}

func applyBundleCode(t *testing.T, engine *Engine, code string) engineapi.State {
	t.Helper()
	engine.Reset()
	var result engineapi.Result
	var err error
	for _, key := range code {
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			t.Fatal(err)
		}
	}
	return result.State
}

func findBundleCandidate(candidates []engineapi.Candidate, text string) *engineapi.Candidate {
	for i := range candidates {
		if candidates[i].Text == text {
			return &candidates[i]
		}
	}
	return nil
}
