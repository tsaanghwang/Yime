package speechruntime

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

type productFixture struct {
	install, indexRoot, dataDir string
	manifest                    ProductManifest
	forward                     ForwardReceipt
	admission                   AdmissionReceipt
}

// Synthetic admission receipts exercise packaging, not linguistic approval.
func newProductFixture(t *testing.T) *productFixture {
	t.Helper()
	base := t.TempDir()
	f := &productFixture{install: filepath.Join(base, "own-product"), indexRoot: filepath.Join(base, "active-indexes"), dataDir: filepath.Join(base, "active-data")}
	old := newManifestFixture(t)
	f.forward = old.forward
	root := filepath.Join(f.install, "speech")
	layout := writeManifestFixtureFile(t, f.dataDir, "yime_yinyuan_layout.json", []byte("synthetic-layout-1"))
	layoutPath := "go-backend/input_methods/yime/data/yime_yinyuan_layout.json"
	f.forward.InputSHA256[layoutPath] = layout.SHA256
	for i := range f.forward.Inputs {
		if f.forward.Inputs[i].Path == layoutPath {
			f.forward.Inputs[i].SHA256 = layout.SHA256
		}
	}
	forward := writeManifestFixtureJSON(t, root, "forward-source.json", f.forward)
	records := writeManifestFixtureJSON(t, root, "admitted-records.json", map[string]string{"synthetic": "packaging-only"})
	f.admission = AdmissionReceipt{SchemaVersion: "yimecore-speech-admission-receipt-v1", Passed: true, RecordCount: 24, ForwardSHA256: forward.SHA256, Records: records, Checks: map[string]bool{"forward_source": true, "four_positions": true, "nonlengthening": true, "canonical_membership": true, "canonical_weights_consistent": true}, Modes: map[string]AdmissionMode{}}
	disabled := false
	f.manifest = ProductManifest{SchemaVersion: ProductSchema, ModuleID: ModuleID, ApprovedRecords: 24, DefaultEnabled: &disabled, LayoutSHA256: layout.SHA256, ForwardSource: forward, Generation: yimebroker.BundleGenerationSpec{Version: "synthetic-product-generation", Modes: map[string]yimebroker.BundleModeSpec{}}}
	if err := os.MkdirAll(filepath.Join(root, "indexes"), 0700); err != nil {
		t.Fatal(err)
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		var entries []yimecore.Entry
		for i := 0; i < 24; i++ {
			entries = append(entries, yimecore.Entry{Text: fmt.Sprintf("合成%02d", i), Code: fmt.Sprintf("ab%02d", i), Weight: 1})
		}
		coreRel, moduleRel := "indexes/"+mode+"-core.yidx", "indexes/"+mode+"-stage5c.yidx"
		core, err := yimecore.BuildIndexEntries(mode, entries, filepath.Join(root, records.Path), filepath.Join(root, filepath.FromSlash(coreRel)))
		if err != nil {
			t.Fatal(err)
		}
		for i := range entries {
			entries[i].Code = fmt.Sprintf("xy%02d", i)
		}
		module, err := yimecore.BuildIndexEntries(mode, entries, filepath.Join(root, records.Path), filepath.Join(root, filepath.FromSlash(moduleRel)))
		if err != nil {
			t.Fatal(err)
		}
		data, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(coreRel)))
		if err != nil {
			t.Fatal(err)
		}
		writeManifestFixtureFile(t, f.indexRoot, mode+".yidx", data)
		f.manifest.Generation.Modes[mode] = yimebroker.BundleModeSpec{Core: yimebroker.IndexSpec{Version: f.manifest.Generation.Version, Mode: mode, Path: coreRel, ExpectedSHA256: core.IndexSHA256}, Modules: []yimebroker.BundleModuleSpec{{ID: ModuleID, Index: yimebroker.IndexSpec{Version: f.manifest.Generation.Version, Mode: mode, Path: moduleRel, ExpectedSHA256: module.IndexSHA256}}}}
		f.admission.Modes[mode] = AdmissionMode{CoreSHA256: core.IndexSHA256, ModuleSHA256: module.IndexSHA256, CanonicalCount: 24, AliasCount: 24}
	}
	f.write(t)
	return f
}

func (f *productFixture) write(t *testing.T) string {
	t.Helper()
	root := filepath.Join(f.install, "speech")
	f.manifest.ForwardSource = writeManifestFixtureJSON(t, root, "forward-source.json", f.forward)
	f.admission.ForwardSHA256 = f.manifest.ForwardSource.SHA256
	f.manifest.Admission = writeManifestFixtureJSON(t, root, "admission.json", f.admission)
	manifest := writeManifestFixtureJSON(t, f.install, ProductManifestPath, f.manifest)
	value := false
	writeManifestFixtureJSON(t, f.install, CapabilityFilename, Capability{SchemaVersion: CapabilitySchema, Product: manifest, DefaultEnabled: &value})
	return manifest.SHA256
}

func TestSpeechProductLoadsIndependentDefaultOffAndMatchesOnlyEnabledGeneration(t *testing.T) {
	f := newProductFixture(t)
	capability, err := LoadCapability(f.install)
	if err != nil || capability == nil {
		t.Fatal(err)
	}
	p, err := OpenProduct(f.install, capability.Product.Path, capability.Product.SHA256)
	if err != nil {
		t.Fatal(err)
	}
	defer p.Close()
	if err = p.ValidateIndexes(f.indexRoot, f.dataDir); err != nil {
		t.Fatal(err)
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		core, err := yimecore.OpenResidentFileIndex(filepath.Join(f.indexRoot, mode+".yidx"))
		if err != nil {
			t.Fatal(err)
		}
		defer core.Close()
		before := core.SourceID()
		modules, err := p.Modules(mode, core)
		if err != nil || len(modules) != 1 || modules[0].Index.RecordCount() != 24 {
			t.Fatal(err)
		}
		modules[0].ID = "caller-mutated-copy"
		again, err := p.Modules(mode, core)
		if err != nil || again[0].ID != ModuleID || core.SourceID() != before {
			t.Fatal("module snapshot changed product/core identity")
		}
	}
	writeManifestFixtureFile(t, f.dataDir, "yime_yinyuan_layout.json", []byte("alternative-layout"))
	if err = p.ValidateIndexes(f.indexRoot, f.dataDir); err == nil {
		t.Fatal("mixed layout accepted for enablement")
	}
	// Product capability itself remains healthy with a different active layout;
	// only the explicit enabled-generation check rejects it.
	if reloaded, err := OpenProduct(f.install, capability.Product.Path, capability.Product.SHA256); err != nil {
		t.Fatal(err)
	} else {
		_ = reloaded.Close()
	}
	if _, err := Load(f.install, ProductManifestPath, capability.Product.SHA256); err == nil {
		t.Fatal("experiment root restriction was relaxed")
	}
}

func TestSpeechProductAdmittedRecordsReturnsVerifiedImmutableSnapshot(t *testing.T) {
	f := newProductFixture(t)
	capability, err := LoadCapability(f.install)
	if err != nil {
		t.Fatal(err)
	}
	product, err := OpenProduct(f.install, capability.Product.Path, capability.Product.SHA256)
	if err != nil {
		t.Fatal(err)
	}
	defer product.Close()
	original := product.AdmittedRecords()
	if len(original) == 0 {
		t.Fatal("missing pinned record bytes")
	}
	copyOfOriginal := string(original)
	original[0] = '!'
	if string(product.AdmittedRecords()) != copyOfOriginal {
		t.Fatal("caller mutated product annotation evidence")
	}
	path := filepath.Join(f.install, "speech", "admitted-records.json")
	if err := os.WriteFile(path, []byte("changed-after-load"), 0600); err != nil {
		t.Fatal(err)
	}
	if string(product.AdmittedRecords()) != copyOfOriginal {
		t.Fatal("product reread unverified record bytes")
	}
}

func TestSpeechProductRejectsScopeReceiptPathsAndGeneration(t *testing.T) {
	for _, kind := range []string{"default_on", "missing_default", "unknown_module", "records", "layout", "forward_closure", "receipt_count", "missing_mode", "wrong_version", "wrong_index_path", "wrong_index_hash", "wrong_mode", "extra_module"} {
		t.Run(kind, func(t *testing.T) {
			f := newProductFixture(t)
			switch kind {
			case "default_on":
				value := true
				f.manifest.DefaultEnabled = &value
			case "missing_default":
				f.manifest.DefaultEnabled = nil
			case "unknown_module":
				f.manifest.ModuleID = "unreviewed"
			case "records":
				f.manifest.ApprovedRecords = 25
			case "layout":
				f.manifest.LayoutSHA256 = strings.Repeat("0", 64)
			case "forward_closure":
				f.forward.Inputs = f.forward.Inputs[1:]
			case "receipt_count":
				f.admission.RecordCount = 23
			case "missing_mode":
				delete(f.manifest.Generation.Modes, "full")
			case "wrong_version":
				item := f.manifest.Generation.Modes["full"]
				item.Core.Version = "new-core-only"
				f.manifest.Generation.Modes["full"] = item
			case "wrong_index_path":
				item := f.manifest.Generation.Modes["full"]
				item.Modules[0].Index.Path = "../outside"
				f.manifest.Generation.Modes["full"] = item
			case "wrong_index_hash":
				item := f.manifest.Generation.Modes["full"]
				item.Core.ExpectedSHA256 = strings.Repeat("0", 64)
				f.manifest.Generation.Modes["full"] = item
			case "wrong_mode":
				item := f.manifest.Generation.Modes["full"]
				item.Core.Mode = "variable"
				f.manifest.Generation.Modes["full"] = item
			case "extra_module":
				item := f.manifest.Generation.Modes["full"]
				item.Modules = append(item.Modules, item.Modules[0])
				f.manifest.Generation.Modes["full"] = item
			}
			hash := f.write(t)
			if product, err := OpenProduct(f.install, ProductManifestPath, hash); err == nil {
				_ = product.Close()
				t.Fatal("invalid product generation accepted")
			}
		})
	}
}

func TestSpeechProductRejectsAllSixTamperedIndexBytes(t *testing.T) {
	for _, mode := range []string{"full", "variable", "shorthand"} {
		for _, suffix := range []string{"core", "stage5c"} {
			t.Run(mode+suffix, func(t *testing.T) {
				f := newProductFixture(t)
				hash := f.write(t)
				writeManifestFixtureFile(t, filepath.Join(f.install, "speech"), "indexes/"+mode+"-"+suffix+".yidx", []byte("damaged"))
				if product, err := OpenProduct(f.install, ProductManifestPath, hash); err == nil {
					_ = product.Close()
					t.Fatal("damaged index accepted")
				}
			})
		}
	}
}

func TestSpeechCapabilityAbsentVersusMalformed(t *testing.T) {
	root := t.TempDir()
	if capability, err := LoadCapability(root); err != nil || capability != nil {
		t.Fatal("legacy product requires capability")
	}
	if entries, err := os.ReadDir(root); err != nil || len(entries) != 0 {
		t.Fatal("read-only compatibility created files")
	}
	f := newProductFixture(t)
	for _, data := range []string{
		`{}`, `{"schema_version":"yimecore-speech-capability-v1","default_enabled":false,"product":{"path":"../outside","sha256":"` + strings.Repeat("0", 64) + `"}}`,
		`{"schema_version":"yimecore-speech-capability-v1","default_enabled":false,"default_enabled":true,"product":{}}`,
	} {
		writeManifestFixtureFile(t, f.install, CapabilityFilename, []byte(data))
		if _, err := LoadCapability(f.install); err == nil {
			t.Fatal("invalid capability accepted")
		}
	}
}

func TestSpeechSettingsStrictDefaultOffAtomicAndNoLearningMutation(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "speech.json")
	model := writeManifestFixtureFile(t, root, "model.json", []byte("private synthetic learning sentinel"))
	settings, err := LoadSettings(path)
	if err != nil || settings.Enabled {
		t.Fatal("missing settings not off")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("read created settings")
	}
	if err := SaveSettings(path, true, false); err == nil {
		t.Fatal("enabled missing capability")
	}
	for _, enabled := range []bool{true, false, true, false} {
		if err := SaveSettings(path, enabled, true); err != nil {
			t.Fatal(err)
		}
		loaded, err := LoadSettings(path)
		if err != nil || loaded.Enabled != enabled {
			t.Fatal("explicit setting not persisted")
		}
	}
	if hash, err := HashFile(filepath.Join(root, "model.json")); err != nil || hash != model.SHA256 {
		t.Fatal("setting mutated learning")
	}
	if matches, err := filepath.Glob(filepath.Join(root, ".speech-settings-*.tmp")); err != nil || len(matches) != 0 {
		t.Fatal("temporary settings file leaked")
	}
	for _, data := range []string{`{}`, `{"schema_version":"yimecore-speech-settings-v1"}`, `{"schema_version":"yimecore-speech-settings-v1","enabled":null}`, `{"schema_version":"yimecore-speech-settings-v1","enabled":false,"enabled":true}`, `{"schema_version":"yimecore-speech-settings-v1","enabled":true,"path":"outside"}`, `{"schema_version":"yimecore-speech-settings-v1","ENABLED":true}`, `{"schema_version":"unknown","enabled":false}`} {
		writeManifestFixtureFile(t, root, "speech.json", []byte(data))
		if _, err := LoadSettings(path); err == nil {
			t.Fatal("malformed settings accepted")
		}
		if err := SaveSettings(path, false, true); err == nil {
			t.Fatal("malformed state silently overwritten")
		}
	}
}

func TestSpeechProductManifestRejectsUnknownAndDuplicateJSON(t *testing.T) {
	f := newProductFixture(t)
	data, err := json.Marshal(f.manifest)
	if err != nil {
		t.Fatal(err)
	}
	for _, bad := range [][]byte{append([]byte(`{"unknown":1,`), data[1:]...), append([]byte(`{"module_id":"third-tone-stage5c",`), data[1:]...), append(append([]byte{}, data...), []byte(`{}`)...)} {
		ref := writeManifestFixtureFile(t, f.install, ProductManifestPath, bad)
		if p, err := OpenProduct(f.install, ProductManifestPath, ref.SHA256); err == nil {
			_ = p.Close()
			t.Fatal("ambiguous product JSON accepted")
		}
	}
}
