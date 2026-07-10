package runtimechange

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"time"
)

const FileName = "yime_runtime_change.json"

const (
	ScopeSettings = "settings"
	ScopeLexicon  = "lexicon"
)

type Event struct {
	Revision         int64  `json:"revision"`
	Scope            string `json:"scope"`
	RequiresRedeploy bool   `json:"requires_redeploy"`
}

func Path(userDir string) string {
	if userDir == "" {
		return ""
	}
	return filepath.Join(userDir, FileName)
}

func Notify(userDir, scope string, requiresRedeploy bool) (Event, error) {
	path := Path(userDir)
	if path == "" {
		return Event{}, errors.New("用户目录为空")
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return Event{}, err
	}
	revision := time.Now().UnixNano()
	if previous, err := Read(userDir); err == nil && previous.Revision >= revision {
		revision = previous.Revision + 1
	}
	event := Event{Revision: revision, Scope: scope, RequiresRedeploy: requiresRedeploy}
	payload, err := json.Marshal(event)
	if err != nil {
		return Event{}, err
	}
	temp, err := os.CreateTemp(userDir, ".yime-runtime-change-*.tmp")
	if err != nil {
		return Event{}, err
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath)
	if _, err := temp.Write(append(payload, '\n')); err != nil {
		temp.Close()
		return Event{}, err
	}
	if err := temp.Close(); err != nil {
		return Event{}, err
	}
	if err := os.Rename(tempPath, path); err != nil {
		return Event{}, err
	}
	return event, nil
}

func Read(userDir string) (Event, error) {
	path := Path(userDir)
	if path == "" {
		return Event{}, errors.New("用户目录为空")
	}
	payload, err := os.ReadFile(path)
	if err != nil {
		return Event{}, err
	}
	var event Event
	if err := json.Unmarshal(payload, &event); err != nil {
		return Event{}, err
	}
	return event, nil
}
