package userlexicon

import (
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
	if sharedDir == "" || userDir == "" {
		return nil
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return err
	}
	for _, mode := range schemaModes {
		name := "yime_" + mode + ".schema.yaml"
		content, err := os.ReadFile(filepath.Join(sharedDir, name))
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return fmt.Errorf("读取共享方案 %s 失败: %w", name, err)
		}
		if err := os.WriteFile(filepath.Join(userDir, name), content, 0o644); err != nil {
			return fmt.Errorf("更新用户方案 %s 失败: %w", name, err)
		}
	}
	return nil
}
