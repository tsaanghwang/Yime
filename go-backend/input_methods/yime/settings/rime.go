package settings

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func FindDeployerPath(sharedDir string) string {
	for _, candidate := range deployerCandidates(sharedDir) {
		if candidate == "" {
			continue
		}
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return ""
}

func InvokeRimeBuild(userDir, sharedDir string) error {
	deployer := FindDeployerPath(sharedDir)
	if deployer == "" {
		return fmt.Errorf("当前运行环境未找到 rime_deployer.exe")
	}
	buildDir := filepath.Join(userDir, "build")
	cmd := exec.Command(deployer, "--build", userDir, sharedDir, buildDir)
	output, err := cmd.CombinedOutput()
	if err != nil {
		detail := strings.TrimSpace(string(output))
		if detail == "" {
			detail = "无输出。若 PIME 正在运行，请先退出托盘中的 PIME，再点【应用并重建】。"
		}
		return fmt.Errorf("rime_deployer.exe 失败: %w\n%s", err, detail)
	}
	return nil
}

func deployerCandidates(sharedDir string) []string {
	candidates := []string{}
	if sharedDir != "" {
		candidates = append(candidates, filepath.Join(installRootFromShared(sharedDir), "rime_deployer.exe"))
		candidates = append(candidates, filepath.Join(filepath.Dir(sharedDir), "rime_deployer.exe"))
	}
	candidates = append(candidates, `C:\dev\librime\build\bin\Release\rime_deployer.exe`)
	return candidates
}

func installRootFromShared(sharedDir string) string {
	if sharedDir == "" {
		return ""
	}
	return filepath.Clean(filepath.Join(sharedDir, "..", "..", ".."))
}
