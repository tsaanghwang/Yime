package lexiconpromotion

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestScanFindsRepeatedUnknownHanPhrases(t *testing.T) {
	root := t.TempDir()
	shared, user := filepath.Join(root, "shared"), filepath.Join(root, "user")
	mustWrite(t, filepath.Join(shared, "yime_trial.dict.yaml"), "# Rime dictionary\n---\nname: yime_trial\n...\n已有词\taa\t10\n")
	mustWrite(t, filepath.Join(shared, "yime_trial.schema.yaml"), "translator:\n  user_dict: yime_trial_layout_x\n")
	snapshot := filepath.Join(user, "sync", "device", "yime_trial_layout_x.userdb.txt")
	mustWrite(t, snapshot, "# Rime user dictionary\n"+
		"aa \t已有词\tc=9 d=4 t=9\n"+
		"bb \t新发现词\tc=5 d=3.5 t=8\n"+
		"cc \t低频词\tc=2 d=1 t=7\n"+
		"dd \t姓名A\tc=20 d=9 t=6\n")

	result, err := Scan(DefaultConfig(shared, user, "yime_trial"), time.Unix(100, 0))
	if err != nil {
		t.Fatal(err)
	}
	if got := result.Report.Summary.PromotionCandidates; got != 1 {
		t.Fatalf("candidates=%d", got)
	}
	if result.Report.Candidates[0].Text != "新发现词" || result.Report.Candidates[0].Commits != 5 {
		t.Fatalf("candidate=%#v", result.Report.Candidates[0])
	}
	if result.Report.Summary.AlreadyInSystem != 1 || result.Report.Summary.BelowFrequency != 1 || result.Report.Summary.RejectedNonHan != 1 {
		t.Fatalf("summary=%#v", result.Report.Summary)
	}
	payload, err := os.ReadFile(result.JSONPath)
	if err != nil {
		t.Fatal(err)
	}
	var report Report
	if err := json.Unmarshal(payload, &report); err != nil {
		t.Fatal(err)
	}
	if !report.OfflineOnly || report.UploadPerformed {
		t.Fatalf("privacy flags=%#v", report)
	}
	if _, err := os.Stat(result.TSVPath); err != nil {
		t.Fatal(err)
	}
}

func TestScanRequiresSyncedUserDBSnapshot(t *testing.T) {
	root := t.TempDir()
	shared, user := filepath.Join(root, "shared"), filepath.Join(root, "user")
	mustWrite(t, filepath.Join(shared, "yime_trial.dict.yaml"), "---\n...\n词\ta\t1\n")
	mustWrite(t, filepath.Join(shared, "yime_trial.schema.yaml"), "translator:\n  user_dict: yime_trial_user\n")
	if _, err := Scan(DefaultConfig(shared, user, "yime_trial"), time.Now()); err == nil {
		t.Fatal("expected missing sync snapshot error")
	}
}

func mustWrite(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}
