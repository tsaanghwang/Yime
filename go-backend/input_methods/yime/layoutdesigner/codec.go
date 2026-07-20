package layoutdesigner

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

type Codec struct {
	sourceByKey map[rune]string
	targetByID  map[string]string
}

func NewCodec(source, target Profile) (*Codec, error) {
	inverse, err := inverseProjection(source)
	if err != nil {
		return nil, err
	}
	if err := target.Validate(); err != nil {
		return nil, err
	}
	projection := make(map[string]string, len(target.Projection))
	for id, key := range target.Projection {
		projection[id] = key
	}
	return &Codec{inverse, projection}, nil
}

func inverseProjection(p Profile) (map[rune]string, error) {
	if err := p.Validate(); err != nil {
		return nil, err
	}
	result := map[rune]string{}
	for id, key := range p.Projection {
		result[[]rune(key)[0]] = id
	}
	return result, nil
}

func DecodeFullCode(full string, source Profile) ([]string, error) {
	inverse, err := inverseProjection(source)
	if err != nil {
		return nil, err
	}
	runes := []rune(strings.TrimSpace(full))
	if len(runes) == 0 || len(runes)%4 != 0 {
		return nil, fmt.Errorf("等长码长度必须是 4 的倍数: %q", full)
	}
	ids := make([]string, 0, len(runes))
	for _, r := range runes {
		id := inverse[r]
		if id == "" {
			return nil, fmt.Errorf("源布局没有键 %q", r)
		}
		ids = append(ids, id)
	}
	return ids, nil
}

func ProjectIDs(ids []string, target Profile) (string, error) {
	if err := target.Validate(); err != nil {
		return "", err
	}
	var b strings.Builder
	for _, id := range ids {
		key := target.Projection[id]
		if key == "" {
			return "", fmt.Errorf("目标布局缺少 %s", id)
		}
		b.WriteString(key)
	}
	return b.String(), nil
}

// ReencodeRecord follows key -> Yinyuan ID -> new key. Variable and shorthand
// rules operate on IDs, so their meaning is independent of physical placement.
func ReencodeRecord(full string, source, target Profile) (codemode.Record, error) {
	codec, err := NewCodec(source, target)
	if err != nil {
		return codemode.Record{}, err
	}
	return codec.Reencode(full)
}

func (c *Codec) Reencode(full string) (codemode.Record, error) {
	runes := []rune(strings.TrimSpace(full))
	if len(runes) == 0 || len(runes)%4 != 0 {
		return codemode.Record{}, fmt.Errorf("等长码长度必须是 4 的倍数: %q", full)
	}
	ids := make([]string, 0, len(runes))
	for _, r := range runes {
		id := c.sourceByKey[r]
		if id == "" {
			return codemode.Record{}, fmt.Errorf("源布局没有键 %q", r)
		}
		ids = append(ids, id)
	}
	project := func(items []string) (string, error) {
		var b strings.Builder
		for _, id := range items {
			key := c.targetByID[id]
			if key == "" {
				return "", fmt.Errorf("目标布局缺少 %s", id)
			}
			b.WriteString(key)
		}
		return b.String(), nil
	}
	projected, err := project(ids)
	if err != nil {
		return codemode.Record{}, err
	}
	var variable, shorthand []string
	for start := 0; start < len(ids); start += 4 {
		part := mergeIDs(ids[start : start+4])
		variable = append(variable, part...)
		// N12 is the virtual initial. Preserve it just like a real initial so
		// zero-initial syllables retain an explicit boundary after projection.
		initial := part[:1]
		ganyin := part[1:]
		shorthand = append(shorthand, initial...)
		shorthand = append(shorthand, omitMiddleID(ganyin)...)
	}
	variableCode, err := project(variable)
	if err != nil {
		return codemode.Record{}, err
	}
	shortCode, err := project(shorthand)
	if err != nil {
		return codemode.Record{}, err
	}
	return codemode.Record{Full: projected, Variable: variableCode, Shorthand: shortCode}, nil
}

func mergeIDs(ids []string) []string {
	result := make([]string, 0, len(ids))
	for _, id := range ids {
		if len(result) == 0 || result[len(result)-1] != id {
			result = append(result, id)
		}
	}
	return result
}

func musicalPosition(id string) (group, level int, ok bool) {
	if len(id) != 3 || id[0] != 'M' {
		return 0, 0, false
	}
	n, err := strconv.Atoi(id[1:])
	if err != nil || n < 1 || n > 33 {
		return 0, 0, false
	}
	return (n - 1) / 3, (n - 1) % 3, true
}

func omitMiddleID(ids []string) []string {
	if len(ids) != 3 {
		return append([]string(nil), ids...)
	}
	g0, l0, o0 := musicalPosition(ids[0])
	g1, l1, o1 := musicalPosition(ids[1])
	g2, l2, o2 := musicalPosition(ids[2])
	if o0 && o1 && o2 && g0 == g1 && g1 == g2 && l1 == 1 && ((l0 == 0 && l2 == 2) || (l0 == 2 && l2 == 0)) {
		return []string{ids[0], ids[2]}
	}
	return append([]string(nil), ids...)
}
