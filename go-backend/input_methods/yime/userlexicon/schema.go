package userlexicon

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/learningmigration"
)

var schemaModes = []string{"variable", "full", "shorthand"}
var generatedLexiconFiles = []string{
	"yime_full.dict.yaml",
	"yime_variable.dict.yaml",
	"yime_shorthand.dict.yaml",
	"yime_lexicon_manifest.json",
}

// SyncRimeSchemas refreshes generated user-directory schema copies from the
// installed shared data before a lexicon build. Customizations remain in the
// separate *.custom.yaml files and are applied by Rime during deployment.
func SyncRimeSchemas(sharedDir, userDir string) error {
	_, err := RefreshRimeSchemas(sharedDir, userDir)
	return err
}

// RefreshRimeData refreshes generated schemas and system lexicon artifacts in
// the Rime user directory. User-authored *.custom.yaml and user lexicon files
// are deliberately outside this set.
func RefreshRimeData(sharedDir, userDir string) (bool, error) {
	transitions, err := learningmigration.DetectTransitions(sharedDir, userDir)
	if err != nil {
		return false, err
	}
	// Migrate while both the old user-directory dictionary and the incoming
	// shared dictionary are available. This preserves the precise pronunciation
	// choice for entries that have the same text under more than one code.
	if _, err := learningmigration.MigrateAll(sharedDir, userDir, transitions); err != nil {
		return false, fmt.Errorf("migrate learning records after layout update: %w", err)
	}
	lexiconChanged, err := refreshGeneratedLexicon(sharedDir, userDir)
	if err != nil {
		return false, err
	}
	if lexiconChanged {
		if err := RebuildAllRimeLexicons(sharedDir, userDir); err != nil {
			return false, fmt.Errorf("rebuild user lexicons after code-map update: %w", err)
		}
		if err := copyGeneratedLexiconManifest(sharedDir, userDir); err != nil {
			return false, err
		}
	}
	schemasChanged, err := RefreshRimeSchemas(sharedDir, userDir)
	if err != nil {
		return false, err
	}
	return schemasChanged || lexiconChanged, nil
}

func refreshGeneratedLexicon(sharedDir, userDir string) (bool, error) {
	sharedManifestPath := filepath.Join(sharedDir, "yime_lexicon_manifest.json")
	sharedManifest, err := os.ReadFile(sharedManifestPath)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("读取共享词典清单失败: %w", err)
	}

	userManifest, manifestErr := os.ReadFile(filepath.Join(userDir, "yime_lexicon_manifest.json"))
	needsRefresh := manifestErr != nil || !bytes.Equal(userManifest, sharedManifest)
	if !needsRefresh {
		for _, name := range generatedLexiconFiles[:3] {
			if _, statErr := os.Stat(filepath.Join(userDir, name)); statErr != nil {
				needsRefresh = true
				break
			}
		}
	}
	if !needsRefresh {
		return false, nil
	}

	// The manifest is written by RefreshRimeData only after the derived user
	// lexicons have also been rebuilt successfully.
	for _, name := range generatedLexiconFiles[:3] {
		content, readErr := os.ReadFile(filepath.Join(sharedDir, name))
		if readErr != nil {
			return false, fmt.Errorf("读取共享词典文件 %s 失败: %w", name, readErr)
		}
		if writeErr := os.WriteFile(filepath.Join(userDir, name), content, 0o644); writeErr != nil {
			return false, fmt.Errorf("更新用户目录词典文件 %s 失败: %w", name, writeErr)
		}
	}
	return true, nil
}

func copyGeneratedLexiconManifest(sharedDir, userDir string) error {
	name := generatedLexiconFiles[3]
	content, err := os.ReadFile(filepath.Join(sharedDir, name))
	if err != nil {
		return fmt.Errorf("读取共享词典文件 %s 失败: %w", name, err)
	}
	if err := os.WriteFile(filepath.Join(userDir, name), content, 0o644); err != nil {
		return fmt.Errorf("更新用户目录词典文件 %s 失败: %w", name, err)
	}
	return nil
}

// RefreshRimeSchemas copies changed generated schemas into the user directory
// and reports whether Rime needs to rebuild its compiled configuration.
func RefreshRimeSchemas(sharedDir, userDir string) (bool, error) {
	if sharedDir == "" || userDir == "" {
		return false, nil
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return false, err
	}
	changed := false
	for _, mode := range schemaModes {
		name := "yime_" + mode + ".schema.yaml"
		content, err := os.ReadFile(filepath.Join(sharedDir, name))
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return false, fmt.Errorf("读取共享方案 %s 失败: %w", name, err)
		}
		targetPath := filepath.Join(userDir, name)
		if current, readErr := os.ReadFile(targetPath); readErr == nil && bytes.Equal(current, content) {
			continue
		} else if readErr != nil && !errors.Is(readErr, os.ErrNotExist) {
			return false, fmt.Errorf("读取用户方案 %s 失败: %w", name, readErr)
		}
		if err := os.WriteFile(targetPath, content, 0o644); err != nil {
			return false, fmt.Errorf("更新用户方案 %s 失败: %w", name, err)
		}
		changed = true
	}
	return changed, nil
}
