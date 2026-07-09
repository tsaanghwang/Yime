package yime

import (
	"fmt"
	"path/filepath"
)

type toolActionType string

const (
	toolActionOpenPath      toolActionType = "open_path"
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

// buildToolHubManifest assembles the native tool hub menu.
//
// Summary and Note are intentionally omitted from the UI. Developer-facing hints
// are kept here as comments only:
//   - The hub launches standalone Win32 tools instead of running inside language-bar callbacks.
//   - Opening a subtool keeps the hub window open for quick re-selection.
func buildToolHubManifest(sharedDir, userDir, helpDir, logDir, lexiconManagerPath, reverseLookupToolPath, systemLexiconAuditPath, blocklistManagerPath, settingsToolPath, diagnosticsToolPath, mode string) toolHubManifest {

	return toolHubManifest{
		Title:   "Yime 工具箱",
		Summary: "",
		Note:    "",
		Tools: []toolHubEntry{
			{
				ID:          "lexicon-manager",
				Label:       "词库管理",
				Description: "打开词库管理器，添加、删除、导入个人词条。",
				ActionType:  toolActionRunExecutable,
				TargetPath:  lexiconManagerPath,
				Arguments: []string{
					"-SharedDir", sharedDir,
					"-UserDir", userDir,
					"-Mode", mode,
				},
			},
			{
				ID:          "reverse-lookup-tool",
				Label:       "反查编码",
				Description: "打开反查编码工具，查询字词的拼音和音元编码。",
				ActionType:  toolActionRunExecutable,
				TargetPath:  reverseLookupToolPath,
				Arguments: []string{
					"-SharedDir", sharedDir,
					"-UserDir", userDir,
					"-Mode", mode,
				},
			},
			{
				ID:          "system-lexicon-audit",
				Label:       "系统词库审查",
				Description: "只读扫描已安装系统词库，列出疑似不合理词条并导出报告。",
				ActionType:  toolActionRunExecutable,
				TargetPath:  systemLexiconAuditPath,
				Arguments: []string{
					"-SharedDir", sharedDir,
					"-UserDir", userDir,
					"-Mode", mode,
				},
			},
			{
				ID:          "user-blocklist-manager",
				Label:       "用户屏蔽词表",
				Description: "管理个人屏蔽词表，被屏蔽的词条不会出现在输入候选中。",
				ActionType:  toolActionRunExecutable,
				TargetPath:  blocklistManagerPath,
				Arguments: []string{
					"-UserDir", userDir,
				},
			},
			{
				ID:          "settings-tool",
				Label:       "设置工具",
				Description: "打开设置工具，修改方案、候选项数等配置。",
				ActionType:  toolActionRunExecutable,
				TargetPath:  settingsToolPath,
				Arguments: []string{
					"-UserDir", userDir,
					"-SharedDir", sharedDir,
					"-HelpDir", helpDir,
					"-LogDir", logDir,
				},
			},
			{
				ID:          "diagnostics-tool",
				Label:       "诊断工具",
				Description: "打开诊断工具，收集系统信息和运行状态。",
				ActionType:  toolActionRunExecutable,
				TargetPath:  diagnosticsToolPath,
				Arguments: []string{
					"-UserDir", userDir,
					"-SharedDir", sharedDir,
					"-HelpDir", helpDir,
					"-LogDir", logDir,
				},
			},
			{
				ID:          "settings-data",
				Label:       "用户数据目录",
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
				ID:          "help-readme",
				Label:       "查看帮助",
				Description: "打开主帮助文档。",
				ActionType:  toolActionOpenPath,
				TargetPath:  filepath.Join(helpDir, "README.html"),
			},
			{
				ID:          "help-trial-feedback",
				Label:       "反馈说明",
				Description: "打开反馈说明文档。",
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
