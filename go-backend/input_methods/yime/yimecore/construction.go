package yimecore

import (
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

type constructionRule struct {
	anchorParts         []string
	wholeRightSlots     []string
	rightSlotLocalizers []string
}

var registeredConstructionRules = []constructionRule{
	{
		anchorParts:         []string{"保存", "在"},
		wholeRightSlots:     []string{"哪里"},
		rightSlotLocalizers: []string{"中"},
	},
}

func (e *Engine) expandSentenceSegment(sentence *engineapi.Candidate, focused engineapi.Segment) (*engineapi.Candidate, *engineapi.Segment, bool) {
	if sentence == nil || len(sentence.Segments) == 0 {
		return nil, nil, false
	}
	focusedIndex := -1
	for index, segment := range sentence.Segments {
		if segment.Start == focused.Start && segment.End == focused.End && segment.Text == focused.Text {
			focusedIndex = index
			break
		}
	}
	if focusedIndex < 0 {
		return nil, nil, false
	}
	decomposed, ok := e.decomposeSurfaceSegment(focused)
	if !ok {
		return nil, nil, false
	}
	segments := append([]engineapi.Segment(nil), sentence.Segments[:focusedIndex]...)
	segments = append(segments, decomposed.segments...)
	segments = append(segments, sentence.Segments[focusedIndex+1:]...)
	path, ok := e.pathForSegments(segments)
	if !ok {
		return nil, nil, false
	}
	expanded := cloneCandidate(*sentence)
	expanded.ID = sentenceCandidateID(e.rawInput, path)
	expanded.Weight = path.base
	expanded.Score.Context = path.context
	expanded.Segments = segments
	first := expanded.Segments[focusedIndex]
	return &expanded, &first, true
}

func (e *Engine) decomposeSurfaceSegment(segment engineapi.Segment) (sentencePath, bool) {
	if segment.Start < 0 || segment.End > len(e.rawInput) || segment.Start >= segment.End || segment.Text == "" {
		return sentencePath{}, false
	}
	maxCodeBytes := e.index.maximumCodeBytes()
	if maxCodeBytes <= 0 {
		return sentencePath{}, false
	}
	states := make([]map[int]sentencePath, len(e.rawInput)+1)
	states[segment.Start] = map[int]sentencePath{0: {}}
	for start := segment.Start; start < segment.End; start++ {
		if len(states[start]) == 0 {
			continue
		}
		lastEnd := start + maxCodeBytes
		if lastEnd > segment.End {
			lastEnd = segment.End
		}
		for textStart, path := range states[start] {
			for end := start + 1; end <= lastEnd; end++ {
				if start == segment.Start && end == segment.End {
					continue
				}
				for _, match := range e.exactMatches(e.rawInput[start:end]) {
					if match.text == "" || !strings.HasPrefix(segment.Text[textStart:], match.text) {
						continue
					}
					textEnd := textStart + len(match.text)
					sourceID := match.source
					if sourceID == "" {
						sourceID = e.index.identity()
					}
					segments := append([]engineapi.Segment(nil), path.segments...)
					segments = append(segments, engineapi.Segment{
						Start: start, End: end, Text: match.text, Code: match.code, SourceID: sourceID,
					})
					next := sentencePath{
						text: segment.Text[:textEnd],
						base: saturatingAdd(path.base, e.lexicalRecordScore(match)-generatedSegmentPenalty),
						segments: segments,
					}
					next.context = saturatingAdd(path.context, e.sentenceTransitionBoost(path, match))
					next.score = saturatingAdd(next.base, next.context)
					if states[end] == nil {
						states[end] = make(map[int]sentencePath)
					}
					existing, found := states[end][textEnd]
					if !found || betterSentencePath(next, existing) {
						states[end][textEnd] = next
					}
				}
			}
		}
	}
	path, found := states[segment.End][len(segment.Text)]
	return path, found && len(path.segments) >= 2 && path.text == segment.Text
}

func (e *Engine) pathForSegments(segments []engineapi.Segment) (sentencePath, bool) {
	path := sentencePath{segments: append([]engineapi.Segment(nil), segments...)}
	for _, segment := range segments {
		bestContribution := int64(0)
		found := false
		for _, match := range e.exactMatches(segment.Code) {
			if match.text != segment.Text {
				continue
			}
			sourceID := match.source
			if sourceID == "" {
				sourceID = e.index.identity()
			}
			if segment.SourceID != "" && segment.SourceID != sourceID {
				continue
			}
			contribution := e.lexicalRecordScore(match) - generatedSegmentPenalty
			if !found || contribution > bestContribution {
				bestContribution = contribution
				found = true
			}
		}
		if !found {
			return sentencePath{}, false
		}
		path.text += segment.Text
		path.base = saturatingAdd(path.base, bestContribution)
	}
	path.context = e.segmentSequenceContextBoost(path.segments)
	path.score = saturatingAdd(path.base, path.context)
	return path, true
}

func (e *Engine) resegmentConstruction(sentence *engineapi.Candidate, focused engineapi.Segment) (*engineapi.Candidate, *engineapi.Segment, bool) {
	if sentence == nil || len(sentence.Segments) == 0 {
		return nil, nil, false
	}
	focusedIndex := -1
	for index, segment := range sentence.Segments {
		if segment.Start == focused.Start && segment.End == focused.End && segment.Text == focused.Text {
			focusedIndex = index
			break
		}
	}
	if focusedIndex < 0 {
		return nil, nil, false
	}

	for _, rule := range registeredConstructionRules {
		if focused.Text != strings.Join(rule.anchorParts, "") {
			continue
		}
		anchor, anchorScore, ok := e.sourceSegmentsForTexts(focused.Start, focused.End, rule.anchorParts)
		if !ok || len(anchor) < 2 {
			continue
		}
		rightStart := focused.End
		rightEnd := rightStart
		var rightSurface strings.Builder
		for _, segment := range sentence.Segments[focusedIndex+1:] {
			if segment.Start != rightEnd {
				return nil, nil, false
			}
			rightEnd = segment.End
			rightSurface.WriteString(segment.Text)
		}
		rightTexts, ok := rule.rightSlotParts(rightSurface.String())
		if !ok {
			continue
		}
		right, rightScore, ok := e.sourceSegmentsForTexts(rightStart, rightEnd, rightTexts)
		if !ok {
			continue
		}

		segments := append([]engineapi.Segment(nil), sentence.Segments[:focusedIndex]...)
		segments = append(segments, anchor...)
		segments = append(segments, right...)
		base := saturatingAdd(anchorScore, rightScore)
		context := e.segmentSequenceContextBoost(segments)
		path := sentencePath{text: sentence.Text, base: base, context: context,
			score: saturatingAdd(base, context), segments: segments}
		expanded := cloneCandidate(*sentence)
		expanded.ID = sentenceCandidateID(e.rawInput, path)
		expanded.Weight = path.base
		expanded.Score.Context = path.context
		expanded.Segments = segments
		first := expanded.Segments[focusedIndex]
		return &expanded, &first, true
	}
	return nil, nil, false
}

func (e *Engine) segmentSequenceContextBoost(segments []engineapi.Segment) int64 {
	previous := e.previousCommit
	var total int64
	for _, segment := range segments {
		total = saturatingAdd(total, e.userModel.contextBoost(previous, segment.Code, segment.Text))
		previous = segment.Text
	}
	return total
}

func (rule constructionRule) rightSlotParts(surface string) ([]string, bool) {
	for _, whole := range rule.wholeRightSlots {
		if surface == whole {
			return []string{whole}, true
		}
	}
	for _, localizer := range rule.rightSlotLocalizers {
		base := strings.TrimSuffix(surface, localizer)
		if base != "" && base != surface {
			return []string{base, localizer}, true
		}
	}
	return nil, false
}

func (e *Engine) sourceSegmentsForTexts(start, end int, texts []string) ([]engineapi.Segment, int64, bool) {
	if start < 0 || end > len(e.rawInput) || start >= end || len(texts) == 0 {
		return nil, 0, false
	}
	type result struct {
		segments []engineapi.Segment
		score    int64
		found    bool
	}
	var search func(position, textIndex int) result
	search = func(position, textIndex int) result {
		if textIndex == len(texts) {
			return result{found: position == end}
		}
		best := result{}
		for next := position + 1; next <= end; next++ {
			for _, match := range e.exactMatches(e.rawInput[position:next]) {
				if match.text != texts[textIndex] {
					continue
				}
				tail := search(next, textIndex+1)
				if !tail.found {
					continue
				}
				sourceID := match.source
				if sourceID == "" {
					sourceID = e.index.identity()
				}
				segment := engineapi.Segment{
					Start: position, End: next, Text: match.text, Code: match.code, SourceID: sourceID,
				}
				score := saturatingAdd(e.lexicalRecordScore(match)-generatedSegmentPenalty, tail.score)
				if !best.found || score > best.score {
					best = result{
						segments: append([]engineapi.Segment{segment}, tail.segments...),
						score:    score, found: true,
					}
				}
			}
		}
		return best
	}
	matched := search(start, 0)
	return matched.segments, matched.score, matched.found
}

func (e *Engine) expandExactWholeSentence(sentence *engineapi.Candidate, start, end int) (*engineapi.Candidate, *engineapi.Segment, bool) {
	if sentence == nil || len(sentence.Segments) != 0 || start != 0 || end != len(e.rawInput) ||
		sentence.Text == "" {
		return nil, nil, false
	}
	for _, candidate := range e.composeSentences(e.rawInput, sentenceBeamWidth) {
		if !candidate.Exact || candidate.Text != sentence.Text || len(candidate.Segments) < 2 {
			continue
		}
		expanded := cloneCandidate(candidate)
		expanded.SourceID = sentence.SourceID
		first := expanded.Segments[0]
		return &expanded, &first, true
	}
	return nil, nil, false
}
