package systemlexicon

import (
	"strings"
	"unicode/utf8"
)

type RuleID string

const (
	RuleAll             RuleID = "all"
	RuleSuffixParticle  RuleID = "suffix_particle"
)

var ruleLabels = map[RuleID]string{
	RuleAll:            "全部规则",
	RuleSuffixParticle: "助词/语气词结尾",
}

func RuleLabel(rule RuleID) string {
	if label, ok := ruleLabels[rule]; ok {
		return label
	}
	return string(rule)
}

func RuleOptions() []RuleID {
	return []RuleID{RuleAll, RuleSuffixParticle}
}

// particleSuffixChars mirrors prototype lexicon_quality.PARTICLE_SUFFIX_CHARS.
var particleSuffixChars = map[rune]bool{
	'的': true, '了': true, '吗': true, '呢': true, '吧': true,
	'啊': true, '嘛': true, '呀': true, '哦': true, '哈': true,
	'呗': true, '哇': true, '呐': true, '麽': true,
}

var particleSuffixWhitelist = map[string]bool{
	"你的": true, "我的": true, "他的": true, "她的": true, "它的": true,
	"我们的": true, "你们的": true, "他们的": true,
	"好的": true, "对了": true, "行了": true, "可以了": true,
	"知道了": true, "怎么了": true, "为什么": true, "是不是": true,
}

type Finding struct {
	Rule      RuleID `json:"rule"`
	RuleLabel string `json:"rule_label"`
	Text      string `json:"text"`
	Code      string `json:"code"`
	Weight    int    `json:"weight"`
	Detail    string `json:"detail"`
}

type Summary struct {
	TotalEntries int            `json:"total_entries"`
	FindingCount int            `json:"finding_count"`
	ByRule       map[RuleID]int `json:"by_rule"`
	DictPath     string         `json:"dict_path"`
	Mode         string         `json:"mode"`
}

func endsWithParticle(text string) bool {
	if utf8.RuneCountInString(text) < 2 {
		return false
	}
	r, _ := utf8.DecodeLastRuneInString(text)
	return particleSuffixChars[r]
}

func AuditEntries(entries []Entry) ([]Finding, Summary) {
	findings := make([]Finding, 0, 128)
	byRule := map[RuleID]int{}

	for _, entry := range entries {
		if utf8.RuneCountInString(entry.Text) < 2 {
			continue
		}
		if particleSuffixWhitelist[entry.Text] {
			continue
		}
		if !endsWithParticle(entry.Text) {
			continue
		}
		r, _ := utf8.DecodeLastRuneInString(entry.Text)
		finding := Finding{
			Rule:      RuleSuffixParticle,
			RuleLabel: RuleLabel(RuleSuffixParticle),
			Text:      entry.Text,
			Code:      entry.Code,
			Weight:    entry.Weight,
			Detail:    "词语以助词/语气词「" + string(r) + "」结尾，建议人工审阅是否保留。",
		}
		findings = append(findings, finding)
		byRule[RuleSuffixParticle]++
	}

	return findings, Summary{
		TotalEntries: len(entries),
		FindingCount: len(findings),
		ByRule:       byRule,
	}
}

func FilterFindings(findings []Finding, rule RuleID, keyword string) []Finding {
	keyword = strings.TrimSpace(keyword)
	filtered := make([]Finding, 0, len(findings))
	for _, item := range findings {
		if rule != RuleAll && item.Rule != rule {
			continue
		}
		if keyword != "" && !containsFold(item.Text, keyword) && !containsFold(item.Code, keyword) && !containsFold(item.Detail, keyword) {
			continue
		}
		filtered = append(filtered, item)
	}
	return filtered
}

func containsFold(haystack, needle string) bool {
	if needle == "" {
		return true
	}
	return strings.Contains(strings.ToLower(haystack), strings.ToLower(needle))
}
