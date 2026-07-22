package layoutdesigner

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/learningmigration"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/runtimechange"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userlexicon"
)

var generatedUserLexiconFiles = []string{
	"custom_phrase_full.txt",
	"custom_phrase_variable.txt",
	"custom_phrase_shorthand.txt",
}

// UserApplyResult describes a completed user-layout switch. The installed
// shared data remains read-only; generated overrides live in the Rime user dir.
type UserApplyResult struct {
	Plan       Plan
	Migrations []learningmigration.Report
}

// EffectiveDataDir returns the complete active user override when one exists,
// otherwise it returns the installed official shared data.
func EffectiveDataDir(sharedDir, userDir string) (string, error) {
	if completeGeneratedSet(userDir) {
		return filepath.Clean(userDir), nil
	}
	if completeGeneratedSet(sharedDir) {
		return filepath.Clean(sharedDir), nil
	}
	return "", fmt.Errorf("找不到完整的 Yime 布局数据：shared=%s user=%s", sharedDir, userDir)
}

func PreviewUser(sharedDir, userDir string, target Profile) (Plan, error) {
	sourceDir, err := EffectiveDataDir(sharedDir, userDir)
	if err != nil {
		return Plan{}, err
	}
	return Preview(sourceDir, target)
}

// ApplyUser regenerates a complete override, migrates learning data, builds
// Rime outside the IME process, and only then asks active sessions to reload.
// Failed builds restore the previous override set.
func ApplyUser(sharedDir, userDir string, target Profile) (UserApplyResult, error) {
	if strings.TrimSpace(sharedDir) == "" || strings.TrimSpace(userDir) == "" {
		return UserApplyResult{}, fmt.Errorf("共享目录和用户目录不能为空")
	}
	if filepath.Clean(sharedDir) == filepath.Clean(userDir) {
		return UserApplyResult{}, fmt.Errorf("用户布局不能写入共享数据目录")
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return UserApplyResult{}, err
	}
	lockPath := filepath.Join(userDir, ".yime-user-layout.lock")
	lock, err := os.OpenFile(lockPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return UserApplyResult{}, fmt.Errorf("已有布局切换任务正在运行: %w", err)
	}
	_ = lock.Close()
	defer os.Remove(lockPath)

	sourceDir, err := EffectiveDataDir(sharedDir, userDir)
	if err != nil {
		return UserApplyResult{}, err
	}
	plan, err := Preview(sourceDir, target)
	if err != nil || len(plan.ChangedIDs) == 0 {
		return UserApplyResult{Plan: plan}, err
	}
	stage, err := os.MkdirTemp(userDir, ".yime-user-layout-stage-")
	if err != nil {
		return UserApplyResult{}, err
	}
	defer os.RemoveAll(stage)
	if err := copyGeneratedSet(sourceDir, stage); err != nil {
		return UserApplyResult{}, err
	}
	generatedPlan, err := Apply(stage, target)
	if err != nil {
		return UserApplyResult{}, err
	}
	if err := userlexicon.RebuildAllRimeLexiconsTo(stage, userDir, stage); err != nil {
		return UserApplyResult{}, fmt.Errorf("按新布局重建用户词库: %w", err)
	}
	transitions, err := learningmigration.DetectTransitionsBetween(sourceDir, stage)
	if err != nil {
		return UserApplyResult{}, err
	}
	reports, err := learningmigration.MigrateAll(sharedDir, userDir, transitions)
	if err != nil {
		return UserApplyResult{}, err
	}

	installNames := append([]string(nil), generatedFiles...)
	for _, name := range generatedUserLexiconFiles {
		if info, statErr := os.Stat(filepath.Join(stage, name)); statErr == nil && !info.IsDir() && info.Size() > 0 {
			installNames = append(installNames, name)
		}
	}
	restore, commit, err := installUserSet(userDir, stage, installNames)
	if err != nil {
		return UserApplyResult{}, err
	}
	if err := buildUserRimeData(sharedDir, userDir); err != nil {
		restore()
		_ = buildUserRimeData(sharedDir, userDir)
		return UserApplyResult{}, err
	}
	if err := validateUserBuild(userDir); err != nil {
		restore()
		_ = buildUserRimeData(sharedDir, userDir)
		return UserApplyResult{}, err
	}
	commit()
	if _, err := runtimechange.Notify(userDir, runtimechange.ScopeRedeploy, true); err != nil {
		return UserApplyResult{}, fmt.Errorf("布局已构建，但通知输入会话刷新失败: %w", err)
	}
	return UserApplyResult{Plan: generatedPlan, Migrations: reports}, nil
}

func completeGeneratedSet(dir string) bool {
	if strings.TrimSpace(dir) == "" {
		return false
	}
	for _, name := range generatedFiles {
		info, err := os.Stat(filepath.Join(dir, name))
		if err != nil || info.IsDir() || info.Size() == 0 {
			return false
		}
	}
	return true
}

func copyGeneratedSet(source, target string) error {
	if err := os.MkdirAll(target, 0o755); err != nil {
		return err
	}
	for _, name := range generatedFiles {
		in, err := os.Open(filepath.Join(source, name))
		if err != nil {
			return err
		}
		out, err := os.Create(filepath.Join(target, name))
		if err == nil {
			_, err = io.Copy(out, in)
		}
		closeOutErr := error(nil)
		if out != nil {
			closeOutErr = out.Close()
		}
		_ = in.Close()
		if err != nil {
			return err
		}
		if closeOutErr != nil {
			return closeOutErr
		}
	}
	return nil
}

func installUserSet(userDir, stage string, names []string) (restore func(), commit func(), err error) {
	backup, err := os.MkdirTemp(userDir, ".yime-user-layout-backup-")
	if err != nil {
		return nil, nil, err
	}
	installed := []string{}
	backedUp := []string{}
	restoreFn := func() {
		for _, name := range installed {
			_ = os.Remove(filepath.Join(userDir, name))
		}
		for _, name := range backedUp {
			_ = os.Rename(filepath.Join(backup, name), filepath.Join(userDir, name))
		}
		_ = os.RemoveAll(backup)
	}
	for _, name := range names {
		dst := filepath.Join(userDir, name)
		if _, statErr := os.Stat(dst); statErr == nil {
			if renameErr := os.Rename(dst, filepath.Join(backup, name)); renameErr != nil {
				restoreFn()
				return nil, nil, renameErr
			}
			backedUp = append(backedUp, name)
		} else if !os.IsNotExist(statErr) {
			restoreFn()
			return nil, nil, statErr
		}
		if renameErr := os.Rename(filepath.Join(stage, name), dst); renameErr != nil {
			restoreFn()
			return nil, nil, renameErr
		}
		installed = append(installed, name)
	}
	return restoreFn, func() { _ = os.RemoveAll(backup) }, nil
}

func buildUserRimeData(sharedDir, userDir string) error {
	deployer := filepath.Join(filepath.Dir(sharedDir), "rime_deployer.exe")
	if info, err := os.Stat(deployer); err != nil || info.IsDir() {
		return fmt.Errorf("找不到 Rime 部署器: %s", deployer)
	}
	cmd := exec.Command(deployer, "--build", userDir, sharedDir, filepath.Join(userDir, "build"))
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("Rime 构建失败: %w: %s", err, strings.TrimSpace(string(output)))
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		schema := filepath.Join(userDir, "yime_"+mode+".schema.yaml")
		if _, err := os.Stat(schema); err != nil {
			schema = filepath.Join(sharedDir, "yime_"+mode+".schema.yaml")
		}
		compile := exec.Command(deployer, "--compile", schema, userDir, sharedDir, filepath.Join(userDir, "build"))
		if output, err := compile.CombinedOutput(); err != nil {
			return fmt.Errorf("Rime %s 方案编译失败: %w: %s", mode, err, strings.TrimSpace(string(output)))
		}
	}
	return nil
}

func validateUserBuild(userDir string) error {
	for _, mode := range []string{"full", "variable", "shorthand"} {
		path := filepath.Join(userDir, "build", "yime_"+mode+".schema.yaml")
		if info, err := os.Stat(path); err != nil || info.IsDir() || info.Size() == 0 {
			return fmt.Errorf("新布局没有生成有效方案: %s", path)
		}
	}
	return nil
}
