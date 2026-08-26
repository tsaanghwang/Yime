package yimecore

import "github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"

// DecodeTraceSchemaVersion identifies the stable, host-neutral explanation
// format. The trace is diagnostic evidence, not a candidate-window contract.
const DecodeTraceSchemaVersion = "yimecore-decode-trace-v1"

// DecodeTrace exposes the lexicon edges, retained sentence paths and visible
// ranking for the current input without depending on TSF or any Windows UI.
// V1 reports paths retained by the production beam. A later schema can add
// every rejected path and its pruning reason without changing the decoder.
type DecodeTrace struct {
	SchemaVersion     string                  `json:"schema_version"`
	IndexSourceID     string                  `json:"index_source_id"`
	Input             string                  `json:"input"`
	PreviousCommit    string                  `json:"previous_commit,omitempty"`
	Limits            DecodeLimits            `json:"limits"`
	Edges             []DecodeEdge            `json:"edges"`
	RetainedPaths     []DecodePath            `json:"retained_paths"`
	PreeditSentence   *engineapi.Candidate    `json:"preedit_sentence,omitempty"`
	VisibleCandidates []RankedDecodeCandidate `json:"visible_candidates"`
	Limitations       []string                `json:"limitations,omitempty"`
}

type DecodeLimits struct {
	SentenceBeamWidth     int `json:"sentence_beam_width"`
	SegmentCandidateLimit int `json:"segment_candidate_limit"`
	VisibleCandidateLimit int `json:"visible_candidate_limit"`
}

// DecodeEdge is one exact dictionary match over a byte span of the raw ASCII
// input. SourceID keeps the contributing bundle/index auditable.
type DecodeEdge struct {
	Start    int    `json:"start"`
	End      int    `json:"end"`
	Text     string `json:"text"`
	Code     string `json:"code"`
	Weight   int64  `json:"weight"`
	SourceID string `json:"source_id"`
}

// DecodePath is one complete or incomplete multi-edge path retained by the
// same beam used by the runtime sentence composer.
type DecodePath struct {
	Rank           int                 `json:"rank"`
	Text           string              `json:"text"`
	Code           string              `json:"code"`
	Complete       bool                `json:"complete"`
	Segments       []engineapi.Segment `json:"segments"`
	Score          engineapi.Score     `json:"score"`
	SegmentPenalty int64               `json:"segment_penalty"`
}

type RankedDecodeCandidate struct {
	Rank      int                 `json:"rank"`
	Candidate engineapi.Candidate `json:"candidate"`
}

// Explain returns an immutable diagnostic snapshot for the current input.
// It performs no persistence and does not change the active candidate page.
func (e *Engine) Explain() DecodeTrace {
	trace := DecodeTrace{
		SchemaVersion:  DecodeTraceSchemaVersion,
		IndexSourceID:  e.index.identity(),
		Input:          e.rawInput,
		PreviousCommit: e.previousCommit,
		Limits: DecodeLimits{
			SentenceBeamWidth: sentenceBeamWidth, SegmentCandidateLimit: segmentCandidateLimit,
			VisibleCandidateLimit: e.limit,
		},
		Limitations: []string{
			"v1 records paths retained by the runtime beam, not every rejected path",
			"static weight still combines lexicon ranking evidence and source priority",
		},
	}
	if e.rawInput == "" {
		return trace
	}
	trace.Edges = e.explainEdges(e.rawInput)
	paths := e.composeSentences(e.rawInput, sentenceBeamWidth)
	trace.RetainedPaths = make([]DecodePath, 0, len(paths))
	for i := range paths {
		candidate := cloneCandidate(paths[i])
		e.scoreCandidate(&candidate)
		trace.RetainedPaths = append(trace.RetainedPaths, DecodePath{
			Rank: i + 1, Text: candidate.Text, Code: candidate.Code, Complete: candidate.Exact,
			Segments: append([]engineapi.Segment(nil), candidate.Segments...), Score: candidate.Score,
			SegmentPenalty: int64(len(candidate.Segments)) * generatedSegmentPenalty,
		})
	}
	trace.VisibleCandidates = make([]RankedDecodeCandidate, len(e.candidates))
	for i := range e.candidates {
		trace.VisibleCandidates[i] = RankedDecodeCandidate{Rank: i + 1, Candidate: cloneCandidate(e.candidates[i])}
	}
	if e.sentence != nil {
		sentence := cloneCandidate(*e.sentence)
		trace.PreeditSentence = &sentence
	} else if e.focusedSentence != nil {
		sentence := cloneCandidate(*e.focusedSentence)
		trace.PreeditSentence = &sentence
	}
	return trace
}

func (e *Engine) explainEdges(input string) []DecodeEdge {
	maxCodeBytes := e.index.maximumCodeBytes()
	if maxCodeBytes <= 0 {
		return nil
	}
	edges := make([]DecodeEdge, 0, len(input)*2)
	for end := 1; end <= len(input); end++ {
		first := end - maxCodeBytes
		if first < 0 {
			first = 0
		}
		for start := first; start < end; start++ {
			for _, match := range e.index.exact(input[start:end], segmentCandidateLimit) {
				sourceID := match.source
				if sourceID == "" {
					sourceID = e.index.identity()
				}
				edges = append(edges, DecodeEdge{
					Start: start, End: end, Text: match.text, Code: match.code,
					Weight: match.weight, SourceID: sourceID,
				})
			}
		}
	}
	return edges
}
