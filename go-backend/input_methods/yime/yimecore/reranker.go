package yimecore

import (
	"strconv"
	"unicode/utf8"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

const (
	maximumRerankerFeatureValue = int64(4096)
	rerankerLearningStep        = int64(100_000_000)
	maximumRerankerWeight       = int64(800_000_000)
)

func sentenceRerankerFeatures(segments []engineapi.Segment) map[string]int64 {
	features := make(map[string]int64, len(segments)*2+2)
	features["segment_count"] = int64(len(segments))
	previous := "<start>"
	for _, segment := range segments {
		features["segment\x1f"+segment.Code+"\x1f"+segment.Text]++
		features["transition\x1f"+previous+"\x1f"+segment.Text]++
		features["segment_runes\x1f"+strconv.Itoa(utf8.RuneCountInString(segment.Text))]++
		previous = segment.Text
	}
	return features
}

func (m *UserModel) sentenceRerankerScore(segments []engineapi.Segment) int64 {
	if m == nil || len(segments) < 2 {
		return 0
	}
	features := sentenceRerankerFeatures(segments)
	m.mu.RLock()
	defer m.mu.RUnlock()
	var score int64
	for feature, value := range features {
		if value > maximumRerankerFeatureValue {
			value = maximumRerankerFeatureValue
		}
		score = saturatingAdd(score, saturatingMultiply(m.rerankerWeights[feature], value))
	}
	return score
}

func rerankerCorrectionDelta(rejected, selected []engineapi.Segment) map[string]int64 {
	if len(rejected) < 2 || len(selected) < 2 {
		return nil
	}
	delta := sentenceRerankerFeatures(selected)
	for feature, value := range sentenceRerankerFeatures(rejected) {
		delta[feature] -= value
	}
	for feature, value := range delta {
		if value == 0 {
			delete(delta, feature)
		}
	}
	return delta
}

func validRerankerDelta(delta map[string]int64) bool {
	if len(delta) > maximumUserModelItems {
		return false
	}
	for feature, value := range delta {
		if feature == "" || value == 0 || value > maximumRerankerFeatureValue || value < -maximumRerankerFeatureValue {
			return false
		}
	}
	return true
}

func (m *UserModel) applyRerankerDeltaLocked(delta map[string]int64) {
	if len(delta) != 0 && m.rerankerWeights == nil {
		m.rerankerWeights = make(map[string]int64)
	}
	for feature, value := range delta {
		change := saturatingMultiply(value, rerankerLearningStep)
		weight := saturatingAdd(m.rerankerWeights[feature], change)
		if weight > maximumRerankerWeight {
			weight = maximumRerankerWeight
		} else if weight < -maximumRerankerWeight {
			weight = -maximumRerankerWeight
		}
		if weight == 0 {
			delete(m.rerankerWeights, feature)
		} else {
			m.rerankerWeights[feature] = weight
		}
	}
}

func saturatingMultiply(left, right int64) int64 {
	if left == 0 || right == 0 {
		return 0
	}
	if left > 0 && right > 0 && left > int64(^uint64(0)>>1)/right {
		return int64(^uint64(0) >> 1)
	}
	if left < 0 && right > 0 && left < -int64(^uint64(0)>>1)/right {
		return -int64(^uint64(0)>>1) - 1
	}
	return left * right
}
