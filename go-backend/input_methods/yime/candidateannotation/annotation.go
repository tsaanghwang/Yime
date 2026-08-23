// Package candidateannotation decorates host-neutral YimeCore candidates with
// display-only encodings derived from the reviewed runtime data. It does not
// alter lookup, ranking, selection IDs or committed text.
package candidateannotation

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

type codeRecord struct {
	full, variable, shorthand string
}

type Resolver struct {
	mode          reverselookup.Mode
	codeByNumeric map[string]codeRecord
	numericByCode map[string][]string
	marked        map[string]string
	pua           map[string]string
	sourceTruth   map[string][]string
}

func Load(dataDir, modeName string) (*Resolver, error) {
	mode := reverselookup.Mode(modeName)
	if mode != reverselookup.ModeFull && mode != reverselookup.ModeVariable && mode != reverselookup.ModeShorthand {
		return nil, fmt.Errorf("unsupported annotation mode %q", modeName)
	}
	records, err := loadCodeRecords(filepath.Join(dataDir, "yime_pinyin_codes.tsv"))
	if err != nil {
		return nil, err
	}
	truth, err := reverselookup.LoadSourceTruth(dataDir, mode)
	if err != nil {
		return nil, err
	}
	marked, err := loadStringMap(filepath.Join(dataDir, "pinyin_normalized.json"))
	if err != nil {
		return nil, err
	}
	pua, err := loadPUA(filepath.Join(dataDir, "yime_pua_pinyin.json"))
	if err != nil {
		return nil, err
	}
	resolver := &Resolver{
		mode: mode, codeByNumeric: records, marked: marked, pua: pua, sourceTruth: truth,
		numericByCode: make(map[string][]string),
	}
	for numeric, record := range records {
		code := record.variable
		if mode == reverselookup.ModeFull {
			code = record.full
		} else if mode == reverselookup.ModeShorthand {
			code = record.shorthand
		}
		resolver.numericByCode[code] = appendUnique(resolver.numericByCode[code], numeric)
	}
	for code := range resolver.numericByCode {
		sort.Strings(resolver.numericByCode[code])
	}
	return resolver, nil
}

func (r *Resolver) Annotate(candidate *engineapi.Candidate) {
	if candidate == nil {
		return
	}
	candidate.Annotations.KeySequence = strings.ReplaceAll(strings.TrimSpace(candidate.Code), " ", "")
	if r == nil || candidate.Annotations.KeySequence == "" {
		return
	}
	alternatives := r.sourceTruth[reverselookup.SourceTruthLookupKey(candidate.Text, candidate.Code)]
	if len(alternatives) == 0 {
		if parts, ok := r.splitCode(candidate.Annotations.KeySequence); ok {
			alternatives = []string{strings.Join(parts, " ")}
		}
	}
	if len(alternatives) == 0 && len(candidate.Segments) >= 2 {
		var numericParts []string
		for _, segment := range candidate.Segments {
			parts, ok := r.splitCode(strings.ReplaceAll(segment.Code, " ", ""))
			if !ok {
				numericParts = nil
				break
			}
			numericParts = append(numericParts, parts...)
		}
		if len(numericParts) > 0 {
			alternatives = []string{strings.Join(numericParts, " ")}
		}
	}
	markedValues := make([]string, 0, len(alternatives))
	yinyuanValues := make([]string, 0, len(alternatives))
	for _, numeric := range alternatives {
		parts := strings.Fields(numeric)
		if value, ok := r.markedSequence(parts); ok {
			markedValues = appendUnique(markedValues, value)
		}
		if value, ok := r.yinyuanSequence(parts); ok {
			yinyuanValues = appendUnique(yinyuanValues, value)
		}
	}
	candidate.Annotations.StandardPinyin = strings.Join(markedValues, " / ")
	candidate.Annotations.Yinyuan = strings.Join(yinyuanValues, " / ")
}

func (r *Resolver) splitCode(code string) ([]string, bool) {
	if code == "" {
		return nil, false
	}
	type path struct {
		parts []string
		ok    bool
		many  bool
	}
	states := make([]path, len(code)+1)
	states[0].ok = true
	for end := 1; end <= len(code); end++ {
		for start := 0; start < end; start++ {
			if !states[start].ok {
				continue
			}
			values := r.numericByCode[code[start:end]]
			for _, numeric := range values {
				candidate := append(append([]string(nil), states[start].parts...), numeric)
				if !states[end].ok {
					states[end] = path{parts: candidate, ok: true, many: states[start].many || len(values) > 1}
				} else if strings.Join(states[end].parts, "\x00") != strings.Join(candidate, "\x00") {
					states[end].many = true
				}
			}
		}
	}
	return states[len(code)].parts, states[len(code)].ok && !states[len(code)].many
}

func (r *Resolver) markedSequence(parts []string) (string, bool) {
	values := make([]string, 0, len(parts))
	for _, numeric := range parts {
		marked := strings.TrimSpace(r.marked[normalizeNumeric(numeric)])
		if marked == "" {
			return "", false
		}
		values = append(values, marked)
	}
	return strings.Join(values, " "), len(values) > 0
}

func (r *Resolver) yinyuanSequence(parts []string) (string, bool) {
	var output strings.Builder
	for _, numeric := range parts {
		record, exists := r.codeByNumeric[normalizeNumeric(numeric)]
		fullPUA := r.pua[normalizeNumeric(numeric)]
		if !exists || fullPUA == "" {
			return "", false
		}
		projected, err := codemode.ProjectAligned(record.full, fullPUA)
		if err != nil {
			return "", false
		}
		switch r.mode {
		case reverselookup.ModeFull:
			output.WriteString(projected.Full)
		case reverselookup.ModeShorthand:
			output.WriteString(projected.Shorthand)
		default:
			output.WriteString(projected.Variable)
		}
	}
	return output.String(), output.Len() > 0
}

func loadCodeRecords(path string) (map[string]codeRecord, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	result := make(map[string]codeRecord)
	scanner := bufio.NewScanner(file)
	line := 0
	for scanner.Scan() {
		line++
		if line == 1 {
			continue
		}
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) < 2 {
			return nil, fmt.Errorf("annotation code map line %d has fewer than two columns", line)
		}
		numeric := normalizeNumeric(fields[0])
		record := codeRecord{}
		if len(fields) >= 4 {
			record = codeRecord{strings.TrimSpace(fields[1]), strings.TrimSpace(fields[2]), strings.TrimSpace(fields[3])}
		} else {
			derived, deriveErr := codemode.BuildRecord(fields[1])
			if deriveErr != nil {
				return nil, fmt.Errorf("annotation code map line %d: %w", line, deriveErr)
			}
			record = codeRecord{derived.Full, derived.Variable, derived.Shorthand}
		}
		if numeric == "" || record.full == "" || record.variable == "" || record.shorthand == "" {
			return nil, fmt.Errorf("annotation code map line %d is incomplete", line)
		}
		result[numeric] = record
	}
	return result, scanner.Err()
}

func loadStringMap(path string) (map[string]string, error) {
	payload, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	raw := map[string]string{}
	if err := json.Unmarshal(payload, &raw); err != nil {
		return nil, err
	}
	result := make(map[string]string, len(raw))
	for key, value := range raw {
		result[normalizeNumeric(key)] = strings.TrimSpace(value)
	}
	return result, nil
}

func loadPUA(path string) (map[string]string, error) {
	payload, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	raw := map[string][]string{}
	if err := json.Unmarshal(payload, &raw); err != nil {
		return nil, err
	}
	result := make(map[string]string)
	for glyphs, values := range raw {
		for _, numeric := range values {
			key := normalizeNumeric(numeric)
			if key != "" {
				result[key] = glyphs
			}
		}
	}
	return result, nil
}

func normalizeNumeric(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.ReplaceAll(value, "u:", "ü")
	return strings.ReplaceAll(value, "v", "ü")
}

func appendUnique(values []string, value string) []string {
	for _, existing := range values {
		if existing == value {
			return values
		}
	}
	return append(values, value)
}

// Engine decorates all candidate snapshots while preserving the wrapped
// engine's state transitions and stable candidate IDs.
type Engine struct {
	inner    engineapi.Engine
	resolver *Resolver
}

func Wrap(inner engineapi.Engine, resolver *Resolver) (engineapi.Engine, error) {
	if inner == nil || resolver == nil {
		return nil, fmt.Errorf("engine and candidate annotation resolver are required")
	}
	return &Engine{inner: inner, resolver: resolver}, nil
}

func (e *Engine) Apply(event engineapi.Event) (engineapi.Result, error) {
	result, err := e.inner.Apply(event)
	e.decorate(&result)
	return result, err
}

func (e *Engine) Select(candidateID string) (engineapi.Result, error) {
	result, err := e.inner.Select(candidateID)
	e.decorate(&result)
	return result, err
}

func (e *Engine) SelectIdempotent(candidateID, mutationID string) (engineapi.Result, error) {
	selector, ok := e.inner.(interface {
		SelectIdempotent(string, string) (engineapi.Result, error)
	})
	if !ok {
		return engineapi.Result{}, fmt.Errorf("wrapped engine does not support idempotent selection")
	}
	result, err := selector.SelectIdempotent(candidateID, mutationID)
	e.decorate(&result)
	return result, err
}

func (e *Engine) Reset() engineapi.Result {
	result := e.inner.Reset()
	e.decorate(&result)
	return result
}

func (e *Engine) Close() error {
	if closer, ok := e.inner.(interface{ Close() error }); ok {
		return closer.Close()
	}
	return nil
}

func (e *Engine) IndexVersion() string {
	if versioned, ok := e.inner.(interface{ IndexVersion() string }); ok {
		return versioned.IndexVersion()
	}
	return ""
}

func (e *Engine) decorate(result *engineapi.Result) {
	for index := range result.State.Candidates {
		e.resolver.Annotate(&result.State.Candidates[index])
	}
}
