package speechruntime

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const CapabilitySchema = "yimecore-speech-capability-v1"
const CapabilityFilename = "speech-capability.json"
const ProductSchema = "yimecore-speech-product-v1"
const ProductManifestPath = "speech/product.json"

type Capability struct {
	SchemaVersion  string  `json:"schema_version"`
	Product        FileRef `json:"product"`
	DefaultEnabled *bool   `json:"default_enabled"`
}

type ProductManifest struct {
	SchemaVersion   string                          `json:"schema_version"`
	ModuleID        string                          `json:"module_id"`
	ApprovedRecords int                             `json:"approved_records"`
	DefaultEnabled  *bool                           `json:"default_enabled"`
	LayoutSHA256    string                          `json:"layout_sha256"`
	Admission       FileRef                         `json:"admission"`
	ForwardSource   FileRef                         `json:"forward_source"`
	Generation      yimebroker.BundleGenerationSpec `json:"generation"`
}

// Product owns only immutable speech modules. Existing Broker transport, core
// managers and user-model namespaces continue to own their normal resources.
type Product struct {
	manifest        ProductManifest
	modules         map[string]*yimecore.FileIndex
	admittedRecords []byte
}

func productChild(root, relative string) (string, error) {
	if !filepath.IsAbs(root) {
		return "", errors.New("explicit absolute product root required")
	}
	path, err := Child(root, relative)
	if err != nil {
		return "", err
	}
	if err = productPlainPath(path); err != nil {
		return "", err
	}
	return path, nil
}

func readProductFile(root, relative, expected string, limit int64) ([]byte, error) {
	if !canonicalForwardDigest(expected) {
		return nil, errors.New("product file requires pinned lowercase SHA-256")
	}
	path, err := productChild(root, relative)
	if err != nil {
		return nil, err
	}
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, errors.New("product evidence must be an ordinary file")
	}
	data, err := readLimited(path, limit)
	if err != nil {
		return nil, err
	}
	sum := sha256.Sum256(data)
	if hex.EncodeToString(sum[:]) != expected {
		return nil, errors.New("product evidence hash mismatch")
	}
	return data, nil
}

func exactProductFields(data []byte, names ...string) error {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	if len(fields) != len(names) {
		return errors.New("product JSON field set mismatch")
	}
	for _, name := range names {
		if len(fields[name]) == 0 || string(fields[name]) == "null" {
			return errors.New("product JSON missing or noncanonical field")
		}
	}
	return nil
}

// LoadCapability never searches for another installation or creates state.
// Absence alone means an older core-only product; a damaged descriptor fails.
func LoadCapability(installRoot string) (*Capability, error) {
	path, err := productChild(installRoot, CapabilityFilename)
	if err != nil {
		return nil, err
	}
	data, err := readLimited(path, 16*1024)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var capability Capability
	if err = strictJSON(data, &capability); err != nil {
		return nil, err
	}
	if err = exactProductFields(data, "schema_version", "product", "default_enabled"); err != nil {
		return nil, err
	}
	if capability.SchemaVersion != CapabilitySchema || capability.DefaultEnabled == nil || *capability.DefaultEnabled || capability.Product.Path != ProductManifestPath || !canonicalForwardDigest(capability.Product.SHA256) {
		return nil, errors.New("unsupported product speech capability")
	}
	if _, err = readProductFile(installRoot, capability.Product.Path, capability.Product.SHA256, 128*1024); err != nil {
		return nil, err
	}
	return &capability, nil
}

// OpenProduct is a separate installed-product loader. It does not call or
// relax Load/IsTrialRoot, and never opens an experiment user-model namespace.
func OpenProduct(installRoot, manifestPath, expected string) (*Product, error) {
	if manifestPath != ProductManifestPath {
		return nil, errors.New("fixed speech/product.json required")
	}
	data, err := readProductFile(installRoot, manifestPath, expected, 128*1024)
	if err != nil {
		return nil, err
	}
	var manifest ProductManifest
	if err = strictJSON(data, &manifest); err != nil {
		return nil, err
	}
	if err = exactProductFields(data, "schema_version", "module_id", "approved_records", "default_enabled", "layout_sha256", "admission", "forward_source", "generation"); err != nil {
		return nil, err
	}
	if manifest.SchemaVersion != ProductSchema || manifest.ModuleID != ModuleID || manifest.ApprovedRecords != 24 || manifest.DefaultEnabled == nil || *manifest.DefaultEnabled || !canonicalForwardDigest(manifest.LayoutSHA256) {
		return nil, errors.New("unsupported product speech scope or policy")
	}
	if manifest.Admission.Path != "admission.json" || manifest.ForwardSource.Path != "forward-source.json" {
		return nil, errors.New("fixed product speech receipt paths required")
	}
	root := filepath.Join(installRoot, "speech")
	if _, err = readProductFile(root, manifest.ForwardSource.Path, manifest.ForwardSource.SHA256, 128*1024); err != nil {
		return nil, err
	}
	forwardPath, _ := productChild(root, manifest.ForwardSource.Path)
	forward, err := ReadForward(forwardPath)
	if err != nil {
		return nil, err
	}
	if manifest.LayoutSHA256 != forward.InputSHA256["go-backend/input_methods/yime/data/yime_yinyuan_layout.json"] {
		return nil, errors.New("product layout not bound to forward receipt")
	}
	data, err = readProductFile(root, manifest.Admission.Path, manifest.Admission.SHA256, 128*1024)
	if err != nil {
		return nil, err
	}
	var admission AdmissionReceipt
	if err = strictJSON(data, &admission); err != nil {
		return nil, err
	}
	if admission.SchemaVersion != "yimecore-speech-admission-receipt-v1" || !admission.Passed || admission.RecordCount != 24 || admission.ForwardSHA256 != manifest.ForwardSource.SHA256 || admission.Records.Path != "admitted-records.json" || len(admission.Modes) != 3 {
		return nil, errors.New("product admission receipt incomplete")
	}
	for _, gate := range []string{"forward_source", "four_positions", "nonlengthening", "canonical_membership", "canonical_weights_consistent"} {
		if !admission.Checks[gate] {
			return nil, errors.New("product admission gate missing")
		}
	}
	admittedRecords, err := readProductFile(root, admission.Records.Path, admission.Records.SHA256, 512*1024)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(manifest.Generation.Version) == "" || len(manifest.Generation.Modes) != 3 {
		return nil, errors.New("complete product generation required")
	}
	product := &Product{manifest: manifest, modules: map[string]*yimecore.FileIndex{}, admittedRecords: admittedRecords}
	fail := func(err error) (*Product, error) { _ = product.Close(); return nil, err }
	for _, mode := range []string{"full", "variable", "shorthand"} {
		item, ok := manifest.Generation.Modes[mode]
		if !ok || len(item.Modules) != 1 || item.Modules[0].ID != ModuleID {
			return fail(errors.New("only one admitted module per mode allowed"))
		}
		proof, ok := admission.Modes[mode]
		if !ok || proof.CanonicalCount != 24 || proof.AliasCount != 24 || proof.CoreSHA256 != item.Core.ExpectedSHA256 || proof.ModuleSHA256 != item.Modules[0].Index.ExpectedSHA256 {
			return fail(errors.New("product generation not bound to admission"))
		}
		for _, module := range []bool{false, true} {
			spec, suffix := item.Core, "-core.yidx"
			if module {
				spec, suffix = item.Modules[0].Index, "-stage5c.yidx"
			}
			if spec.Mode != mode || spec.Version != manifest.Generation.Version || spec.Path != "indexes/"+mode+suffix || !canonicalForwardDigest(spec.ExpectedSHA256) {
				return fail(errors.New("product index mode/path/generation mismatch"))
			}
			path, err := productChild(root, spec.Path)
			if err != nil {
				return fail(err)
			}
			index, err := yimecore.OpenResidentFileIndex(path)
			if err != nil {
				return fail(err)
			}
			valid := index.Mode() == mode && index.SHA256() == spec.ExpectedSHA256 && index.RecordCount() >= 24
			if module {
				valid = valid && index.RecordCount() == 24
			}
			if !valid {
				_ = index.Close()
				return fail(errors.New("product index bytes/mode/count mismatch"))
			}
			if module {
				product.modules[mode] = index
			} else {
				if err = index.Close(); err != nil {
					return fail(err)
				}
			}
		}
	}
	return product, nil
}

func (p *Product) LayoutSHA256() string {
	if p == nil {
		return ""
	}
	return p.manifest.LayoutSHA256
}

// AdmittedRecords returns only the immutable bytes already bound to the
// admission receipt. Callers cannot mutate the cache or re-read an unpinned path.
func (p *Product) AdmittedRecords() []byte {
	if p == nil {
		return nil
	}
	return append([]byte(nil), p.admittedRecords...)
}

func (p *Product) ValidateLayout(dataDir string) error {
	if p == nil {
		return errors.New("speech capability unavailable")
	}
	path, err := productChild(dataDir, "yime_yinyuan_layout.json")
	if err != nil {
		return err
	}
	hash, err := HashFile(path)
	if err != nil || hash != p.manifest.LayoutSHA256 {
		return errors.New("active annotation layout differs from admitted speech generation")
	}
	return nil
}

// ValidateIndexes is used only before explicit enablement. Disabled products
// remain compatible with existing user layouts and core-only index controls.
func (p *Product) ValidateIndexes(indexRoot, dataDir string) error {
	if err := p.ValidateLayout(dataDir); err != nil {
		return err
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		path, err := productChild(indexRoot, mode+".yidx")
		if err != nil {
			return err
		}
		hash, err := HashFile(path)
		if err != nil || hash != p.manifest.Generation.Modes[mode].Core.ExpectedSHA256 {
			return fmt.Errorf("active %s core differs from admitted speech generation", mode)
		}
	}
	return nil
}

// Modules returns a fresh declaration slice, retaining immutable indexes owned
// by Product. Call only after the caller has read an enabled settings snapshot.
func (p *Product) Modules(mode string, core *yimecore.FileIndex) ([]yimecore.BundleModule, error) {
	if p == nil || core == nil {
		return nil, errors.New("speech capability and active core required")
	}
	spec, ok := p.manifest.Generation.Modes[mode]
	if !ok || core.Mode() != mode || core.SHA256() != spec.Core.ExpectedSHA256 || p.modules[mode] == nil {
		return nil, errors.New("active core does not match admitted speech generation")
	}
	return []yimecore.BundleModule{{ID: ModuleID, Index: p.modules[mode]}}, nil
}

func (p *Product) Close() error {
	if p == nil {
		return nil
	}
	var result error
	for mode, index := range p.modules {
		result = errors.Join(result, index.Close())
		delete(p.modules, mode)
	}
	return result
}
