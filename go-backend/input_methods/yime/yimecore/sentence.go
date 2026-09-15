package yimecore

import (
	"math"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

const (
	sentenceBeamWidth        = 64
	segmentCandidateLimit    = 64
	sentenceSurfacePathLimit = 4
	generatedSegmentPenalty  = int64(250_000)
	maximumExactCacheItems   = 4096
	maximumSentenceBytes     = 256
	maximumLearnedTextBytes  = 4096
	sentenceShapePrefix      = 8
)

type sentencePath struct {
	text     string
	base     int64
	context  int64
	score    int64
	segments []engineapi.Segment
	tail     *sentenceNode
	keyHash  uint64
	lengths  [sentenceShapePrefix]uint16
	count    uint16
}

type sentenceNode struct {
	parent  *sentenceNode
	segment engineapi.Segment
}

type completion struct {
	candidate engineapi.Candidate
	segments  int
	score     int64
}

// bestSentence returns the single preedit sentence for the current input.
// Exact dictionary entries win, followed by an exact word-graph path, an
// incomplete path with a completed left side, and finally one root-prefix
// prediction. State.Sentence owns the best preedit independently from the
// selectable exact and prefix candidates published by Engine.refresh.
func (e *Engine) bestSentence(exact []engineapi.Candidate, limit int) *engineapi.Candidate {
	var preferredExact *engineapi.Candidate
	if len(exact) > 0 && len(e.segmentChoices) == 0 {
		candidate := cloneCandidate(exact[0])
		preferredExact = &candidate
		if candidate.SourceID != "user-model" {
			return preferredExact
		}
	}
	generated := e.composeSentences(e.rawInput, limit)
	records := e.sentencePrefixRecords(e.rawInput, limit)
	for _, item := range records {
		if item.code == e.rawInput || !strings.HasPrefix(item.code, e.rawInput) {
			continue
		}
		sourceID := item.source
		if sourceID == "" {
			sourceID = e.index.identity()
		}
		candidate := engineapi.Candidate{
			ID:       "sentence-prefix\x1f" + e.rawInput + "\x1f" + item.code + "\x1f" + item.text,
			Text:     item.text,
			Code:     item.code,
			SourceID: sourceID,
			Weight:   item.weight,
			Exact:    false,
			Segments: []engineapi.Segment{{
				Start: 0, End: len(e.rawInput), Text: item.text, Code: item.code, SourceID: sourceID,
			}},
		}
		generated = append(generated, candidate)
	}
	for i := range generated {
		e.scoreComposedCandidateWithContext(&generated[i], generated[i].Score.Context)
	}
	rankGeneratedCandidates(generated)
	if preferredExact != nil {
		if rebuilt := e.composeLearnedSentence(e.rawInput, preferredExact.Text); rebuilt != nil {
			e.scoreComposedCandidateWithContext(rebuilt, rebuilt.Score.Context)
			return rebuilt
		}
		for index := range generated {
			if generated[index].Exact && generated[index].Code == preferredExact.Code &&
				generated[index].Text == preferredExact.Text {
				candidate := cloneCandidate(generated[index])
				candidate.SourceID = "user-model"
				return &candidate
			}
		}
		return preferredExact
	}
	if len(generated) == 0 {
		return nil
	}
	candidate := cloneCandidate(generated[0])
	return &candidate
}

func (e *Engine) sentencePrefixRecords(input string, limit int) []record {
	if !e.isFirstSyllableInput(input) {
		return e.index.lookup(input, limit)
	}
	fetchLimit := segmentCandidateLimit
	if fetchLimit < limit {
		fetchLimit = limit
	}
	for {
		source := e.index.lookup(input, fetchLimit)
		records := singleCharacterRecords(source, limit)
		if len(records) >= limit {
			return records
		}
		if len(source) < fetchLimit || fetchLimit >= maximumExactCacheItems {
			if len(records) > 0 {
				return records
			}
			return e.index.lookup(input, limit)
		}
		fetchLimit *= 2
		if fetchLimit > maximumExactCacheItems {
			fetchLimit = maximumExactCacheItems
		}
	}
}

func (e *Engine) firstSyllableExactRecords(input string, limit int) ([]record, bool) {
	if !e.isFirstSyllableInput(input) {
		return e.index.exact(input, limit), false
	}
	fetchLimit := segmentCandidateLimit
	if fetchLimit < limit {
		fetchLimit = limit
	}
	for {
		source := e.index.exact(input, fetchLimit)
		records := singleCharacterRecords(source, limit)
		if len(records) >= limit {
			return records, true
		}
		if len(source) < fetchLimit || fetchLimit >= maximumExactCacheItems {
			if len(records) > 0 {
				return records, true
			}
			return e.index.exact(input, limit), false
		}
		fetchLimit *= 2
		if fetchLimit > maximumExactCacheItems {
			fetchLimit = maximumExactCacheItems
		}
	}
}

func (e *Engine) isFirstSyllableInput(input string) bool {
	for end := 1; end < len(input); end++ {
		for _, item := range e.exactMatches(input[:end]) {
			if isSingleCharacter(item.text) {
				return false
			}
		}
	}
	return true
}

func singleCharacterRecords(records []record, limit int) []record {
	result := make([]record, 0, limit)
	for _, item := range records {
		if isSingleCharacter(item.text) {
			result = append(result, item)
			if len(result) == limit {
				break
			}
		}
	}
	return result
}

func isSingleCharacter(text string) bool {
	return utf8.RuneCountInString(text) == 1
}

func (e *Engine) composeLearnedSentence(input, text string) *engineapi.Candidate {
	if len(input) < 2 || len(input) > maximumSentenceBytes || text == "" ||
		len(text) > maximumLearnedTextBytes {
		return nil
	}
	maxCodeBytes := e.index.maximumCodeBytes()
	if maxCodeBytes <= 0 {
		return nil
	}
	states := make([]map[int]sentencePath, len(input)+1)
	states[0] = map[int]sentencePath{0: {}}
	for start := 0; start < len(input); start++ {
		if len(states[start]) == 0 {
			continue
		}
		lastEnd := start + maxCodeBytes
		if lastEnd > len(input) {
			lastEnd = len(input)
		}
		for textStart, path := range states[start] {
			for end := start + 1; end <= lastEnd; end++ {
				for _, match := range e.exactMatches(input[start:end]) {
					if match.text == "" || !strings.HasPrefix(text[textStart:], match.text) {
						continue
					}
					textEnd := textStart + len(match.text)
					sourceID := match.source
					if sourceID == "" {
						sourceID = e.index.identity()
					}
					segment := engineapi.Segment{
						Start: start, End: end, Text: match.text, Code: match.code, SourceID: sourceID,
					}
					next := sentencePath{
						text: text[:textEnd],
						base: saturatingAdd(path.base, e.lexicalRecordScore(match)-generatedSegmentPenalty),
					}
					appendSentenceSegment(&next, path, segment)
					next.context = saturatingAdd(path.context, e.sentenceTransitionBoost(path, match))
					next.score = saturatingAdd(next.base, next.context)
					if states[end] == nil {
						states[end] = make(map[int]sentencePath)
					}
					existing, found := states[end][textEnd]
					if !found || e.betterLearnedSentencePath(next, existing) {
						states[end][textEnd] = next
					}
				}
			}
		}
	}
	path, found := states[len(input)][len(text)]
	if !found || path.count < 2 || path.text != text {
		return nil
	}
	path = e.collapseExactSegmentGroups(path)
	segments := sentencePathSegments(path)
	return &engineapi.Candidate{
		ID: sentenceCandidateID(input, path), Text: text, Code: input,
		SourceID: "user-model", Weight: path.base, Exact: true, Segments: segments,
		Score: engineapi.Score{Context: path.context},
	}
}

func (e *Engine) betterLearnedSentencePath(left, right sentencePath) bool {
	leftBoost := e.sentencePathLearningBoost(left)
	rightBoost := e.sentencePathLearningBoost(right)
	if leftBoost != rightBoost {
		return leftBoost > rightBoost
	}
	return betterSentencePath(left, right)
}

func (e *Engine) sentencePathLearningBoost(path sentencePath) int64 {
	previous := e.previousCommit
	var boost int64
	for _, segment := range sentencePathSegments(path) {
		boost = saturatingAdd(boost, e.userCandidateBoost(segment.Code, segment.Text))
		boost = saturatingAdd(boost, e.userContextBoost(previous, segment.Code, segment.Text))
		previous = segment.Text
	}
	return boost
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
		if path.count >= 2 {
			complete = append(complete, path)
		}
	}
	sort.Slice(complete, func(i, j int) bool { return e.betterRetainedSentencePath(complete[i], complete[j]) })
	if len(complete) > limit {
		complete = complete[:limit]
	}
	result := make([]engineapi.Candidate, 0, len(complete))
	for _, path := range complete {
		segments := sentencePathSegments(path)
		result = append(result, engineapi.Candidate{
			ID: sentenceCandidateID(input, path), Text: path.text, Code: input,
			Weight: path.base, Exact: true, Segments: segments,
			Score: engineapi.Score{Context: path.context},
		})
	}
	for _, candidate := range e.composeIncompleteTail(input, limit, maxCodeBytes) {
		result = append(result, candidate)
	}
	return result
}

func (e *Engine) betterRetainedSentencePath(left, right sentencePath) bool {
	if priority := compareSentencePathShape(left, right); priority != 0 {
		return priority > 0
	}
	if e.linearReranker {
		leftScore := saturatingAdd(left.score, e.userModel.sentenceRerankerScore(sentencePathSegments(left)))
		rightScore := saturatingAdd(right.score, e.userModel.sentenceRerankerScore(sentencePathSegments(right)))
		if leftScore != rightScore {
			return leftScore > rightScore
		}
	}
	return betterSentencePath(left, right)
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
	top := make([]completion, 0, limit)
	seen := make(map[string]struct{}, limit*2)
	for split := firstSplit; split < len(input); split++ {
		paths := e.sentenceStates[split]
		if len(paths) == 0 {
			continue
		}
		suffix := input[split:]
		matches := e.sentencePrefixRecords(suffix, limit)
		pathLimit := len(paths)
		if pathLimit > limit {
			pathLimit = limit
		}
		materialized := make([][]engineapi.Segment, pathLimit)
		for index, path := range paths[:pathLimit] {
			if path.count > 0 {
				materialized[index] = sentencePathSegments(path)
			}
		}
		for _, match := range matches {
			if match.code == suffix || !strings.HasPrefix(match.code, suffix) {
				continue
			}
			for pathIndex, path := range paths[:pathLimit] {
				if path.count == 0 {
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
				segments := make([]engineapi.Segment, len(materialized[pathIndex])+1)
				copy(segments, materialized[pathIndex])
				segments[len(segments)-1] = engineapi.Segment{
					Start: split, End: len(input), Text: match.text, Code: match.code, SourceID: sourceID,
				}
				base := saturatingAdd(path.base, e.lexicalRecordScore(match)-generatedSegmentPenalty)
				context := saturatingAdd(path.context, e.sentenceTransitionBoost(path, match))
				score := saturatingAdd(base, context)
				item := completion{candidate: engineapi.Candidate{
					ID:   "sentence-prefix\x1f" + input + "\x1f" + completedCode + "\x1f" + text,
					Text: text, Code: completedCode, Weight: base, Exact: false, Segments: segments,
					Score: engineapi.Score{Context: context},
				}, segments: len(segments), score: score}
				top = insertCompletion(top, item, limit)
			}
		}
	}
	result := make([]engineapi.Candidate, len(top))
	for index := range top {
		result[index] = top[index].candidate
	}
	return result
}

func insertCompletion(top []completion, item completion, limit int) []completion {
	if len(top) == limit && !betterCompletion(item, top[len(top)-1]) {
		return top
	}
	if len(top) < limit {
		top = append(top, item)
	} else {
		top[len(top)-1] = item
	}
	for position := len(top) - 1; position > 0 && betterCompletion(top[position], top[position-1]); position-- {
		top[position], top[position-1] = top[position-1], top[position]
	}
	return top
}

func betterCompletion(left, right completion) bool {
	if priority := compareWordFirstSegments(left.candidate.Segments, right.candidate.Segments); priority != 0 {
		return priority > 0
	}
	if left.score != right.score {
		return left.score > right.score
	}
	if left.candidate.Text != right.candidate.Text {
		return left.candidate.Text < right.candidate.Text
	}
	return left.candidate.Code < right.candidate.Code
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
				segment := engineapi.Segment{
					Start: start, End: end, Text: match.text, Code: match.code, SourceID: sourceID,
				}
				next := sentencePath{
					text: path.text + match.text,
					base: saturatingAdd(path.base, e.lexicalRecordScore(match)-generatedSegmentPenalty),
				}
				appendSentenceSegment(&next, path, segment)
				next.context = saturatingAdd(path.context, e.sentenceTransitionBoost(path, match))
				next.score = saturatingAdd(next.base, next.context)
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

func (e *Engine) lexicalRecordScore(item record) int64 {
	return saturatingAdd(lexicalScore(item.weight), e.userCandidateBoost(item.code, item.text))
}

func (e *Engine) sentenceTransitionBoost(path sentencePath, item record) int64 {
	previous := e.previousCommit
	if path.tail != nil {
		previous = path.tail.segment.Text
	} else if len(path.segments) > 0 {
		previous = path.segments[len(path.segments)-1].Text
	}
	return e.userContextBoost(previous, item.code, item.text)
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
	itemHash := sentencePathHash(item)
	var sameText [sentenceSurfacePathLimit]int
	sameTextCount := 0
	for i := range top {
		if top[i].text != item.text {
			continue
		}
		if sameTextCount < len(sameText) {
			sameText[sameTextCount] = i
			sameTextCount++
		}
		if sentencePathHash(top[i]) != itemHash || sentencePathKey(top[i]) != sentencePathKey(item) {
			continue
		}
		if betterSentencePath(item, top[i]) {
			top[i] = item
			bubbleSentencePathUp(top, i)
		}
		return top
	}
	// Distinct segmentations of the same surface text must survive long enough
	// for explainable path scoring and future word-context models. Bound their
	// contribution so one ambiguous surface cannot consume the whole beam.
	if sameTextCount >= sentenceSurfacePathLimit {
		worst := sameText[0]
		for _, position := range sameText[1:sameTextCount] {
			if betterSentencePath(top[worst], top[position]) {
				worst = position
			}
		}
		if betterSentencePath(item, top[worst]) {
			top[worst] = item
			bubbleSentencePathUp(top, worst)
		}
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

func bubbleSentencePathUp(top []sentencePath, position int) {
	for position > 0 && betterSentencePath(top[position], top[position-1]) {
		top[position], top[position-1] = top[position-1], top[position]
		position--
	}
}

func betterSentencePath(left, right sentencePath) bool {
	if priority := compareSentencePathShape(left, right); priority != 0 {
		return priority > 0
	}
	if left.score != right.score {
		return left.score > right.score
	}
	if left.text != right.text {
		return left.text < right.text
	}
	return sentencePathKey(left) < sentencePathKey(right)
}

func appendSentenceShape(next *sentencePath, parent sentencePath, text string) {
	next.lengths = parent.lengths
	next.count = parent.count + 1
	if parent.count < sentenceShapePrefix {
		next.lengths[parent.count] = uint16(utf8.RuneCountInString(text))
	}
}

func appendSentenceSegment(next *sentencePath, parent sentencePath, segment engineapi.Segment) {
	parentTail := parent.tail
	if parentTail == nil && len(parent.segments) > 0 {
		for _, existing := range parent.segments {
			parentTail = &sentenceNode{parent: parentTail, segment: existing}
		}
	}
	next.tail = &sentenceNode{parent: parentTail, segment: segment}
	next.keyHash = appendSentencePathHash(parent.keyHash, segment)
	appendSentenceShape(next, parent, segment.Text)
}

func sentencePathSegments(path sentencePath) []engineapi.Segment {
	if path.segments != nil || path.count == 0 {
		return path.segments
	}
	segments := make([]engineapi.Segment, int(path.count))
	node := path.tail
	for index := len(segments) - 1; index >= 0 && node != nil; index-- {
		segments[index] = node.segment
		node = node.parent
	}
	return segments
}

func compareSentencePathShape(left, right sentencePath) int {
	count := int(left.count)
	if int(right.count) < count {
		count = int(right.count)
	}
	if count > sentenceShapePrefix {
		count = sentenceShapePrefix
	}
	for index := 0; index < count; index++ {
		if left.lengths[index] > right.lengths[index] {
			return 1
		}
		if left.lengths[index] < right.lengths[index] {
			return -1
		}
	}
	if left.count <= sentenceShapePrefix && right.count <= sentenceShapePrefix {
		if left.count < right.count {
			return 1
		}
		if left.count > right.count {
			return -1
		}
		return 0
	}
	return compareWordFirstSegments(sentencePathSegments(left), sentencePathSegments(right))
}

func compareWordFirstSegments(left, right []engineapi.Segment) int {
	// Input-order priority is lexicographic: prefer the longest built-in word
	// at the first differing segment, then use frequency for an equal shape.
	count := len(left)
	if len(right) < count {
		count = len(right)
	}
	for index := 0; index < count; index++ {
		leftLength := utf8.RuneCountInString(left[index].Text)
		rightLength := utf8.RuneCountInString(right[index].Text)
		if leftLength > rightLength {
			return 1
		}
		if leftLength < rightLength {
			return -1
		}
	}
	if len(left) < len(right) {
		return 1
	}
	if len(left) > len(right) {
		return -1
	}
	return 0
}

func sentenceCandidateID(input string, path sentencePath) string {
	return "sentence\x1f" + input + "\x1f" + path.text + "\x1f" + sentencePathKey(path)
}

func sentencePathKey(path sentencePath) string {
	key := ""
	for _, segment := range sentencePathSegments(path) {
		key = appendSentencePathKey(key, segment)
	}
	return key
}

func sentencePathHash(path sentencePath) uint64 {
	if path.keyHash != 0 || path.count == 0 {
		return path.keyHash
	}
	var hash uint64
	for _, segment := range sentencePathSegments(path) {
		hash = appendSentencePathHash(hash, segment)
	}
	return hash
}

func appendSentencePathHash(hash uint64, segment engineapi.Segment) uint64 {
	const offset64 = uint64(14695981039346656037)
	const prime64 = uint64(1099511628211)
	if hash == 0 {
		hash = offset64
	}
	appendByte := func(value byte) { hash = (hash ^ uint64(value)) * prime64 }
	for shift := 0; shift < 32; shift += 8 {
		appendByte(byte(uint32(segment.Start) >> shift))
	}
	for shift := 0; shift < 32; shift += 8 {
		appendByte(byte(uint32(segment.End) >> shift))
	}
	for index := 0; index < len(segment.Code); index++ {
		appendByte(segment.Code[index])
	}
	appendByte(0xff)
	for index := 0; index < len(segment.Text); index++ {
		appendByte(segment.Text[index])
	}
	appendByte(0xfe)
	return hash
}

func appendSentencePathKey(prefix string, segment engineapi.Segment) string {
	buffer := make([]byte, 0, len(prefix)+len(segment.Code)+len(segment.Text)+24)
	buffer = append(buffer, prefix...)
	buffer = strconv.AppendInt(buffer, int64(segment.Start), 10)
	buffer = append(buffer, ':')
	buffer = strconv.AppendInt(buffer, int64(segment.End), 10)
	buffer = append(buffer, ':')
	buffer = append(buffer, segment.Code...)
	buffer = append(buffer, ':')
	buffer = append(buffer, segment.Text...)
	buffer = append(buffer, '\x1e')
	return string(buffer)
}
