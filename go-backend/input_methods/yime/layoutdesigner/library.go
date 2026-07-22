package layoutdesigner

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const UserLayoutDirectoryName = "yime_layouts"

type StoredProfile struct {
	Path    string
	Profile Profile
}

func UserLayoutDirectory(userDir string) string {
	return filepath.Join(userDir, UserLayoutDirectoryName)
}

func ListStoredProfiles(userDir string) ([]StoredProfile, error) {
	dir := UserLayoutDirectory(userDir)
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	result := []StoredProfile{}
	for _, entry := range entries {
		if entry.IsDir() || strings.EqualFold(entry.Name(), "auto-draft.json") || !strings.HasSuffix(strings.ToLower(entry.Name()), ".json") {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		profile, loadErr := LoadProfile(path)
		if loadErr != nil {
			continue
		}
		result = append(result, StoredProfile{Path: path, Profile: profile})
	}
	sort.Slice(result, func(i, j int) bool {
		return strings.ToLower(result[i].Profile.Name) < strings.ToLower(result[j].Profile.Name)
	})
	return result, nil
}

func SaveStoredProfile(userDir string, profile Profile) (string, error) {
	profile.Name = strings.TrimSpace(profile.Name)
	if profile.Name == "" {
		return "", fmt.Errorf("方案名称不能为空")
	}
	if err := profile.Validate(); err != nil {
		return "", err
	}
	sum := sha256.Sum256([]byte(strings.ToLower(profile.Name)))
	name := "layout-" + hex.EncodeToString(sum[:6]) + ".json"
	path := filepath.Join(UserLayoutDirectory(userDir), name)
	return path, WriteProfileAtomic(path, profile)
}

func DeleteStoredProfile(path, userDir string) error {
	root, err := filepath.Abs(UserLayoutDirectory(userDir))
	if err != nil {
		return err
	}
	target, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	rel, err := filepath.Rel(root, target)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return fmt.Errorf("方案不在用户布局目录中")
	}
	return os.Remove(target)
}
