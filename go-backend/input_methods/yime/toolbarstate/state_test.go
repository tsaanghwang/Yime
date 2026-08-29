package toolbarstate

import (
	"path/filepath"
	"testing"
)

func TestUpdateWritesCompleteVersionedStateAndSkipsUnchangedRevision(t *testing.T) {
	path := filepath.Join(t.TempDir(), FileName)
	first, err := Update(path, "toolbar", func(state *State) bool {
		state.ASCII = true
		state.FullShape = true
		state.ASCIIPunctuation = true
		state.Traditionalization = true
		state.SchemaID = "yime_full"
		state.Vertical = true
		state.OrientationSet = true
		state.ToolbarLayoutVersion = LayoutVersion
		state.HiddenButtons = []string{"punctuation", "unicode"}
		state.ToolbarDisplay = ToolbarDisplayIcon
		state.ToolbarTransparent = true
		return true
	})
	if err != nil {
		t.Fatal(err)
	}
	if first.Version != FormatVersion || first.Revision == 0 ||
		first.UpdatedAt == "" || first.Source != "toolbar" {
		t.Fatalf("incomplete state metadata: %#v", first)
	}

	second, err := Update(path, "backend", func(state *State) bool {
		return false
	})
	if err != nil {
		t.Fatal(err)
	}
	if second.Revision != first.Revision {
		t.Fatalf("unchanged state advanced revision: %d -> %d", first.Revision, second.Revision)
	}

	got, err := Read(path)
	if err != nil {
		t.Fatal(err)
	}
	if !got.ASCII || !got.FullShape || !got.ASCIIPunctuation ||
		!got.Traditionalization || got.SchemaID != "yime_full" ||
		!got.Vertical || !got.OrientationSet || got.ToolbarLayoutVersion != LayoutVersion || len(got.HiddenButtons) != 2 ||
		got.ToolbarDisplay != ToolbarDisplayIcon || !got.ToolbarTransparent {
		t.Fatalf("state file is incomplete: %#v", got)
	}
}

func TestNormalizeExperimentDefaultsAndPreservesValidSelections(t *testing.T) {
	state := State{}
	if !NormalizeExperiment(&state) {
		t.Fatal("empty experiment state did not receive defaults")
	}
	if state.ExperimentMode != ExperimentModeVariable || state.CandidateFontPreset != CandidateFontMedium ||
		state.CandidateFontFamily != CandidateFontMicrosoftYaHeiUI ||
		state.CandidateAnnotation != AnnotationKeySequence {
		t.Fatalf("experiment defaults = %#v", state)
	}
	if NormalizeExperiment(&state) {
		t.Fatal("valid experiment state was rewritten")
	}
	state.ExperimentMode = ExperimentModeShorthand
	state.CandidateFontPreset = CandidateFontLarge
	state.CandidateFontFamily = CandidateFontYinyuan
	state.CandidateAnnotation = AnnotationYinyuan
	if NormalizeExperiment(&state) {
		t.Fatal("explicit Yinyuan font and annotation selections were rewritten")
	}
}
