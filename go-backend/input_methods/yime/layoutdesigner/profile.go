// Package layoutdesigner provides the guarded, single-source workflow used by
// Yime maintainers to design and apply Yinyuan-ID keyboard projections.
package layoutdesigner

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const (
	ProfileFileName      = "yime_yinyuan_layout.json"
	ProfileFormatVersion = 1
)

var reservedKeys = map[rune]string{
	'~': "Shift+反引号保留键",
	'!': "Shift+数字候选键的物理键面", '@': "Shift+数字候选键的物理键面", '#': "Shift+数字候选键的物理键面", '$': "Shift+数字候选键的物理键面",
	'%': "Shift+数字候选键的物理键面", '^': "Shift+数字候选键的物理键面", '&': "Shift+数字候选键的物理键面", '*': "Shift+数字候选键的物理键面", '(': "Shift+数字候选键的物理键面",
}

// sharedIdentityGroups are deliberate many-to-one physical projections.  The
// IDs remain distinct in the semantic layer and may have different contextual
// realizations, but users type the same key because their distributions are
// mutually exclusive at the shouyin position.
var sharedIdentityGroups = [][]string{
	{"N12", "N26"}, // ordinary zero/virtual onset and particle-a [ŋ]
	{"N25", "N27"}, // yu-family [ɥ] and particle-a apical [ɹ]
}

// Profile is the sole editable projection. Yinyuan identity and codec
// semantics are intentionally absent: maintainers can move IDs, not redefine
// them from the middle of the encoding chain.
type Profile struct {
	FormatVersion int               `json:"format_version"`
	Name          string            `json:"name"`
	Description   string            `json:"description,omitempty"`
	BasedOnDigest string            `json:"based_on_layout_digest,omitempty"`
	Projection    map[string]string `json:"yinyuan_id_to_key"`
}

func ExpectedIDs() []string {
	ids := make([]string, 0, 60)
	for i := 1; i <= 27; i++ {
		ids = append(ids, fmt.Sprintf("N%02d", i))
	}
	for i := 1; i <= 33; i++ {
		ids = append(ids, fmt.Sprintf("M%02d", i))
	}
	return ids
}

func DescribeID(id string) string {
	shouyinLabels := []string{"b", "p", "f", "m", "d", "t", "l", "n", "g", "k", "h", "'（非高呼音前虚首音）", "z", "c", "s", "zh", "ch", "sh", "r [ʐ]/[ɻ]", "j", "q", "x", "y [j]（虚首音）", "w（虚首音）", "ɥ（ü 前虚首音）", "ŋ（啊的同化首音）", "ɹ（啊的舌尖同化首音）"}
	if strings.HasPrefix(id, "N") {
		if n, err := strconv.Atoi(strings.TrimPrefix(id, "N")); err == nil && n >= 1 && n <= len(shouyinLabels) {
			return shouyinLabels[n-1]
		}
	}
	groups := []string{"i", "u", "ü", "a", "o", "e/ê", "舌尖 i", "er", "m", "n", "ng"}
	levels := []string{"高", "中", "低"}
	if strings.HasPrefix(id, "M") {
		if n, err := strconv.Atoi(strings.TrimPrefix(id, "M")); err == nil && n >= 1 && n <= 33 {
			return groups[(n-1)/3] + levels[(n-1)%3]
		}
	}
	return "未知"
}

func LoadProfile(path string) (Profile, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Profile{}, err
	}
	var p Profile
	if err := json.Unmarshal(data, &p); err != nil {
		return Profile{}, fmt.Errorf("解析布局 %s: %w", path, err)
	}
	upgradeLegacyProjection(&p)
	if err := p.Validate(); err != nil {
		return Profile{}, err
	}
	return p, nil
}

func (p Profile) Validate() error {
	var issues []string
	if p.FormatVersion != ProfileFormatVersion {
		issues = append(issues, fmt.Sprintf("format_version 必须为 %d", ProfileFormatVersion))
	}
	expected := map[string]bool{}
	for _, id := range ExpectedIDs() {
		expected[id] = true
	}
	occupied := map[rune]string{}
	for id, key := range p.Projection {
		if !expected[id] {
			issues = append(issues, "未知 Yinyuan ID: "+id)
			continue
		}
		r := []rune(key)
		if len(r) != 1 {
			issues = append(issues, id+" 必须映射到一个可打印 ASCII 字符")
			continue
		}
		if r[0] < '!' || r[0] > '~' {
			issues = append(issues, fmt.Sprintf("%s 的键 %q 不是可打印 ASCII", id, key))
			continue
		}
		if reason := reservedKeys[r[0]]; reason != "" {
			issues = append(issues, fmt.Sprintf("%s 占用了%s %q", id, reason, key))
		}
		if old := occupied[r[0]]; old != "" && !sameSharedIdentityGroup(old, id) {
			issues = append(issues, fmt.Sprintf("键 %q 非法地同时分配给 %s 和 %s", key, old, id))
		} else {
			occupied[r[0]] = id
		}
		delete(expected, id)
	}
	for _, group := range sharedIdentityGroups {
		key := p.Projection[group[0]]
		for _, id := range group[1:] {
			if p.Projection[id] != key {
				issues = append(issues, fmt.Sprintf("受控共享组 %s 必须共用一键", strings.Join(group, "/")))
			}
		}
	}
	if len(expected) > 0 {
		missing := make([]string, 0, len(expected))
		for id := range expected {
			missing = append(missing, id)
		}
		sort.Strings(missing)
		issues = append(issues, "缺少 Yinyuan ID: "+strings.Join(missing, " "))
	}
	if len(issues) > 0 {
		return fmt.Errorf("布局无效：%s", strings.Join(issues, "；"))
	}
	return nil
}

func (p Profile) Digest() (string, error) {
	if err := p.Validate(); err != nil {
		return "", err
	}
	ids := ExpectedIDs()
	sort.Strings(ids)
	pairs := make([][2]string, 0, len(ids))
	for _, id := range ids {
		pairs = append(pairs, [2]string{id, p.Projection[id]})
	}
	var encoded bytes.Buffer
	encoder := json.NewEncoder(&encoded)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(pairs); err != nil {
		return "", err
	}
	data := bytes.TrimSuffix(encoded.Bytes(), []byte{'\n'})
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:]), nil
}

func (p Profile) Alphabet() string {
	const order = "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"
	used := map[rune]bool{}
	for _, key := range p.Projection {
		r := []rune(key)
		if len(r) == 1 {
			used[r[0]] = true
		}
	}
	var b strings.Builder
	for _, r := range order {
		if used[r] {
			b.WriteRune(r)
			delete(used, r)
		}
	}
	extra := make([]rune, 0, len(used))
	for r := range used {
		extra = append(extra, r)
	}
	sort.Slice(extra, func(i, j int) bool { return extra[i] < extra[j] })
	for _, r := range extra {
		b.WriteRune(r)
	}
	return b.String()
}

// Assign puts id on key and swaps with the current occupant, preserving total
// one-to-one coverage throughout an interactive editing session.
func (p *Profile) Assign(id, key string) error {
	if p.Projection == nil {
		return fmt.Errorf("布局没有 projection")
	}
	if _, ok := p.Projection[id]; !ok {
		return fmt.Errorf("未知 Yinyuan ID: %s", id)
	}
	r := []rune(key)
	if len(r) != 1 {
		return fmt.Errorf("键必须是单个字符")
	}
	old := p.Projection[id]
	moving := sharedGroupMembers(id)
	occupants := []string{}
	for other, current := range p.Projection {
		if current == key && !containsString(moving, other) {
			occupants = append(occupants, other)
		}
	}
	for _, occupant := range occupants {
		for _, member := range sharedGroupMembers(occupant) {
			p.Projection[member] = old
		}
	}
	for _, member := range moving {
		p.Projection[member] = key
	}
	return p.Validate()
}

func sharedGroupMembers(id string) []string {
	for _, group := range sharedIdentityGroups {
		if containsString(group, id) {
			return append([]string(nil), group...)
		}
	}
	return []string{id}
}

func sameSharedIdentityGroup(left, right string) bool {
	for _, group := range sharedIdentityGroups {
		if containsString(group, left) && containsString(group, right) {
			return true
		}
	}
	return false
}

func containsString(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}

// upgradeLegacyProjection keeps stored 57-yinyuan user layouts loadable.  The
// newly stable identities inherit their mandated shared keys; no old key is
// moved, and the formerly reserved backtick becomes the new [ɥ]/[ɹ] key.
func upgradeLegacyProjection(p *Profile) {
	if p == nil || p.Projection == nil || p.Projection["N25"] != "" || p.Projection["N26"] != "" || p.Projection["N27"] != "" {
		return
	}
	if p.Projection["N12"] == "" || p.Projection["N24"] == "" {
		return
	}
	p.Projection["N25"] = "`"
	p.Projection["N26"] = p.Projection["N12"]
	p.Projection["N27"] = "`"
	// A legacy based-on digest describes a 57-ID projection and cannot be
	// compared meaningfully with the promoted 60-ID canonical profile.
	p.BasedOnDigest = ""
}

func WriteProfileAtomic(path string, p Profile) error {
	if err := p.Validate(); err != nil {
		return err
	}
	data, err := json.MarshalIndent(p, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
