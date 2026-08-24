package yimecore

import (
	"fmt"
	"math"
	"sort"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

const (
	sentenceBeamWidth       = 64
	segmentCandidateLimit   = 64
	generatedSegmentPenalty = int64(250_000)
	maximumExactCacheItems  = 4096
	maximumSentenceBytes    = 256
)

type sentencePath struct {
	text     string
	score    int64
	segments []engineapi.Segment
}

func (e *Engine) composeSentences(input string, limit int) []engineapi.Candidate {
	if limit <= 0 || len(input) < 2 || len(input) > maximumSentenceBytes {
		return nil
	}
	maxCodeBytes := e.index.maximumCodeBytes()
	if maxCodeBytes <= 0 {
		return nil
	}
	e.syncSentenceLattice(input, maxCodeBytes)

	complete := make([]sentencePath, 0, len(e.sentenceStates[len(input)]))
	for _, path := range e.sentenceStates[len(input)] {
		if len(path.segments) >= 2 {
			complete = append(complete, path)
		}
	}
	sort.Slice(complete, func(i, j int) bool { return betterSentencePath(complete[i], complete[j]) })
	if len(complete) > limit {
		complete = complete[:limit]
	}
	result := make([]engineapi.Candidate, 0, len(complete))
	for _, path := range complete {
		result = append(result, engineapi.Candidate{
			ID: sentenceCandidateID(input, path), Text: path.text, Code: input,
			Weight: path.score, Exact: true, Segments: path.segments,
		})
	}
	for _, candidate := range e.composeIncompleteTail(input, limit, maxCodeBytes) {
		result = append(result, candidate)
	}
	return result
}

// composeIncompleteTail carries already completed search-tree paths into the
// next still-incomplete term. Without this bridge, a valid prefix such as the
// first three keys of the second word can produce an empty candidate node even
// though both the completed left path and the right prefix are valid.
func (e *Engine) composeIncompleteTail(input string, limit, maxCodeBytes int) []engineapi.Candidate {
	if limit <= 0 || len(input) < 2 || len(e.sentenceStates) <= len(input) {
		return nil
	}
	firstSplit := len(input) - maxCodeBytes + 1
	if firstSplit < 1 {
		firstSplit = 1
	}
	type completion struct {
		candidate engineapi.Candidate
		segments  int
	}
	top := make([]completion, 0, limit)
	seen := make(map[string]struct{}, limit*2)
	for split := firstSplit; split < len(input); split++ {
		paths := e.sentenceStates[split]
		if len(paths) == 0 {
			continue
		}
		suffix := input[split:]
		matches := e.index.lookup(suffix, limit)
		for _, match := range matches {
			if match.code == suffix || !strings.HasPrefix(match.code, suffix) {
				continue
			}
			pathLimit := len(paths)
			if pathLimit > limit {
				pathLimit = limit
			}
			for _, path := range paths[:pathLimit] {
				if len(path.segments) == 0 {
					continue
				}
				completedCode := input[:split] + match.code
				text := path.text + match.text
				key := completedCode + "\x1f" + text
				if _, exists := seen[key]; exists {
					continue
				}
				seen[key] = struct{}{}
				sourceID := match.source
				if sourceID == "" {
					sourceID = e.index.identity()
				}
				segments := append([]engineapi.Segment(nil), path.segments...)
				segments = append(segments, engineapi.Segment{
					Start: split, End: len(input), Text: match.text, Code: match.code, SourceID: sourceID,
				})
				weight := saturatingAdd(path.score, lexicalScore(match.weight)-generatedSegmentPenalty)
				top = append(top, completion{candidate: engineapi.Candidate{
					ID:   "sentence-prefix\x1f" + input + "\x1f" + completedCode + "\x1f" + text,
					Text: text, Code: completedCode, Weight: weight, Exact: false, Segments: segments,
				}, segments: len(segments)})
			}
		}
	}
	sort.Slice(top, func(i, j int) bool {
		if top[i].segments != top[j].segments {
			return top[i].segments < top[j].segments
		}
		if top[i].candidate.Weight != top[j].candidate.Weight {
			return top[i].candidate.Weight > top[j].candidate.Weight
		}
		if top[i].candidate.Text != top[j].candidate.Text {
			return top[i].candidate.Text < top[j].candidate.Text
		}
		return top[i].candidate.Code < top[j].candidate.Code
	})
	if len(top) > limit {
		top = top[:limit]
	}
	result := make([]engineapi.Candidate, len(top))
	for index := range top {
		result[index] = top[index].candidate
	}
	return result
}

func (e *Engine) syncSentenceLattice(input string, maxCodeBytes int) {
	if input == e.sentenceInput {
		return
	}
	if e.sentenceStates == nil || !strings.HasPrefix(input, e.sentenceInput) {
		if strings.HasPrefix(e.sentenceInput, input) && len(e.sentenceStates) >= len(input)+1 {
			e.sentenceStates = e.sentenceStates[:len(input)+1]
			e.sentenceInput = input
			return
		}
		e.sentenceInput = ""
		e.sentenceStates = [][]sentencePath{{{}}}
	}
	for len(e.sentenceInput) < len(input) {
		nextEnd := len(e.sentenceInput) + 1
		e.extendSentenceLattice(input[:nextEnd], maxCodeBytes)
	}
}

func (e *Engine) extendSentenceLattice(input string, maxCodeBytes int) {
	end := len(input)
	e.sentenceStates = append(e.sentenceStates, nil)
	// Rime accepts apostrophe as an explicit boundary even though it is also
	// part of Yime's alphabet. Retain both interpretations.
	if input[end-1] == '\'' {
		for _, path := range e.sentenceStates[end-1] {
			e.sentenceStates[end] = insertSentencePath(e.sentenceStates[end], path, sentenceBeamWidth)
		}
	}
	first := end - maxCodeBytes
	if first < 0 {
		first = 0
	}
	for start := first; start < end; start++ {
		if len(e.sentenceStates[start]) == 0 {
			continue
		}
		span := segmentSpan{start: start, end: end}
		selected, hasSelection := e.segmentChoices[span]
		if e.segmentOverlapsSelection(span) && !hasSelection {
			continue
		}
		matches := e.exactMatches(input[start:end])
		if hasSelection {
			matches = []record{selected}
		}
		for _, match := range matches {
			for _, path := range e.sentenceStates[start] {
				sourceID := match.source
				if sourceID == "" {
					sourceID = e.index.identity()
				}
				segments := append([]engineapi.Segment(nil), path.segments...)
				segments = append(segments, engineapi.Segment{
					Start: start, End: end, Text: match.text, Code: match.code, SourceID: sourceID,
				})
				next := sentencePath{
					text:     path.text + match.text,
					score:    saturatingAdd(path.score, lexicalScore(match.weight)-generatedSegmentPenalty),
					segments: segments,
				}
				e.sentenceStates[end] = insertSentencePath(e.sentenceStates[end], next, sentenceBeamWidth)
			}
		}
	}
	e.sentenceInput = input
}

func (e *Engine) segmentOverlapsSelection(candidate segmentSpan) bool {
	for selected := range e.segmentChoices {
		if candidate.start < selected.end && candidate.end > selected.start {
			return true
		}
	}
	return false
}

func (e *Engine) resetSentenceComposer() {
	e.exactCache = nil
	e.sentenceInput = ""
	e.sentenceStates = nil
}

func (e *Engine) exactMatches(code string) []record {
	if matches, found := e.exactCache[code]; found {
		return matches
	}
	matches := e.index.exact(code, segmentCandidateLimit)
	if len(e.exactCache) < maximumExactCacheItems {
		if e.exactCache == nil {
			e.exactCache = make(map[string][]record)
		}
		e.exactCache[code] = matches
	}
	return matches
}

func lexicalScore(weight int64) int64 {
	return weight
}

func saturatingAdd(left, right int64) int64 {
	if right > 0 && left > math.MaxInt64-right {
		return math.MaxInt64
	}
	if right < 0 && left < math.MinInt64-right {
		return math.MinInt64
	}
	return left + right
}

func insertSentencePath(top []sentencePath, item sentencePath, limit int) []sentencePath {
	for i := range top {
		if top[i].text != item.text {
			continue
		}
		if betterSentencePath(item, top[i]) {
			top[i] = item
		}
		sort.Slice(top, func(i, j int) bool { return betterSentencePath(top[i], top[j]) })
		return top
	}
	if len(top) == limit && !betterSentencePath(item, top[len(top)-1]) {
		return top
	}
	if len(top) < limit {
		top = append(top, item)
	} else {
		top[len(top)-1] = item
	}
	for i := len(top) - 1; i > 0 && betterSentencePath(top[i], top[i-1]); i-- {
		top[i], top[i-1] = top[i-1], top[i]
	}
	return top
}

func betterSentencePath(left, right sentencePath) bool {
	if len(left.segments) != len(right.segments) {
		return len(left.segments) < len(right.segments)
	}
	if left.score != right.score {
		return left.score > right.score
	}
	if left.text != right.text {
		return left.text < right.text
	}
	return sentencePathKey(left) < sentencePathKey(right)
}

func sentenceCandidateID(input string, path sentencePath) string {
	return "sentence\x1f" + input + "\x1f" + path.text + "\x1f" + sentencePathKey(path)
}

func sentencePathKey(path sentencePath) string {
	var key strings.Builder
	for _, segment := range path.segments {
		fmt.Fprintf(&key, "%d:%d:%s:%s\x1e", segment.Start, segment.End, segment.Code, segment.Text)
	}
	return key.String()
}
