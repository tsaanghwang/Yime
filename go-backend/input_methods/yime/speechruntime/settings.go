package speechruntime

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
)

const SettingsSchema = "yimecore-speech-settings-v1"

type Settings struct {
	SchemaVersion string `json:"schema_version"`
	Enabled       bool   `json:"enabled"`
}

func DefaultSettings() Settings { return Settings{SchemaVersion: SettingsSchema, Enabled: false} }

func settingsPath(path string) error {
	if !filepath.IsAbs(path) || filepath.Base(path) != "speech.json" {
		return errors.New("explicit private speech.json settings path required")
	}
	return productPlainPath(path)
}

func LoadSettings(path string) (Settings, error) {
	if err := settingsPath(path); err != nil {
		return Settings{}, err
	}
	data, err := readLimited(path, 16*1024)
	if errors.Is(err, os.ErrNotExist) {
		return DefaultSettings(), nil
	}
	if err != nil {
		return Settings{}, err
	}
	var settings Settings
	if err = strictJSON(data, &settings); err != nil {
		return Settings{}, err
	}
	if err = exactProductFields(data, "schema_version", "enabled"); err != nil {
		return Settings{}, err
	}
	if settings.SchemaVersion != SettingsSchema {
		return Settings{}, errors.New("unknown speech settings schema")
	}
	return settings, nil
}

// SaveSettings changes only this explicit settings file. Neither disabling nor
// enabling migrates, deletes or opens learning state or another product.
func SaveSettings(path string, enabled, capabilityAvailable bool) error {
	if enabled && !capabilityAvailable {
		return errors.New("speech capability unavailable; cannot enable")
	}
	if err := settingsPath(path); err != nil {
		return err
	}
	if _, err := LoadSettings(path); err != nil {
		return err
	}
	data, err := json.MarshalIndent(Settings{SchemaVersion: SettingsSchema, Enabled: enabled}, "", "  ")
	if err != nil {
		return err
	}
	directory := filepath.Dir(path)
	if err = os.MkdirAll(directory, 0700); err != nil {
		return err
	}
	if err = productPlainPath(path); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(directory, ".speech-settings-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err = temporary.Chmod(0600); err != nil {
		_ = temporary.Close()
		return err
	}
	if _, err = temporary.Write(append(data, '\n')); err != nil {
		_ = temporary.Close()
		return err
	}
	if err = temporary.Sync(); err != nil {
		_ = temporary.Close()
		return err
	}
	if err = temporary.Close(); err != nil {
		return err
	}
	if err = productPlainPath(path); err != nil {
		return err
	}
	return replaceSettingsAtomically(temporaryPath, path)
}
