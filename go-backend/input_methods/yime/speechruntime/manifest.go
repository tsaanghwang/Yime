// Package speechruntime loads explicitly pinned, isolated speech trial bundles.
// It contains no pronunciation generator, Rime dependency or installed settings.
package speechruntime

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
)

const Schema = "yimecore-speech-isolated-bundle-v1"
const ModuleID = "third-tone-stage5c"
const ModelNamespace = "yimecore-speech-stage5c-isolated-v1"

type Manifest struct {
	SchemaVersion   string                          `json:"schema_version"`
	Enabled         bool                            `json:"enabled"`
	ApprovedRecords int                             `json:"approved_records"`
	Admission       FileRef                         `json:"admission"`
	ForwardSource   FileRef                         `json:"forward_source"`
	Generation      yimebroker.BundleGenerationSpec `json:"generation"`
}

type FileRef struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
}

type AdmissionReceipt struct {
	SchemaVersion string                   `json:"schema_version"`
	Passed        bool                     `json:"passed"`
	RecordCount   int                      `json:"record_count"`
	ForwardSHA256 string                   `json:"forward_sha256"`
	Records       FileRef                  `json:"records"`
	Checks        map[string]bool          `json:"checks"`
	Modes         map[string]AdmissionMode `json:"modes"`
}

type AdmissionMode struct {
	CoreSHA256     string `json:"core_sha256"`
	ModuleSHA256   string `json:"module_sha256"`
	CanonicalCount int    `json:"canonical_count"`
	AliasCount     int    `json:"alias_count"`
}

type ForwardReceipt struct {
	SchemaVersion string            `json:"schema_version"`
	Passed        bool              `json:"passed"`
	RecordCount   int               `json:"record_count"`
	SyllableCount int               `json:"syllable_count"`
	Checks        map[string]bool   `json:"checks"`
	RecordIDs     []string          `json:"record_ids"`
	InputSHA256   map[string]string `json:"input_sha256"`
	Inputs        []struct {
		Role   string `json:"role"`
		Path   string `json:"path"`
		SHA256 string `json:"sha256"`
	} `json:"inputs"`
}

func readLimited(path string, limit int64) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > limit {
		return nil, errors.New("trial evidence exceeds size limit")
	}
	return data, nil
}

func ReadForward(path string) (ForwardReceipt, error) {
	var result ForwardReceipt
	data, err := readLimited(path, 128*1024)
	if err != nil {
		return result, err
	}
	if err = strictJSON(data, &result); err != nil {
		return result, err
	}
	if result.SchemaVersion != "yimecore-speech-forward-source-v1" || !result.Passed || result.RecordCount != 24 || result.SyllableCount != 50 || len(result.RecordIDs) != 24 || len(result.InputSHA256) == 0 {
		return result, errors.New("forward source receipt incomplete")
	}
	if err := validateForwardInputs(result); err != nil {
		return result, err
	}
	for _, gate := range []string{"canonical_phrase_source", "canonical_inventory_membership", "formal_four_id_decomposition", "canonical_layout_projection", "semantic_tone_substitutions", "inputs_unchanged"} {
		if !result.Checks[gate] {
			return result, errors.New("forward source gate did not pass")
		}
	}
	if result.Checks["rime_executed"] || result.Checks["aliases_generated"] {
		return result, errors.New("unexpected forward source operation")
	}
	seen := map[string]bool{}
	for _, id := range result.RecordIDs {
		if seen[id] {
			return result, errors.New("duplicate forward record")
		}
		seen[id] = true
	}
	for i := 1; i <= 24; i++ {
		if !seen[fmt.Sprintf("T3-5B-%03d", i)] {
			return result, errors.New("unknown forward record set")
		}
	}
	return result, nil
}

func HashFile(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err = io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// Child rejects alternate/indirect paths before any data or state is opened.
func Child(root, relative string) (string, error) {
	if relative == "" || filepath.IsAbs(relative) || strings.Contains(relative, ":") || strings.Contains(relative, "\\") {
		return "", errors.New("expected canonical slash-relative trial path")
	}
	for _, part := range strings.Split(relative, "/") {
		if part == "" || part == "." || part == ".." || strings.TrimRight(part, " .") != part {
			return "", errors.New("noncanonical trial path")
		}
	}
	abs, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	path := filepath.Join(abs, filepath.FromSlash(relative))
	if err := PlainPath(path); err != nil {
		return "", err
	}
	return path, nil
}

func PlainPath(path string) error {
	abs, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	for current := abs; ; current = filepath.Dir(current) {
		info, statErr := os.Lstat(current)
		if statErr != nil && !os.IsNotExist(statErr) {
			return statErr
		}
		if statErr == nil && info.Mode()&os.ModeSymlink != 0 {
			return errors.New("indirect trial paths are forbidden")
		}
		if filepath.Dir(current) == current {
			break
		}
	}
	return nil
}

func IsTrialRoot(root string) error {
	abs, err := filepath.Abs(root)
	if err != nil {
		return err
	}
	if !strings.HasPrefix(filepath.Base(abs), "speech-admission-") || len(filepath.Base(abs)) <= len("speech-admission-") {
		return errors.New("explicit speech-admission-<unique> trial root required")
	}
	return PlainPath(abs)
}

func Load(root, path, expected string) (Manifest, error) {
	var manifest Manifest
	if err := IsTrialRoot(root); err != nil {
		return manifest, err
	}
	resolved, err := Child(root, path)
	if err != nil {
		return manifest, err
	}
	data, err := readLimited(resolved, 128*1024)
	if err != nil {
		return manifest, err
	}
	sum := sha256.Sum256(data)
	if len(expected) != 64 || hex.EncodeToString(sum[:]) != expected {
		return manifest, errors.New("trial manifest hash mismatch")
	}
	if err := strictJSON(data, &manifest); err != nil {
		return manifest, err
	}
	if manifest.SchemaVersion != Schema || manifest.ApprovedRecords != 24 {
		return manifest, errors.New("unknown trial schema or admission scope")
	}
	for _, ref := range []FileRef{manifest.Admission, manifest.ForwardSource} {
		p, err := Child(root, ref.Path)
		if err != nil {
			return manifest, err
		}
		hash, err := HashFile(p)
		if err != nil || hash != ref.SHA256 {
			return manifest, errors.New("trial admission evidence hash mismatch")
		}
	}
	forwardPath, _ := Child(root, manifest.ForwardSource.Path)
	if _, err = ReadForward(forwardPath); err != nil {
		return manifest, err
	}
	admissionPath, _ := Child(root, manifest.Admission.Path)
	admissionData, err := readLimited(admissionPath, 128*1024)
	if err != nil {
		return manifest, err
	}
	var admission AdmissionReceipt
	if err = strictJSON(admissionData, &admission); err != nil {
		return manifest, err
	}
	if admission.SchemaVersion != "yimecore-speech-admission-receipt-v1" || !admission.Passed || admission.RecordCount != 24 || admission.ForwardSHA256 != manifest.ForwardSource.SHA256 || len(admission.Modes) != 3 {
		return manifest, errors.New("admission receipt incomplete or not bound to forward source")
	}
	for _, gate := range []string{"forward_source", "four_positions", "nonlengthening", "canonical_membership", "canonical_weights_consistent"} {
		if !admission.Checks[gate] {
			return manifest, errors.New("required admission gate did not pass")
		}
	}
	recordPath, err := Child(root, admission.Records.Path)
	if err != nil {
		return manifest, err
	}
	recordHash, err := HashFile(recordPath)
	if err != nil || recordHash != admission.Records.SHA256 {
		return manifest, errors.New("admission records hash mismatch")
	}
	if len(manifest.Generation.Modes) != 3 {
		return manifest, errors.New("all three modes are required")
	}
	if strings.TrimSpace(manifest.Generation.Version) == "" {
		return manifest, errors.New("generation version is required")
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		item, ok := manifest.Generation.Modes[mode]
		if !ok || item.Core.Mode != mode {
			return manifest, errors.New("missing or mismatched core mode")
		}
		if len(item.Modules) != 1 || item.Modules[0].ID != ModuleID {
			return manifest, errors.New("only the admitted Stage5C module is allowed")
		}
		if item.Core.Version != manifest.Generation.Version || item.Modules[0].Index.Version != manifest.Generation.Version || item.Modules[0].Index.Mode != mode {
			return manifest, errors.New("all declarations must bind the same mode and generation")
		}
		for _, hash := range []string{item.Core.ExpectedSHA256, item.Modules[0].Index.ExpectedSHA256} {
			decoded, err := hex.DecodeString(hash)
			if err != nil || len(decoded) != 32 || strings.ToLower(hash) != hash {
				return manifest, errors.New("invalid declared index digest")
			}
		}
		proof, ok := admission.Modes[mode]
		if !ok || proof.CoreSHA256 != item.Core.ExpectedSHA256 || proof.ModuleSHA256 != item.Modules[0].Index.ExpectedSHA256 || proof.CanonicalCount != 24 || proof.AliasCount != 24 {
			return manifest, errors.New("admission receipt does not bind the complete generation")
		}
		item.Core.Path, err = Child(root, item.Core.Path)
		if err != nil {
			return manifest, err
		}
		for i := range item.Modules {
			item.Modules[i].Index.Path, err = Child(root, item.Modules[i].Index.Path)
			if err != nil {
				return manifest, err
			}
		}
		manifest.Generation.Modes[mode] = item
	}
	return manifest, nil
}

// EffectiveGeneration never mutates the decoded manifest. Disabled modules are
// omitted as a whole; their private learning namespace is deliberately retained.
func (m Manifest) EffectiveGeneration() yimebroker.BundleGenerationSpec {
	result := yimebroker.BundleGenerationSpec{Version: m.Generation.Version, Modes: make(map[string]yimebroker.BundleModeSpec)}
	for mode, item := range m.Generation.Modes {
		item.Modules = append([]yimebroker.BundleModuleSpec(nil), item.Modules...)
		if !m.Enabled {
			item.Modules = nil
		}
		result.Modes[mode] = item
	}
	return result
}

func strictJSON(data []byte, target any) error {
	// encoding/json otherwise accepts duplicate object keys, including modes.
	check := json.NewDecoder(bytes.NewReader(data))
	var walk func() error
	walk = func() error {
		token, err := check.Token()
		if err != nil {
			return err
		}
		if delim, ok := token.(json.Delim); ok {
			switch delim {
			case '{':
				seen := map[string]bool{}
				for check.More() {
					key, err := check.Token()
					if err != nil {
						return err
					}
					name, ok := key.(string)
					if !ok || seen[name] {
						return errors.New("duplicate JSON object key")
					}
					seen[name] = true
					if err := walk(); err != nil {
						return err
					}
				}
			case '[':
				for check.More() {
					if err := walk(); err != nil {
						return err
					}
				}
			default:
				return errors.New("unexpected JSON delimiter")
			}
			_, err = check.Token()
			return err
		}
		return nil
	}
	if err := walk(); err != nil {
		return fmt.Errorf("trial JSON: %w", err)
	}
	if _, err := check.Token(); err != io.EOF {
		return errors.New("trailing trial JSON")
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	return decoder.Decode(target)
}
