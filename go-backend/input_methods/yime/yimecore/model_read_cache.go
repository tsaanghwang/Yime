package yimecore

type candidateModelScore struct {
	user    int64
	context int64
}

type modelScoreSequenceKey struct {
	input        string
	previous     string
	page         int
	segmentStart int
	segmentEnd   int
	segmentCode  string
	segmentText  string
}

type candidateModelScoreEntry struct {
	identity candidateIdentity
	score    candidateModelScore
}

// User-model writes are rare compared with scoring reads. Cache immutable
// scores per engine generation so one refresh takes one model lock to observe
// the generation instead of taking locks for every candidate and sentence
// segment. A mutation increments Generation and invalidates all cached views
// before the next refresh.
func (e *Engine) syncUserModelReadCache() {
	if e == nil || e.userModel == nil {
		return
	}
	generation := e.userModel.Generation()
	if e.modelGenerationOK && e.modelGeneration == generation {
		return
	}
	e.modelGeneration = generation
	e.modelGenerationOK = true
	e.modelCandidate = nil
	e.modelContext = nil
	e.modelScoreContext = ""
	e.modelScore = nil
	e.modelSequences = nil
	e.modelSequence = nil
	e.modelSequenceAt = 0
	e.modelSequenceItems = 0
	e.modelSequenceNew = false
	e.modelSequenceLive = false
	e.modelLearned = nil
}

// beginUserModelScoreSequence turns the repeated scoring order for one input
// state into a fast, validated read path. Interactive edits and E3 replay both
// revisit the same small states far more often than the user model changes.
// Every entry still carries its full identity, so a changed candidate order
// falls back to the ordinary cache without reusing a mismatched score.
func (e *Engine) beginUserModelScoreSequence() bool {
	if e == nil || e.userModel == nil || e.modelSequenceLive {
		return false
	}
	key := modelScoreSequenceKey{
		input: e.rawInput, previous: e.previousCommit, page: e.pageNumber,
		segmentStart: -1, segmentEnd: -1,
	}
	if e.activeSegment != nil {
		key.segmentStart = e.activeSegment.Start
		key.segmentEnd = e.activeSegment.End
		key.segmentCode = e.activeSegment.Code
		key.segmentText = e.activeSegment.Text
	}
	e.modelSequenceKey = key
	e.modelSequenceAt = 0
	e.modelSequenceLive = true
	if sequence, found := e.modelSequences[key]; found {
		e.modelSequence = sequence
		e.modelSequenceNew = false
	} else {
		e.modelSequence = nil
		e.modelSequenceNew = true
	}
	return true
}

func (e *Engine) endUserModelScoreSequence() {
	if e == nil || !e.modelSequenceLive {
		return
	}
	if e.modelSequenceNew && len(e.modelSequence) > 0 &&
		e.modelSequenceItems+len(e.modelSequence) <= maximumExactCacheItems {
		if e.modelSequences == nil {
			e.modelSequences = make(map[modelScoreSequenceKey][]candidateModelScoreEntry)
		}
		e.modelSequences[e.modelSequenceKey] = e.modelSequence
		e.modelSequenceItems += len(e.modelSequence)
	}
	e.modelSequence = nil
	e.modelSequenceAt = 0
	e.modelSequenceNew = false
	e.modelSequenceLive = false
}

func (e *Engine) userCandidateModelScore(previous, code, text string) candidateModelScore {
	if e == nil || e.userModel == nil {
		return candidateModelScore{}
	}
	identity := candidateIdentity{code: code, text: text}
	if e.modelSequenceLive && !e.modelSequenceNew && e.modelSequenceAt < len(e.modelSequence) {
		entry := e.modelSequence[e.modelSequenceAt]
		if entry.identity == identity {
			e.modelSequenceAt++
			return entry.score
		}
		// The state key is intentionally compact. If another editing detail
		// changes the scoring order, abandon this replay instead of guessing.
		e.modelSequence = nil
	}
	if previous != e.modelScoreContext {
		e.modelScoreContext = previous
		e.modelScore = nil
	}
	if score, found := e.modelScore[identity]; found {
		e.recordUserModelScore(identity, score)
		return score
	}
	score := candidateModelScore{
		user:    e.userCandidateBoost(code, text),
		context: e.userContextBoost(previous, code, text),
	}
	if len(e.modelScore) < maximumExactCacheItems {
		if e.modelScore == nil {
			e.modelScore = make(map[candidateIdentity]candidateModelScore)
		}
		e.modelScore[identity] = score
	}
	e.recordUserModelScore(identity, score)
	return score
}

func (e *Engine) recordUserModelScore(identity candidateIdentity, score candidateModelScore) {
	if !e.modelSequenceLive || !e.modelSequenceNew || len(e.modelSequence) >= maximumExactCacheItems {
		return
	}
	e.modelSequence = append(e.modelSequence, candidateModelScoreEntry{identity: identity, score: score})
}

func (e *Engine) userCandidateBoost(code, text string) int64 {
	if e == nil || e.userModel == nil {
		return 0
	}
	identity := candidateIdentity{code: code, text: text}
	if boost, found := e.modelCandidate[identity]; found {
		return boost
	}
	boost := e.userModel.candidateBoost(code, text)
	if len(e.modelCandidate) < maximumExactCacheItems {
		if e.modelCandidate == nil {
			e.modelCandidate = make(map[candidateIdentity]int64)
		}
		e.modelCandidate[identity] = boost
	}
	return boost
}

func (e *Engine) userContextBoost(previous, code, text string) int64 {
	if e == nil || e.userModel == nil || previous == "" {
		return 0
	}
	identity := contextIdentity{previous: previous, candidateIdentity: candidateIdentity{code: code, text: text}}
	if boost, found := e.modelContext[identity]; found {
		return boost
	}
	boost := e.userModel.contextBoost(previous, code, text)
	if len(e.modelContext) < maximumExactCacheItems {
		if e.modelContext == nil {
			e.modelContext = make(map[contextIdentity]int64)
		}
		e.modelContext[identity] = boost
	}
	return boost
}

func (e *Engine) userLearnedCandidates(code string, limit int) []candidateIdentity {
	if e == nil || e.userModel == nil || code == "" || limit <= 0 {
		return nil
	}
	key := prefixCacheKey{prefix: code, limit: limit}
	if candidates, found := e.modelLearned[key]; found {
		return candidates
	}
	candidates := e.userModel.learnedCandidates(code, limit)
	if len(e.modelLearned) < maximumExactCacheItems {
		if e.modelLearned == nil {
			e.modelLearned = make(map[prefixCacheKey][]candidateIdentity)
		}
		e.modelLearned[key] = candidates
	}
	return candidates
}
