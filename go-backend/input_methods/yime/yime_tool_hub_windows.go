//go:build windows

package yime

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

func (ime *IME) openToolHub() error {
	manifestPath, err := ime.ensureToolHubManifest()
	if err != nil {
		return err
	}
	toolPath := ime.toolHubPath()
	if toolPath == "" {
		return os.ErrNotExist
	}
	return startDetachedExecutable(
		toolPath,
		"-ManifestPath", manifestPath,
	)
}

func (ime *IME) ensureToolHubManifest() (string, error) {
	userDir := ime.userDir()
	sharedDir := ime.sharedDir()
	helpDir := ime.helpDir()
	if userDir == "" || sharedDir == "" || helpDir == "" {
		return "", os.ErrNotExist
	}
	lexiconManagerPath := ime.lexiconManagerToolPath()
	reverseLookupToolPath := ime.reverseLookupToolPath()
	systemLexiconAuditPath := ime.systemLexiconAuditToolPath()
	blocklistManagerPath := ime.blocklistManagerToolPath()
	settingsToolPath := ime.settingsToolPath()
	diagnosticsToolPath := ime.diagnosticsToolPath()
	layoutDesignerPath := ime.layoutDesignerToolPath()
	if lexiconManagerPath == "" || reverseLookupToolPath == "" || systemLexiconAuditPath == "" || blocklistManagerPath == "" || settingsToolPath == "" || diagnosticsToolPath == "" || layoutDesignerPath == "" {
		return "", os.ErrNotExist
	}
	for _, toolPath := range []string{lexiconManagerPath, reverseLookupToolPath, systemLexiconAuditPath, blocklistManagerPath, settingsToolPath, diagnosticsToolPath, layoutDesignerPath} {
		if _, err := os.Stat(toolPath); err != nil {
			return "", fmt.Errorf("missing native tool executable: %s", toolPath)
		}
	}
	manifest := buildToolHubManifest(
		sharedDir,
		userDir,
		helpDir,
		filepath.Join(os.Getenv("LOCALAPPDATA"), "PIME", "Logs"),
		lexiconManagerPath,
		reverseLookupToolPath,
		systemLexiconAuditPath,
		blocklistManagerPath,
		settingsToolPath,
		diagnosticsToolPath,
		layoutDesignerPath,
		ime.currentYimeMode(),
	)
	if err := validateToolHubManifest(manifest); err != nil {
		return "", err
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return "", err
	}
	manifestPath := filepath.Join(userDir, "pime_yime_tool_hub.json")
	payload, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(manifestPath, payload, 0o644); err != nil {
		return "", err
	}
	return manifestPath, nil
}

func (ime *IME) toolHubPath() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepathJoinExecutableDir(exePath, "tool-hub.exe")
}

func filepathJoinExecutableDir(exePath, name string) string {
	return filepath.Join(filepath.Dir(exePath), name)
}
