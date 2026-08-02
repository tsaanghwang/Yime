package trainer

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

func repositoryDataDir(t *testing.T) string {
	t.Helper()
	path, err := filepath.Abs(filepath.Join("..", "data"))
	if err != nil {
		t.Fatal(err)
	}
	return path
}

func TestFoundationLessonResolvesAgainstCurrentThreeModeData(t *testing.T) {
	dataDir := repositoryDataDir(t)
	lesson, err := Load(filepath.Join(dataDir, "trainer", "foundation.json"))
	if err != nil {
		t.Fatal(err)
	}
	resolver, err := NewResolver(dataDir)
	if err != nil {
		t.Fatal(err)
	}

	byMode := map[reverselookup.Mode][]Exercise{}
	for _, mode := range []reverselookup.Mode{
		reverselookup.ModeVariable,
		reverselookup.ModeFull,
		reverselookup.ModeShorthand,
	} {
		exercises, err := resolver.Resolve(lesson, mode)
		if err != nil {
			t.Fatalf("mode %s: %v", mode, err)
		}
		if len(exercises) != 3 {
			t.Fatalf("mode %s resolved %d static exercises, want 3", mode, len(exercises))
		}
		for _, exercise := range exercises {
			if strings.TrimSpace(exercise.Expected) == "" {
				t.Fatalf("mode %s has empty target: %#v", mode, exercise)
			}
			if strings.Contains(exercise.Expected, "ma1") || strings.Contains(exercise.Expected, "wo3") {
				t.Fatalf("mode %s leaked placeholder pinyin into target: %#v", mode, exercise)
			}
		}
		groups, err := resolver.ResolveSyllablePracticeGroups(mode)
		if err != nil {
			t.Fatalf("mode %s syllable practice: %v", mode, err)
		}
		for _, group := range groups {
			byMode[mode] = append(byMode[mode], group.Exercises...)
		}
	}
	ma1 := func(mode reverselookup.Mode) Exercise {
		for _, exercise := range byMode[mode] {
			if exercise.SectionType == SectionSyllablePractice && exercise.NumericPinyin == "ma1" {
				return exercise
			}
		}
		t.Fatalf("mode %s has no ma1 contrast exercise", mode)
		return Exercise{}
	}
	a4 := func(mode reverselookup.Mode) Exercise {
		for _, exercise := range byMode[mode] {
			if exercise.SectionType == SectionSyllablePractice && exercise.NumericPinyin == "a4" {
				return exercise
			}
		}
		t.Fatalf("mode %s has no a4 contrast exercise", mode)
		return Exercise{}
	}
	if ma1(reverselookup.ModeFull).Expected == ma1(reverselookup.ModeVariable).Expected {
		t.Fatal("ma1 must demonstrate the fixed-length versus variable-length projection")
	}
	if a4(reverselookup.ModeVariable).Expected == a4(reverselookup.ModeShorthand).Expected {
		t.Fatal("a4 must demonstrate the variable-length versus shorthand projection")
	}
}

func TestFoundationUsesOneDynamicEncodingPracticeInsteadOfFourStaticAssociationExamples(t *testing.T) {
	lesson, err := Load(filepath.Join(repositoryDataDir(t), "trainer", "foundation.json"))
	if err != nil {
		t.Fatal(err)
	}
	encodingSections := 0
	for _, section := range lesson.Sections {
		if section.Type == SectionSyllableAssociate || section.Title == "标准拼音与音元联想" || section.Title == "音节练习" {
			t.Fatalf("foundation retained superseded practice section: %#v", section)
		}
		if section.Type == SectionSyllablePractice {
			encodingSections++
			if section.Title != "编码练习" || len(section.Items) != 0 {
				t.Fatalf("dynamic encoding practice=%#v", section)
			}
		}
	}
	if encodingSections != 1 {
		t.Fatalf("dynamic encoding practice sections=%d want 1", encodingSections)
	}
}

func TestFoundationDeclaresFivePracticeTypesInRequiredOrder(t *testing.T) {
	lesson, err := Load(filepath.Join(repositoryDataDir(t), "trainer", "foundation.json"))
	if err != nil {
		t.Fatal(err)
	}
	wantTypes := []string{
		SectionKeymap,
		SectionSyllableComposition,
		SectionSyllablePractice,
		SectionWordPractice,
		SectionSentencePractice,
	}
	wantTitles := []string{"音元练习", "分段练习", "编码练习", "字词练习", "短句练习"}
	if len(lesson.Sections) != len(wantTypes) {
		t.Fatalf("foundation sections=%d want %d", len(lesson.Sections), len(wantTypes))
	}
	for index, section := range lesson.Sections {
		if section.Type != wantTypes[index] || section.Title != wantTitles[index] {
			t.Fatalf("section %d=%#v want type=%s title=%s", index, section, wantTypes[index], wantTitles[index])
		}
		if index > 0 && len(section.Items) != 0 {
			t.Fatalf("dynamic section %s retained static examples", section.Title)
		}
	}
}

func TestSyllablePracticeUsesAll1729EncodedSyllablesGroupedBy24Shouyin(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	for _, mode := range []reverselookup.Mode{
		reverselookup.ModeVariable,
		reverselookup.ModeFull,
		reverselookup.ModeShorthand,
	} {
		groups, err := resolver.ResolveSyllablePracticeGroups(mode)
		if err != nil {
			t.Fatalf("mode %s: %v", mode, err)
		}
		if len(groups) != 24 {
			t.Fatalf("mode %s groups=%d want 24 stable shouyin groups", mode, len(groups))
		}
		total := 0
		seen := map[string]bool{}
		seenGroups := map[string]bool{}
		n23HasY, n23HasHui := false, false
		for _, group := range groups {
			if len(group.Exercises) == 0 {
				t.Fatalf("mode %s has empty shouyin group %#v", mode, group)
			}
			if seenGroups[group.ID] {
				t.Fatalf("mode %s duplicates group %s", mode, group.ID)
			}
			seenGroups[group.ID] = true
			previousPinyin := ""
			for _, exercise := range group.Exercises {
				total++
				if strings.TrimSpace(exercise.Expected) == "" {
					t.Fatalf("mode %s has empty target: %#v", mode, exercise)
				}
				if strings.TrimSpace(exercise.NumericPinyin) == "" {
					t.Fatalf("mode %s has empty numeric pinyin: %#v", mode, exercise)
				}
				row, exists := resolver.decomposition[exercise.NumericPinyin]
				if !exists || row.Status != "ok" {
					t.Fatalf("mode %s includes non-runtime syllable %q with status %q", mode, exercise.NumericPinyin, row.Status)
				}
				if len(exercise.Segments) != 4 {
					t.Fatalf("mode %s syllable %s has %d structural segments", mode, exercise.NumericPinyin, len(exercise.Segments))
				}
				for index, segment := range exercise.Segments {
					if segment.ID != row.IDs[index] || segment.Notation != row.Names[index] || segment.Key == "" {
						t.Fatalf("mode %s syllable %s segment %d=%#v", mode, exercise.NumericPinyin, index, segment)
					}
				}
				if previousPinyin != "" && exercise.NumericPinyin < previousPinyin {
					t.Fatalf("mode %s group %s is not ordered by pinyin: %s before %s", mode, group.ID, previousPinyin, exercise.NumericPinyin)
				}
				previousPinyin = exercise.NumericPinyin
				if seen[exercise.NumericPinyin] {
					t.Fatalf("mode %s duplicates %s", mode, exercise.NumericPinyin)
				}
				seen[exercise.NumericPinyin] = true
				if got, want := exercise.Expected, codeRecordForMode(resolver.codeMap[exercise.NumericPinyin], mode); got != want {
					t.Fatalf("mode %s syllable %s target=%q want code table %q", mode, exercise.NumericPinyin, got, want)
				}
				if group.ID == "syllables-n23" {
					n23HasY = n23HasY || strings.Contains(exercise.Detail, "首音分析：y")
					n23HasHui = n23HasHui || strings.Contains(exercise.Detail, "首音分析：ɥ")
				}
			}
		}
		if total != 1729 || len(seen) != 1729 || len(seenGroups) != 24 {
			t.Fatalf("mode %s exercises=%d identified=%d want exactly 1729 encoded syllables", mode, total, len(seen))
		}
		if !n23HasY || !n23HasHui {
			t.Fatalf("mode %s N23 did not combine y and ɥ surface forms", mode)
		}
		for _, sourceOnly := range []string{"guai2", "ra4", "tin4"} {
			if seen[sourceOnly] {
				t.Fatalf("mode %s includes source-only syllable %s", mode, sourceOnly)
			}
		}
	}
}

func TestEncodingPracticeShowsShouyinThenGanyinAnalysisBeforeWholeYinyuanPinyin(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	groups, err := resolver.ResolveSyllablePracticeGroups(reverselookup.ModeVariable)
	if err != nil {
		t.Fatal(err)
	}
	var yi1 Exercise
	for _, group := range groups {
		for _, exercise := range group.Exercises {
			if exercise.NumericPinyin == "yi1" {
				yi1 = exercise
			}
		}
	}
	if yi1.SectionTitle != "编码练习" || yi1.AnswerLabel != "完整编码" {
		t.Fatalf("yi1 encoding exercise labels=%#v", yi1)
	}
	lines := splitDetailLines(yi1.Detail)
	if len(lines) != 3 ||
		!strings.HasPrefix(lines[0], "首音分析：y → ") || !strings.Contains(lines[0], "（N23）") ||
		!strings.HasPrefix(lines[1], "干音分析：i1 → ") || strings.Count(lines[1], "（M01）") != 3 ||
		!strings.HasPrefix(lines[2], "完整音元拼音：") {
		t.Fatalf("yi1 did not preserve the two-stage encoding flow: %q", yi1.Detail)
	}
}

func splitDetailLines(value string) []string {
	return strings.Split(strings.ReplaceAll(value, "\r\n", "\n"), "\n")
}

func TestKeymapExerciseUsesActiveLayoutProjection(t *testing.T) {
	dataDir := repositoryDataDir(t)
	lesson, err := Load(filepath.Join(dataDir, "trainer", "foundation.json"))
	if err != nil {
		t.Fatal(err)
	}
	resolver, err := NewResolver(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	exercises, err := resolver.Resolve(lesson, reverselookup.ModeVariable)
	if err != nil {
		t.Fatal(err)
	}
	var n01 Exercise
	for _, exercise := range exercises {
		if exercise.SectionType == SectionKeymap && strings.Contains(exercise.Detail, "N01") {
			n01 = exercise
			break
		}
	}
	if n01.Expected != resolver.layout.Projection["N01"] {
		t.Fatalf("keymap target %q does not follow current N01 projection %q", n01.Expected, resolver.layout.Projection["N01"])
	}
}

func TestResolverSeparatesActiveLayoutFromReadOnlyTrainingMetadata(t *testing.T) {
	dataDir := repositoryDataDir(t)
	trainingDataDir := t.TempDir()
	trainerDir := filepath.Join(trainingDataDir, "trainer")
	if err := os.MkdirAll(trainerDir, 0700); err != nil {
		t.Fatal(err)
	}
	catalog, err := LoadCatalog(filepath.Join(dataDir, "trainer", CatalogFileName))
	if err != nil {
		t.Fatal(err)
	}
	catalog.Entries[0].DisplayName = "只读教学目录标记"
	payload, err := json.Marshal(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(trainerDir, CatalogFileName), payload, 0600); err != nil {
		t.Fatal(err)
	}
	groups, err := os.ReadFile(filepath.Join(dataDir, "trainer", GroupCatalogFileName))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(trainerDir, GroupCatalogFileName), groups, 0600); err != nil {
		t.Fatal(err)
	}

	resolver, err := NewResolverWithTrainingData(dataDir, trainingDataDir)
	if err != nil {
		t.Fatal(err)
	}
	entry, ok := resolver.catalog.Lookup(catalog.Entries[0].ID)
	if !ok || entry.DisplayName != "只读教学目录标记" {
		t.Fatalf("resolver did not use separate training metadata: %#v", entry)
	}
}

func TestGroupedKeymapCoversAll57IDsFromActiveLayoutExactlyOnce(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	groups, err := resolver.ResolveKeymapGroups()
	if err != nil {
		t.Fatal(err)
	}
	if len(groups) != 17 {
		t.Fatalf("resolved %d groups, want six zaoyin plus eleven yueyin", len(groups))
	}
	seen := map[string]bool{}
	zaoyinGroups, yueyinGroups := 0, 0
	for _, group := range groups {
		switch group.Category {
		case GroupCategoryZaoyin:
			zaoyinGroups++
		case GroupCategoryYueyin:
			yueyinGroups++
		default:
			t.Fatalf("unknown group category: %#v", group)
		}
		for _, exercise := range group.Exercises {
			fields := strings.SplitN(exercise.Detail, " ", 2)
			id := fields[0]
			if seen[id] {
				t.Fatalf("Yinyuan %s appears in more than one drill group", id)
			}
			seen[id] = true
			if exercise.Expected != resolver.layout.Projection[id] {
				t.Fatalf("%s target=%q want active layout key %q", id, exercise.Expected, resolver.layout.Projection[id])
			}
		}
	}
	if zaoyinGroups != 6 || yueyinGroups != 11 || len(seen) != 57 {
		t.Fatalf("coverage zaoyin=%d yueyin=%d ids=%d", zaoyinGroups, yueyinGroups, len(seen))
	}
	for _, id := range layoutdesigner.ExpectedIDs() {
		if !seen[id] {
			t.Fatalf("group drills omit %s", id)
		}
	}
}

func TestGroupedKeymapKeepsPrototypeAuxiliaryMembersOnCurrentStableIDs(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string][]string{
		"zaoyin-dental":  {"N13", "N14", "N15", "N24"},
		"zaoyin-palatal": {"N20", "N21", "N22", "N23"},
		"zaoyin-velar":   {"N09", "N10", "N11", "N12"},
	}
	for _, group := range resolver.groups.Groups {
		ids, exists := want[group.ID]
		if exists && !reflect.DeepEqual(group.YinyuanIDs, ids) {
			t.Fatalf("group %s=%v want %v", group.ID, group.YinyuanIDs, ids)
		}
		delete(want, group.ID)
	}
	if len(want) != 0 {
		t.Fatalf("missing prototype-derived groups: %#v", want)
	}
}

func TestSyllableCompositionReusesSixShouyinGroups(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	groups, err := resolver.ResolveShouyinCompositionGroups()
	if err != nil {
		t.Fatal(err)
	}
	if len(groups) != 6 {
		t.Fatalf("shouyin groups=%d want 6", len(groups))
	}
	count := 0
	for _, group := range groups {
		if group.Category != GroupCategoryZaoyin {
			t.Fatalf("composition shouyin reused non-shouyin group: %#v", group)
		}
		count += len(group.Exercises)
	}
	if count != 24 {
		t.Fatalf("shouyin exercises=%d want all 24 stable initial IDs", count)
	}
}

func TestGanyinCompositionDerivesEighteenRhymeQualityClasses(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	groups, err := resolver.ResolveGanyinCompositionGroups()
	if err != nil {
		t.Fatal(err)
	}
	if len(groups) != 18 {
		t.Fatalf("ganyin rhyme classes=%d want 18", len(groups))
	}
	patterns := map[int]string{1: "高高高", 2: "低中高", 3: "低低低", 4: "高中低"}
	seenPairs := map[string]bool{}
	for _, group := range groups {
		pair := group.MainQuality + "+" + group.FinalQuality
		if pair == "m+m" {
			t.Fatal("the [m] ganyin class must remain excluded")
		}
		if seenPairs[pair] {
			t.Fatalf("duplicate rhyme-quality class %s", pair)
		}
		seenPairs[pair] = true
		total := 0
		for _, toneGroup := range group.ToneGroups {
			if toneGroup.TonePattern != patterns[toneGroup.Tone] {
				t.Fatalf("%s tone %d pattern=%q", pair, toneGroup.Tone, toneGroup.TonePattern)
			}
			if len(toneGroup.Exercises) > 4 {
				t.Fatalf("%s/%s has %d exercises, want at most four medials", pair, toneGroup.Title, len(toneGroup.Exercises))
			}
			total += len(toneGroup.Exercises)
		}
		if total > 16 {
			t.Fatalf("%s has %d exercises, want at most 16", pair, total)
		}
	}
	if !seenPairs["a+n"] || !seenPairs["o+ng"] || len(seenPairs) != 18 {
		t.Fatalf("rhyme-quality coverage=%v", seenPairs)
	}
}

func TestGanyinANClassHasFourMedialsForEachToneAndUsesActiveLayout(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	groups, err := resolver.ResolveGanyinCompositionGroups()
	if err != nil {
		t.Fatal(err)
	}
	var an GanyinRhymeGroup
	for _, group := range groups {
		if group.MainQuality == "a" && group.FinalQuality == "n" {
			an = group
			break
		}
	}
	if len(an.ToneGroups) != 4 {
		t.Fatalf("[a+n] tone groups=%d want 4", len(an.ToneGroups))
	}
	for _, toneGroup := range an.ToneGroups {
		if len(toneGroup.Exercises) != 4 {
			t.Fatalf("[a+n]/%s exercises=%d want an, ian, uan, üan", toneGroup.Title, len(toneGroup.Exercises))
		}
	}
	want := resolver.layout.Projection["M10"] + resolver.layout.Projection["M10"] + resolver.layout.Projection["M28"]
	found := false
	for _, exercise := range an.ToneGroups[0].Exercises {
		if exercise.Prompt == "干音 an1" {
			found = true
			if exercise.Expected != want {
				t.Fatalf("an1 target=%q want current layout %q", exercise.Expected, want)
			}
		}
	}
	if !found {
		t.Fatal("[a+n]/高高高 does not contain an1")
	}
}

func TestOngUengSharedSequenceAlwaysShowsItsStructuralCondition(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	groups, err := resolver.ResolveGanyinCompositionGroups()
	if err != nil {
		t.Fatal(err)
	}
	checkedTones := map[int]bool{}
	for _, group := range groups {
		if group.MainQuality != "o" || group.FinalQuality != "ng" {
			continue
		}
		for _, toneGroup := range group.ToneGroups {
			for _, exercise := range toneGroup.Exercises {
				wantOng := fmt.Sprintf("ong%d（与首音相拼时）", toneGroup.Tone)
				wantUeng := fmt.Sprintf("ueng%d（独立成音节时，对应 weng%d）", toneGroup.Tone, toneGroup.Tone)
				if strings.Contains(exercise.Prompt, wantOng) || strings.Contains(exercise.Prompt, wantUeng) {
					if !strings.Contains(exercise.Prompt, wantOng) || !strings.Contains(exercise.Prompt, wantUeng) ||
						!strings.Contains(exercise.Detail, "形式条件") {
						t.Fatalf("tone %d condition is incomplete: %#v", toneGroup.Tone, exercise)
					}
					checkedTones[toneGroup.Tone] = true
				}
			}
		}
	}
	for tone := 1; tone <= 4; tone++ {
		if !checkedTones[tone] {
			t.Fatalf("ong/ueng condition omitted tone %d", tone)
		}
	}
}

func TestLessonValidationRejectsStaleTargetOnlySyllable(t *testing.T) {
	lesson := Lesson{
		SchemaVersion: SchemaVersion,
		ID:            "bad",
		Title:         "bad",
		Sections: []Section{{
			ID:    "syllable",
			Type:  SectionSyllableContrast,
			Title: "syllable",
			Items: []Item{{Prompt: "旧占位题"}},
		}},
	}
	if err := lesson.Validate(); err == nil {
		t.Fatal("expected missing canonical syllable to fail validation")
	}
}

func TestEvaluateKeepsUppercaseLayoutKeysSignificant(t *testing.T) {
	if !Evaluate("Jf", "Jf") {
		t.Fatal("exact target should pass")
	}
	if Evaluate("jf", "Jf") {
		t.Fatal("uppercase layout keys must remain significant")
	}
}

func TestCatalogCoversStableIDsAndKeepsAudioOptional(t *testing.T) {
	dataDir := repositoryDataDir(t)
	catalog, err := LoadCatalog(filepath.Join(dataDir, "trainer", CatalogFileName))
	if err != nil {
		t.Fatal(err)
	}
	if len(catalog.Entries) != 57 {
		t.Fatalf("catalog has %d entries, want 57", len(catalog.Entries))
	}
	m03, ok := catalog.Lookup("M03")
	if !ok {
		t.Fatal("catalog is missing M03")
	}
	if m03.DisplayName != "低调[i]乐音" || m03.RepresentativeIPA != "i˩" {
		t.Fatalf("M03 teaching anchor is incomplete: %#v", m03)
	}
	if !reflect.DeepEqual(m03.CoveredPianyinLevels, []int{3, 2, 1}) {
		t.Fatalf("M03 must cover pianyin levels 3,2,1: %#v", m03.CoveredPianyinLevels)
	}
	if m03.Audio != "" || catalog.AudioPath(m03) != "" {
		t.Fatal("the first catalog must load without an audio asset")
	}
}

func TestEncodingPracticeStartsFromStandardPinyinAndResolvesFourIDs(t *testing.T) {
	dataDir := repositoryDataDir(t)
	resolver, err := NewResolver(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	groups, err := resolver.ResolveSyllablePracticeGroups(reverselookup.ModeFull)
	if err != nil {
		t.Fatal(err)
	}
	var yi2 Exercise
	for _, group := range groups {
		for _, exercise := range group.Exercises {
			if exercise.NumericPinyin == "yi2" {
				yi2 = exercise
				break
			}
		}
	}
	if len(yi2.Segments) != 4 {
		t.Fatalf("yi2 resolved %d segments, want 4: %#v", len(yi2.Segments), yi2)
	}
	wantIDs := []string{"N23", "M03", "M02", "M01"}
	wantNotations := []string{"y", "ɪ̀", "ɪ̄", "ɪ́"}
	for index, want := range wantIDs {
		if yi2.Segments[index].ID != want {
			t.Fatalf("yi2 segment %d is %s, want %s", index, yi2.Segments[index].ID, want)
		}
		if yi2.Segments[index].Key == "" || yi2.Segments[index].DisplayName == "" {
			t.Fatalf("yi2 segment %d lacks active key or teaching name: %#v", index, yi2.Segments[index])
		}
		if yi2.Segments[index].Notation != wantNotations[index] {
			t.Fatalf("yi2 segment %d notation is %q, want %q", index, yi2.Segments[index].Notation, wantNotations[index])
		}
	}
	if !strings.Contains(yi2.Detail, "完整音元拼音：y + ɪ̀ + ɪ̄ + ɪ́") {
		t.Fatalf("yi2 detail does not expose the standard-pinyin to Yinyuan-pinyin bridge: %q", yi2.Detail)
	}
	if yi2.Expected != "ylkj" {
		t.Fatalf("yi2 full target is %q, want current canonical code ylkj", yi2.Expected)
	}
	if yi2.AudioPath != "" || yi2.AudioDeclared {
		t.Fatal("missing optional syllable audio must not block or masquerade as present")
	}
}

func TestDeclaredMissingAudioDegradesWithoutMutatingLessonDirectory(t *testing.T) {
	tempDir := t.TempDir()
	lessonPath := filepath.Join(tempDir, "lesson.json")
	payload := `{"schema_version":"1.2","id":"audio-optional","title":"audio","sections":[{"id":"keys","type":"keymap","title":"keys","items":[{"yinyuan_id":"M01","audio":"audio/M01.wav"}]}]}`
	if err := os.WriteFile(lessonPath, []byte(payload), 0600); err != nil {
		t.Fatal(err)
	}
	lesson, err := Load(lessonPath)
	if err != nil {
		t.Fatal(err)
	}
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	exercises, err := resolver.Resolve(lesson, reverselookup.ModeVariable)
	if err != nil {
		t.Fatal(err)
	}
	if len(exercises) != 1 || !exercises[0].AudioDeclared || exercises[0].AudioPath != "" {
		t.Fatalf("missing optional audio did not degrade cleanly: %#v", exercises)
	}
	entries, err := os.ReadDir(tempDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "lesson.json" {
		t.Fatalf("resolver wrote into the lesson directory: %#v", entries)
	}
}
