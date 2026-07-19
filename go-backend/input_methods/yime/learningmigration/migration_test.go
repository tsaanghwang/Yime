package learningmigration

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/systemlexicon"
)

func TestDetectTransitionsIgnoresStableCustomPhrase(t *testing.T) {
	shared, user := t.TempDir(), t.TempDir()
	old := "translator:\n  user_dict: yime_full\ncustom_phrase:\n  user_dict: custom_phrase_full\n"
	newSchema := "translator:\n  user_dict: yime_full_layout_abc123\ncustom_phrase:\n  user_dict: custom_phrase_full\n"
	if err := os.WriteFile(filepath.Join(user, "yime_full.schema.yaml"), []byte(old), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(shared, "yime_full.schema.yaml"), []byte(newSchema), 0644); err != nil {
		t.Fatal(err)
	}
	got, err := DetectTransitions(shared, user)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].SourceDB != "yime_full" || got[0].TargetDB != "yime_full_layout_abc123" {
		t.Fatalf("unexpected: %#v", got)
	}
}

func TestDetectTransitionsBetweenUsesExplicitOldAndNewDataSets(t *testing.T) {
	oldDir, newDir := t.TempDir(), t.TempDir()
	oldSchema := "translator:\n  user_dict: yime_full_layout_old\n"
	newSchema := "translator:\n  user_dict: yime_full_layout_new\n"
	if err := os.WriteFile(filepath.Join(oldDir, "yime_full.schema.yaml"), []byte(oldSchema), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(newDir, "yime_full.schema.yaml"), []byte(newSchema), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := DetectTransitionsBetween(oldDir, newDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].SourceDB != "yime_full_layout_old" || got[0].TargetDB != "yime_full_layout_new" {
		t.Fatalf("unexpected transitions: %#v", got)
	}
	if got[0].OldDictionary != filepath.Join(oldDir, "yime_full.dict.yaml") || got[0].Dictionary != filepath.Join(newDir, "yime_full.dict.yaml") {
		t.Fatalf("unexpected dictionary paths: %#v", got[0])
	}
}

func TestTransformReencodesAndPreservesLearningStats(t *testing.T) {
	input := "# Rime user dictionary\n#@/db_name\tyime_full\n#@/db_type\tuserdb\n#@/tick\t300\n#@/user_id\ttest-user\nold1 \t知道\tc=10 d=4.60295 t=264\nold2 \t未知词\tc=2 d=1 t=9\n"
	index := buildIndex([]systemlexicon.Entry{{Text: "知道", Code: "new7J", Weight: 100}})
	var out bytes.Buffer
	r, err := transform(strings.NewReader(input), &out, Transition{Mode: "full", SourceDB: "yime_full", TargetDB: "yime_full_layout_new"}, index)
	if err != nil {
		t.Fatal(err)
	}
	if r.Total != 2 || r.Migrated != 1 || r.Unmatched != 1 {
		t.Fatalf("unexpected: %#v", r)
	}
	for _, want := range []string{"#@/db_name\tyime_full_layout_new", "#@/tick\t300", "#@/user_id\ttest-user", "new7J \t知道\tc=10 d=4.60295 t=264"} {
		if !strings.Contains(out.String(), want) {
			t.Fatalf("missing %q in:\n%s", want, out.String())
		}
	}
}

func TestTransformMergesCollidingRecords(t *testing.T) {
	input := "a\t词\tc=2 d=1.5 t=8\nb\t词\tc=3 d=2.5 t=7\n"
	index := buildIndex([]systemlexicon.Entry{{Text: "词", Code: "x", Weight: 1}})
	var out bytes.Buffer
	if _, err := transform(strings.NewReader(input), &out, Transition{TargetDB: "target"}, index); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "x \t词\tc=5 d=2.5 t=8") {
		t.Fatalf("unexpected:\n%s", out.String())
	}
}

func TestTransformUsesOldCodeToPreserveAmbiguousReading(t *testing.T) {
	oldEntries := []systemlexicon.Entry{{Text: "重", Code: "old-zhong", Weight: 10}, {Text: "重", Code: "old-chong", Weight: 1}}
	newEntries := []systemlexicon.Entry{{Text: "重", Code: "new-zhong", Weight: 1}, {Text: "重", Code: "new-chong", Weight: 100}}
	index := buildIndexWithOld(oldEntries, newEntries)
	var out bytes.Buffer
	input := "old-zhong \t重\tc=7 d=3 t=4\n"
	if _, err := transform(strings.NewReader(input), &out, Transition{TargetDB: "target"}, index); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "new-zhong \t重\tc=7 d=3 t=4") {
		t.Fatalf("reading changed:\n%s", out.String())
	}
}

func TestRimeDictManagerRestoresTransformedSnapshot(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("Rime manager integration is Windows-only")
	}
	manager := findManager(filepath.Join(t.TempDir(), "data"))
	if manager == "" {
		t.Skip("rime_dict_manager.exe is not available")
	}
	userDir := t.TempDir()
	installation := "distribution_code_name: YimeTest\ninstallation_id: yime-layout-migration-test\nrime_version: 1.16.1\n"
	if err := os.WriteFile(filepath.Join(userDir, "installation.yaml"), []byte(installation), 0644); err != nil {
		t.Fatal(err)
	}
	var snapshot bytes.Buffer
	input := "# Rime user dictionary\n#@/db_name\told\n#@/db_type\tuserdb\n#@/rime_version\t1.16.1\n#@/tick\t12\nold \t词\tc=4 d=2.5 t=11\n"
	index := buildIndex([]systemlexicon.Entry{{Text: "词", Code: "new", Weight: 1}})
	if _, err := transform(strings.NewReader(input), &snapshot, Transition{TargetDB: "new_layout"}, index); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(userDir, "new_layout.userdb.txt")
	if err := os.WriteFile(path, snapshot.Bytes(), 0644); err != nil {
		t.Fatal(err)
	}
	if err := runManager(manager, userDir, "--restore", path); err != nil {
		t.Fatal(err)
	}
	dbs, err := listDatabases(manager, userDir)
	if err != nil {
		t.Fatal(err)
	}
	if !dbs["new_layout"] {
		t.Fatalf("restored database not listed: %#v", dbs)
	}
}
