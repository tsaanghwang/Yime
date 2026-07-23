package layoutdesigner

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func defaultProfile(t *testing.T) Profile {
	t.Helper()
	p, err := LoadProfile(filepath.Join("..", "data", ProfileFileName))
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func TestCanonicalProfileMatchesCurrentLayoutDigest(t *testing.T) {
	p := defaultProfile(t)
	digest, err := p.Digest()
	if err != nil {
		t.Fatal(err)
	}
	if digest != "6d00e609f6899a5ba85de857a18e7c9cca60d898c521dce16fac3fa76af532fb" {
		t.Fatalf("digest=%s", digest)
	}
}

func TestEffectiveDataDirPrefersOnlyCompleteUserOverride(t *testing.T) {
	shared, user := t.TempDir(), t.TempDir()
	for _, name := range generatedFiles {
		if err := os.WriteFile(filepath.Join(shared, name), []byte("shared"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got, err := EffectiveDataDir(shared, user)
	if err != nil || filepath.Clean(got) != filepath.Clean(shared) {
		t.Fatalf("expected shared data, got %q err=%v", got, err)
	}
	for _, name := range generatedFiles {
		if err := os.WriteFile(filepath.Join(user, name), []byte("user"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got, err = EffectiveDataDir(shared, user)
	if err != nil || filepath.Clean(got) != filepath.Clean(user) {
		t.Fatalf("expected user override, got %q err=%v", got, err)
	}
}

func TestStoredProfileRoundTripAndDelete(t *testing.T) {
	userDir := t.TempDir()
	profile := defaultProfile(t)
	profile.Name = "我的试验布局"
	path, err := SaveStoredProfile(userDir, profile)
	if err != nil {
		t.Fatal(err)
	}
	profiles, err := ListStoredProfiles(userDir)
	if err != nil || len(profiles) != 1 || profiles[0].Profile.Name != profile.Name {
		t.Fatalf("unexpected stored profiles: %#v err=%v", profiles, err)
	}
	if err := DeleteStoredProfile(path, userDir); err != nil {
		t.Fatal(err)
	}
	profiles, err = ListStoredProfiles(userDir)
	if err != nil || len(profiles) != 0 {
		t.Fatalf("profile was not deleted: %#v err=%v", profiles, err)
	}
}

func TestReencodeUsesYinyuanIDsAndSemanticShorthand(t *testing.T) {
	source := defaultProfile(t)
	target := source
	target.Projection = cloneProjection(source.Projection)
	if err := target.Assign("M16", "]"); err != nil {
		t.Fatal(err)
	}
	record, err := ReencodeRecord("]vcx", source, target)
	if err != nil {
		t.Fatal(err)
	}
	if record.Full != "v]cx" || record.Variable != "v]cx" || record.Shorthand != "v]x" {
		t.Fatalf("unexpected: %#v", record)
	}
}

func TestReencodePreservesVirtualShouyinAsSyllableBoundary(t *testing.T) {
	source := defaultProfile(t)
	record, err := ReencodeRecord("'sdf", source, source)
	if err != nil {
		t.Fatal(err)
	}
	if record.Full != "'sdf" || record.Variable != "'sdf" || record.Shorthand != "'sf" {
		t.Fatalf("unexpected: %#v", record)
	}
}

func TestDescribeIDDistinguishesRealAndVirtualShouyin(t *testing.T) {
	want := map[string]string{
		"N01": "b",
		"N12": "'（虚首音）",
		"N23": "y（虚首音）",
		"N24": "w（虚首音）",
	}
	for id, label := range want {
		if got := DescribeID(id); got != label {
			t.Errorf("DescribeID(%q) = %q, want %q", id, got, label)
		}
	}
}

func TestValidateRejectsReservedCandidateKey(t *testing.T) {
	p := defaultProfile(t)
	p.Projection = cloneProjection(p.Projection)
	p.Projection["N01"] = "!"
	if err := p.Validate(); err == nil {
		t.Fatal("expected reserved-key failure")
	}
}

func TestTrialPinyinUsesDraftProjection(t *testing.T) {
	dir := t.TempDir()
	source := defaultProfile(t)
	if err := WriteProfileAtomic(filepath.Join(dir, ProfileFileName), source); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "yime_pinyin_codes.tsv"), []byte("pinyin_tone\tfull\na1\t]vcx\n"), 0644); err != nil {
		t.Fatal(err)
	}
	target := source
	target.Projection = cloneProjection(source.Projection)
	if err := target.Assign("M16", "]"); err != nil {
		t.Fatal(err)
	}
	got, err := TrialPinyin(dir, target, "a1")
	if err != nil {
		t.Fatal(err)
	}
	if got.Full != "v]cx" || got.Shorthand != "v]x" {
		t.Fatalf("trial=%#v", got)
	}
}

func TestApplyRegeneratesLockedArtifactSet(t *testing.T) {
	dir := t.TempDir()
	source := defaultProfile(t)
	if err := WriteProfileAtomic(filepath.Join(dir, ProfileFileName), source); err != nil {
		t.Fatal(err)
	}
	write := func(name, content string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	write("yime_pinyin_codes.tsv", "pinyin_tone\tfull\na1\t]vcx\n")
	write("yime_full.dict.yaml", "---\nname: yime_full\n...\n词\t]vcx\t10\n")
	for _, mode := range []string{"full", "variable", "shorthand"} {
		write("yime_"+mode+".schema.yaml", "schema:\n  version: old\nengine:\n  translators:\n    - table_translator@custom_phrase\n    - script_translator\nspeller:\n  alphabet: old\n  delimiter: \" \"\ntranslator:\n  dictionary: yime_"+mode+"\n  user_dict: yime_"+mode+"\n  enable_completion: true\n  enable_sentence: true\n  sentence_over_completion: true\ncustom_phrase:\n  enable_completion: true\n  enable_sentence: true\n  sentence_over_completion: true\n")
	}
	target := source
	target.Projection = cloneProjection(source.Projection)
	target.Name = "trial"
	target.BasedOnDigest, _ = source.Digest()
	if err := target.Assign("M16", "]"); err != nil {
		t.Fatal(err)
	}
	plan, err := Apply(dir, target)
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.ChangedIDs) != 2 {
		t.Fatalf("changed=%v", plan.ChangedIDs)
	}
	tsv, err := os.ReadFile(filepath.Join(dir, "yime_pinyin_codes.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(tsv), "a1\tv]cx\tv]cx\tv]x") {
		t.Fatalf("tsv:\n%s", tsv)
	}
	schema, err := os.ReadFile(filepath.Join(dir, "yime_full.schema.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(schema), "user_dict: yime_full_layout_") || !strings.Contains(string(schema), "_script_v1") {
		t.Fatalf("schema:\n%s", schema)
	}
}

func TestValidateContinuousInputSchemaRejectsCompletionOnlyFallback(t *testing.T) {
	schema := []byte("engine:\n  translators:\n    - script_translator\nspeller:\n  delimiter: \" \"\ntranslator:\n  enable_completion: true\n  enable_sentence: true\n  sentence_over_completion: true\ncustom_phrase:\n  enable_completion: true\n  enable_sentence: true\n  sentence_over_completion: true\n")
	if err := validateContinuousInputSchema(schema, "variable"); err != nil {
		t.Fatalf("valid continuous-input schema rejected: %v", err)
	}
	broken := []byte(strings.Replace(string(schema), "sentence_over_completion: true", "sentence_over_completion: false", 1))
	if err := validateContinuousInputSchema(broken, "variable"); err == nil {
		t.Fatal("expected schema without sentence_over_completion to be rejected")
	}
}

func cloneProjection(source map[string]string) map[string]string {
	result := make(map[string]string, len(source))
	for k, v := range source {
		result[k] = v
	}
	return result
}
