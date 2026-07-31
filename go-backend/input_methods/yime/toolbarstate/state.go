package toolbarstate

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"time"
)

const (
	FileName      = "yime_input_toolbar_state.json"
	FormatVersion = 1
)

// State is the small, process-independent contract shared by the Yime backend
// and input-toolbar.exe. Boolean fields are explicit target values, never
// context-dependent "toggle" commands, so all active editor sessions converge.
type State struct {
	Version            int      `json:"version"`
	Revision           int64    `json:"revision"`
	UpdatedAt          string   `json:"updated_at,omitempty"`
	Source             string   `json:"source,omitempty"`
	ASCII              bool     `json:"ascii_mode"`
	FullShape          bool     `json:"full_shape"`
	ASCIIPunctuation   bool     `json:"ascii_punctuation"`
	Traditionalization bool     `json:"traditionalization"`
	SchemaID           string   `json:"schema_id,omitempty"`
	Vertical           bool     `json:"toolbar_vertical,omitempty"`
	OrientationSet     bool     `json:"toolbar_orientation_set,omitempty"`
	HiddenButtons      []string `json:"toolbar_hidden_buttons,omitempty"`
}

func Path(userDir string) string {
	if userDir == "" {
		return ""
	}
	return filepath.Join(userDir, FileName)
}

func Read(path string) (State, error) {
	if path == "" {
		return State{}, errors.New("工具栏状态路径为空")
	}
	payload, err := os.ReadFile(path)
	if err != nil {
		return State{}, err
	}
	var state State
	if err := json.Unmarshal(payload, &state); err != nil {
		return State{}, err
	}
	if state.Version != FormatVersion {
		return State{}, errors.New("不支持的工具栏状态版本")
	}
	return state, nil
}

// Update serializes writers from the backend and toolbar, then atomically
// replaces the state file. The revision only advances when update reports a
// material change.
func Update(path string, source string, update func(*State) bool) (State, error) {
	if path == "" {
		return State{}, errors.New("工具栏状态路径为空")
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return State{}, err
	}
	release, err := acquireLock(path)
	if err != nil {
		return State{}, err
	}
	defer release()

	state, err := Read(path)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return State{}, err
		}
		state = State{Version: FormatVersion}
	}
	if !update(&state) {
		return state, nil
	}
	now := time.Now()
	revision := now.UnixNano()
	if revision <= state.Revision {
		revision = state.Revision + 1
	}
	state.Version = FormatVersion
	state.Revision = revision
	state.UpdatedAt = now.UTC().Format(time.RFC3339Nano)
	state.Source = source

	payload, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return State{}, err
	}
	temp, err := os.CreateTemp(dir, ".yime-input-toolbar-*.tmp")
	if err != nil {
		return State{}, err
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath)
	if _, err := temp.Write(append(payload, '\n')); err != nil {
		temp.Close()
		return State{}, err
	}
	if err := temp.Close(); err != nil {
		return State{}, err
	}
	if err := replaceFile(tempPath, path); err != nil {
		return State{}, err
	}
	return state, nil
}

func acquireLock(path string) (func(), error) {
	lockPath := path + ".lock"
	deadline := time.Now().Add(3 * time.Second)
	for {
		file, err := os.OpenFile(lockPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
		if err == nil {
			token := []byte(time.Now().UTC().Format(time.RFC3339Nano))
			if _, writeErr := file.Write(token); writeErr != nil {
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
				if readErr == nil && string(content) == string(token) {
					_ = os.Remove(lockPath)
				}
			}, nil
		}
		if info, statErr := os.Stat(lockPath); statErr == nil &&
			time.Since(info.ModTime()) > 30*time.Second {
			_ = os.Remove(lockPath)
			continue
		}
		if time.Now().After(deadline) {
			return nil, errors.New("等待工具栏状态锁超时")
		}
		time.Sleep(10 * time.Millisecond)
	}
}
