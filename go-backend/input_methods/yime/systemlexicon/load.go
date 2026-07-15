package systemlexicon

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

// Entry is one row from a Rime dict.yaml data section.
type Entry struct {
	Text   string
	Code   string
	Weight int
}

func DictPath(sharedDir, userDir string, mode reverselookup.Mode) string {
	schemaID := reverselookup.SchemaIDFromMode(mode)
	candidates := []string{
		filepath.Join(sharedDir, schemaID+".dict.yaml"),
	}
	if userDir != "" {
		candidates = append(candidates, filepath.Join(userDir, schemaID+".dict.yaml"))
	}
	for _, candidate := range candidates {
		if info, err := os.Stat(candidate); err == nil && info.Size() > 0 {
			return candidate
		}
	}
	if len(candidates) > 0 {
		return candidates[0]
	}
	return ""
}

func LoadDictFile(path string) ([]Entry, error) {
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("找不到系统词库文件：%s", path)
		}
		return nil, err
	}
	defer file.Close()

	entries := make([]Entry, 0, 4096)
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	inData := false
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !inData {
			if line == "..." {
				inData = true
			}
			continue
		}
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			continue
		}
		text := strings.TrimSpace(fields[0])
		code := strings.TrimSpace(fields[1])
		if text == "" || code == "" {
			continue
		}
		weight := 0
		if len(fields) >= 3 {
			if parsed, err := strconv.Atoi(strings.TrimSpace(fields[2])); err == nil {
				weight = parsed
			}
		}
		entries = append(entries, Entry{
			Text:   text,
			Code:   code,
			Weight: weight,
		})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return entries, nil
}
