package toolhub

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

// ActionType describes how a tool hub entry should be launched.
type ActionType string

const (
	ActionOpenPath      ActionType = "open_path"
	ActionRunPowerShell ActionType = "run_powershell"
	ActionRunExecutable ActionType = "run_executable"
)

// Entry is one tool hub manifest item.
type Entry struct {
	ID               string     `json:"id"`
	Label            string     `json:"label"`
	Description      string     `json:"description,omitempty"`
	ActionType       ActionType `json:"action_type"`
	TargetPath       string     `json:"target_path"`
	Arguments        []string   `json:"arguments,omitempty"`
	CloseAfterLaunch bool       `json:"close_after_launch,omitempty"`
}

// Manifest is the tool hub JSON payload.
type Manifest struct {
	Title   string  `json:"title"`
	Summary string  `json:"summary"`
	Note    string  `json:"note"`
	Tools   []Entry `json:"tools"`
}

// Validate checks manifest invariants.
func Validate(manifest Manifest) error {
	if manifest.Title == "" {
		return fmt.Errorf("tool hub title is required")
	}
	if len(manifest.Tools) == 0 {
		return fmt.Errorf("tool hub must contain at least one tool entry")
	}
	seenIDs := map[string]struct{}{}
	for _, tool := range manifest.Tools {
		if tool.ID == "" || tool.Label == "" {
			return fmt.Errorf("tool hub entry requires id and label")
		}
		if _, ok := seenIDs[tool.ID]; ok {
			return fmt.Errorf("tool hub entry %q is duplicated", tool.ID)
		}
		seenIDs[tool.ID] = struct{}{}
		if tool.TargetPath == "" {
			return fmt.Errorf("tool %q requires a target path", tool.ID)
		}
	}
	return nil
}

// Invoke launches one manifest entry. The returned bool indicates whether the hub should close.
func Invoke(entry Entry) (bool, error) {
	if strings.TrimSpace(entry.TargetPath) == "" {
		return false, fmt.Errorf("tool target path is empty: %s", entry.ID)
	}
	switch entry.ActionType {
	case ActionOpenPath:
		if _, err := os.Stat(entry.TargetPath); err != nil {
			return false, fmt.Errorf("missing target: %s", entry.TargetPath)
		}
		if err := shellExecute(entry.TargetPath, "", swShowNormal); err != nil {
			return false, err
		}
		return false, nil
	case ActionRunPowerShell:
		return false, fmt.Errorf("工具 %q 仍使用已废弃的 PowerShell 启动方式，请重新编译并安装 Yime 后从语言栏重新打开工具箱", entry.ID)
	case ActionRunExecutable:
		if _, err := os.Stat(entry.TargetPath); err != nil {
			return false, fmt.Errorf("missing executable: %s", entry.TargetPath)
		}
		if err := win32ui.StartDetachedGUIExecutable(entry.TargetPath, entry.Arguments...); err != nil {
			return false, err
		}
		return entry.CloseAfterLaunch, nil
	default:
		return false, fmt.Errorf("unknown tool action: %s", entry.ActionType)
	}
}

// ExecutableDir returns the directory containing an executable path.
func ExecutableDir(exePath string) string {
	if exePath == "" {
		return ""
	}
	return filepath.Dir(exePath)
}
