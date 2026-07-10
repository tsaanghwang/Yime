package runtimechange

import (
	"encoding/json"
	"errors"
	"fmt"
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
	SettingsRevision int64  `json:"settings_revision,omitempty"`
	LexiconRevision  int64  `json:"lexicon_revision,omitempty"`
	RedeployRevision int64  `json:"redeploy_revision,omitempty"`
	Scope            string `json:"scope,omitempty"`
	RequiresRedeploy bool   `json:"requires_redeploy,omitempty"`
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
	release, err := acquireNotificationLock(userDir)
	if err != nil {
		return Event{}, err
	}
	defer release()

	revision := time.Now().UnixNano()
	event, readErr := Read(userDir)
	if readErr == nil && event.Revision >= revision {
		revision = event.Revision + 1
	}
	if readErr != nil && !errors.Is(readErr, os.ErrNotExist) {
		backupPath := path + ".corrupt"
		_ = os.Remove(backupPath)
		if err := os.Rename(path, backupPath); err != nil {
			return Event{}, readErr
		}
		event = Event{}
	}
	event.Revision = revision
	event.Scope = ""
	event.RequiresRedeploy = false
	switch scope {
	case ScopeSettings:
		event.SettingsRevision = revision
	case ScopeLexicon:
		event.LexiconRevision = revision
	default:
		return Event{}, errors.New("未知的运行时变更范围")
	}
	if requiresRedeploy {
		event.RedeployRevision = revision
	}
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
	if err := replaceMarkerFile(tempPath, path); err != nil {
		return Event{}, err
	}
	return event, nil
}

func replaceMarkerFile(tempPath, path string) error {
	var lastErr error
	for i := 0; i < 50; i++ {
		if err := os.Rename(tempPath, path); err == nil {
			return nil
		} else {
			lastErr = err
		}
		time.Sleep(10 * time.Millisecond)
	}
	// Some Windows filesystems do not replace an existing destination with
	// os.Rename. Writers are serialized, and readers retry on the next request.
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return lastErr
	}
	return os.Rename(tempPath, path)
}

func acquireNotificationLock(userDir string) (func(), error) {
	lockPath := filepath.Join(userDir, ".yime-runtime-change.lock")
	deadline := time.Now().Add(5 * time.Second)
	for {
		file, err := os.OpenFile(lockPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
		if err == nil {
			token := fmt.Sprintf("%d-%d", os.Getpid(), time.Now().UnixNano())
			if _, writeErr := file.WriteString(token); writeErr != nil {
				file.Close()
				_ = os.Remove(lockPath)
				return nil, writeErr
			}
			if closeErr := file.Close(); closeErr != nil {
				_ = os.Remove(lockPath)
				return nil, closeErr
			}
			return func() {
				content, readErr := os.ReadFile(lockPath)
				if readErr == nil && string(content) == token {
					_ = os.Remove(lockPath)
				}
			}, nil
		}
		info, statErr := os.Stat(lockPath)
		if statErr == nil && time.Since(info.ModTime()) > 30*time.Second {
			_ = os.Remove(lockPath)
			continue
		}
		if statErr != nil && !errors.Is(statErr, os.ErrNotExist) && !os.IsPermission(statErr) {
			return nil, err
		}
		if time.Now().After(deadline) {
			return nil, errors.New("等待运行时变更锁超时")
		}
		time.Sleep(10 * time.Millisecond)
	}
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
	// Migrate markers written before per-scope revisions were introduced.
	if event.SettingsRevision == 0 && event.LexiconRevision == 0 && event.Revision > 0 {
		switch event.Scope {
		case ScopeSettings:
			event.SettingsRevision = event.Revision
		case ScopeLexicon:
			event.LexiconRevision = event.Revision
		}
		if event.RequiresRedeploy {
			event.RedeployRevision = event.Revision
		}
	}
	return event, nil
}
