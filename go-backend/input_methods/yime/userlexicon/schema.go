package userlexicon

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

var schemaModes = []string{"variable", "full", "shorthand"}

// SyncRimeSchemas refreshes generated user-directory schema copies from the
// installed shared data before a lexicon build. Customizations remain in the
// separate *.custom.yaml files and are applied by Rime during deployment.
func SyncRimeSchemas(sharedDir, userDir string) error {
	_, err := RefreshRimeSchemas(sharedDir, userDir)
	return err
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
