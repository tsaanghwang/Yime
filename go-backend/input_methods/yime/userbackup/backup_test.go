package userbackup

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestCreateCapturesCompletePortableUserData(t *testing.T) {
	userDir := t.TempDir()
	writeTestFile(t, filepath.Join(userDir, "default.custom.yaml"), "patch:\n")
	writeTestFile(t, filepath.Join(userDir, "yime_user_phrases.txt"), "中国\n")
	writeTestFile(t, filepath.Join(userDir, "yime_blocklist.txt"), "测试\n")
	writeTestFile(t, filepath.Join(userDir, "user.userdb", "data.bin"), "userdb")
	writeTestFile(t, filepath.Join(userDir, "sync", "installation", "user.yaml"), "sync")
	writeTestFile(t, filepath.Join(userDir, "build", "compiled.bin"), "generated")
	writeTestFile(t, filepath.Join(userDir, "yime_runtime_change.json"), "{}")

	snapshot, err := Create(userDir, filepath.Join(t.TempDir(), "YIME 备份"), "用户数据", time.Date(2026, 7, 14, 12, 30, 0, 0, time.Local))
	if err != nil {
		t.Fatal(err)
	}
	for _, rel := range []string{
		"default.custom.yaml",
		"yime_user_phrases.txt",
		"yime_blocklist.txt",
		filepath.Join("sync", "installation", "user.yaml"),
	} {
		if _, err := os.Stat(filepath.Join(snapshot.Path, DataDirectory, rel)); err != nil {
			t.Fatalf("portable user data missing %s: %v", rel, err)
		}
	}
	for _, rel := range []string{filepath.Join("build", "compiled.bin"), filepath.Join("user.userdb", "data.bin"), "yime_runtime_change.json"} {
		if _, err := os.Stat(filepath.Join(snapshot.Path, DataDirectory, rel)); !os.IsNotExist(err) {
			t.Fatalf("generated or transient file must be excluded: %s", rel)
		}
	}
	if err := Validate(snapshot); err != nil {
		t.Fatalf("new backup must validate: %v", err)
	}
}

func TestLatestSelectsNewestValidSnapshot(t *testing.T) {
	userDir := t.TempDir()
	writeTestFile(t, filepath.Join(userDir, "user.yaml"), "old")
	root := t.TempDir()
	old, err := Create(userDir, root, "用户数据", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, filepath.Join(userDir, "user.yaml"), "new")
	newer, err := Create(userDir, root, "用户数据", time.Date(2026, 2, 1, 0, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, filepath.Join(root, "not-a-backup", "random.txt"), "ignored")

	latest, err := Latest(root)
	if err != nil {
		t.Fatal(err)
	}
	if latest.Path != newer.Path || latest.Path == old.Path {
		t.Fatalf("expected newest backup %q, got %q", newer.Path, latest.Path)
	}
}

func TestValidateRejectsTamperedBackupBeforeRestore(t *testing.T) {
	userDir := t.TempDir()
	writeTestFile(t, filepath.Join(userDir, "user.yaml"), "original")
	snapshot, err := Create(userDir, t.TempDir(), "用户数据", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, filepath.Join(snapshot.Path, DataDirectory, "user.yaml"), "tampered")
	if err := Validate(snapshot); err == nil {
		t.Fatal("tampered backup must be rejected")
	}
}

func TestRestoreOverlaysBackupAndLeavesGeneratedBuildForDeployer(t *testing.T) {
	backupSource := t.TempDir()
	writeTestFile(t, filepath.Join(backupSource, "default.custom.yaml"), "restored")
	writeTestFile(t, filepath.Join(backupSource, "sync", "installation", "user.userdb.txt"), "history")
	snapshot, err := Create(backupSource, t.TempDir(), "用户数据", time.Now())
	if err != nil {
		t.Fatal(err)
	}

	live := t.TempDir()
	writeTestFile(t, filepath.Join(live, "default.custom.yaml"), "current")
	writeTestFile(t, filepath.Join(live, "newer-version-file.txt"), "keep")
	writeTestFile(t, filepath.Join(live, "build", "stale.bin"), "stale")
	if err := Restore(snapshot, live); err != nil {
		t.Fatal(err)
	}
	assertTestFile(t, filepath.Join(live, "default.custom.yaml"), "restored")
	assertTestFile(t, filepath.Join(live, "sync", "installation", "user.userdb.txt"), "history")
	assertTestFile(t, filepath.Join(live, "newer-version-file.txt"), "keep")
	assertTestFile(t, filepath.Join(live, "build", "stale.bin"), "stale")
}

func writeTestFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func assertTestFile(t *testing.T, path, want string) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != want {
		t.Fatalf("%s: want %q, got %q", path, want, data)
	}
}
