// Package tsffrontend delivers final edits to the activated independent 18u TIP.
// It never synthesizes input and never retries a mutation after unknown outcome.
package tsffrontend

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"
	"unicode/utf8"
)

type Transport interface {
	Exchange([]byte) ([]byte, error)
	Close() error
}
type Client struct {
	mu           sync.Mutex
	transport    Transport
	sequence     uint64
	activationID string
	generation   uint64
	closed       bool
}
type Reply struct {
	Version      int    `json:"version"`
	Sequence     uint64 `json:"sequence"`
	OK           bool   `json:"ok"`
	Outcome      string `json:"outcome"`
	RetryAllowed bool   `json:"retryAllowed"`
	ActivationID string `json:"activationId"`
	Generation   uint64 `json:"generation"`
	Reason       string `json:"reason,omitempty"`
}

func Bind(t Transport, window, focus uint64) (*Client, error) {
	c := &Client{transport: t}
	if window == 0 || focus == 0 {
		t.Close()
		return nil, errors.New("missing foreground/focus window")
	}
	if err := c.call("bind", map[string]any{"window": window, "focus": focus}, "bound"); err != nil {
		return nil, err
	}
	return c, nil
}
func (c *Client) call(operation string, fields map[string]any, outcome string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return errors.New("TSF session stopped; a new session is required, no replay")
	}
	fail := func(err error) error { c.closed = true; _ = c.transport.Close(); return err }
	if c.sequence == ^uint64(0) {
		return fail(errors.New("TSF sequence exhausted"))
	}
	c.sequence++
	request := map[string]any{"version": 2, "sequence": c.sequence, "operation": operation}
	if operation != "bind" {
		request["activationId"], request["generation"] = c.activationID, c.generation
	}
	for k, v := range fields {
		request[k] = v
	}
	raw, err := json.Marshal(request)
	if err != nil || len(raw) >= 16384 {
		return fail(errors.New("TSF request exceeds limit"))
	}
	raw, err = c.transport.Exchange(append(raw, '\n'))
	if err != nil {
		if operation == "edit" {
			return fail(fmt.Errorf("TSF edit result unknown; no replay: %w", err))
		}
		return fail(fmt.Errorf("TSF %s transport failed; no replay: %w", operation, err))
	}
	if len(raw) > 4096 {
		return fail(errors.New("TSF response exceeds limit"))
	}
	if !validReplyObject(raw) {
		return fail(errors.New("incomplete TSF response"))
	}
	var r Reply
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&r) != nil || decoder.Decode(new(any)) != io.EOF || r.Version != 2 || r.Sequence != c.sequence || r.RetryAllowed || !validActivationID(r.ActivationID) || r.Generation == 0 {
		return fail(errors.New("invalid TSF response; session stopped, no replay"))
	}
	// A new activation or context generation is never adopted from a response.
	// Only a fresh bind may establish an identity for future user actions.
	if operation != "bind" && (r.ActivationID != c.activationID || r.Generation != c.generation) {
		return fail(fmt.Errorf("TSF %s identity changed; session stopped, no replay", operation))
	}
	if !r.OK || r.Outcome != outcome || r.Reason != "" {
		if !r.OK && operation == "bind" && r.Outcome == "bind-rejected" && knownBindReason(r.Reason) {
			return fail(fmt.Errorf("TSF bind rejected: %s", r.Reason))
		}
		if operation == "status" && r.OK && r.Outcome == "unavailable" && knownStatusReason(r.Reason) {
			return fail(fmt.Errorf("TSF target unavailable: %s", r.Reason))
		}
		return fail(fmt.Errorf("TSF %s was not confirmed; session stopped, no replay", operation))
	}
	if operation == "bind" {
		c.activationID, c.generation = r.ActivationID, r.Generation
	}
	return nil
}

func validActivationID(id string) bool {
	return len(id) > 0 && len(id) <= 128 && utf8.ValidString(id) && !strings.ContainsRune(id, 0)
}

func validReplyObject(raw []byte) bool {
	d := json.NewDecoder(bytes.NewReader(raw))
	t, err := d.Token()
	if err != nil || t != json.Delim('{') {
		return false
	}
	seen := map[string]bool{}
	for d.More() {
		t, err = d.Token()
		key, ok := t.(string)
		if err != nil || !ok || seen[key] {
			return false
		}
		seen[key] = true
		var value json.RawMessage
		if d.Decode(&value) != nil || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return false
		}
	}
	t, err = d.Token()
	return err == nil && t == json.Delim('}') && seen["version"] && seen["sequence"] && seen["ok"] && seen["outcome"] && seen["retryAllowed"] && seen["activationId"] && seen["generation"] && (len(seen) == 7 || len(seen) == 8 && seen["reason"]) && d.Decode(new(any)) == io.EOF
}

func knownBindReason(reason string) bool {
	switch reason {
	case "peer-process-unavailable", "peer-image-mismatch", "peer-session-mismatch", "peer-token-unavailable", "peer-user-mismatch", "peer-logon-mismatch", "peer-integrity-mismatch", "native-host-required", "native-peer-required":
		return true
	case "lease-inactive", "callback-thread-mismatch", "foreground-changed", "focus-changed", "focus-owner-mismatch", "no-focused-document", "document-changed", "no-top-context", "context-changed":
		return true
	case "activation-ended", "key-focus-missing", "thread-focus-unavailable", "thread-focus-missing", "profile-unavailable", "profile-inactive", "generation-exhausted", "context-status-unavailable", "context-read-only", "context-loading":
		return true
	}
	return false
}

func knownStatusReason(reason string) bool {
	return knownBindReason(reason) || reason == "stale-activation" || reason == "stale-generation"
}

// Status checks the bound TIP's current identity without editing the document.
// It shares the request sequence and serialization lock with Edit. An unavailable
// target retires this client; it never silently rebinds or clears an edit fault.
func (c *Client) Status() error {
	return c.call("status", nil, "ready")
}
func (c *Client) Edit(text, key string, extend bool) error {
	if (text == "") == (key == "") || len(text) > 4096 || !utf8.ValidString(text) || strings.ContainsRune(text, 0) {
		return errors.New("invalid TSF edit")
	}
	if key != "" {
		switch key {
		case "Enter", "Tab", "Backspace", "Delete", "ArrowLeft", "ArrowRight", "Home", "End", "SelectAll":
		default:
			return errors.New("unsupported TSF key")
		}
	}
	if extend && key != "ArrowLeft" && key != "ArrowRight" && key != "Home" && key != "End" {
		return errors.New("unsupported TSF selection modifier")
	}
	return c.call("edit", map[string]any{"text": text, "key": key, "extend": extend}, "applied")
}
func (c *Client) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return nil
	}
	c.closed = true
	return c.transport.Close()
}
