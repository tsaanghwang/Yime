package yimecore

type candidateModelScore struct {
	user    int64
	context int64
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
	e.modelLearned = nil
}

func (e *Engine) userCandidateModelScore(previous, code, text string) candidateModelScore {
	if e == nil || e.userModel == nil {
		return candidateModelScore{}
	}
	if previous != e.modelScoreContext {
		e.modelScoreContext = previous
		e.modelScore = nil
	}
	identity := candidateIdentity{code: code, text: text}
	if score, found := e.modelScore[identity]; found {
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
	return score
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
