package systemlexicon

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

const ManifestFileName = "yime_lexicon_manifest.json"

// Manifest proves that all runtime dictionaries came from one canonical file.
type Manifest struct {
	FormatVersion int               `json:"format_version"`
	GeneratedAt   string            `json:"generated_at"`
	SourceFile    string            `json:"source_file"`
	SourceSHA256  string            `json:"source_sha256"`
	Transform     string            `json:"transform_version"`
	Layout        string            `json:"layout_version"`
	EntryCount    int               `json:"entry_count"`
	OutputSHA256  map[string]string `json:"output_sha256"`
}

type derivedEntry struct {
	text      string
	weight    int
	full      string
	variable  string
	shorthand string
}

// DeriveFromFullDictionary validates one fixed-length Rime dictionary and
// atomically replaces the three internal runtime dictionaries.
func DeriveFromFullDictionary(sourcePath, outputDir string) (Manifest, error) {
	sourceData, err := os.ReadFile(sourcePath)
	if err != nil {
		return Manifest{}, err
	}
	entries, err := LoadDictFile(sourcePath)
	if err != nil {
		return Manifest{}, err
	}
	if len(entries) == 0 {
		return Manifest{}, fmt.Errorf("等长码表没有有效词条")
	}
	derived := make([]derivedEntry, 0, len(entries))
	for index, entry := range entries {
		record, err := codemode.BuildRecord(entry.Code)
		if err != nil {
			return Manifest{}, fmt.Errorf("第 %d 个词条 %q 的等长码无效: %w", index+1, entry.Text, err)
		}
		derived = append(derived, derivedEntry{
			text: entry.Text, weight: entry.Weight,
			full: record.Full, variable: record.Variable, shorthand: record.Shorthand,
		})
	}
	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		return Manifest{}, err
	}
	stage, err := os.MkdirTemp(outputDir, ".yime-lexicon-stage-")
	if err != nil {
		return Manifest{}, err
	}
	defer os.RemoveAll(stage)

	sourceHash := hashBytes(sourceData)
	// Version runtime dictionaries from normalized entries, not source headers.
	// This makes a generated full dictionary safe to use as the next input.
	dictionaryVersion := hashBytes(buildDictionary("yime_full", "full", "canonical", derived))[:12]
	outputs := map[string][]byte{
		"yime_full.dict.yaml":      buildDictionary("yime_full", "full", dictionaryVersion, derived),
		"yime_variable.dict.yaml":  buildDictionary("yime_variable", "variable", dictionaryVersion, derived),
		"yime_shorthand.dict.yaml": buildDictionary("yime_shorthand", "shorthand", dictionaryVersion, derived),
	}
	manifest := Manifest{
		FormatVersion: 1, GeneratedAt: time.Now().Format(time.RFC3339),
		SourceFile: filepath.Base(sourcePath), SourceSHA256: sourceHash,
		Transform: "full-derived-v1", Layout: "rime-layout-key-2026-04-25",
		EntryCount: len(derived), OutputSHA256: map[string]string{},
	}
	for name, data := range outputs {
		manifest.OutputSHA256[name] = hashBytes(data)
		if err := os.WriteFile(filepath.Join(stage, name), data, 0o644); err != nil {
			return Manifest{}, err
		}
	}
	manifestData, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return Manifest{}, err
	}
	manifestData = append(manifestData, '\n')
	if err := os.WriteFile(filepath.Join(stage, ManifestFileName), manifestData, 0o644); err != nil {
		return Manifest{}, err
	}
	if err := replaceGeneratedSet(stage, outputDir, []string{
		"yime_full.dict.yaml", "yime_variable.dict.yaml", "yime_shorthand.dict.yaml", ManifestFileName,
	}); err != nil {
		return Manifest{}, err
	}
	return manifest, nil
}

func buildDictionary(name, mode, version string, entries []derivedEntry) []byte {
	var content strings.Builder
	content.WriteString("# Rime dictionary\n")
	content.WriteString("# GENERATED FILE - DO NOT EDIT\n")
	content.WriteString("# Derived from one canonical fixed-length Yime dictionary.\n")
	content.WriteString("---\nname: ")
	content.WriteString(name)
	content.WriteString("\nversion: \"")
	content.WriteString(version)
	content.WriteString("\"\nsort: by_weight\nuse_preset_vocabulary: false\n...\n")
	for _, entry := range entries {
		code := entry.full
		if mode == "variable" {
			code = entry.variable
		} else if mode == "shorthand" {
			code = entry.shorthand
		}
		fmt.Fprintf(&content, "%s\t%s\t%d\n", entry.text, code, entry.weight)
	}
	return []byte(content.String())
}

func replaceGeneratedSet(stage, outputDir string, names []string) error {
	backupDir, err := os.MkdirTemp(outputDir, ".yime-lexicon-backup-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(backupDir)
	replaced := make([]string, 0, len(names))
	backedUp := make([]string, 0, len(names))
	rollback := func() {
		for _, name := range replaced {
			_ = os.Remove(filepath.Join(outputDir, name))
		}
		for _, name := range backedUp {
			_ = os.Rename(filepath.Join(backupDir, name), filepath.Join(outputDir, name))
		}
	}
	for _, name := range names {
		target := filepath.Join(outputDir, name)
		if _, err := os.Stat(target); err == nil {
			if err := os.Rename(target, filepath.Join(backupDir, name)); err != nil {
				rollback()
				return err
			}
			backedUp = append(backedUp, name)
		} else if !os.IsNotExist(err) {
			rollback()
			return err
		}
		if err := os.Rename(filepath.Join(stage, name), target); err != nil {
			rollback()
			return err
		}
		replaced = append(replaced, name)
	}
	return nil
}

func hashBytes(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}
