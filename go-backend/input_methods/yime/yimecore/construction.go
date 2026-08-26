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
		path := sentencePath{text: sentence.Text, score: saturatingAdd(anchorScore, rightScore), segments: segments}
		expanded := cloneCandidate(*sentence)
		expanded.ID = sentenceCandidateID(e.rawInput, path)
		expanded.Weight = path.score
		expanded.Segments = segments
		first := expanded.Segments[focusedIndex]
		return &expanded, &first, true
	}
	return nil, nil, false
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
				score := saturatingAdd(lexicalScore(match.weight)-generatedSegmentPenalty, tail.score)
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
