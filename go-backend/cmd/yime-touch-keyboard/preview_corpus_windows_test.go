//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/csv"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

var previewIntegrationRoot = flag.String("desktop-preview-integration-root", "", "explicit checkout with complete generated lab dictionaries")
var previewEvidenceDir = flag.String("desktop-preview-evidence-dir", "", "optional output directory for complete-corpus controlled preview evidence")

func TestPreviewCompleteCorpus(t *testing.T) {
	if *previewIntegrationRoot == "" {
		t.Skip("explicit complete-corpus root required")
	}
	root, err := filepath.Abs(*previewIntegrationRoot)
	if err != nil {
		t.Fatal(err)
	}
	r, err := keyboardlab.OpenRuntime(root, filepath.Join(root, ".generated/ascii-keyboard-134/data"))
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()
	p, err := newPreview(r.Sessions, r.LayoutID, true)
	if err != nil {
		t.Fatal(err)
	}
	codes := previewCanonicalCodes(t, root)
	results := map[string]any{}
	for _, mode := range keyboardlab.Modes() {
		if err := p.switchMode(mode); err != nil {
			t.Fatal(err)
		}
		p.editor = previewEditor{}
		codeFor := func(pinyin string) string {
			c := codes[pinyin]
			return map[string]string{"variable": c.Variable, "full": c.Full, "shorthand": c.Shorthand}[mode]
		}
		for i, pinyin := range []string{"ni3", "hao3"} {
			code := codeFor(pinyin)
			for _, c := range code {
				previewAction(t, p, "input", string(c), "")
			}
			if p.snapshot.State.RawInput != code {
				t.Fatalf("%s raw input differs", mode)
			}
			wanted := []string{"你", "好"}[i]
			selected := false
			for pages := 0; pages < 100; pages++ {
				for j, c := range p.snapshot.State.Candidates {
					if c.Text == wanted {
						if err := p.selectCandidate(p.candidate(j)); err != nil {
							t.Fatal(err)
						}
						selected = true
						break
					}
				}
				if selected || !p.snapshot.State.HasNext {
					break
				}
				if err := p.page(1); err != nil {
					t.Fatal(err)
				}
			}
			if !selected {
				t.Fatalf("%s missing %s", mode, wanted)
			}
		}
		if string(p.editor.text) != "你好" {
			t.Fatalf("%s committed %q", mode, string(p.editor.text))
		}
		for _, c := range codeFor("ni3") {
			previewAction(t, p, "input", string(c), "")
		}
		if *previewEvidenceDir != "" {
			renderCorpusPreview(t, root, mode, p)
		}
		results[mode] = map[string]any{"output": string(p.editor.text), "ni3_code": codeFor("ni3"), "hao3_code": codeFor("hao3"), "composition": p.snapshot.State, "index": r.Builds[mode]}
		previewAction(t, p, "clear", "", "")
		previewAction(t, p, "backspace", "", "")
		if p.snapshot.State.RawInput != "" || string(p.editor.text) != "你" {
			t.Fatal("corpus cancel/edit failed")
		}
		t.Logf("%s: %d indexed records; selected 你好; cancelled pending code and edited local output", mode, r.Builds[mode].IndexedRecords)
	}
	if *previewEvidenceDir != "" {
		report := map[string]any{"schemaVersion": 1, "recordedAtUTC": time.Now().UTC().Format(time.RFC3339), "scope": "P3 controlled desktop preview, complete isolated corpus", "layoutId": r.LayoutID, "modes": results, "osInputSent": false, "fingerAcceptance": false, "penAcceptance": false, "realHostAcceptance": false, "rendering": "GDI memory bitmap from hidden own window; no physical touch"}
		data, err := json.MarshalIndent(report, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		if err = os.WriteFile(filepath.Join(*previewEvidenceDir, "complete-corpus-preview.json"), append(data, '\n'), 0600); err != nil {
			t.Fatal(err)
		}
	}
}

func previewCanonicalCodes(t *testing.T, root string) map[string]codemode.Record {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(root, "prototypes/touch-terminal/encoding/yime_yinyuan_layout.json"))
	if err != nil {
		t.Fatal(err)
	}
	var layout struct {
		Keys map[string]string `json:"yinyuan_id_to_key"`
	}
	if err = json.Unmarshal(data, &layout); err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(filepath.Join(root, "internal_data/yime_syllable_decomposition.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	reader := csv.NewReader(f)
	reader.Comma = '\t'
	header, err := reader.Read()
	if err != nil {
		t.Fatal(err)
	}
	cols := map[string]int{}
	for i, k := range header {
		cols[k] = i
	}
	found := map[string]codemode.Record{}
	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		py := row[cols["pinyin_tone"]]
		if py != "ni3" && py != "hao3" {
			continue
		}
		if row[cols["status"]] != "ok" {
			t.Fatal("unadmitted canonical input")
		}
		full := ""
		for _, slot := range []string{"shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
			key := layout.Keys[row[cols[slot]]]
			if len(key) != 1 {
				t.Fatal("missing projected ID")
			}
			full += key
		}
		record, err := codemode.BuildRecord(full)
		if err != nil {
			t.Fatal(err)
		}
		found[py] = record
	}
	if len(found) != 2 {
		t.Fatal("canonical records missing")
	}
	return found
}

func renderCorpusPreview(t *testing.T, root, mode string, p *preview) {
	t.Helper()
	if err := os.MkdirAll(*previewEvidenceDir, 0700); err != nil {
		t.Fatal(err)
	}
	b, err := load(options{Root: root, Zones: "none", Gutters: true})
	if err != nil {
		t.Fatal(err)
	}
	glyphs, err := loadPreviewGlyphs(root)
	if err != nil {
		t.Fatal(err)
	}
	a := &ui{s: tk.NewState(b), preview: p, ppm: 2560 / 597.73, top: 300, border: 10, glyphs: glyphs, showGlyphs: true, status: "完整隔离词典 / 自动化本地预览 / 非真人触摸或宿主验收"}
	a.s.Original, a.s.Semantic = true, true
	w := a.previewWidth()
	height := int(math.Ceil(b.Bounds.Height*tk.UnitMM*a.ppm)) + a.top + a.border
	a.h, _, _ = U("CreateWindowExW").Call(0x08000080, ptr(str("STATIC")), 0, 0x80000000, 0, 0, uintptr(w), uintptr(height), 0, 0, 0, 0)
	if a.h == 0 {
		t.Fatal("hidden own screenshot window")
	}
	defer U("DestroyWindow").Call(a.h)
	fontPath := filepath.Join(root, "go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf")
	if n, _, _ := G("AddFontResourceExW").Call(ptr(str(fontPath)), 0x10, 0); n == 0 {
		t.Fatal("private font load")
	}
	defer G("RemoveFontResourceExW").Call(ptr(str(fontPath)), 0x10, 0)
	heightPx := int32(-15)
	a.font, _, _ = G("CreateFontW").Call(uintptr(heightPx), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str("Segoe UI")))
	defer G("DeleteObject").Call(a.font)
	heightPx = -19
	a.glyphFont, _, _ = G("CreateFontW").Call(uintptr(heightPx), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str("YinYuan")))
	defer G("DeleteObject").Call(a.glyphFont)
	if err = a.screenshot(filepath.Join(*previewEvidenceDir, fmt.Sprintf("%s-preview.png", mode))); err != nil {
		t.Fatal(err)
	}
}
