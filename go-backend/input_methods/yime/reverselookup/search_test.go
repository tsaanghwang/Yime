package reverselookup

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSearchResolvesUserPhraseAndDictEntry(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()

	// 等长码（full）必须是 4 的倍数；~~dd 经 mergeAdjacent 推导出变长码 ~d。
	codeMapTSV := "pinyin\tfull\tvariable\tshorthand\nba1\t~~dd\t~d\t~d\n"
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), []byte(codeMapTSV), 0o644); err != nil {
		t.Fatalf("write code map: %v", err)
	}
	dictYAML := "name: test\n...\n巴\t~d\n"
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_variable.dict.yaml"), []byte(dictYAML), 0o644); err != nil {
		t.Fatalf("write dict: %v", err)
	}
	userPhrase := "北京\tbei3 jing1\n"
	if err := os.WriteFile(filepath.Join(userDir, "yime_user_phrases.txt"), []byte(userPhrase), 0o644); err != nil {
		t.Fatalf("write user phrases: %v", err)
	}

	index, err := Load(sharedDir, userDir, ModeVariable)
	if err != nil {
		t.Fatalf("Load failed: %v", err)
	}

	dictResults := index.Search("巴", false)
	if len(dictResults) != 1 || dictResults[0].ActiveCode != "~d" {
		t.Fatalf("expected dict lookup for 巴, got %#v", dictResults)
	}

	userResults := index.Search("北京", false)
	if len(userResults) != 1 || userResults[0].Source != "用户词库" {
		t.Fatalf("expected user phrase lookup for 北京, got %#v", userResults)
	}
}

func TestSearchContainsMatchFindsPartialPhrase(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()

	// 等长码 zzzz 推导出变长码 z，与词典中 中国\tz 的编码对应。
	codeMapTSV := "pinyin\tfull\tvariable\tshorthand\nzhong1\tzzzz\tz\tz\n"
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), []byte(codeMapTSV), 0o644); err != nil {
		t.Fatalf("write code map: %v", err)
	}
	dictYAML := "name: test\n...\n中国\tz\n"
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_variable.dict.yaml"), []byte(dictYAML), 0o644); err != nil {
		t.Fatalf("write dict: %v", err)
	}

	index, err := Load(sharedDir, userDir, ModeVariable)
	if err != nil {
		t.Fatalf("Load failed: %v", err)
	}

	if results := index.Search("国", false); len(results) != 0 {
		t.Fatalf("expected no exact match for 国, got %#v", results)
	}
	if results := index.Search("国", true); len(results) == 0 {
		t.Fatalf("expected contains match for 国 inside 中国, got %#v", results)
	}
}

func TestCacheSpeedsUpSecondLoad(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	cacheDir := t.TempDir()
	t.Setenv("LOCALAPPDATA", cacheDir)

	// 等长码 ~~dd 推导出变长码 ~d，与词典中 巴\t~d 的编码对应。
	codeMapTSV := "pinyin\tfull\tvariable\tshorthand\nba1\t~~dd\t~d\t~d\n"
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), []byte(codeMapTSV), 0o644); err != nil {
		t.Fatalf("write code map: %v", err)
	}
	dictYAML := "name: test\n...\n巴\t~d\n"
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_variable.dict.yaml"), []byte(dictYAML), 0o644); err != nil {
		t.Fatalf("write dict: %v", err)
	}

	if _, err := Load(sharedDir, userDir, ModeVariable); err != nil {
		t.Fatalf("first Load failed: %v", err)
	}
	cachePath := filepath.Join(cacheDir, "PIME", "Cache", "reverse_lookup_yime_variable.gob")
	if _, err := os.Stat(cachePath); err != nil {
		t.Fatalf("expected cache file at %s: %v", cachePath, err)
	}

	index, err := Load(sharedDir, userDir, ModeVariable)
	if err != nil {
		t.Fatalf("second Load failed: %v", err)
	}
	if results := index.Search("巴", false); len(results) != 1 {
		t.Fatalf("expected cached index to search 巴, got %#v", results)
	}
}
