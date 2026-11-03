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
	mu        sync.Mutex
	transport Transport
	sequence  uint64
	closed    bool
}
type Reply struct {
	Version      int    `json:"version"`
	Sequence     uint64 `json:"sequence"`
	OK           bool   `json:"ok"`
	Outcome      string `json:"outcome"`
	RetryAllowed bool   `json:"retryAllowed"`
}

func Bind(t Transport, window uint64) (*Client, error) {
	c := &Client{transport: t}
	if window == 0 {
		t.Close()
		return nil, errors.New("missing foreground window")
	}
	if err := c.call("bind", map[string]any{"window": window}, "bound"); err != nil {
		return nil, err
	}
	return c, nil
}
func (c *Client) call(operation string, fields map[string]any, outcome string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return errors.New("TSF session stopped; bind explicitly, no replay")
	}
	fail := func(err error) error { c.closed = true; _ = c.transport.Close(); return err }
	if c.sequence == ^uint64(0) {
		return fail(errors.New("TSF sequence exhausted"))
	}
	c.sequence++
	request := map[string]any{"version": 1, "sequence": c.sequence, "operation": operation}
	for k, v := range fields {
		request[k] = v
	}
	raw, err := json.Marshal(request)
	if err != nil || len(raw) >= 16384 {
		return fail(errors.New("TSF request exceeds limit"))
	}
	raw, err = c.transport.Exchange(append(raw, '\n'))
	if err != nil {
		return fail(fmt.Errorf("TSF result unknown; no replay: %w", err))
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
	if decoder.Decode(&r) != nil || decoder.Decode(new(any)) != io.EOF || r.Version != 1 || r.Sequence != c.sequence || r.RetryAllowed || !r.OK || r.Outcome != outcome {
		return fail(errors.New("TSF edit was not confirmed; session stopped, no replay"))
	}
	return nil
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
	return err == nil && t == json.Delim('}') && len(seen) == 5 && d.Decode(new(any)) == io.EOF
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
