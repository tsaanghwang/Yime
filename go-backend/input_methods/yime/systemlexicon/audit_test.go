package systemlexicon

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

func TestAuditEntriesFlagsSuffixParticle(t *testing.T) {
	entries := []Entry{
		{Text: "走了吗", Code: "abc", Weight: 10},
		{Text: "你的", Code: "def", Weight: 20},
		{Text: "中国", Code: "ghi", Weight: 100},
		{Text: "好", Code: "jkl", Weight: 1},
	}
	findings, summary := AuditEntries(entries)
	if summary.FindingCount != 1 {
		t.Fatalf("expected 1 finding, got %d (%#v)", summary.FindingCount, findings)
	}
	if findings[0].Text != "走了吗" {
		t.Fatalf("unexpected finding %#v", findings[0])
	}
}

func TestFilterFindingsByRuleAndKeyword(t *testing.T) {
	findings := []Finding{
		{Rule: RuleSuffixParticle, Text: "走了吗", Code: "abc"},
		{Rule: RuleSuffixParticle, Text: "可以吧", Code: "def"},
	}
	filtered := FilterFindings(findings, RuleSuffixParticle, "走吧")
	if len(filtered) != 0 {
		t.Fatalf("expected no match, got %#v", filtered)
	}
	filtered = FilterFindings(findings, RuleAll, "可以")
	if len(filtered) != 1 || filtered[0].Text != "可以吧" {
		t.Fatalf("unexpected filtered %#v", filtered)
	}
}

func TestLoadDictFileParsesDataSection(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "yime_variable.dict.yaml")
	content := "name: test\n...\n走了吗\tcode-a\t12\n中国\tcode-b\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	entries, err := LoadDictFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %#v", entries)
	}
	if entries[0].Weight != 12 {
		t.Fatalf("expected weight 12, got %d", entries[0].Weight)
	}
}

func TestVisitDictFileStreamsEntriesWithoutChangingSource(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "yime_full.dict.yaml")
	content := []byte("name: test\n...\n我们\ta b\t20\n中国\tc d\t10\n")
	if err := os.WriteFile(path, content, 0o644); err != nil {
		t.Fatal(err)
	}
	var texts []string
	if err := VisitDictFile(path, func(entry Entry) error {
		texts = append(texts, entry.Text)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if len(texts) != 2 || texts[0] != "我们" || texts[1] != "中国" {
		t.Fatalf("visited=%#v", texts)
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(content) {
		t.Fatal("streaming visitor changed the runtime dictionary")
	}
}

func TestDictPathPrefersSharedDir(t *testing.T) {
	shared := t.TempDir()
	user := t.TempDir()
	sharedFile := filepath.Join(shared, "yime_variable.dict.yaml")
	userFile := filepath.Join(user, "yime_variable.dict.yaml")
	if err := os.WriteFile(sharedFile, []byte("...\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(userFile, []byte("...\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := DictPath(shared, user, reverselookup.ModeVariable); got != sharedFile {
		t.Fatalf("expected shared dict path %q, got %q", sharedFile, got)
	}
}

func TestDictPathDoesNotFallBackToRetiredUserCopy(t *testing.T) {
	shared := t.TempDir()
	user := t.TempDir()
	if err := os.WriteFile(
		filepath.Join(user, "yime_variable.dict.yaml"),
		[]byte("stale-user-copy"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(shared, "yime_variable.dict.yaml")
	if got := DictPath(shared, user, reverselookup.ModeVariable); got != filepath.Join(user, "yime_variable.dict.yaml") {
		t.Fatalf("expected existing user dictionary while shared core is absent, got %q (shared target %q)", got, want)
	}
}
