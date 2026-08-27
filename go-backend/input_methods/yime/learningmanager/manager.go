package learningmanager

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const modelSourcePrefix = "yimecore-e6c-three-mode-trial-v1:"

type Paths struct {
	Snapshot string
	Journal  string
}

type Promotion struct {
	Code       string
	Text       string
	Selections uint64
}

func ModelSourceID(indexVersion string) (string, error) {
	indexVersion = strings.TrimSpace(indexVersion)
	if indexVersion == "" || strings.ContainsAny(indexVersion, `/\\`) {
		return "", errors.New("Trial index version is required and must be a name")
	}
	return modelSourcePrefix + indexVersion, nil
}

func ModelPaths(stateRoot, indexVersion string) (Paths, error) {
	if strings.TrimSpace(stateRoot) == "" {
		return Paths{}, errors.New("Trial state root is required")
	}
	if _, err := ModelSourceID(indexVersion); err != nil {
		return Paths{}, err
	}
	root := filepath.Join(filepath.Clean(stateRoot), "user-model", indexVersion)
	return Paths{Snapshot: filepath.Join(root, "user-model.json"), Journal: filepath.Join(root, "user-model.journal")}, nil
}

// ExportStopped writes a validated backup. The Trial runtime must already be
// stopped so its durable owner has checkpointed the journal into the snapshot.
func ExportStopped(stateRoot, indexVersion, destination string) error {
	model, _, err := openStoppedModel(stateRoot, indexVersion)
	if err != nil {
		return err
	}
	if strings.TrimSpace(destination) == "" {
		return errors.New("learning export destination is required")
	}
	return model.SaveTo(destination)
}

// ImportStopped validates source identity before publishing the replacement.
func ImportStopped(stateRoot, indexVersion, backup string) error {
	paths, err := ModelPaths(stateRoot, indexVersion)
	if err != nil {
		return err
	}
	sourceID, _ := ModelSourceID(indexVersion)
	model, err := yimecore.OpenUserModel(backup, sourceID)
	if err != nil {
		return fmt.Errorf("validate learning backup: %w", err)
	}
	if err := model.SaveTo(paths.Snapshot); err != nil {
		return fmt.Errorf("publish learning snapshot: %w", err)
	}
	return removeJournal(paths.Journal)
}

func ClearStopped(stateRoot, indexVersion string) error {
	paths, err := ModelPaths(stateRoot, indexVersion)
	if err != nil {
		return err
	}
	sourceID, _ := ModelSourceID(indexVersion)
	model, err := yimecore.NewUserModel(sourceID)
	if err != nil {
		return err
	}
	if err := model.SaveTo(paths.Snapshot); err != nil {
		return fmt.Errorf("publish empty learning snapshot: %w", err)
	}
	return removeJournal(paths.Journal)
}

func RecordsStopped(stateRoot, indexVersion string) ([]yimecore.LearnedRecord, error) {
	model, _, err := openStoppedModel(stateRoot, indexVersion)
	if err != nil {
		return nil, err
	}
	return model.LearnedRecords(), nil
}

func ScanStopped(stateRoot, indexVersion, indexPath string, minimumSelections uint64) ([]Promotion, error) {
	if minimumSelections == 0 {
		return nil, errors.New("minimum selections must be positive")
	}
	records, err := RecordsStopped(stateRoot, indexVersion)
	if err != nil {
		return nil, err
	}
	index, err := yimecore.OpenFileIndex(indexPath)
	if err != nil {
		return nil, err
	}
	defer index.Close()
	type identity struct{ code, text string }
	static := make(map[identity]struct{}, index.RecordCount())
	if err := index.VisitEntries(func(entry yimecore.Entry) bool {
		static[identity{code: entry.Code, text: entry.Text}] = struct{}{}
		return true
	}); err != nil {
		return nil, err
	}
	result := make([]Promotion, 0)
	for _, record := range records {
		if record.Selections < minimumSelections {
			continue
		}
		if _, exists := static[identity{code: record.Code, text: record.Text}]; !exists {
			result = append(result, Promotion(record))
		}
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].Selections != result[j].Selections {
			return result[i].Selections > result[j].Selections
		}
		if result[i].Text != result[j].Text {
			return result[i].Text < result[j].Text
		}
		return result[i].Code < result[j].Code
	})
	return result, nil
}

func openStoppedModel(stateRoot, indexVersion string) (*yimecore.UserModel, Paths, error) {
	paths, err := ModelPaths(stateRoot, indexVersion)
	if err != nil {
		return nil, paths, err
	}
	sourceID, _ := ModelSourceID(indexVersion)
	model, err := yimecore.OpenUserModel(paths.Snapshot, sourceID)
	if err != nil {
		return nil, paths, err
	}
	return model, paths, nil
}

func removeJournal(path string) error {
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("remove superseded learning journal: %w", err)
	}
	return nil
}
