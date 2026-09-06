package speechruntime

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
)

type manifestFixture struct {
	root      string
	manifest  Manifest
	admission AdmissionReceipt
	forward   ForwardReceipt
}

func fixtureDigest(data []byte) string {
	digest := sha256.Sum256(data)
	return hex.EncodeToString(digest[:])
}

func writeManifestFixtureFile(t *testing.T, root, name string, data []byte) FileRef {
	t.Helper()
	path := filepath.Join(root, filepath.FromSlash(name))
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	return FileRef{Path: name, SHA256: fixtureDigest(data)}
}

func writeManifestFixtureJSON(t *testing.T, root, name string, value any) FileRef {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return writeManifestFixtureFile(t, root, name, data)
}

// The receipts and payload bytes below are synthetic parser fixtures, not
// claims that arbitrary records have received linguistic admission.
func newManifestFixture(t *testing.T) *manifestFixture {
	t.Helper()
	f := &manifestFixture{root: filepath.Join(t.TempDir(), "speech-admission-synthetic")}
	if err := os.Mkdir(f.root, 0o700); err != nil {
		t.Fatal(err)
	}
	f.forward = ForwardReceipt{
		SchemaVersion: "yimecore-speech-forward-source-v1", Passed: true, RecordCount: 24, SyllableCount: 50,
		Checks:      map[string]bool{"canonical_phrase_source": true, "canonical_inventory_membership": true, "formal_four_id_decomposition": true, "canonical_layout_projection": true, "semantic_tone_substitutions": true, "inputs_unchanged": true},
		InputSHA256: make(map[string]string),
	}
	for role, path := range expectedForwardInputs {
		digest := fixtureDigest([]byte("synthetic formal source " + role))
		f.forward.InputSHA256[path] = digest
		f.forward.Inputs = append(f.forward.Inputs, struct {
			Role   string `json:"role"`
			Path   string `json:"path"`
			SHA256 string `json:"sha256"`
		}{Role: role, Path: path, SHA256: digest})
	}
	for i := 1; i <= 24; i++ {
		f.forward.RecordIDs = append(f.forward.RecordIDs, fmt.Sprintf("T3-5B-%03d", i))
	}
	f.manifest = Manifest{
		SchemaVersion: Schema, Enabled: true, ApprovedRecords: 24,
		Generation: yimebroker.BundleGenerationSpec{Version: "synthetic-generation-1", Modes: make(map[string]yimebroker.BundleModeSpec)},
	}
	f.admission = AdmissionReceipt{
		SchemaVersion: "yimecore-speech-admission-receipt-v1", Passed: true, RecordCount: 24,
		Records: writeManifestFixtureFile(t, f.root, "evidence/records.json", []byte("synthetic admitted-record payload")),
		Checks:  map[string]bool{"forward_source": true, "four_positions": true, "nonlengthening": true, "canonical_membership": true, "canonical_weights_consistent": true},
		Modes:   make(map[string]AdmissionMode),
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		core := writeManifestFixtureFile(t, f.root, "indexes/"+mode+"-core.yidx", []byte("synthetic core "+mode))
		module := writeManifestFixtureFile(t, f.root, "indexes/"+mode+"-module.yidx", []byte("synthetic module "+mode))
		indexSpec := func(ref FileRef) yimebroker.IndexSpec {
			return yimebroker.IndexSpec{Version: f.manifest.Generation.Version, Mode: mode, Path: ref.Path, ExpectedSHA256: ref.SHA256}
		}
		f.manifest.Generation.Modes[mode] = yimebroker.BundleModeSpec{Core: indexSpec(core), Modules: []yimebroker.BundleModuleSpec{{ID: ModuleID, Index: indexSpec(module)}}}
		f.admission.Modes[mode] = AdmissionMode{CoreSHA256: core.SHA256, ModuleSHA256: module.SHA256, CanonicalCount: 24, AliasCount: 24}
	}
	f.writeForward(t)
	f.writeAdmission(t)
	return f
}

func (f *manifestFixture) writeForward(t *testing.T) {
	t.Helper()
	f.manifest.ForwardSource = writeManifestFixtureJSON(t, f.root, "evidence/forward.json", f.forward)
	f.admission.ForwardSHA256 = f.manifest.ForwardSource.SHA256
}

func (f *manifestFixture) writeAdmission(t *testing.T) {
	t.Helper()
	f.manifest.Admission = writeManifestFixtureJSON(t, f.root, "evidence/admission.json", f.admission)
}

func (f *manifestFixture) load(t *testing.T) (Manifest, error) {
	t.Helper()
	ref := writeManifestFixtureJSON(t, f.root, "manifest.json", f.manifest)
	return Load(f.root, ref.Path, ref.SHA256)
}

func TestSpeechManifestLoadsPinnedThreeModesAndDisablesWithoutMutation(t *testing.T) {
	f := newManifestFixture(t)
	loaded, err := f.load(t)
	if err != nil {
		t.Fatal(err)
	}
	for mode, item := range loaded.Generation.Modes {
		if !filepath.IsAbs(item.Core.Path) || !filepath.IsAbs(item.Modules[0].Index.Path) || item.Core.Mode != mode {
			t.Fatal("manifest did not resolve the complete, explicit three-mode generation")
		}
	}
	original, err := json.Marshal(loaded.Generation)
	if err != nil {
		t.Fatal(err)
	}
	enabled := loaded.EffectiveGeneration()
	enabled.Modes["full"].Modules[0].ID = "changed-copy"
	delete(enabled.Modes, "variable")
	if loaded.Generation.Modes["full"].Modules[0].ID != ModuleID || len(loaded.Generation.Modes) != 3 {
		t.Fatal("effective generation retained caller-mutable maps or module slices")
	}
	loaded.Enabled = false
	disabled := loaded.EffectiveGeneration()
	for _, mode := range []string{"full", "variable", "shorthand"} {
		if len(disabled.Modes[mode].Modules) != 0 || disabled.Modes[mode].Core != loaded.Generation.Modes[mode].Core {
			t.Fatal("disable changed core identity or retained a module")
		}
	}
	after, err := json.Marshal(loaded.Generation)
	if err != nil || !reflect.DeepEqual(original, after) {
		t.Fatal("module disable mutated the manifest generation")
	}
	f.manifest.Enabled = false
	if _, err := f.load(t); err != nil {
		t.Fatal("valid disabled manifest rejected", err)
	}
}

func TestSpeechManifestRejectsUnboundOrFailedAdmission(t *testing.T) {
	tests := map[string]func(*manifestFixture){
		"failed":            func(f *manifestFixture) { f.admission.Passed = false },
		"wrong-schema":      func(f *manifestFixture) { f.admission.SchemaVersion = "unknown" },
		"wrong-count":       func(f *manifestFixture) { f.admission.RecordCount = 25 },
		"forward-hash":      func(f *manifestFixture) { f.admission.ForwardSHA256 = strings.Repeat("0", 64) },
		"records-hash":      func(f *manifestFixture) { f.admission.Records.SHA256 = strings.Repeat("0", 64) },
		"records-traversal": func(f *manifestFixture) { f.admission.Records.Path = "../records.json" },
		"missing-mode":      func(f *manifestFixture) { delete(f.admission.Modes, "shorthand") },
		"unknown-mode": func(f *manifestFixture) {
			f.admission.Modes["bogus"] = f.admission.Modes["shorthand"]
			delete(f.admission.Modes, "shorthand")
		},
		"mixed-mode-core": func(f *manifestFixture) {
			m := f.admission.Modes["shorthand"]
			m.CoreSHA256 = f.admission.Modes["full"].CoreSHA256
			f.admission.Modes["shorthand"] = m
		},
		"mixed-mode-module": func(f *manifestFixture) {
			m := f.admission.Modes["variable"]
			m.ModuleSHA256 = f.admission.Modes["full"].ModuleSHA256
			f.admission.Modes["variable"] = m
		},
		"canonical-count": func(f *manifestFixture) {
			m := f.admission.Modes["full"]
			m.CanonicalCount = 23
			f.admission.Modes["full"] = m
		},
		"alias-count": func(f *manifestFixture) {
			m := f.admission.Modes["full"]
			m.AliasCount = 23
			f.admission.Modes["full"] = m
		},
	}
	for _, gate := range []string{"forward_source", "four_positions", "nonlengthening", "canonical_membership", "canonical_weights_consistent"} {
		gate := gate
		tests["missing-gate-"+gate] = func(f *manifestFixture) { delete(f.admission.Checks, gate) }
	}
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			f := newManifestFixture(t)
			mutate(f)
			f.writeAdmission(t)
			if _, err := f.load(t); err == nil {
				t.Fatal("invalid admission receipt accepted")
			}
		})
	}
}

func TestSpeechManifestRejectsIncompleteOrMixedGeneration(t *testing.T) {
	tests := map[string]func(*Manifest){
		"schema":       func(m *Manifest) { m.SchemaVersion = "unknown" },
		"record-count": func(m *Manifest) { m.ApprovedRecords = 72 },
		"missing-mode": func(m *Manifest) { delete(m.Generation.Modes, "shorthand") },
		"unknown-mode": func(m *Manifest) {
			m.Generation.Modes["bogus"] = m.Generation.Modes["shorthand"]
			delete(m.Generation.Modes, "shorthand")
		},
		"wrong-core-mode": func(m *Manifest) {
			item := m.Generation.Modes["full"]
			item.Core.Mode = "shorthand"
			m.Generation.Modes["full"] = item
		},
		"partial-module": func(m *Manifest) {
			item := m.Generation.Modes["full"]
			item.Modules = nil
			m.Generation.Modes["full"] = item
		},
		"unknown-module": func(m *Manifest) { m.Generation.Modes["full"].Modules[0].ID = "research-only" },
		"duplicate-module": func(m *Manifest) {
			item := m.Generation.Modes["full"]
			item.Modules = append(item.Modules, item.Modules[0])
			m.Generation.Modes["full"] = item
		},
		"module-mode":    func(m *Manifest) { m.Generation.Modes["full"].Modules[0].Index.Mode = "variable" },
		"module-version": func(m *Manifest) { m.Generation.Modes["full"].Modules[0].Index.Version = "another-generation" },
		"core-version": func(m *Manifest) {
			item := m.Generation.Modes["full"]
			item.Core.Version = "another-generation"
			m.Generation.Modes["full"] = item
		},
		"core-hash": func(m *Manifest) {
			item := m.Generation.Modes["full"]
			item.Core.ExpectedSHA256 = strings.Repeat("0", 64)
			m.Generation.Modes["full"] = item
		},
		"module-hash": func(m *Manifest) {
			m.Generation.Modes["full"].Modules[0].Index.ExpectedSHA256 = strings.Repeat("0", 64)
		},
		"core-path-traversal": func(m *Manifest) {
			item := m.Generation.Modes["full"]
			item.Core.Path = "../core.yidx"
			m.Generation.Modes["full"] = item
		},
		"module-path-traversal": func(m *Manifest) { m.Generation.Modes["full"].Modules[0].Index.Path = "../alias.yidx" },
		"admission-ref-hash":    func(m *Manifest) { m.Admission.SHA256 = strings.Repeat("0", 64) },
		"forward-ref-hash":      func(m *Manifest) { m.ForwardSource.SHA256 = strings.Repeat("0", 64) },
	}
	for name, mutate := range tests {
		for _, enabled := range []bool{true, false} {
			t.Run(fmt.Sprintf("%s/enabled-%v", name, enabled), func(t *testing.T) {
				f := newManifestFixture(t)
				f.manifest.Enabled = enabled
				mutate(&f.manifest)
				if _, err := f.load(t); err == nil {
					t.Fatal("invalid manifest generation accepted")
				}
			})
		}
	}
}

func TestSpeechManifestForwardReceiptRejectsIncompleteScope(t *testing.T) {
	tests := map[string]func(*ForwardReceipt){
		"schema":               func(f *ForwardReceipt) { f.SchemaVersion = "unknown" },
		"failed":               func(f *ForwardReceipt) { f.Passed = false },
		"count":                func(f *ForwardReceipt) { f.RecordCount = 23 },
		"syllables":            func(f *ForwardReceipt) { f.SyllableCount = 49 },
		"missing-record":       func(f *ForwardReceipt) { f.RecordIDs = f.RecordIDs[:23] },
		"duplicate-record":     func(f *ForwardReceipt) { f.RecordIDs[1] = f.RecordIDs[0] },
		"unknown-record":       func(f *ForwardReceipt) { f.RecordIDs[0] = "unreviewed" },
		"rime-executed":        func(f *ForwardReceipt) { f.Checks["rime_executed"] = true },
		"aliases-generated":    func(f *ForwardReceipt) { f.Checks["aliases_generated"] = true },
		"missing-input-hashes": func(f *ForwardReceipt) { f.InputSHA256 = nil },
	}
	for _, gate := range []string{"canonical_phrase_source", "canonical_inventory_membership", "formal_four_id_decomposition", "canonical_layout_projection", "semantic_tone_substitutions", "inputs_unchanged"} {
		gate := gate
		tests["missing-gate-"+gate] = func(f *ForwardReceipt) { delete(f.Checks, gate) }
	}
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			f := newManifestFixture(t)
			mutate(&f.forward)
			f.writeForward(t)
			f.writeAdmission(t)
			if _, err := f.load(t); err == nil {
				t.Fatal("invalid forward-source receipt accepted")
			}
		})
	}
}

func TestSpeechForwardRequiresCompleteFixedInputClosure(t *testing.T) {
	if len(expectedForwardInputs) != 56 {
		t.Fatal("v1 forward-source closure must contain exactly 56 fixed inputs")
	}
	removeRole := func(f *ForwardReceipt, role string) {
		delete(f.InputSHA256, expectedForwardInputs[role])
		for index, input := range f.Inputs {
			if input.Role == role {
				f.Inputs = append(f.Inputs[:index], f.Inputs[index+1:]...)
				return
			}
		}
	}
	tests := map[string]func(*ForwardReceipt){
		"layout-and-inventory-only": func(f *ForwardReceipt) {
			for role := range expectedForwardInputs {
				if role != "canonical_layout" && role != "canonical_inventory" {
					removeRole(f, role)
				}
			}
		},
		"missing-input-array": func(f *ForwardReceipt) { f.Inputs = nil },
		"missing-map-entry": func(f *ForwardReceipt) {
			delete(f.InputSHA256, expectedForwardInputs["canonical_inventory"])
		},
		"missing-array-entry":  func(f *ForwardReceipt) { f.Inputs = f.Inputs[1:] },
		"duplicate-array-role": func(f *ForwardReceipt) { f.Inputs[1] = f.Inputs[0] },
		"duplicate-array-path": func(f *ForwardReceipt) { f.Inputs[1].Path = f.Inputs[0].Path },
		"wrong-role":           func(f *ForwardReceipt) { f.Inputs[0].Role = "unreviewed-source" },
		"wrong-path":           func(f *ForwardReceipt) { f.Inputs[0].Path = "unreviewed/source.json" },
		"map-array-hash-mismatch": func(f *ForwardReceipt) {
			f.InputSHA256[f.Inputs[0].Path] = strings.Repeat("0", 64)
		},
		"map-array-path-mismatch": func(f *ForwardReceipt) {
			digest := f.InputSHA256[f.Inputs[0].Path]
			delete(f.InputSHA256, f.Inputs[0].Path)
			f.InputSHA256["unreviewed/source.json"] = digest
		},
		"extra-map-path": func(f *ForwardReceipt) {
			f.InputSHA256["unreviewed/source.json"] = strings.Repeat("a", 64)
		},
		"extra-array-entry": func(f *ForwardReceipt) { f.Inputs = append(f.Inputs, f.Inputs[0]) },
		"consistent-extra-role-path": func(f *ForwardReceipt) {
			delete(f.InputSHA256, f.Inputs[0].Path)
			f.Inputs[0].Role = "unreviewed-source"
			f.Inputs[0].Path = "unreviewed/source.json"
			f.InputSHA256[f.Inputs[0].Path] = f.Inputs[0].SHA256
		},
	}
	for _, role := range []string{"phrase_pronunciations", "canonical_layout", "formal_encoder", "semantic_musical", "formal_import_01"} {
		role := role
		tests["missing-both-"+role] = func(f *ForwardReceipt) { removeRole(f, role) }
	}
	for label, invalid := range map[string]string{
		"uppercase": strings.Repeat("A", 64),
		"nonhex":    strings.Repeat("g", 64),
		"short":     strings.Repeat("a", 63),
		"long":      strings.Repeat("a", 65),
		"empty":     "",
		"spaces":    strings.Repeat("a", 63) + " ",
	} {
		invalid := invalid
		tests["invalid-both-hashes-"+label] = func(f *ForwardReceipt) {
			f.Inputs[0].SHA256 = invalid
			f.InputSHA256[f.Inputs[0].Path] = invalid
		}
	}
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			f := newManifestFixture(t)
			mutate(&f.forward)
			ref := writeManifestFixtureJSON(t, f.root, "evidence/invalid-forward.json", f.forward)
			if _, err := ReadForward(filepath.Join(f.root, filepath.FromSlash(ref.Path))); err == nil {
				t.Fatal("incomplete, undeclared or inconsistent forward input closure accepted")
			}
		})
	}
}

func TestSpeechManifestStrictJSONAndLimits(t *testing.T) {
	for _, document := range []string{"manifest", "admission", "forward"} {
		for _, change := range []string{"unknown", "duplicate", "trailing", "oversized"} {
			t.Run(document+"/"+change, func(t *testing.T) {
				f := newManifestFixture(t)
				var value any = f.manifest
				if document == "admission" {
					value = f.admission
				} else if document == "forward" {
					value = f.forward
				}
				data, err := json.Marshal(value)
				if err != nil {
					t.Fatal(err)
				}
				switch change {
				case "unknown":
					data = append([]byte(`{"unapproved_option":true,`), data[1:]...)
				case "duplicate":
					data = append([]byte(`{"schema_version":"duplicate",`), data[1:]...)
				case "trailing":
					data = append(data, []byte(` {"second":true}`)...)
				case "oversized":
					data = append(data, []byte(strings.Repeat(" ", 128*1024))...)
				}
				if document == "manifest" {
					ref := writeManifestFixtureFile(t, f.root, "invalid.json", data)
					if _, err := Load(f.root, ref.Path, ref.SHA256); err == nil {
						t.Fatal("invalid pinned manifest accepted")
					}
					return
				}
				ref := writeManifestFixtureFile(t, f.root, "evidence/"+document+".json", data)
				if document == "admission" {
					f.manifest.Admission = ref
				} else {
					f.manifest.ForwardSource = ref
					f.admission.ForwardSHA256 = ref.SHA256
					f.writeAdmission(t)
				}
				if _, err := f.load(t); err == nil {
					t.Fatal("invalid pinned evidence accepted")
				}
			})
		}
	}
	f := newManifestFixture(t)
	ref := writeManifestFixtureJSON(t, f.root, "manifest.json", f.manifest)
	if _, err := Load(f.root, ref.Path, strings.Repeat("0", 64)); err == nil {
		t.Fatal("manifest hash mismatch accepted")
	}
	// Duplicate mode keys are not preserved by Go maps, so exercise the raw
	// decoder with equal duplicates that a normal JSON unmarshal would accept.
	var parsed map[string]any
	if err := strictJSON([]byte(`{"modes":{"full":{},"full":{}}}`), &parsed); err == nil {
		t.Fatal("duplicate mode object key accepted")
	}
}

func TestSpeechManifestRejectsOutsideAndIndirectPaths(t *testing.T) {
	f := newManifestFixture(t)
	for _, bad := range []string{"", "../outside", "a/../../outside", "/absolute", "a//b", "./a", "a/./b", "a/../b", `a\b`, "a:b", "a./b", "a /b", "a/"} {
		t.Run(fmt.Sprintf("path-%x", bad), func(t *testing.T) {
			if _, err := Child(f.root, bad); err == nil {
				t.Fatal("noncanonical or outside path accepted")
			}
		})
	}
	for _, bad := range []string{filepath.Dir(f.root), filepath.Join(filepath.Dir(f.root), "speech-admission-")} {
		if err := IsTrialRoot(bad); err == nil {
			t.Fatal("nontrial root accepted")
		}
	}
	t.Run("symlink", func(t *testing.T) {
		target := t.TempDir()
		link := filepath.Join(f.root, "indirect")
		if err := os.Symlink(target, link); err != nil {
			t.Skipf("local account cannot create an isolated symlink fixture: %v", err)
		}
		if _, err := Child(f.root, "indirect/file.json"); err == nil {
			t.Fatal("indirect trial path accepted")
		}
	})
}
