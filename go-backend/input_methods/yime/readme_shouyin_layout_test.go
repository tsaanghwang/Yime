package yime

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadmeShouyinTablesMatchRuntimeLayout(t *testing.T) {
	expected := runtimeShouyinLayout(t)
	tests := []struct {
		path    string
		heading string
	}{
		{filepath.Join("..", "..", "..", "README.zh-CN.md"), "### 首音→键盘映射"},
		{filepath.Join("..", "..", "..", "README.md"), "### Shouyin → key mapping"},
	}
	for _, test := range tests {
		t.Run(filepath.Base(test.path), func(t *testing.T) {
			got := readShouyinTable(t, test.path, test.heading)
			if len(got) != len(expected) {
				t.Fatalf("documented %d shouyin mappings, want %d: %#v", len(got), len(expected), got)
			}
			for label, wantKey := range expected {
				if gotKey := got[label]; gotKey != wantKey {
					t.Errorf("shouyin %q uses key %q in README, want runtime key %q", label, gotKey, wantKey)
				}
			}
		})
	}
}

func runtimeShouyinLayout(t *testing.T) map[string]string {
	t.Helper()
	layoutPayload, err := os.ReadFile(filepath.Join("data", "yime_yinyuan_layout.json"))
	if err != nil {
		t.Fatal(err)
	}
	var layout struct {
		YinyuanIDToKey map[string]string `json:"yinyuan_id_to_key"`
	}
	if err := json.Unmarshal(layoutPayload, &layout); err != nil {
		t.Fatal(err)
	}

	catalogPayload, err := os.ReadFile(filepath.Join("data", "trainer", "yinyuan_catalog.json"))
	if err != nil {
		t.Fatal(err)
	}
	var catalog struct {
		Entries []struct {
			ID             string `json:"id"`
			Category       string `json:"category"`
			ReferenceLabel string `json:"reference_label"`
		} `json:"entries"`
	}
	if err := json.Unmarshal(catalogPayload, &catalog); err != nil {
		t.Fatal(err)
	}
	expected := make(map[string]string)
	for _, entry := range catalog.Entries {
		if entry.Category != "shouyin" {
			continue
		}
		if key, ok := layout.YinyuanIDToKey[entry.ID]; ok {
			expected[entry.ReferenceLabel] = key
		}
	}
	return expected
}

func readShouyinTable(t *testing.T, path, heading string) map[string]string {
	t.Helper()
	payload, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	inSection := false
	result := make(map[string]string)
	for _, line := range strings.Split(string(payload), "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == heading {
			inSection = true
			continue
		}
		if inSection && strings.HasPrefix(trimmed, "### ") {
			break
		}
		if !inSection || !strings.HasPrefix(trimmed, "|") {
			continue
		}
		cells := strings.Split(strings.Trim(trimmed, "|"), "|")
		firstCell := strings.TrimSpace(cells[0])
		if len(cells) != 4 || firstCell == "首音" || firstCell == "Shouyin" || strings.Contains(firstCell, "---") {
			continue
		}
		for index := 0; index < len(cells); index += 2 {
			label := normalizeDocumentedShouyin(cells[index])
			if label == "" {
				continue
			}
			key := strings.TrimSpace(strings.Trim(strings.TrimSpace(cells[index+1]), "`"))
			result[label] = key
		}
	}
	return result
}

func normalizeDocumentedShouyin(value string) string {
	value = strings.TrimSpace(value)
	if index := strings.IndexAny(value, "（("); index >= 0 {
		value = value[:index]
	}
	return strings.Trim(strings.TrimSpace(value), "`")
}
