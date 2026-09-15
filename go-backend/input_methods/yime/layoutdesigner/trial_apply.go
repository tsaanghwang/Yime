package layoutdesigner

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userlexicon"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const TrialGenerationSchema = "yimecore-trial-layout-generation-v1"

type TrialIndexSpec struct {
	Mode   string `json:"mode"`
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
}

type TrialGeneration struct {
	SchemaVersion string                    `json:"schema_version"`
	Version       string                    `json:"version"`
	GeneratedAt   string                    `json:"generated_at"`
	DataDir       string                    `json:"data_dir"`
	IndexRoot     string                    `json:"index_root"`
	Plan          Plan                      `json:"plan"`
	Indexes       map[string]TrialIndexSpec `json:"indexes"`
}

func TrialLayoutRoot(stateRoot string) string {
	return filepath.Join(stateRoot, "layout")
}

func TrialGenerationManifestPath(stateRoot string) string {
	return filepath.Join(TrialLayoutRoot(stateRoot), "current.json")
}

func BuildTrialLayoutGeneration(sharedDir, stateRoot string, target Profile) (TrialGeneration, error) {
	if strings.TrimSpace(sharedDir) == "" || strings.TrimSpace(stateRoot) == "" {
		return TrialGeneration{}, errors.New("Trial 共享目录和状态目录不能为空")
	}
	sourceDir := sharedDir
	if current, err := LoadTrialLayoutGeneration(stateRoot); err == nil {
		sourceDir = current.DataDir
	} else if !errors.Is(err, os.ErrNotExist) {
		return TrialGeneration{}, err
	}
	layoutRoot := TrialLayoutRoot(stateRoot)
	generationRoot := filepath.Join(layoutRoot, "generations")
	if err := os.MkdirAll(generationRoot, 0o755); err != nil {
		return TrialGeneration{}, err
	}
	stage, err := os.MkdirTemp(generationRoot, ".stage-")
	if err != nil {
		return TrialGeneration{}, err
	}
	defer os.RemoveAll(stage)
	dataDir := filepath.Join(stage, "data")
	indexRoot := filepath.Join(stage, "indexes")
	if err := copyGeneratedSet(sourceDir, dataDir); err != nil {
		return TrialGeneration{}, err
	}
	plan, err := Apply(dataDir, target)
	if err != nil {
		return TrialGeneration{}, err
	}
	if err := os.MkdirAll(indexRoot, 0o755); err != nil {
		return TrialGeneration{}, err
	}
	userLexiconDir := filepath.Join(stage, "user-lexicons")
	if err := userlexicon.RebuildAllRimeLexiconsTo(dataDir, stateRoot, userLexiconDir); err != nil {
		return TrialGeneration{}, fmt.Errorf("重建 Trial 用户词库: %w", err)
	}
	indexes := make(map[string]TrialIndexSpec, 3)
	for _, mode := range []string{"full", "variable", "shorthand"} {
		path := filepath.Join(indexRoot, mode+".yidx")
		result, buildErr := yimecore.BuildIndexFile(mode, filepath.Join(dataDir, "yime_"+mode+".dict.yaml"), path)
		if buildErr != nil {
			return TrialGeneration{}, fmt.Errorf("构建 Trial %s 索引: %w", mode, buildErr)
		}
		index, openErr := yimecore.OpenFileIndex(path)
		if openErr != nil {
			return TrialGeneration{}, fmt.Errorf("校验 Trial %s 索引: %w", mode, openErr)
		}
		valid := index.Mode() == mode && index.RecordCount() == result.IndexedRecords
		_ = index.Close()
		if !valid {
			return TrialGeneration{}, fmt.Errorf("Trial %s 索引校验失败", mode)
		}
		indexes[mode] = TrialIndexSpec{Mode: mode, Path: path, SHA256: result.IndexSHA256}
	}
	version := "layout-" + plan.TargetDigest[:12]
	finalRoot := filepath.Join(generationRoot, version)
	if err := os.RemoveAll(finalRoot); err != nil {
		return TrialGeneration{}, err
	}
	if err := os.Rename(stage, finalRoot); err != nil {
		return TrialGeneration{}, err
	}
	dataDir = filepath.Join(finalRoot, "data")
	indexRoot = filepath.Join(finalRoot, "indexes")
	for mode, spec := range indexes {
		spec.Path = filepath.Join(indexRoot, mode+".yidx")
		indexes[mode] = spec
	}
	generation := TrialGeneration{
		SchemaVersion: TrialGenerationSchema, Version: version,
		GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), DataDir: dataDir, IndexRoot: indexRoot,
		Plan: plan, Indexes: indexes,
	}
	var restoreLexicons func()
	var commitLexicons func()
	if _, statErr := os.Stat(filepath.Join(finalRoot, "user-lexicons", "custom_phrase_full.txt")); statErr == nil {
		names := []string{"custom_phrase_full.txt", "custom_phrase_variable.txt", "custom_phrase_shorthand.txt"}
		var installErr error
		restoreLexicons, commitLexicons, installErr = installUserSet(stateRoot, filepath.Join(finalRoot, "user-lexicons"), names)
		if installErr != nil {
			return TrialGeneration{}, installErr
		}
	}
	if err := writeTrialGenerationManifest(TrialGenerationManifestPath(stateRoot), generation); err != nil {
		if restoreLexicons != nil {
			restoreLexicons()
		}
		return TrialGeneration{}, err
	}
	if commitLexicons != nil {
		commitLexicons()
	}
	return generation, nil
}

func LoadTrialLayoutGeneration(stateRoot string) (TrialGeneration, error) {
	data, err := os.ReadFile(TrialGenerationManifestPath(stateRoot))
	if err != nil {
		return TrialGeneration{}, err
	}
	var generation TrialGeneration
	if err := json.Unmarshal(data, &generation); err != nil {
		return TrialGeneration{}, err
	}
	if generation.SchemaVersion != TrialGenerationSchema || generation.Version == "" || len(generation.Indexes) != 3 {
		return TrialGeneration{}, errors.New("Trial 布局 generation 清单无效")
	}
	root, err := filepath.Abs(TrialLayoutRoot(stateRoot))
	if err != nil {
		return TrialGeneration{}, err
	}
	for _, path := range []string{generation.DataDir, generation.IndexRoot} {
		absolute, absErr := filepath.Abs(path)
		relative, relErr := filepath.Rel(root, absolute)
		if absErr != nil || relErr != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
			return TrialGeneration{}, errors.New("Trial 布局 generation 越过状态目录")
		}
	}
	if !completeGeneratedSet(generation.DataDir) {
		return TrialGeneration{}, errors.New("Trial 布局 generation 数据不完整")
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		spec, ok := generation.Indexes[mode]
		if !ok || spec.Mode != mode || filepath.Clean(spec.Path) != filepath.Join(generation.IndexRoot, mode+".yidx") || len(spec.SHA256) != 64 {
			return TrialGeneration{}, fmt.Errorf("Trial %s 索引清单无效", mode)
		}
		if _, err := os.Stat(spec.Path); err != nil {
			return TrialGeneration{}, err
		}
	}
	return generation, nil
}

func writeTrialGenerationManifest(path string, generation TrialGeneration) error {
	data, err := json.MarshalIndent(generation, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".current-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, path); err == nil {
		return nil
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return os.Rename(temporaryPath, path)
}
