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

func buildToolHubManifest(sharedDir, userDir, helpDir, logDir, lexiconManagerScript, reverseLookupToolScript, settingsToolScript, diagnosticsToolScript, mode string) toolHubManifest {

	return toolHubManifest{
		Title:   "Yime 工具箱",
		Summary: "独立工具界面，不影响语言栏轻量回调路径。",
		Note:    "扩展工具时请修改此清单，而非扩展 TSF 回调路径。",
		Tools: []toolHubEntry{
			{
				ID:               "lexicon-manager",
				Label:            "用户词库管理",
				Description:      "打开词库管理器，添加、删除、导入词条。",
				ActionType:       toolActionRunPowerShell,
				TargetPath:       lexiconManagerScript,
				CloseAfterLaunch: true,
				Arguments: []string{
					"-SharedDir", sharedDir,
					"-UserDir", userDir,
					"-Mode", mode,
				},
			},
			{
				ID:               "reverse-lookup-tool",
				Label:            "反查编码",
				Description:      "打开反查编码工具，查询字词的拼音和音元编码。",
				ActionType:       toolActionRunPowerShell,
				TargetPath:       reverseLookupToolScript,
				CloseAfterLaunch: true,
				Arguments: []string{
					"-SharedDir", sharedDir,
					"-UserDir", userDir,
					"-Mode", mode,
				},
			},
			{
				ID:               "settings-tool",
				Label:            "设置工具",
				Description:      "打开设置工具，修改方案、候选项数等配置。",
				ActionType:       toolActionRunPowerShell,
				TargetPath:       settingsToolScript,
				CloseAfterLaunch: true,
				Arguments: []string{
					"-UserDir", userDir,
					"-SharedDir", sharedDir,
					"-HelpDir", helpDir,
					"-LogDir", logDir,
				},
			},
			{
				ID:          "settings-data",
				Label:       "设置与用户目录",
				Description: "打开 Yime 用户数据目录。",
				ActionType:  toolActionOpenPath,
				TargetPath:  userDir,
			},
			{
				ID:          "shared-data",
				Label:       "共享数据目录",
				Description: "打开已安装的共享运行时数据目录。",
				ActionType:  toolActionOpenPath,
				TargetPath:  sharedDir,
			},
			{
				ID:               "diagnostics-tool",
				Label:            "诊断工具",
				Description:      "打开诊断工具，收集系统信息和运行状态。",
				ActionType:       toolActionRunPowerShell,
				TargetPath:       diagnosticsToolScript,
				CloseAfterLaunch: true,
				Arguments: []string{
					"-UserDir", userDir,
					"-SharedDir", sharedDir,
					"-HelpDir", helpDir,
					"-LogDir", logDir,
				},
			},
			{
				ID:          "diagnostics-guide",
				Label:       "诊断说明",
				Description: "打开诊断说明文档。",
				ActionType:  toolActionOpenPath,
				TargetPath:  filepath.Join(helpDir, "diagnostics.html"),
			},
			{
				ID:          "diagnostics-logs",
				Label:       "诊断日志目录",
				Description: "打开 PIME 日志目录。",
				ActionType:  toolActionOpenPath,
				TargetPath:  logDir,
			},
			{
				ID:          "settings-guide",
				Label:       "设置说明",
				Description: "打开设置与数据说明文档。",
				ActionType:  toolActionOpenPath,
				TargetPath:  filepath.Join(helpDir, "settings-and-data.html"),
			},
			{
				ID:          "help-readme",
				Label:       "查看帮助",
				Description: "打开主帮助文档。",
				ActionType:  toolActionOpenPath,
				TargetPath:  filepath.Join(helpDir, "README.html"),
			},
			{
				ID:          "help-trial-feedback",
				Label:       "试用反馈说明",
				Description: "打开试用反馈说明文档。",
				ActionType:  toolActionOpenPath,
				TargetPath:  filepath.Join(helpDir, "trial-feedback.html"),
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
