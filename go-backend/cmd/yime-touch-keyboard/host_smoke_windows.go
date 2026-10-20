//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"syscall"
	"time"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

// This diagnostic runs only with explicit --host-input --host-self-test. Every
// target is a disposable EDIT owned by this process; no existing document opens.
func (a *ui) hostSmoke(instance uintptr) error {
	probe, err := hostProbeCodes(a.o.Root)
	if err != nil {
		return err
	}
	c := wc{Proc: syscall.NewCallback(func(h uintptr, m uint32, w, l uintptr) uintptr { return def(h, m, w, l) }), Instance: instance, Name: str("YimeChineseHostTest")}
	c.Size = uint32(unsafe.Sizeof(c))
	U("RegisterClassExW").Call(uintptr(unsafe.Pointer(&c)))
	h, _, e := U("CreateWindowExW").Call(0, ptr(c.Name), ptr(str("Yime disposable Chinese EDIT test")), 0x10CF0000, 100, 100, 700, 360, 0, 0, instance, 0)
	if h == 0 {
		return e
	}
	defer U("DestroyWindow").Call(h)
	edit, _, _ := U("CreateWindowExW").Call(0, ptr(str("EDIT")), 0, 0x50800084, 10, 10, 650, 120, h, 0, instance, 0)
	other, _, _ := U("CreateWindowExW").Call(0, ptr(str("EDIT")), 0, 0x50800084, 10, 150, 650, 120, h, 0, instance, 0)
	if edit == 0 || other == 0 {
		return errors.New("own EDIT creation failed")
	}
	U("SetForegroundWindow").Call(h)
	U("SetFocus").Call(edit)
	drain(100 * time.Millisecond)
	if foreground() != (target{h, edit}) {
		return errors.New("own target did not acquire foreground; no input sent")
	}
	read := func(w uintptr) string {
		buf := make([]uint16, 4096)
		U("GetWindowTextW").Call(w, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
		return syscall.UTF16ToString(buf)
	}
	action := func(o tk.Output) error {
		ticket := a.host.ticket()
		if !a.host.valid(ticket) {
			return errors.New("own test target binding lost")
		}
		a.hostBusy = true
		defer func() { a.hostBusy = false }()
		a.hostSink(ticket)
		return a.preview.apply(o, a.preview.stamp())
	}
	input := func(kind, code, key string) error {
		return action(tk.Output{Action: tk.Action{Type: kind, ASCII: code, Key: key}})
	}
	compose := func() error {
		for _, c := range probe[a.preview.mode] {
			if err := input("input", string(c), ""); err != nil {
				return err
			}
		}
		return nil
	}
	for _, mode := range keyboardlab.Modes() {
		U("SetWindowTextW").Call(edit, ptr(str("")))
		if err := a.bindHost(); err != nil {
			return err
		}
		if err := a.preview.switchMode(mode); err != nil {
			return err
		}
		// ni3 is derived from admitted canonical IDs through this lab's projection.
		if err := compose(); err != nil {
			return err
		}
		if read(edit) != "" || len(a.preview.snapshot.State.Candidates) == 0 {
			return errors.New("composition wrote host text or no actual dictionary candidate")
		}
		candidate := a.preview.candidate(0)
		want := a.preview.snapshot.State.Candidates[0].Text
		chinese := false
		for _, r := range want {
			if r > 127 {
				chinese = true
			}
		}
		if !chinese {
			return errors.New("test probe did not produce non-ASCII text")
		}
		box := a.candidateRect(0)
		x, y := (box.L+box.R)/2, (box.T+box.B)/2
		a.down(710, x, y)
		a.up(710, x, y)
		a.up(710, x, y)
		drain(50 * time.Millisecond)
		if read(edit) != want {
			return fmt.Errorf("%s candidate UP/dedup output: %q want %q", mode, read(edit), want)
		}
		if err := a.preview.selectCandidate(candidate); err == nil {
			return errors.New("old candidate accepted")
		}
		if err := action(tk.Output{Action: tk.Action{Type: "local", Key: "Home"}, Ctrl: true}); err != nil {
			return err
		}
		if err := action(tk.Output{Action: tk.Action{Type: "local", Key: "End"}, Shift: true}); err != nil {
			return err
		}
		if err := input("symbol", "√", ""); err != nil {
			return err
		}
		drain(40 * time.Millisecond)
		if read(edit) != "√" {
			return fmt.Errorf("native Ctrl+Home/Shift+End Unicode replacement: %q", read(edit))
		}
		if err := input("backspace", "", ""); err != nil {
			return err
		}
		drain(30 * time.Millisecond)
		if read(edit) != "" {
			return errors.New("native Backspace failed")
		}
		if err := compose(); err != nil {
			return err
		}
		if err := input("clear", "", ""); err != nil {
			return err
		}
		if read(edit) != "" {
			return errors.New("cancel committed raw input")
		}
		fmt.Printf("PASS native EDIT %s: actual candidate %q; composed only in keyboard, candidate UP/dedup, Ctrl+Home/Shift+End replacement, Backspace and cancel\n", mode, want)
	}
	if err := input("toggle-language", "", ""); err != nil {
		return err
	}
	if err := input("input", "a", ""); err != nil {
		return err
	}
	if err := input("literal", "\n", ""); err != nil {
		return err
	}
	if err := input("input", "b", ""); err != nil {
		return err
	}
	drain(40 * time.Millisecond)
	if read(edit) != "a\r\nb" {
		return fmt.Errorf("native literal Enter: %q", read(edit))
	}
	U("SetWindowTextW").Call(edit, ptr(str("")))
	if err := input("toggle-language", "", ""); err != nil {
		return err
	}
	fmt.Println("PASS native English switch and literal Enter: own EDIT received a CRLF b; returned to Chinese without changing system input method")
	if err := compose(); err != nil {
		return err
	}
	box := a.candidateRect(0)
	x, y := (box.L+box.R)/2, (box.T+box.B)/2
	a.down(711, x, y)
	U("SetFocus").Call(other)
	U("SetFocus").Call(edit)
	drain(50 * time.Millisecond)
	a.up(711, x, y)
	if read(edit) != "" || read(other) != "" || a.host.target.Window != 0 || a.preview.snapshot.State.RawInput != "" {
		return errors.New("focus away/back did not cancel original composition and touch")
	}
	if err := a.bindHost(); err != nil {
		return err
	}
	if err := compose(); err != nil {
		return err
	}
	base := a.preview.sessions
	a.preview.sessions = hostDelayedReply{base, func() { U("SetFocus").Call(other); U("SetFocus").Call(edit) }}
	if err := input("confirm", "", "Space"); err == nil {
		return errors.New("late response reached old focus epoch")
	}
	a.preview.sessions = base
	drain(40 * time.Millisecond)
	if read(edit) != "" || read(other) != "" {
		return errors.New("late response wrote target")
	}
	fmt.Println("PASS native focus notification: away/back and delayed response dropped; both own EDIT texts unchanged")
	if err := a.bindHost(); err != nil {
		return err
	}
	sender := a.host.send
	calls := 0
	a.host.send = func(hostTarget, tk.Output) error { calls++; return errors.New("injected zero-send failure") }
	if err := input("literal", "7", ""); err == nil {
		return errors.New("failed send accepted")
	}
	_ = input("literal", "7", "")
	if calls != 1 || read(edit) != "" {
		return errors.New("failed send replayed")
	}
	a.host.send = sender
	if err := a.bindHost(); err != nil {
		return err
	}
	calls = 0
	a.host.send = func(t hostTarget, o tk.Output) error {
		calls++
		if err := sender(t, tk.Output{Text: "部"}); err != nil {
			return err
		}
		return errors.New("injected unknown result after one actual Unicode prefix")
	}
	if err := input("literal", "8", ""); err == nil {
		return errors.New("partial result accepted")
	}
	_ = input("literal", "8", "")
	drain(40 * time.Millisecond)
	if calls != 1 || read(edit) != "部" || read(other) != "" {
		return errors.New("partial result replayed or changed other target")
	}
	a.host.send = sender
	if err := a.bindHost(); err != nil {
		return err
	}
	if err := input("literal", "9", ""); err != nil {
		return err
	}
	drain(40 * time.Millisecond)
	if read(edit) != "部9" {
		return errors.New("explicit recovery altered prior host text")
	}
	fmt.Println("PASS controlled fault injection: zero-send and uncertain-prefix stop future sends; explicit rebind preserves prefix; no replay. Injected faults are not naturally observed OS failures.")
	fmt.Println("PASS P4 controlled native EDIT; NOT physical finger/pen, real app or ARM64 native acceptance. No installed/default input-method or user-data changes.")
	return nil
}

// Source-only native diagnostic: never infer pronunciation or Yinyuan IDs from
// dictionary codes, and never manufacture an encoding to make this check pass.
func hostProbeCodes(root string) (map[string]string, error) {
	data, err := os.ReadFile(filepath.Join(root, "prototypes/touch-terminal/encoding/yime_yinyuan_layout.json"))
	if err != nil {
		return nil, err
	}
	var layout struct {
		Keys map[string]string `json:"yinyuan_id_to_key"`
	}
	if err = json.Unmarshal(data, &layout); err != nil {
		return nil, err
	}
	f, err := os.Open(filepath.Join(root, "internal_data/yime_syllable_decomposition.tsv"))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	r := csv.NewReader(f)
	r.Comma = '\t'
	header, err := r.Read()
	if err != nil {
		return nil, err
	}
	columns := map[string]int{}
	for i, k := range header {
		columns[k] = i
	}
	for _, key := range []string{"pinyin_tone", "status", "shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
		if _, ok := columns[key]; !ok {
			return nil, fmt.Errorf("canonical column missing: %s", key)
		}
	}
	for {
		row, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		if row[columns["pinyin_tone"]] != "ni3" {
			continue
		}
		if row[columns["status"]] != "ok" {
			return nil, errors.New("probe not admitted")
		}
		full := ""
		for _, slot := range []string{"shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
			key := layout.Keys[row[columns[slot]]]
			if len(key) != 1 {
				return nil, errors.New("probe projection missing")
			}
			full += key
		}
		record, err := codemode.BuildRecord(full)
		if err != nil {
			return nil, err
		}
		return map[string]string{"variable": record.Variable, "full": record.Full, "shorthand": record.Shorthand}, nil
	}
	return nil, errors.New("canonical ni3 missing")
}

type hostDelayedReply struct {
	previewSessions
	beforeReturn func()
}

func (s hostDelayedReply) Dispatch(e keyboardlab.Event) keyboardlab.Reply {
	r := s.previewSessions.Dispatch(e)
	if e.Type == "select" {
		s.beforeReturn()
	}
	return r
}
