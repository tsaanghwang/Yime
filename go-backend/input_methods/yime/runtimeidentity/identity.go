// Package runtimeidentity derives the installed core lexicon identity from
// the checked-in source manifest. The identity is content-addressed so a
// regenerated core cannot silently reuse another core's learned-candidate
// namespace merely because the two cores have the same row count.
package runtimeidentity

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
)

const SourceManifestFileName = "yime_core_source_manifest.json"

var sha256Pattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

type Identity struct {
	EntryCount             int    `json:"entry_count"`
	DistinctTexts          int    `json:"distinct_texts"`
	SourceDictionarySHA256 string `json:"source_dictionary_sha256"`
	SourceSelectionSHA256  string `json:"source_selection_sha256"`
}

func Load(dataDir string) (Identity, error) {
	path := filepath.Join(dataDir, SourceManifestFileName)
	payload, err := os.ReadFile(path)
	if err != nil {
		return Identity{}, fmt.Errorf("read core source manifest %s: %w", path, err)
	}
	var identity Identity
	if err := json.Unmarshal(payload, &identity); err != nil {
		return Identity{}, fmt.Errorf("parse core source manifest %s: %w", path, err)
	}
	if identity.EntryCount <= 0 || identity.DistinctTexts <= 0 || identity.DistinctTexts > identity.EntryCount {
		return Identity{}, fmt.Errorf("invalid core counts in %s: entries=%d distinct_texts=%d", path, identity.EntryCount, identity.DistinctTexts)
	}
	if !sha256Pattern.MatchString(identity.SourceDictionarySHA256) {
		return Identity{}, fmt.Errorf("invalid source dictionary SHA-256 in %s", path)
	}
	if !sha256Pattern.MatchString(identity.SourceSelectionSHA256) {
		return Identity{}, fmt.Errorf("invalid source selection SHA-256 in %s", path)
	}
	return identity, nil
}

func (identity Identity) DigestPrefix() string {
	return identity.SourceDictionarySHA256[:12]
}

func (identity Identity) CoreVersion() string {
	return "core-" + identity.DigestPrefix()
}

func (identity Identity) UserDBNamespace() string {
	return "core_" + identity.DigestPrefix()
}
