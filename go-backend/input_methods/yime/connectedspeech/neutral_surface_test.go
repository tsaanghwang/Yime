package connectedspeech

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNeutralSurfaceAuditPreservesFourContextsAndReportsProjectionCollision(t *testing.T) {
	config := newNeutralSurfaceFixture(t, validNeutralSurfaceClasses())
	result, err := RunNeutralSurfaceAudit(config)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Summary.Passed || result.Summary.ContextClassCount != 4 || result.Summary.SurfacePitchLevelCount != 4 {
		t.Fatalf("unexpected neutral surface summary: %#v", result.Summary)
	}
	if result.Summary.ProjectedGradeCount != 2 || result.Summary.ProjectionCollisionBucketCount != 1 || result.Summary.ContextualIdentityCount != 4 {
		t.Fatalf("neutral surface collision was not preserved and reported: %#v", result.Summary)
	}
	if result.Summary.YinyuanEntryCount != 6 || result.Summary.RewriteMapRowCount != 24 || result.Summary.RuntimeAliasesGenerated != 0 {
		t.Fatalf("unexpected rewrite/runtime counts: %#v", result.Summary)
	}
	if result.Summary.NeutralSyllableCount != 2 || result.Summary.SyllableProjectionCount != 8 ||
		result.Summary.CompatibilityTupleMatchCount != 2 || result.Summary.SameBaseTone3CollisionCount != 6 {
		t.Fatalf("unexpected syllable projection counts: %#v", result.Summary)
	}
	collisions, err := os.ReadFile(filepath.Join(config.OutputDir, "projection_collisions.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(collisions), "low\t3\tafter_t1_level2,after_t2_level3,after_t4_level1\t2,3,1\ttrue") {
		t.Fatalf("three-to-one low-grade collision missing:\n%s", collisions)
	}
	rewrites, err := os.ReadFile(filepath.Join(config.OutputDir, "yinyuan_rewrite_map.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(rewrites), "after_t3_level4\t4\tmid\tM01\ti\tM02\ttone_grade") ||
		!strings.Contains(string(rewrites), "after_t1_level2\t2\tlow\tM04\tu\tM06\ttone_grade") {
		t.Fatalf("stable-ID grade rewrite map is incomplete:\n%s", rewrites)
	}
}

func TestNeutralSurfaceAuditRejectsProjectionThatDisagreesWithCatalog(t *testing.T) {
	classes := strings.Replace(validNeutralSurfaceClasses(), "after_t3_level4\t3\t4\tmid", "after_t3_level4\t3\t4\tlow", 1)
	config := newNeutralSurfaceFixture(t, classes)
	result, err := RunNeutralSurfaceAudit(config)
	if err == nil || !strings.Contains(err.Error(), "gates did not pass") {
		t.Fatalf("catalog projection mismatch was not rejected: result=%#v err=%v", result, err)
	}
	issues, readErr := os.ReadFile(filepath.Join(config.OutputDir, "issues.tsv"))
	if readErr != nil {
		t.Fatal(readErr)
	}
	if !strings.Contains(string(issues), "projected_grade_mismatch\tafter_t3_level4\tlow vs mid") {
		t.Fatalf("projection mismatch issue missing:\n%s", issues)
	}
}

func TestNeutralSurfaceAuditRejectsOutputOutsideTemporaryRoot(t *testing.T) {
	root := t.TempDir()
	config := DefaultNeutralSurfaceAuditConfig(root)
	config.OutputDir = filepath.Join(root, "reports", "neutral-tone-context-audit")
	if _, err := RunNeutralSurfaceAudit(config); err == nil {
		t.Fatal("expected neutral surface output outside .tmp to be rejected")
	}
}

func newNeutralSurfaceFixture(t *testing.T, classes string) NeutralSurfaceAuditConfig {
	t.Helper()
	root := t.TempDir()
	classesPath := filepath.Join(root, "docs", "project", "connected_speech", "neutral_tone_context_classes.tsv")
	catalogPath := filepath.Join(root, "data", "trainer", "yinyuan_catalog.json")
	decompositionPath := filepath.Join(root, "data", "yime_syllable_decomposition.tsv")
	if err := os.MkdirAll(filepath.Dir(classesPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(catalogPath), 0o755); err != nil {
		t.Fatal(err)
	}
	writeText(t, classesPath, classes)
	writeText(t, catalogPath, `{
  "format_version": 1,
  "entries": [
    {"id":"M01","category":"yueyin","quality_group":"i","tone_grade":"high","covered_pianyin_levels":[5]},
    {"id":"M02","category":"yueyin","quality_group":"i","tone_grade":"mid","covered_pianyin_levels":[4]},
    {"id":"M03","category":"yueyin","quality_group":"i","tone_grade":"low","covered_pianyin_levels":[3,2,1]},
    {"id":"M04","category":"yueyin","quality_group":"u","tone_grade":"high","covered_pianyin_levels":[5]},
    {"id":"M05","category":"yueyin","quality_group":"u","tone_grade":"mid","covered_pianyin_levels":[4]},
    {"id":"M06","category":"yueyin","quality_group":"u","tone_grade":"low","covered_pianyin_levels":[3,2,1]}
  ]
}
`)
	writeText(t, decompositionPath, "pinyin_tone\tshouyin_id\thuyin_id\tzhuyin_id\tmoyin_id\n"+
		"bi3\tN01\tM03\tM03\tM03\n"+
		"bi5\tN01\tM02\tM02\tM02\n"+
		"bu3\tN01\tM06\tM06\tM06\n"+
		"bu5\tN01\tM05\tM05\tM05\n")
	return NeutralSurfaceAuditConfig{
		RepoRoot: root, ClassesPath: classesPath, CatalogPath: catalogPath, DecompositionPath: decompositionPath,
		OutputDir: filepath.Join(root, ".tmp", "neutral-tone-context-audit"), AllowedOutputRoot: filepath.Join(root, ".tmp"),
	}
}

func validNeutralSurfaceClasses() string {
	return "class_id\tconditioning_surface_tone\tsurface_pitch_level\texpected_projected_grade\tconditioning_stage\tadjudication_status\tnote\n" +
		"after_t1_level2\t1\t2\tlow\tpost_tone_sandhi_surface\tresearch_only\tt1\n" +
		"after_t2_level3\t2\t3\tlow\tpost_tone_sandhi_surface\tresearch_only\tt2\n" +
		"after_t3_level4\t3\t4\tmid\tpost_tone_sandhi_surface\tresearch_only\tt3\n" +
		"after_t4_level1\t4\t1\tlow\tpost_tone_sandhi_surface\tresearch_only\tt4\n"
}
