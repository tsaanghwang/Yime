package yime

import (
	"fmt"
	"path/filepath"
)

type toolActionType string

const (
	toolActionOpenPath      toolActionType = "open_path"
	toolActionRunPowerShell toolActionType = "run_powershell"
	toolActionRunExecutable toolActionType = "run_executable"
)

type toolHubEntry struct {
	ID               string         `json:"id"`
	Label            string         `json:"label"`
	Description      string         `json:"description,omitempty"`
	ActionType       toolActionType `json:"action_type"`
	TargetPath       string         `json:"target_path"`
	Arguments        []string       `json:"arguments,omitempty"`
	CloseAfterLaunch bool           `json:"close_after_launch,omitempty"`
}

type toolHubManifest struct {
	Title   string         `json:"title"`
	Summary string         `json:"summary"`
	Note    string         `json:"note"`
	Tools   []toolHubEntry `json:"tools"`
}

func buildToolHubManifest(sharedDir, userDir, helpDir, logDir, launcherPath, lexiconManagerScript, mode string) toolHubManifest {
	settingsToolScript := filepath.Join(userDir, "pime_yime_settings_tool.ps1")
	diagnosticsToolScript := filepath.Join(userDir, "pime_yime_diagnostics_tool.ps1")

	return toolHubManifest{
		Title:   "Yime Tool Hub",
		Summary: "Keep rich UI in standalone tools, and keep the language-bar callback path lightweight.",
		Note:    "Add future standalone settings or diagnostics programs by extending this tool manifest rather than expanding the TSF callback path.",
		Tools: []toolHubEntry{
			{
				ID:               "lexicon-manager",
				Label:            "用户词库管理",
				Description:      "Open the standalone lexicon manager dialog.",
				ActionType:       toolActionRunExecutable,
				TargetPath:       launcherPath,
				CloseAfterLaunch: true,
				Arguments: []string{
					"powershell-script",
					lexiconManagerScript,
					"-SharedDir", sharedDir,
					"-UserDir", userDir,
					"-Mode", mode,
				},
			},
			{
				ID:               "settings-tool",
				Label:            "设置工具",
				Description:      "Open the standalone settings shell.",
				ActionType:       toolActionRunExecutable,
				TargetPath:       launcherPath,
				CloseAfterLaunch: true,
				Arguments: []string{
					"powershell-script",
					settingsToolScript,
					"-UserDir", userDir,
					"-SharedDir", sharedDir,
					"-HelpDir", helpDir,
					"-LogDir", logDir,
				},
			},
			{
				ID:          "settings-data",
				Label:       "设置与用户目录",
				Description: "Open the Yime user data directory.",
				ActionType:  toolActionOpenPath,
				TargetPath:  userDir,
			},
			{
				ID:          "shared-data",
				Label:       "共享数据目录",
				Description: "Open the installed shared runtime data.",
				ActionType:  toolActionOpenPath,
				TargetPath:  sharedDir,
			},
			{
				ID:               "diagnostics-tool",
				Label:            "诊断工具",
				Description:      "Open the standalone diagnostics shell.",
				ActionType:       toolActionRunExecutable,
				TargetPath:       launcherPath,
				CloseAfterLaunch: true,
				Arguments: []string{
					"powershell-script",
					diagnosticsToolScript,
					"-UserDir", userDir,
					"-SharedDir", sharedDir,
					"-HelpDir", helpDir,
					"-LogDir", logDir,
				},
			},
			{
				ID:          "diagnostics-guide",
				Label:       "诊断说明",
				Description: "Open the diagnostics guide for this input method.",
				ActionType:  toolActionOpenPath,
				TargetPath:  filepath.Join(helpDir, "diagnostics.md"),
			},
			{
				ID:          "diagnostics-logs",
				Label:       "诊断日志目录",
				Description: "Open the PIME log directory.",
				ActionType:  toolActionOpenPath,
				TargetPath:  logDir,
			},
			{
				ID:          "settings-guide",
				Label:       "设置说明",
				Description: "Open the settings and data guide.",
				ActionType:  toolActionOpenPath,
				TargetPath:  filepath.Join(helpDir, "settings-and-data.md"),
			},
			{
				ID:          "help-readme",
				Label:       "查看帮助",
				Description: "Open the main help document.",
				ActionType:  toolActionOpenPath,
				TargetPath:  filepath.Join(helpDir, "README.md"),
			},
			{
				ID:          "help-trial-feedback",
				Label:       "试用反馈说明",
				Description: "Open the trial feedback guide.",
				ActionType:  toolActionOpenPath,
				TargetPath:  filepath.Join(helpDir, "trial-feedback.md"),
			},
		},
	}
}

func validateToolHubManifest(manifest toolHubManifest) error {
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
