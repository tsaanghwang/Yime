package userbackup

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const (
	ManifestFileName = "yime-backup.json"
	DataDirectory    = "data"
	manifestFormat   = "yime-user-data-backup"
	manifestVersion  = 1
)

type FileRecord struct {
	Path   string `json:"path"`
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256"`
}

type Manifest struct {
	Format    string       `json:"format"`
	Version   int          `json:"version"`
	Purpose   string       `json:"purpose"`
	CreatedAt time.Time    `json:"created_at"`
	Files     []FileRecord `json:"files"`
}

type Snapshot struct {
	Path     string
	Manifest Manifest
}

// Create stores portable user data while omitting generated build output,
// transient runtime files, and live LevelDB *.userdb directories. The latter
// are locked by Rime and cannot be copied consistently while the IME is active;
// portable Rime snapshots under sync remain part of the backup.
func Create(userDir, backupRoot, label string, now time.Time) (Snapshot, error) {
	if strings.TrimSpace(userDir) == "" || strings.TrimSpace(backupRoot) == "" {
		return Snapshot{}, errors.New("用户目录或备份目录为空")
	}
	if label == "" {
		label = "用户数据"
	}
	if err := os.MkdirAll(backupRoot, 0o755); err != nil {
		return Snapshot{}, err
	}
	tempDir, err := os.MkdirTemp(backupRoot, ".yime-backup-creating-")
	if err != nil {
		return Snapshot{}, err
	}
	defer os.RemoveAll(tempDir)
	dataDir := filepath.Join(tempDir, DataDirectory)
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return Snapshot{}, err
	}

	purpose := "manual"
	if label == "恢复前" {
		purpose = "pre-restore-safety"
	}
	manifest := Manifest{Format: manifestFormat, Version: manifestVersion, Purpose: purpose, CreatedAt: now.UTC()}
	err = filepath.WalkDir(userDir, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		rel, err := filepath.Rel(userDir, path)
		if err != nil || rel == "." {
			return err
		}
		if shouldExclude(rel) {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("备份中不允许符号链接：%s", rel)
		}
		target := filepath.Join(dataDir, rel)
		if entry.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if !info.Mode().IsRegular() {
			return nil
		}
		record, err := copyAndHash(path, target, info.Mode().Perm())
		if err != nil {
			return err
		}
		record.Path = filepath.ToSlash(rel)
		manifest.Files = append(manifest.Files, record)
		return nil
	})
	if err != nil {
		return Snapshot{}, err
	}
	sort.Slice(manifest.Files, func(i, j int) bool { return manifest.Files[i].Path < manifest.Files[j].Path })
	payload, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return Snapshot{}, err
	}
	if err := os.WriteFile(filepath.Join(tempDir, ManifestFileName), append(payload, '\n'), 0o644); err != nil {
		return Snapshot{}, err
	}

	base := fmt.Sprintf("YIME-%s-%s", sanitizeLabel(label), now.Format("20060102-150405"))
	finalDir := uniqueDirectory(filepath.Join(backupRoot, base))
	if err := os.Rename(tempDir, finalDir); err != nil {
		return Snapshot{}, err
	}
	return Snapshot{Path: finalDir, Manifest: manifest}, nil
}

func Latest(backupRoot string) (Snapshot, error) {
	entries, err := os.ReadDir(backupRoot)
	if err != nil {
		return Snapshot{}, err
	}
	var snapshots []Snapshot
	for _, entry := range entries {
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
			continue
		}
		snapshot, err := Load(filepath.Join(backupRoot, entry.Name()))
		if err == nil && snapshot.Manifest.Purpose != "pre-restore-safety" {
			snapshots = append(snapshots, snapshot)
		}
	}
	if len(snapshots) == 0 {
		return Snapshot{}, errors.New("没有找到有效的 YIME 用户数据备份")
	}
	sort.Slice(snapshots, func(i, j int) bool {
		return snapshots[i].Manifest.CreatedAt.After(snapshots[j].Manifest.CreatedAt)
	})
	return snapshots[0], nil
}

func Load(snapshotDir string) (Snapshot, error) {
	payload, err := os.ReadFile(filepath.Join(snapshotDir, ManifestFileName))
	if err != nil {
		return Snapshot{}, err
	}
	var manifest Manifest
	if err := json.Unmarshal(payload, &manifest); err != nil {
		return Snapshot{}, err
	}
	if manifest.Format != manifestFormat || manifest.Version != manifestVersion {
		return Snapshot{}, errors.New("不是当前版本支持的 YIME 用户数据备份")
	}
	return Snapshot{Path: snapshotDir, Manifest: manifest}, nil
}

// Validate verifies every relative path, size, and SHA-256 digest before any
// restore operation is allowed to modify the live user directory.
func Validate(snapshot Snapshot) error {
	seen := make(map[string]bool, len(snapshot.Manifest.Files))
	for _, record := range snapshot.Manifest.Files {
		rel, err := safeRelativePath(record.Path)
		if err != nil {
			return err
		}
		if seen[rel] {
			return fmt.Errorf("备份清单包含重复文件：%s", record.Path)
		}
		seen[rel] = true
		path := filepath.Join(snapshot.Path, DataDirectory, rel)
		info, err := os.Stat(path)
		if err != nil {
			return fmt.Errorf("备份文件缺失：%s: %w", record.Path, err)
		}
		if !info.Mode().IsRegular() || info.Size() != record.Size {
			return fmt.Errorf("备份文件大小不匹配：%s", record.Path)
		}
		digest, err := fileDigest(path)
		if err != nil {
			return err
		}
		if !strings.EqualFold(digest, record.SHA256) {
			return fmt.Errorf("备份文件校验失败：%s", record.Path)
		}
	}
	return nil
}

// Restore overlays the validated portable source data. Existing user files not
// represented in an older backup are retained to avoid destructive loss across
// YIME versions. In particular, the generated build directory is left in place:
// an active Rime session keeps compiled prism files open on Windows, and the
// normal deployer is responsible for updating them after source restoration.
func Restore(snapshot Snapshot, userDir string) error {
	if err := Validate(snapshot); err != nil {
		return err
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return err
	}
	for _, record := range snapshot.Manifest.Files {
		rel, _ := safeRelativePath(record.Path)
		source := filepath.Join(snapshot.Path, DataDirectory, rel)
		target := filepath.Join(userDir, rel)
		if err := copyAtomically(source, target); err != nil {
			return fmt.Errorf("恢复 %s 失败：%w", record.Path, err)
		}
	}
	return nil
}

func shouldExclude(rel string) bool {
	clean := filepath.Clean(rel)
	parts := strings.Split(clean, string(filepath.Separator))
	first := parts[0]
	if strings.EqualFold(first, "build") {
		return true
	}
	for _, part := range parts {
		if strings.HasSuffix(strings.ToLower(part), ".userdb") {
			return true
		}
	}
	base := filepath.Base(clean)
	return strings.EqualFold(base, "yime_runtime_change.json") ||
		strings.EqualFold(base, ".yime-runtime-change.lock") ||
		strings.HasPrefix(strings.ToLower(base), ".yime-runtime-change-")
}

func safeRelativePath(value string) (string, error) {
	value = filepath.FromSlash(value)
	clean := filepath.Clean(value)
	if value == "" || clean == "." || filepath.IsAbs(clean) || clean == ".." || strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("备份包含不安全路径：%s", value)
	}
	return clean, nil
}

func copyAndHash(source, target string, mode os.FileMode) (FileRecord, error) {
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return FileRecord{}, err
	}
	in, err := os.Open(source)
	if err != nil {
		return FileRecord{}, err
	}
	defer in.Close()
	out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return FileRecord{}, err
	}
	hash := sha256.New()
	size, copyErr := io.Copy(io.MultiWriter(out, hash), in)
	closeErr := out.Close()
	if copyErr != nil {
		return FileRecord{}, copyErr
	}
	if closeErr != nil {
		return FileRecord{}, closeErr
	}
	return FileRecord{Size: size, SHA256: hex.EncodeToString(hash.Sum(nil))}, nil
}

func copyAtomically(source, target string) error {
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	temp, err := os.CreateTemp(filepath.Dir(target), ".yime-restore-*.tmp")
	if err != nil {
		return err
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath)
	in, err := os.Open(source)
	if err != nil {
		temp.Close()
		return err
	}
	_, copyErr := io.Copy(temp, in)
	closeInErr := in.Close()
	closeOutErr := temp.Close()
	if copyErr != nil {
		return copyErr
	}
	if closeInErr != nil {
		return closeInErr
	}
	if closeOutErr != nil {
		return closeOutErr
	}
	if err := os.Rename(tempPath, target); err == nil {
		return nil
	}
	if err := os.Remove(target); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return os.Rename(tempPath, target)
}

func fileDigest(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func sanitizeLabel(label string) string {
	replacer := strings.NewReplacer("\\", "-", "/", "-", ":", "-", "*", "-", "?", "-", "\"", "-", "<", "-", ">", "-", "|", "-")
	return strings.Trim(replacer.Replace(label), " .-")
}

func uniqueDirectory(path string) string {
	if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) {
		return path
	}
	for index := 2; ; index++ {
		candidate := fmt.Sprintf("%s-%d", path, index)
		if _, err := os.Stat(candidate); errors.Is(err, os.ErrNotExist) {
			return candidate
		}
	}
}
