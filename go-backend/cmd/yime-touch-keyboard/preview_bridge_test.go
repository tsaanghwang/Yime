package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	codemode "github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	bridge "github.com/tsaanghwang/Yime/go-backend/internal/touchhostbridge"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"os"
	"path/filepath"
	"testing"
)

func bridgeUIData(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	data := filepath.Join(root, "data")
	layout := filepath.Join(root, "prototypes/touch-terminal/data")
	for _, d := range []string{data, layout} {
		if e := os.MkdirAll(d, 0700); e != nil {
			t.Fatal(e)
		}
	}
	write := func(p string, b []byte) {
		t.Helper()
		if e := os.WriteFile(p, b, 0600); e != nil {
			t.Fatal(e)
		}
	}
	b, _ := json.Marshal(map[string]string{"layoutId": codemode.LayoutProjectionSHA256})
	write(filepath.Join(layout, "physical-layout.json"), b)
	hashes := map[string]string{}
	for _, mode := range keyboardlab.Modes() {
		name := "yime_" + mode + ".dict.yaml"
		body := []byte("---\nname: bridge_test\nversion: '1'\n...\n测试\ta\t100\n测验\ta\t90\n")
		for n := 0; n < 10; n++ {
			body = append(body, []byte(fmt.Sprintf("备选%d\ta\t%d\n", n, 80-n))...)
		}
		write(filepath.Join(data, name), body)
		sum := sha256.Sum256(body)
		hashes[name] = hex.EncodeToString(sum[:])
	}
	b, _ = json.Marshal(map[string]any{"schema_version": 1, "scope": "immutable_source_runtime_experiment", "limit": 0, "input_policy": keyboardlab.InputPolicy, "layout_projection_sha256": codemode.LayoutProjectionSHA256, "disabled_yinyuan_ids": []string{}, "dictionary_sha256": hashes})
	write(filepath.Join(data, "ascii_keyboard_manifest.json"), b)
	return root, data
}

func TestBridgePreviewUnknownNeverReplays(t *testing.T) {
	root, data := bridgeUIData(t)
	calls := 0
	p, e := newBridgePreview(root, data, bridge.Focus{Context: "own-test-host", Epoch: 1}, func(c bridge.Commit) (bridge.Outcome, error) {
		calls++
		return bridge.Unknown, fmt.Errorf("lost child")
	})
	if e != nil {
		t.Fatal(e)
	}
	defer p.retire()
	previewAction(t, p, "input", "a", "")
	if e = p.selectCandidate(p.candidate(0)); e == nil {
		t.Fatal("unknown accepted")
	}
	if !p.fault || p.bridge.session.Receipt().Outcome != bridge.Unknown || len(p.editor.text) != 0 {
		t.Fatal("unknown not terminal")
	}
	if e = p.apply(tk.Output{Action: tk.Action{Type: "input", ASCII: "a"}}, p.stamp()); e == nil || calls != 1 {
		t.Fatal("replayed unknown")
	}
}
func TestBridgePreviewUnsupportedHasNoFallback(t *testing.T) {
	root, data := bridgeUIData(t)
	calls := 0
	p, e := newBridgePreview(root, data, bridge.Focus{Context: "own-test-host", Epoch: 1}, func(c bridge.Commit) (bridge.Outcome, error) { calls++; return bridge.Applied, nil })
	if e != nil {
		t.Fatal(e)
	}
	defer p.retire()
	before := p.stamp()
	for _, a := range []tk.Action{{Type: "literal", ASCII: "x"}, {Type: "backspace"}, {Type: "toggle-language"}, {Type: "local", Key: "Delete"}, {Type: "confirm"}} {
		if e = p.apply(tk.Output{Action: a}, p.stamp()); e == nil {
			t.Fatal("unsupported action accepted", a)
		}
	}
	if e = p.switchMode("full"); e == nil {
		t.Fatal("mode unlocked")
	}
	if e = p.dispatch(keyboardlab.Event{Type: "setModes", InputMode: "chinese", PunctuationMode: "chinese"}); e == nil {
		t.Fatal("faked setModes")
	}
	if p.stamp() != before || calls != 0 || len(p.editor.text) != 0 {
		t.Fatal("unsupported fallback")
	}
	previewAction(t, p, "input", "a", "")
	if e = p.selectCandidate(p.candidate(0)); e != nil {
		t.Fatal(e)
	}
	if calls != 1 || p.bridge.session.Receipt().Outcome != bridge.Applied || len(p.editor.text) != 0 {
		t.Fatal("not one external commit")
	}
}

func TestBridgePreviewStaleActionAndSideBackspaceReject(t *testing.T) {
	root, data := bridgeUIData(t)
	calls := 0
	p, e := newBridgePreview(root, data, bridge.Focus{Context: "own-test-host", Epoch: 1}, func(c bridge.Commit) (bridge.Outcome, error) { calls++; return bridge.Applied, nil })
	if e != nil {
		t.Fatal(e)
	}
	defer p.retire()
	previewAction(t, p, "input", "a", "")
	old := p.stamp()
	if e = p.page(1); e != nil {
		t.Fatal(e)
	}
	current := p.stamp()
	for _, kind := range []string{"input", "clear", "backspace"} {
		if e = p.apply(tk.Output{Action: tk.Action{Type: kind, ASCII: "a"}}, old); e == nil {
			t.Fatal("accepted stale", kind)
		}
	}
	for _, zone := range []string{"left", "right"} {
		if e = p.apply(tk.Output{Zone: zone, Action: tk.Action{Type: "backspace"}}, p.stamp()); e == nil {
			t.Fatal("side backspace fallback", zone)
		}
	}
	if p.stamp() != current || p.snapshot.State.RawInput != "a" || calls != 0 || len(p.editor.text) != 0 {
		t.Fatal("rejected action mutated state")
	}
}
