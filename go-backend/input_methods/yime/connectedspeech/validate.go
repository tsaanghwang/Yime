package connectedspeech

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var (
	semverPattern   = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+$`)
	recordIDPattern = regexp.MustCompile(`^cs-[a-z0-9][a-z0-9._-]+$`)
	policyIDPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]+$`)
	sha256Pattern   = regexp.MustCompile(`^[0-9a-f]{64}$`)
	yinyuanPattern  = regexp.MustCompile(`^[NM][0-9]{2}$`)
)

var validPhenomena = stringSet("tone_sandhi", "neutral_tone", "erhua", "particle_allomorphy", "assimilation", "dissimilation")
var validScopes = stringSet("lexical", "construction", "phrase", "prosodic")
var validCandidatePolicies = stringSet("preserve", "explicit_source_variant", "defer_text_mismatch")
var validTranscriptionStatuses = stringSet("raw_unchecked", "machine_matched", "corrected", "needs_review")
var validAdjudicationStatuses = stringSet("approved_compatibility", "approved_surface", "experimental", "research_only", "deferred", "rejected")
var isolatedStatuses = stringSet("research_only", "deferred", "rejected")
var validErhuaStatuses = stringSet("none", "independent_er", "suffix_compatibility", "fused", "oral_hint", "undetermined")
var validRewriteAttributes = stringSet("tone_grade", "quality", "place", "manner", "rhoticity", "nasality")
var validSourcePolicies = stringSet(
	"pypinyin_phrase_v1",
	"wanxiang_phrase_v1",
	"bcc_text_v1",
	"psc_annotated_v1",
	"pronunciation_review_v1",
	"project_manual_v1",
)

type Inventory struct {
	Syllables map[string]YinyuanTuple
	StableIDs map[string]bool
}

type Issue struct {
	RecordID string `json:"record_id"`
	Field    string `json:"field"`
	Code     string `json:"code"`
	Detail   string `json:"detail"`
}

func (issue Issue) Error() string {
	if issue.RecordID == "" {
		return fmt.Sprintf("%s: %s", issue.Field, issue.Detail)
	}
	return fmt.Sprintf("%s %s: %s", issue.RecordID, issue.Field, issue.Detail)
}

func stringSet(values ...string) map[string]bool {
	result := make(map[string]bool, len(values))
	for _, value := range values {
		result[value] = true
	}
	return result
}

func LoadInventory(path string) (Inventory, error) {
	file, err := os.Open(path)
	if err != nil {
		return Inventory{}, fmt.Errorf("读取规范音节分解表 %s: %w", path, err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	if !scanner.Scan() {
		return Inventory{}, fmt.Errorf("规范音节分解表 %s 为空", path)
	}
	header := strings.Split(strings.TrimPrefix(scanner.Text(), "\ufeff"), "\t")
	columns := map[string]int{}
	for index, name := range header {
		columns[strings.TrimSpace(name)] = index
	}
	required := []string{"pinyin_tone", "shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"}
	for _, name := range required {
		if _, ok := columns[name]; !ok {
			return Inventory{}, fmt.Errorf("规范音节分解表缺少列 %s", name)
		}
	}
	inventory := Inventory{Syllables: map[string]YinyuanTuple{}, StableIDs: map[string]bool{}}
	lineNumber := 1
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(scanner.Text(), "\t")
		for _, name := range required {
			if columns[name] >= len(fields) {
				return Inventory{}, fmt.Errorf("规范音节分解表第 %d 行缺少列 %s", lineNumber, name)
			}
		}
		pinyin := strings.TrimSpace(fields[columns["pinyin_tone"]])
		tuple := YinyuanTuple{
			strings.TrimSpace(fields[columns["shouyin_id"]]),
			strings.TrimSpace(fields[columns["huyin_id"]]),
			strings.TrimSpace(fields[columns["zhuyin_id"]]),
			strings.TrimSpace(fields[columns["moyin_id"]]),
		}
		if pinyin == "" {
			return Inventory{}, fmt.Errorf("规范音节分解表第 %d 行拼音为空", lineNumber)
		}
		if _, duplicate := inventory.Syllables[pinyin]; duplicate {
			return Inventory{}, fmt.Errorf("规范音节分解表拼音重复：%s", pinyin)
		}
		inventory.Syllables[pinyin] = tuple
		for _, id := range tuple {
			inventory.StableIDs[id] = true
		}
	}
	if err := scanner.Err(); err != nil {
		return Inventory{}, err
	}
	if len(inventory.Syllables) == 0 {
		return Inventory{}, fmt.Errorf("规范音节分解表没有数据行")
	}
	return inventory, nil
}

func ValidateRecords(records []Record, inventory Inventory) []Issue {
	var issues []Issue
	recordIDs := map[string]bool{}
	observationIDs := map[string]string{}
	ruleIDs := map[string]string{}
	rulesetVersion := ""

	for index := range records {
		record := &records[index]
		id := record.RecordID
		add := func(field, code, format string, args ...any) {
			issues = append(issues, Issue{RecordID: id, Field: field, Code: code, Detail: fmt.Sprintf(format, args...)})
		}
		if record.SchemaVersion != SchemaVersion {
			add("schema_version", "schema_version", "必须为 %d，实际为 %d", SchemaVersion, record.SchemaVersion)
		}
		if !semverPattern.MatchString(record.RulesetVersion) {
			add("ruleset_version", "invalid_semver", "必须为 x.y.z 格式")
		} else if rulesetVersion == "" {
			rulesetVersion = record.RulesetVersion
		} else if record.RulesetVersion != rulesetVersion {
			add("ruleset_version", "mixed_rulesets", "同一输入中混用了 %s 和 %s", rulesetVersion, record.RulesetVersion)
		}
		if !recordIDPattern.MatchString(id) {
			add("record_id", "invalid_record_id", "格式无效")
		}
		if recordIDs[id] {
			add("record_id", "duplicate_record_id", "记录 ID 重复")
		}
		recordIDs[id] = true
		if record.RecordRevision < 1 {
			add("record_revision", "invalid_revision", "必须大于等于 1")
		}
		if strings.TrimSpace(record.Text) == "" {
			add("text", "empty_text", "候选文字不能为空")
		}
		if strings.TrimSpace(record.CanonicalPinyin) == "" {
			add("canonical_pinyin", "empty_canonical_pinyin", "规范拼音不能为空")
		}
		if !validPhenomena[record.Phenomenon] {
			add("phenomenon", "invalid_phenomenon", "未知现象 %q", record.Phenomenon)
		}
		if !validScopes[record.Scope] {
			add("scope", "invalid_scope", "未知范围 %q", record.Scope)
		}
		if !validCandidatePolicies[record.CandidateTextPolicy] {
			add("candidate_text_policy", "invalid_candidate_policy", "未知策略 %q", record.CandidateTextPolicy)
		}
		if record.TranscriptionStatus != "" && !validTranscriptionStatuses[record.TranscriptionStatus] {
			add("transcription_status", "invalid_transcription_status", "未知状态 %q", record.TranscriptionStatus)
		}
		if !validAdjudicationStatuses[record.AdjudicationStatus] {
			add("adjudication_status", "invalid_adjudication_status", "未知状态 %q", record.AdjudicationStatus)
		}
		if isolatedStatuses[record.AdjudicationStatus] && record.RuntimeEnabled {
			add("runtime_enabled", "isolated_record_enabled", "%s 记录必须保持禁用", record.AdjudicationStatus)
		}
		if record.RuleID != "" {
			if !policyIDPattern.MatchString(record.RuleID) {
				add("rule_id", "invalid_rule_id", "格式无效")
			}
			if previous := ruleIDs[record.RuleID]; previous != "" {
				add("rule_id", "duplicate_rule_id", "规则 ID 已由 %s 使用", previous)
			} else {
				ruleIDs[record.RuleID] = id
			}
		}
		if (record.AdjudicationStatus == "approved_surface" || record.AdjudicationStatus == "experimental") && record.RuleID == "" {
			add("rule_id", "missing_rule_id", "表层或实验试算必须绑定规则 ID")
		}
		if record.UnderlyingTone != nil && (*record.UnderlyingTone < 1 || *record.UnderlyingTone > 4) {
			add("underlying_tone", "invalid_underlying_tone", "只能为 1 至 4 或留空")
		}
		if record.ErhuaStatus != "" && !validErhuaStatuses[record.ErhuaStatus] {
			add("erhua_status", "invalid_erhua_status", "未知状态 %q", record.ErhuaStatus)
		}
		if record.ErhuaStatus == "fused" {
			if record.AttachmentSyllableIndex == nil {
				add("attachment_syllable_index", "missing_erhua_attachment", "融合儿化必须指定附着音节")
			}
			if record.ErhuaClass == nil || strings.TrimSpace(*record.ErhuaClass) == "" {
				add("erhua_class", "missing_erhua_class", "融合儿化必须指定类别")
			}
		}
		if record.AttachmentSyllableIndex != nil && (*record.AttachmentSyllableIndex < 0 || *record.AttachmentSyllableIndex >= len(record.CanonicalYinyuanIDs)) {
			add("attachment_syllable_index", "erhua_attachment_out_of_range", "附着音节下标越界")
		}
		if record.ErCharacterIndex != nil && (*record.ErCharacterIndex < 0 || *record.ErCharacterIndex >= len([]rune(record.Text))) {
			add("er_character_index", "er_character_out_of_range", "“儿”字下标越界")
		}
		if len(record.SourceObservations) == 0 {
			add("source_observations", "missing_source_observation", "至少需要一条不可变来源观察")
		}
		for observationIndex, observation := range record.SourceObservations {
			prefix := "source_observations[" + strconv.Itoa(observationIndex) + "]"
			if strings.TrimSpace(observation.ObservationID) == "" {
				add(prefix+".observation_id", "empty_observation_id", "不能为空")
			} else if previous := observationIDs[observation.ObservationID]; previous != "" {
				add(prefix+".observation_id", "duplicate_observation_id", "观察 ID 已由 %s 使用", previous)
			} else {
				observationIDs[observation.ObservationID] = id
			}
			if !validSourcePolicies[observation.SourcePolicy] {
				add(prefix+".source_policy", "unknown_source_policy", "来源政策 %q 未登记", observation.SourcePolicy)
			}
			if strings.TrimSpace(observation.SourceLocator) == "" {
				add(prefix+".source_locator", "empty_source_locator", "不能为空")
			}
			if !sha256Pattern.MatchString(observation.SourceSHA256) {
				add(prefix+".source_sha256", "invalid_source_sha256", "必须是 64 位小写 SHA-256")
			}
			if !validTranscriptionStatuses[observation.TranscriptionStatus] {
				add(prefix+".transcription_status", "invalid_transcription_status", "未知状态 %q", observation.TranscriptionStatus)
			}
			if observation.TranscriptionStatus == "corrected" && observation.TextCorrected == nil && observation.ReadingCorrected == nil {
				add(prefix, "missing_correction", "corrected 状态必须保留至少一个独立校正字段")
			}
		}

		validateSequence := func(field string, sequence YinyuanSequence) {
			if len(sequence) == 0 {
				add(field, "empty_yinyuan_sequence", "至少需要一个音节")
				return
			}
			for syllableIndex, tuple := range sequence {
				for position, yinyuanID := range tuple {
					wantPrefix := byte('M')
					if position == 0 {
						wantPrefix = 'N'
					}
					if !yinyuanPattern.MatchString(yinyuanID) || len(yinyuanID) == 0 || yinyuanID[0] != wantPrefix {
						add(fmt.Sprintf("%s[%d][%d]", field, syllableIndex, position), "invalid_yinyuan_position", "必须是 %cxx，实际为 %q", wantPrefix, yinyuanID)
					} else if !inventory.StableIDs[yinyuanID] {
						add(fmt.Sprintf("%s[%d][%d]", field, syllableIndex, position), "unknown_yinyuan_id", "%s 未在稳定目录登记", yinyuanID)
					}
				}
			}
		}
		validateSequence("canonical_yinyuan_ids", record.CanonicalYinyuanIDs)
		validatePinyinSequence(id, "canonical_pinyin", record.CanonicalPinyin, record.CanonicalYinyuanIDs, inventory, &issues)
		if record.CompatibilityYinyuanIDs != nil {
			validateSequence("compatibility_yinyuan_ids", *record.CompatibilityYinyuanIDs)
			if len(*record.CompatibilityYinyuanIDs) != len(record.CanonicalYinyuanIDs) {
				add("compatibility_yinyuan_ids", "syllable_count_changed", "不得增删音节位置")
			}
		}
		if (record.CompatibilityReading == nil) != (record.CompatibilityYinyuanIDs == nil) {
			add("compatibility_reading", "incomplete_compatibility_path", "兼容读音和兼容四音元必须同时提供或同时省略")
		} else if record.CompatibilityReading != nil && record.CompatibilityYinyuanIDs != nil {
			validateDerivedReadingSequence(id, "compatibility_reading", *record.CompatibilityReading, *record.CompatibilityYinyuanIDs, inventory, true, &issues)
		}
		if record.SurfaceYinyuanIDs != nil {
			validateSequence("surface_yinyuan_ids", *record.SurfaceYinyuanIDs)
			if len(*record.SurfaceYinyuanIDs) != len(record.CanonicalYinyuanIDs) {
				add("surface_yinyuan_ids", "syllable_count_changed", "不得增删音节位置")
			}
		}
		if (record.SurfaceReading == nil) != (record.SurfaceYinyuanIDs == nil) {
			add("surface_reading", "incomplete_surface_path", "表层读音和表层四音元必须同时提供或同时省略")
		} else if record.SurfaceReading != nil && record.SurfaceYinyuanIDs != nil {
			validateDerivedReadingSequence(id, "surface_reading", *record.SurfaceReading, *record.SurfaceYinyuanIDs, inventory, false, &issues)
		}
		if record.AdjudicationStatus == "approved_compatibility" && (record.CompatibilityReading == nil || record.CompatibilityYinyuanIDs == nil) {
			add("compatibility_reading", "missing_compatibility_path", "兼容批准记录必须提供兼容读音和四音元")
		}
		if record.AdjudicationStatus == "approved_surface" && (record.SurfaceReading == nil || record.SurfaceYinyuanIDs == nil || len(record.Rewrites) == 0) {
			add("surface_reading", "missing_surface_path", "表层批准记录必须提供表层读音、四音元和改写")
		}
		validateRewrites(*record, inventory, add)
	}
	sort.SliceStable(issues, func(i, j int) bool {
		left := issues[i].RecordID + "\x00" + issues[i].Field + "\x00" + issues[i].Code
		right := issues[j].RecordID + "\x00" + issues[j].Field + "\x00" + issues[j].Code
		return left < right
	})
	return issues
}

func validateDerivedReadingSequence(recordID, field, reading string, sequence YinyuanSequence, inventory Inventory, requireKnown bool, issues *[]Issue) {
	parts := strings.Fields(reading)
	if strings.TrimSpace(reading) == "" || len(parts) != len(sequence) {
		*issues = append(*issues, Issue{RecordID: recordID, Field: field, Code: "derived_pinyin_syllable_count", Detail: fmt.Sprintf("读音有 %d 个音节，四音元有 %d 组", len(parts), len(sequence))})
		return
	}
	for index, pinyin := range parts {
		canonical, ok := inventory.Syllables[pinyin]
		if !ok {
			if requireKnown {
				*issues = append(*issues, Issue{RecordID: recordID, Field: field, Code: "unknown_compatibility_syllable", Detail: fmt.Sprintf("音节 %d 的 %q 不在规范分解表", index+1, pinyin)})
			}
			continue
		}
		if canonical != sequence[index] {
			*issues = append(*issues, Issue{RecordID: recordID, Field: field, Code: "derived_tuple_mismatch", Detail: fmt.Sprintf("音节 %d 的四音元与已登记音节不一致", index+1)})
		}
	}
}

func validatePinyinSequence(recordID, field, reading string, sequence YinyuanSequence, inventory Inventory, issues *[]Issue) {
	parts := strings.Fields(reading)
	if len(parts) != len(sequence) {
		*issues = append(*issues, Issue{RecordID: recordID, Field: field, Code: "pinyin_syllable_count", Detail: fmt.Sprintf("拼音有 %d 个音节，四音元有 %d 组", len(parts), len(sequence))})
		return
	}
	for index, pinyin := range parts {
		canonical, ok := inventory.Syllables[pinyin]
		if !ok {
			*issues = append(*issues, Issue{RecordID: recordID, Field: field, Code: "unknown_canonical_syllable", Detail: fmt.Sprintf("音节 %d 的 %q 不在规范分解表", index+1, pinyin)})
			continue
		}
		if canonical != sequence[index] {
			*issues = append(*issues, Issue{RecordID: recordID, Field: field, Code: "canonical_tuple_mismatch", Detail: fmt.Sprintf("音节 %d 的四音元与规范分解表不一致", index+1)})
		}
	}
}

func validateRewrites(record Record, inventory Inventory, add func(string, string, string, ...any)) {
	positions := map[string]int{"shouyin": 0, "huyin": 1, "zhuyin": 2, "moyin": 3}
	seen := map[string]bool{}
	target := append(YinyuanSequence(nil), record.CanonicalYinyuanIDs...)
	for index, rewrite := range record.Rewrites {
		field := fmt.Sprintf("rewrites[%d]", index)
		position, ok := positions[rewrite.Position]
		if !ok {
			add(field+".position", "invalid_rewrite_position", "未知位置 %q", rewrite.Position)
			continue
		}
		if rewrite.SyllableIndex < 0 || rewrite.SyllableIndex >= len(record.CanonicalYinyuanIDs) {
			add(field+".syllable_index", "rewrite_out_of_range", "音节下标越界")
			continue
		}
		key := fmt.Sprintf("%d:%d", rewrite.SyllableIndex, position)
		if seen[key] {
			add(field, "duplicate_rewrite_position", "同一位置不能改写两次")
			continue
		}
		seen[key] = true
		canonical := record.CanonicalYinyuanIDs[rewrite.SyllableIndex][position]
		if rewrite.FromID != canonical {
			add(field+".from_id", "rewrite_from_mismatch", "应为规范位置的 %s，实际为 %s", canonical, rewrite.FromID)
		}
		if !inventory.StableIDs[rewrite.ToID] {
			add(field+".to_id", "rewrite_to_unknown", "%s 未在稳定目录登记", rewrite.ToID)
		}
		if len(rewrite.Attributes) == 0 {
			add(field+".attributes", "missing_rewrite_attributes", "至少需要一个变化属性")
		}
		attributeSeen := map[string]bool{}
		for _, attribute := range rewrite.Attributes {
			if !validRewriteAttributes[attribute] {
				add(field+".attributes", "invalid_rewrite_attribute", "未知属性 %q", attribute)
			}
			if attributeSeen[attribute] {
				add(field+".attributes", "duplicate_rewrite_attribute", "属性 %q 重复", attribute)
			}
			attributeSeen[attribute] = true
		}
		tuple := target[rewrite.SyllableIndex]
		tuple[position] = rewrite.ToID
		target[rewrite.SyllableIndex] = tuple
	}
	if len(record.Rewrites) > 0 && record.SurfaceYinyuanIDs != nil && !sequenceEqual(target, *record.SurfaceYinyuanIDs) {
		add("surface_yinyuan_ids", "surface_rewrite_mismatch", "逐位置改写结果与表层四音元不一致")
	}
}

func sequenceEqual(left, right YinyuanSequence) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}
