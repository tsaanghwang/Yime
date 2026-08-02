package trainer

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
)

const (
	PreferencesFileName = "yime_trainer_preferences.json"
	PreferencesDirName  = "YimeTrainer"
	PreferencesVersion  = 1

	FontSizeNormal = "normal"
	FontSizeMedium = "medium"
	FontSizeLarge  = "large"
	FontSizeXLarge = "xlarge"

	BackgroundSoftGray  = "soft-gray"
	BackgroundWarmBeige = "warm-beige"
	BackgroundGrayBlue  = "gray-blue"
)

// PreferencesDirectoryFromRimeUserDir keeps trainer-only UI state beside,
// rather than inside, the Rime user directory supplied by the Yime backend.
func PreferencesDirectoryFromRimeUserDir(rimeUserDir string) string {
	value := strings.TrimSpace(rimeUserDir)
	if value == "" {
		return ""
	}
	cleaned := filepath.Clean(value)
	parent := filepath.Dir(cleaned)
	if parent == "." || parent == cleaned {
		return filepath.Join(cleaned, PreferencesDirName)
	}
	return filepath.Join(parent, PreferencesDirName)
}

// Preferences contains display-only trainer settings. It is deliberately
// separate from Rime and PIME learning data.
type Preferences struct {
	Version       int    `json:"version"`
	FontSize      string `json:"font_size"`
	Background    string `json:"background"`
	LastMode      string `json:"last_mode,omitempty"`
	LastSectionID string `json:"last_section_id,omitempty"`
	ReviewFilter  string `json:"review_filter,omitempty"`
}

func DefaultPreferences() Preferences {
	return Preferences{
		Version:      PreferencesVersion,
		FontSize:     FontSizeMedium,
		Background:   BackgroundSoftGray,
		ReviewFilter: ReviewAll,
	}
}

func NormalizePreferences(value Preferences) Preferences {
	defaults := DefaultPreferences()
	switch strings.TrimSpace(value.FontSize) {
	case FontSizeNormal, FontSizeMedium, FontSizeLarge, FontSizeXLarge:
		defaults.FontSize = strings.TrimSpace(value.FontSize)
	}
	switch strings.TrimSpace(value.Background) {
	case BackgroundSoftGray, BackgroundWarmBeige, BackgroundGrayBlue:
		defaults.Background = strings.TrimSpace(value.Background)
	}
	switch strings.TrimSpace(value.LastMode) {
	case "variable", "full", "shorthand":
		defaults.LastMode = strings.TrimSpace(value.LastMode)
	}
	defaults.LastSectionID = strings.TrimSpace(value.LastSectionID)
	switch strings.TrimSpace(value.ReviewFilter) {
	case ReviewWrong, ReviewToday:
		defaults.ReviewFilter = strings.TrimSpace(value.ReviewFilter)
	default:
		defaults.ReviewFilter = ReviewAll
	}
	return defaults
}

func LoadPreferences(userDir string) (Preferences, error) {
	if strings.TrimSpace(userDir) == "" {
		return DefaultPreferences(), nil
	}
	data, err := os.ReadFile(filepath.Join(userDir, PreferencesFileName))
	if errors.Is(err, os.ErrNotExist) {
		return DefaultPreferences(), nil
	}
	if err != nil {
		return DefaultPreferences(), err
	}
	var value Preferences
	if err := json.Unmarshal(data, &value); err != nil {
		return DefaultPreferences(), err
	}
	return NormalizePreferences(value), nil
}

func SavePreferences(userDir string, value Preferences) error {
	if strings.TrimSpace(userDir) == "" {
		return nil
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return err
	}
	value = NormalizePreferences(value)
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(filepath.Join(userDir, PreferencesFileName), data, 0o644)
}
