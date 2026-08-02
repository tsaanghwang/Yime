package trainer

import (
	"fmt"
	"sort"
)

const GroupCategoryFingering = "fingering"

type fingeringKey struct {
	id, key  string
	entry    Yinyuan
	finger   FingerAssignment
	row, col int
}

func (resolver *Resolver) ResolveFingeringDrills() ([]ExerciseGroup, error) {
	keys := make([]fingeringKey, 0, len(resolver.catalog.Entries))
	for _, entry := range resolver.catalog.Entries {
		key := resolver.layout.Projection[entry.ID]
		row, col, ok := keyboardPosition(physicalBaseKey(key))
		if !ok {
			return nil, fmt.Errorf("音元 %s 的物理键 %q 无法生成指法专项", entry.ID, key)
		}
		keys = append(keys, fingeringKey{id: entry.ID, key: key, entry: entry, finger: fingerForKey(key), row: row, col: col})
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i].id < keys[j].id })
	adjacent := pairAdjacentKeys(keys, 12)
	sameFinger := pairSameFingerKeys(keys, 12)
	alternating := pairAlternatingHands(keys, 12)
	return []ExerciseGroup{
		resolver.fingeringGroup("fingering-adjacent", "相邻键", "练习相邻物理键的准确换位", adjacent),
		resolver.fingeringGroup("fingering-same-finger", "同指换键", "练习同一手指离开和返回基准键", sameFinger),
		resolver.fingeringGroup("fingering-alternating", "左右手交替", "练习左右手连续交替", alternating),
	}, nil
}

func (resolver *Resolver) fingeringGroup(id, title, description string, pairs [][2]fingeringKey) ExerciseGroup {
	group := ExerciseGroup{ID: id, Category: GroupCategoryFingering, Title: title, Description: description}
	for _, pair := range pairs {
		units := make([]AnswerUnit, 0, 2)
		for unitIndex, value := range pair {
			units = append(units, AnswerUnit{ExpectedKey: value.key, Position: fmt.Sprintf("第%d音元", unitIndex+1), YinyuanID: value.id, DisplayName: value.entry.DisplayName})
		}
		group.Exercises = append(group.Exercises, Exercise{
			ID:           fmt.Sprintf("%s:%s:%s", id, pair[0].id, pair[1].id),
			SectionType:  SectionKeymap,
			SectionTitle: "音元练习",
			Instruction:  description + "；按顺序输入两个目标键。",
			Prompt:       pair[0].entry.DisplayName + " → " + pair[1].entry.DisplayName,
			Detail: fmt.Sprintf("%s %s：%s%s（基准键 %s）    %s %s：%s%s（基准键 %s）",
				pair[0].id, pair[0].key, pair[0].finger.Hand, pair[0].finger.Finger, pair[0].finger.HomeKey,
				pair[1].id, pair[1].key, pair[1].finger.Hand, pair[1].finger.Finger, pair[1].finger.HomeKey),
			Expected:     pair[0].key + pair[1].key,
			AnswerLabel:  "目标键序列",
			AnswerUnits:  units,
			LearningTags: []string{"fingering:" + id, "yinyuan:" + pair[0].id, "yinyuan:" + pair[1].id},
		})
	}
	return group
}

func keyboardPosition(key string) (int, int, bool) {
	rows := []string{"`1234567890-=", "qwertyuiop[]\\", "asdfghjkl;'", "zxcvbnm,./"}
	for row, values := range rows {
		for col, char := range values {
			if string(char) == key {
				return row, col, true
			}
		}
	}
	return 0, 0, false
}

func pairAdjacentKeys(keys []fingeringKey, limit int) [][2]fingeringKey {
	result := [][2]fingeringKey{}
	for left := 0; left < len(keys) && len(result) < limit; left++ {
		for right := left + 1; right < len(keys) && len(result) < limit; right++ {
			if physicalBaseKey(keys[left].key) == physicalBaseKey(keys[right].key) {
				continue
			}
			rowDistance := keys[left].row - keys[right].row
			if rowDistance < 0 {
				rowDistance = -rowDistance
			}
			colDistance := keys[left].col - keys[right].col
			if colDistance < 0 {
				colDistance = -colDistance
			}
			if rowDistance <= 1 && colDistance <= 1 {
				result = append(result, [2]fingeringKey{keys[left], keys[right]})
			}
		}
	}
	return result
}

func pairSameFingerKeys(keys []fingeringKey, limit int) [][2]fingeringKey {
	result := [][2]fingeringKey{}
	for left := 0; left < len(keys) && len(result) < limit; left++ {
		for right := left + 1; right < len(keys) && len(result) < limit; right++ {
			if keys[left].finger.Hand == keys[right].finger.Hand && keys[left].finger.Finger == keys[right].finger.Finger &&
				physicalBaseKey(keys[left].key) != physicalBaseKey(keys[right].key) {
				result = append(result, [2]fingeringKey{keys[left], keys[right]})
			}
		}
	}
	return result
}

func pairAlternatingHands(keys []fingeringKey, limit int) [][2]fingeringKey {
	left, right := []fingeringKey{}, []fingeringKey{}
	for _, key := range keys {
		if key.finger.Hand == "左手" {
			left = append(left, key)
		}
		if key.finger.Hand == "右手" {
			right = append(right, key)
		}
	}
	count := minInt(limit, len(left), len(right))
	result := make([][2]fingeringKey, 0, count)
	for index := 0; index < count; index++ {
		result = append(result, [2]fingeringKey{left[index], right[index]})
	}
	return result
}
