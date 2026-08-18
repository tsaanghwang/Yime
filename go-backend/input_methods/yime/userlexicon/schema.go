package userlexicon

import (
	"bytes"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/learningmigration"
)

var schemaModes = []string{"variable", "full", "shorthand"}
var generatedSchemaFiles = []string{
	"yime_variable.schema.yaml",
	"yime_full.schema.yaml",
	"yime_shorthand.schema.yaml",
	"yime_erhua_mixed_variable.schema.yaml",
	"yime_erhua_mixed_full.schema.yaml",
	"yime_erhua_mixed_shorthand.schema.yaml",
	"yime_psc_peripheral_variable.schema.yaml",
	"yime_psc_peripheral_full.schema.yaml",
	"yime_psc_peripheral_shorthand.schema.yaml",
}
var generatedLexiconFiles = []string{
	"yime_full.dict.yaml",
	"yime_variable.dict.yaml",
	"yime_shorthand.dict.yaml",
	"yime_lexicon_manifest.json",
}
var generatedErhuaOverlayFiles = []string{
	"yime_erhua_mixed_full.dict.yaml",
	"yime_erhua_mixed_variable.dict.yaml",
	"yime_erhua_mixed_shorthand.dict.yaml",
	"yime_erhua_mixed_sentence_full.dict.yaml",
	"yime_erhua_mixed_sentence_variable.dict.yaml",
	"yime_erhua_mixed_sentence_shorthand.dict.yaml",
	"yime_sentence_full.dict.yaml",
	"yime_sentence_variable.dict.yaml",
	"yime_sentence_shorthand.dict.yaml",
	"yime_erhua_reverse_source.tsv",
	"yime_erhua_mixed_manifest.json",
}
var generatedThirdToneStage5CFiles = []string{
	"yime_third_tone_stage5c_full.dict.yaml",
	"yime_third_tone_stage5c_variable.dict.yaml",
	"yime_third_tone_stage5c_shorthand.dict.yaml",
	"yime_third_tone_stage5c_manifest.json",
}
var generatedParticleAStage6DFiles = []string{
	"yime_particle_a_stage6d_full.dict.yaml",
	"yime_particle_a_stage6d_variable.dict.yaml",
	"yime_particle_a_stage6d_shorthand.dict.yaml",
	"yime_particle_a_stage6d_manifest.json",
}
var generatedPSCPeripheralFiles = []string{
	"yime_psc_peripheral_full.dict.yaml",
	"yime_psc_peripheral_variable.dict.yaml",
	"yime_psc_peripheral_shorthand.dict.yaml",
	"yime_psc_peripheral_sentence_full.dict.yaml",
	"yime_psc_peripheral_sentence_variable.dict.yaml",
	"yime_psc_peripheral_sentence_shorthand.dict.yaml",
	"yime_psc_peripheral_manifest.json",
}
var retiredCoreTrialFiles = []string{
	"yime_core_trial.dict.yaml",
	"yime_core_trial.schema.yaml",
	"yime_core_trial_manifest.json",
	filepath.Join("build", "yime_core_trial.schema.yaml"),
	filepath.Join("build", "yime_core_trial.prism.bin"),
	filepath.Join("build", "yime_core_trial.table.bin"),
	filepath.Join("build", "yime_core_trial.reverse.bin"),
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
	selectionChanged, err := migrateCoreTrialSelection(userDir)
	if err != nil {
		return false, err
	}
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
	erhuaOverlayChanged, err := refreshGeneratedErhuaOverlay(sharedDir, userDir)
	if err != nil {
		return false, err
	}
	thirdToneChanged, err := refreshGeneratedOverlay(
		sharedDir,
		userDir,
		generatedThirdToneStage5CFiles,
		"上声阶段 5C",
	)
	if err != nil {
		return false, err
	}
	particleAChanged, err := refreshGeneratedOverlay(
		sharedDir,
		userDir,
		generatedParticleAStage6DFiles,
		"语气词啊阶段 6D",
	)
	if err != nil {
		return false, err
	}
	pscPeripheralChanged, err := refreshGeneratedOverlay(
		sharedDir,
		userDir,
		generatedPSCPeripheralFiles,
		"PSC 规范低频外围",
	)
	if err != nil {
		return false, err
	}
	schemasChanged, err := RefreshRimeSchemas(sharedDir, userDir)
	if err != nil {
		return false, err
	}
	retiredChanged, err := removeRetiredCoreTrialFiles(userDir)
	if err != nil {
		return false, err
	}
	return selectionChanged || schemasChanged || lexiconChanged || erhuaOverlayChanged || thirdToneChanged || particleAChanged || pscPeripheralChanged || retiredChanged, nil
}

func refreshGeneratedErhuaOverlay(sharedDir, userDir string) (bool, error) {
	return refreshGeneratedOverlay(
		sharedDir,
		userDir,
		generatedErhuaOverlayFiles,
		"儿化混合",
	)
}

func refreshGeneratedOverlay(sharedDir, userDir string, files []string, label string) (bool, error) {
	manifestName := files[len(files)-1]
	artifactNames := files[:len(files)-1]
	sharedManifestPath := filepath.Join(sharedDir, manifestName)
	sharedManifest, err := os.ReadFile(sharedManifestPath)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("读取共享%s清单失败: %w", label, err)
	}
	userManifest, manifestErr := os.ReadFile(filepath.Join(userDir, manifestName))
	needsRefresh := manifestErr != nil || !bytes.Equal(userManifest, sharedManifest)
	if !needsRefresh {
		for _, name := range artifactNames {
			equal, compareErr := generatedFilesEqual(filepath.Join(sharedDir, name), filepath.Join(userDir, name))
			if compareErr != nil {
				return false, fmt.Errorf("核对用户目录%s词典 %s 失败: %w", label, name, compareErr)
			}
			if !equal {
				needsRefresh = true
				break
			}
		}
	}
	if !needsRefresh {
		return false, nil
	}
	for _, name := range artifactNames {
		content, readErr := os.ReadFile(filepath.Join(sharedDir, name))
		if readErr != nil {
			return false, fmt.Errorf("读取共享%s词典 %s 失败: %w", label, name, readErr)
		}
		if writeErr := os.WriteFile(filepath.Join(userDir, name), content, 0o644); writeErr != nil {
			return false, fmt.Errorf("更新用户目录%s词典 %s 失败: %w", label, name, writeErr)
		}
	}
	if err := os.WriteFile(filepath.Join(userDir, manifestName), sharedManifest, 0o644); err != nil {
		return false, fmt.Errorf("更新用户目录%s清单失败: %w", label, err)
	}
	return true, nil
}

func migrateCoreTrialSelection(userDir string) (bool, error) {
	changed := false
	for _, name := range []string{"user.yaml", "default.custom.yaml"} {
		path := filepath.Join(userDir, name)
		content, err := os.ReadFile(path)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return false, err
		}
		updated := strings.ReplaceAll(
			string(content),
			"yime_core_trial",
			"yime_variable",
		)
		if updated == string(content) {
			continue
		}
		if err := os.WriteFile(path, []byte(updated), 0o644); err != nil {
			return false, err
		}
		changed = true
	}
	return changed, nil
}

func removeRetiredCoreTrialFiles(userDir string) (bool, error) {
	changed := false
	for _, name := range retiredCoreTrialFiles {
		path := filepath.Join(userDir, name)
		if err := os.Remove(path); err == nil {
			changed = true
		} else if !errors.Is(err, os.ErrNotExist) {
			return false, fmt.Errorf("remove retired runtime artifact %s: %w", name, err)
		}
	}
	return changed, nil
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
			equal, compareErr := generatedFilesEqual(filepath.Join(sharedDir, name), filepath.Join(userDir, name))
			if compareErr != nil {
				return false, fmt.Errorf("核对用户目录词典文件 %s 失败: %w", name, compareErr)
			}
			if !equal {
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

func generatedFilesEqual(sharedPath, userPath string) (bool, error) {
	sharedInfo, err := os.Stat(sharedPath)
	if err != nil {
		return false, err
	}
	userInfo, err := os.Stat(userPath)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if sharedInfo.Size() != userInfo.Size() {
		return false, nil
	}
	hashFile := func(path string) ([sha256.Size]byte, error) {
		file, openErr := os.Open(path)
		if openErr != nil {
			return [sha256.Size]byte{}, openErr
		}
		defer file.Close()
		hash := sha256.New()
		if _, copyErr := io.Copy(hash, file); copyErr != nil {
			return [sha256.Size]byte{}, copyErr
		}
		var sum [sha256.Size]byte
		copy(sum[:], hash.Sum(nil))
		return sum, nil
	}
	sharedHash, err := hashFile(sharedPath)
	if err != nil {
		return false, err
	}
	userHash, err := hashFile(userPath)
	if err != nil {
		return false, err
	}
	return sharedHash == userHash, nil
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
	for _, name := range generatedSchemaFiles {
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
