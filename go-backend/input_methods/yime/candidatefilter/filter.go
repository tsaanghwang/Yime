package candidatefilter

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userblocklist"
)

type fileSignature struct {
	exists   bool
	size     int64
	modified time.Time
}

type Engine struct {
	inner     engineapi.Engine
	path      string
	signature fileSignature
	blocked   map[string]struct{}
	visible   map[string]string
}

func Wrap(inner engineapi.Engine, path string) (engineapi.Engine, error) {
	if inner == nil || strings.TrimSpace(path) == "" {
		return nil, errors.New("engine and blocklist path are required")
	}
	engine := &Engine{inner: inner, path: path, visible: map[string]string{}}
	if err := engine.reload(); err != nil {
		return nil, err
	}
	return engine, nil
}

func (e *Engine) Apply(event engineapi.Event) (engineapi.Result, error) {
	result, err := e.inner.Apply(event)
	if err == nil {
		err = e.filter(&result)
	}
	return result, err
}

func (e *Engine) Select(candidateID string) (engineapi.Result, error) {
	if err := e.assertVisible(candidateID); err != nil {
		return engineapi.Result{}, err
	}
	result, err := e.inner.Select(candidateID)
	if err == nil {
		err = e.filter(&result)
	}
	return result, err
}

func (e *Engine) SelectIdempotent(candidateID, mutationID string) (engineapi.Result, error) {
	if err := e.assertVisible(candidateID); err != nil {
		return engineapi.Result{}, err
	}
	selector, ok := e.inner.(interface {
		SelectIdempotent(string, string) (engineapi.Result, error)
	})
	if !ok {
		return engineapi.Result{}, errors.New("wrapped engine does not support idempotent selection")
	}
	result, err := selector.SelectIdempotent(candidateID, mutationID)
	if err == nil {
		err = e.filter(&result)
	}
	return result, err
}

func (e *Engine) ForgetCandidate(candidateID string) (engineapi.Result, error) {
	if err := e.assertVisible(candidateID); err != nil {
		return engineapi.Result{}, err
	}
	forgetter, ok := e.inner.(engineapi.CandidateForgetter)
	if !ok {
		return engineapi.Result{}, errors.New("wrapped engine does not support candidate forgetting")
	}
	result, err := forgetter.ForgetCandidate(candidateID)
	if err == nil {
		err = e.filter(&result)
	}
	return result, err
}

func (e *Engine) SetCandidateLimit(candidateLimit int) error {
	if configurable, ok := e.inner.(interface{ SetCandidateLimit(int) error }); ok {
		return configurable.SetCandidateLimit(candidateLimit)
	}
	return errors.New("wrapped engine does not support candidate limits")
}

func (e *Engine) Reset() engineapi.Result {
	result := e.inner.Reset()
	_ = e.filter(&result)
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

func (e *Engine) assertVisible(candidateID string) error {
	if err := e.reload(); err != nil {
		return err
	}
	text, ok := e.visible[candidateID]
	if !ok || userblocklist.IsBlocked(e.blocked, text) {
		return engineapi.ErrUnknownCandidate
	}
	return nil
}

func (e *Engine) filter(result *engineapi.Result) error {
	if err := e.reload(); err != nil {
		return err
	}
	e.visible = make(map[string]string, len(result.State.Candidates))
	filtered := result.State.Candidates[:0]
	for _, candidate := range result.State.Candidates {
		if userblocklist.IsBlocked(e.blocked, candidate.Text) {
			continue
		}
		filtered = append(filtered, candidate)
		e.visible[candidate.ID] = candidate.Text
	}
	result.State.Candidates = filtered
	if result.State.Sentence != nil {
		if userblocklist.IsBlocked(e.blocked, result.State.Sentence.Text) {
			result.State.Sentence = nil
		} else {
			e.visible[result.State.Sentence.ID] = result.State.Sentence.Text
		}
	}
	return nil
}

func (e *Engine) reload() error {
	info, err := os.Stat(e.path)
	signature := fileSignature{}
	if errors.Is(err, os.ErrNotExist) {
		err = nil
	} else if err == nil {
		signature = fileSignature{exists: true, size: info.Size(), modified: info.ModTime()}
	}
	if err != nil {
		return fmt.Errorf("stat candidate blocklist: %w", err)
	}
	if signature == e.signature && e.blocked != nil {
		return nil
	}
	blocked := map[string]struct{}{}
	if signature.exists {
		blocked, err = userblocklist.LoadSet(e.path)
		if err != nil {
			return fmt.Errorf("load candidate blocklist: %w", err)
		}
	}
	e.signature = signature
	e.blocked = blocked
	return nil
}
