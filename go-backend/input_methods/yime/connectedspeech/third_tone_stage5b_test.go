package connectedspeech

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestThirdToneStage5BReviewIsCompleteAndReadOnly(t *testing.T) {
	root := t.TempDir()
	docs := filepath.Join(root, "docs")
	stage5A := filepath.Join(root, ".tmp", "third-tone-stage5a-audit")
	if err := os.MkdirAll(docs, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(stage5A, 0o755); err != nil {
		t.Fatal(err)
	}
	reviewPath := filepath.Join(docs, "review.tsv")
	decisionsPath := filepath.Join(docs, "decisions.tsv")
	sourcesPath := filepath.Join(docs, "sources.tsv")
	writeText(t, sourcesPath, "source_id\ttitle\tauthority\turl\tsupports\tlimitation\nS1\t规则\t规范机构\thttps://example.invalid/rule\t一般规则\t不裁决逐词\nS2\t标调\t规范机构\thttps://example.invalid/spelling\t原调标写\t不裁决韵律域\n")
	writeText(t, reviewPath, "review_id\ttext\tcanonical_pinyin\texpected_surface_pinyin\tstage5a_record_id_snapshot\tpriority_weight_snapshot\tevidence_class\tprosodic_status\truntime_status\tsource_ids\tnote\nR1\t你好\tni3 hao3\tni2 hao3\tT3-5A-00001\t900\tdirect_disyllabic_lexicon_only\tpending_human_review\tnot_approved\tS1,S2\t仅作复核\n")
	writeText(t, decisionsPath, "review_id\tdecision\tapplicable_context\tblocking_context\ttrial_eligibility\tinput_policy\tadjudicator\tadjudicated_on\tnote\nR1\tapproved_2_3\tordinary_continuous_prosodic_domain\tinternal_emphasis,internal_syllable_boundary_pause,internal_coordination,other_internal_prosodic_constraint\teligible_for_stage5c_temporary_trial\tparallel_alias_keep_canonical\tproject_owner\t2026-08-17\t通常语境核准\n")
	candidateHeader := "record_id\ttext\tcanonical_pinyin\tsurface_pinyin\tweight\tcanonical_full\tsurface_full\tsource_code_ambiguous\tsurface_syllable_attested_in_inventory\tlength_policy\tadjudication_status\n"
	writeText(t, filepath.Join(stage5A, "candidate_inventory.tsv"), candidateHeader+"T3-5A-00001\t你好\tni3 hao3\tni2 hao3\t900\tAAAA BBBB\tAAA BBBB\tfalse\ttrue\tnot_longer_all_modes\tresearch_only\n")
	projectionHeader := strings.Join(thirdToneStage5BProjectionHeader, "\t") + "\n"
	projection := ""
	for _, mode := range []string{"full", "variable", "shorthand"} {
		projection += strings.Join([]string{"T3-5A-00001", "你好", mode, "AAAA BBBB", "AAA BBBB", "8", "7", "-1", "900", "true", "false", "1", "2", "1", "800", "你号", "research_only_not_generated"}, "\t") + "\n"
	}
	writeText(t, filepath.Join(stage5A, "three_mode_projection.tsv"), projectionHeader+projection)
	writeText(t, filepath.Join(stage5A, "summary.json"), "{}\n")
	writeText(t, filepath.Join(stage5A, "manifest.json"), "{}\n")

	config := ThirdToneStage5BConfig{
		RepoRoot: root, ReviewPath: reviewPath, DecisionsPath: decisionsPath, SourcesPath: sourcesPath, Stage5AOutputDir: stage5A,
		OutputDir: filepath.Join(root, ".tmp", "third-tone-stage5b-review"), AllowedOutputRoot: filepath.Join(root, ".tmp"), RefreshStage5A: false,
	}
	beforeReview, _ := os.ReadFile(reviewPath)
	beforeDecisions, _ := os.ReadFile(decisionsPath)
	beforeSources, _ := os.ReadFile(sourcesPath)
	result, err := RunThirdToneStage5BReview(config)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Summary.Passed || result.Summary.ReviewCount != 1 || result.Summary.MatchedStage5ACount != 1 || result.Summary.ThreeModeProjectionCount != 3 {
		t.Fatalf("unexpected summary: %#v", result.Summary)
	}
	if result.Summary.ApprovedCount != 1 || result.Summary.PendingHumanReviewCount != 0 || result.Summary.RuntimeAliasesGenerated != 0 || result.Summary.UnresolvedCount != 0 {
		t.Fatalf("unsafe review result: %#v", result.Summary)
	}
	wantReports := []string{"REPORT.md", "input_hashes_after.json", "input_hashes_before.json", "manifest.json", "review_queue.tsv", "summary.json", "three_mode_review_projection.tsv", "unresolved.tsv"}
	entries, err := os.ReadDir(config.OutputDir)
	if err != nil {
		t.Fatal(err)
	}
	gotReports := make([]string, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() {
			gotReports = append(gotReports, entry.Name())
		}
	}
	if !reflect.DeepEqual(gotReports, wantReports) {
		t.Fatalf("reports=%v, want %v", gotReports, wantReports)
	}
	if len(result.Manifest.InputSHA256) != 7 || len(result.Manifest.OutputSHA256) != len(wantReports)-1 {
		t.Fatalf("incomplete manifest: %#v", result.Manifest)
	}
	afterReview, _ := os.ReadFile(reviewPath)
	afterDecisions, _ := os.ReadFile(decisionsPath)
	afterSources, _ := os.ReadFile(sourcesPath)
	if !reflect.DeepEqual(beforeReview, afterReview) || !reflect.DeepEqual(beforeDecisions, afterDecisions) || !reflect.DeepEqual(beforeSources, afterSources) {
		t.Fatal("Stage 5B modified a checked-in input")
	}
}

func TestThirdToneStage5BDecisionDoesNotTreatListPauseAsInternalBlock(t *testing.T) {
	decision := thirdToneStage5BDecision{
		ReviewID: "R1", Decision: "approved_2_3", ApplicableContext: "ordinary_continuous_prosodic_domain",
		BlockingContext:  "internal_emphasis,internal_syllable_boundary_pause,internal_coordination,other_internal_prosodic_constraint",
		TrialEligibility: "eligible_for_stage5c_temporary_trial", InputPolicy: "parallel_alias_keep_canonical", Adjudicator: "project_owner", AdjudicatedOn: "2026-08-17", Note: "列举停顿位于词条之间",
	}
	if err := validateThirdToneStage5BDecision(decision); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(decision.BlockingContext, ",pause,") {
		t.Fatal("external list pause must not be treated as an internal word boundary")
	}
}

func TestThirdToneStage5BRejectsPrematureApproval(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "review.tsv")
	writeText(t, path, "review_id\ttext\tcanonical_pinyin\texpected_surface_pinyin\tstage5a_record_id_snapshot\tpriority_weight_snapshot\tevidence_class\tprosodic_status\truntime_status\tsource_ids\tnote\nR1\t你好\tni3 hao3\tni2 hao3\tID\t1\tdirect_disyllabic_lexicon_only\tapproved\tapproved_for_runtime\tS1\tbad\n")
	reviews, err := loadThirdToneStage5BReviews(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := validateThirdToneStage5BPendingBoundary(reviews[0]); err == nil {
		t.Fatal("expected premature approval to violate Stage 5B-0 boundary")
	}
}

func TestThirdToneStage5BRejectsOutputOutsideTemporaryRoot(t *testing.T) {
	root := t.TempDir()
	config := DefaultThirdToneStage5BConfig(root)
	config.OutputDir = filepath.Join(root, "reports", "third-tone-stage5b-review")
	if _, err := RunThirdToneStage5BReview(config); err == nil {
		t.Fatal("expected output outside .tmp to be rejected")
	}
}
