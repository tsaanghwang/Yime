package keyboardlab

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
	"os"
	"path/filepath"
)

type dataManifest struct {
	SchemaVersion          int               `json:"schema_version"`
	LayoutProjectionSHA256 string            `json:"layout_projection_sha256"`
	DisabledYinyuanIDs     []string          `json:"disabled_yinyuan_ids"`
	DictionarySHA256       map[string]string `json:"dictionary_sha256"`
	Scope                  string            `json:"scope"`
	Limit                  int               `json:"limit"`
	InputPolicy            string            `json:"input_policy"`
}

func loadManifest(dataDir, layoutID string) (dataManifest, error) {
	var result dataManifest
	data, err := os.ReadFile(filepath.Join(dataDir, "ascii_keyboard_manifest.json"))
	if err != nil {
		return result, fmt.Errorf("read experimental manifest: %w", err)
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return result, fmt.Errorf("experimental manifest: %w", err)
	}
	if result.SchemaVersion != 1 || result.Scope != "immutable_source_runtime_experiment" || result.InputPolicy != inputPolicy || result.LayoutProjectionSHA256 != layoutID || layoutID != codemode.LayoutProjectionSHA256 || result.Limit != 0 {
		return result, errors.New("experimental manifest does not match this physical layout; regenerate data")
	}
	if len(result.DisabledYinyuanIDs) != 0 || len(codemode.LayoutAlphabet) != 75 {
		return result, errors.New("concept keyboard requires 75 active ASCII carriers and no disabled Yinyuan IDs")
	}
	for _, mode := range modes {
		value := result.DictionarySHA256["yime_"+mode+".dict.yaml"]
		digest, err := hex.DecodeString(value)
		if err != nil || len(digest) != 32 {
			return result, fmt.Errorf("manifest lacks valid %s dictionary digest", mode)
		}
	}
	return result, nil
}
