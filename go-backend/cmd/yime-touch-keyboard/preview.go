package main

import (
	"fmt"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

type previewSessions interface {
	Open(string, string) keyboardlab.Reply
	Dispatch(keyboardlab.Event) keyboardlab.Reply
}

// preview is the UI-thread session controller. P3 uses its in-memory sink; P4
// supplies an epoch-bound emitter, without putting host HWND/SendInput into the
// engine. Commits are consumed once; unknown outcomes are never retried.
type preview struct {
	sessions                    previewSessions
	layout, mode                string
	snapshot                    keyboardlab.Response
	sequence                    uint64
	fault                       bool
	englishView, literalEntries bool
	editor                      previewEditor
	emit                        func(string, tk.Output) error // nil keeps P3's in-memory sink.
}

type previewStamp struct {
	session  string
	revision uint64
}
type candidatePress struct {
	stamp previewStamp
	id    string
}

func newPreview(s previewSessions, layout string, englishView bool) (*preview, error) {
	p := &preview{sessions: s, layout: layout, englishView: englishView}
	return p, p.switchMode("variable")
}
func (p *preview) stamp() previewStamp {
	return previewStamp{p.snapshot.SessionID, p.snapshot.Revision}
}
func (p *preview) original() bool { return p.snapshot.Modes.Input != "english" || !p.englishView }
func (p *preview) dispatch(e keyboardlab.Event) error {
	if p.fault || p.snapshot.SessionID == "" {
		return fmt.Errorf("会话已断开；重新启动预览，不重放输入")
	}
	p.sequence++
	e.SessionID, e.BaseRevision, e.EventID = p.snapshot.SessionID, p.snapshot.Revision, fmt.Sprintf("desktop-%d", p.sequence)
	r := p.sessions.Dispatch(e)
	s, err := r.Decode()
	valid := err == nil && s.SessionID == e.SessionID && (s.Modes.Input == "chinese" || s.Modes.Input == "english") && (s.Modes.Punctuation == "chinese" || s.Modes.Punctuation == "english")
	if valid && r.Status == 200 && s.OK && s.Error == "" && s.Revision == e.BaseRevision+1 {
		p.snapshot = s
		p.snapshot.Commit = "" // Ephemeral output is never available for another consumer.
		if s.Commit != "" {
			if p.emit != nil {
				if err := p.emit(e.SessionID+"/"+e.EventID, tk.Output{Text: s.Commit}); err != nil {
					p.fault = true
					return err
				}
			} else {
				p.editor.insert(s.Commit)
			}
		}
		return nil
	}
	if valid && !s.OK && s.Commit == "" && s.Error != "" && ((r.Status == 400 && s.Revision == e.BaseRevision) || (r.Status == 409 && s.Revision >= e.BaseRevision)) {
		p.snapshot = s
		return fmt.Errorf("%s", s.Error)
	}
	p.fault = true
	return fmt.Errorf("会话响应无效或已关闭（%d）；没有重放或追加输出", r.Status)
}
func (p *preview) switchMode(mode string) error {
	if mode != "variable" && mode != "full" && mode != "shorthand" {
		return fmt.Errorf("unknown mode")
	}
	input := p.snapshot.Modes.Input
	if input == "" {
		input = "chinese"
	}
	if p.snapshot.SessionID != "" {
		if err := p.dispatch(keyboardlab.Event{Type: "close"}); err != nil {
			return err
		}
	}
	r := p.sessions.Open(mode, p.layout)
	s, err := r.Decode()
	if err != nil || r.Status != 200 || !s.OK || s.SessionID == "" || s.Commit != "" || s.Revision != 0 {
		p.fault = true
		return fmt.Errorf("无法创建 %s 预览会话", mode)
	}
	p.snapshot, p.mode = s, mode
	return p.dispatch(keyboardlab.Event{Type: "setModes", InputMode: input, PunctuationMode: input})
}
func (p *preview) candidate(index int) candidatePress {
	if index < 0 || index >= len(p.snapshot.State.Candidates) {
		return candidatePress{}
	}
	return candidatePress{p.stamp(), p.snapshot.State.Candidates[index].ID}
}
func (p *preview) selectCandidate(c candidatePress) error {
	if c.id == "" || c.stamp != p.stamp() {
		return fmt.Errorf("候选已更新；本次触点取消")
	}
	return p.dispatch(keyboardlab.Event{Type: "select", CandidateID: c.id})
}
func (p *preview) page(delta int) error {
	if delta < 0 && !p.snapshot.State.HasPrevious || delta > 0 && !p.snapshot.State.HasNext {
		return nil
	}
	return p.dispatch(keyboardlab.Event{Type: "page", Delta: delta})
}
func (p *preview) toggleLayout() {
	// Chinese always shows CN. Retain the English preference across CN/EN.
	if p.snapshot.Modes.Input == "english" {
		p.englishView = !p.englishView
	}
}
func (p *preview) apply(o tk.Output, down previewStamp) error {
	a := o.Action
	if p.fault {
		return fmt.Errorf("会话已断开；请重新启动预览")
	}
	if p.emit != nil && (o.Ctrl || o.Alt) {
		if p.snapshot.State.RawInput != "" {
			return fmt.Errorf("请先确认或取消组合，再发送宿主快捷键")
		}
		if a.Type == "input" || a.Type == "literal" {
			if a.Type == "literal" && a.ASCII == "\n" {
				return p.emitEdit(tk.Output{Key: "Enter", Shift: o.Shift, Ctrl: o.Ctrl, Alt: o.Alt})
			}
			return p.emitEdit(tk.Output{Text: a.ASCII, Shift: o.Shift, Ctrl: o.Ctrl, Alt: o.Alt})
		}
		if a.Type == "local" || a.Type == "backspace" || a.Type == "confirm" {
			key := a.Key
			if a.Type == "backspace" {
				key = "Backspace"
			}
			return p.emitEdit(tk.Output{Key: key, Shift: o.Shift, Ctrl: o.Ctrl, Alt: o.Alt})
		}
		return fmt.Errorf("此组合键不支持宿主提交")
	}
	if o.Alt {
		return fmt.Errorf("预览不执行 Alt 快捷键")
	}
	if o.Ctrl {
		if a.Type == "input" && strings.EqualFold(a.ASCII, "a") && p.snapshot.State.RawInput == "" {
			p.editor.anchor, p.editor.cursor = 0, len(p.editor.text)
			return nil
		}
		return fmt.Errorf("预览仅支持无组合时 Ctrl+A 全选本地文本")
	}
	switch a.Type {
	case "toggle-layout":
		p.toggleLayout()
		return nil
	case "toggle-language":
		mode := "english"
		if p.snapshot.Modes.Input == "english" {
			mode = "chinese"
		}
		return p.dispatch(keyboardlab.Event{Type: "setModes", InputMode: mode, PunctuationMode: mode})
	case "input", "literal", "symbol":
		// Side Enter bypasses composition. Preserve its modifiers rather than
		// round-tripping a newline through a text-only engine commit.
		if p.emit != nil && a.Type == "literal" && a.ASCII == "\n" {
			return p.emitEdit(tk.Output{Key: "Enter", Shift: o.Shift})
		}
		// A digit may have meant candidate selection at DOWN. Never reinterpret
		// that gesture as a new-page ordinal or a literal after the snapshot changes.
		if a.Type == "input" && len(a.ASCII) == 1 && a.ASCII[0] >= '1' && a.ASCII[0] <= '9' && down != p.stamp() {
			return fmt.Errorf("数字动作的候选状态已更新；本次触点取消")
		}
		kind := a.Type
		if a.LiteralEntry && p.literalEntries {
			kind = "symbol"
		}
		return p.dispatch(keyboardlab.Event{Type: kind, Code: a.ASCII})
	case "confirm":
		if down != p.stamp() {
			return fmt.Errorf("确认前候选已更新；本次触点取消")
		}
		if p.snapshot.Modes.Input == "english" {
			code := " "
			if a.Key == "Enter" {
				if p.emit != nil {
					return p.emitEdit(tk.Output{Key: "Enter", Shift: o.Shift})
				}
				code = "\n"
			}
			return p.dispatch(keyboardlab.Event{Type: "literal", Code: code})
		}
		if len(p.snapshot.State.Candidates) > 0 {
			return p.selectCandidate(p.candidate(0))
		}
		return nil
	case "clear":
		return p.dispatch(keyboardlab.Event{Type: "clear"})
	case "backspace":
		if o.Zone != "left" && o.Zone != "right" && p.snapshot.State.RawInput != "" && p.snapshot.Modes.Input == "chinese" {
			return p.dispatch(keyboardlab.Event{Type: "backspace"})
		}
		if p.emit != nil {
			return p.emitEdit(tk.Output{Key: "Backspace", Shift: o.Shift})
		}
		p.editor.edit("Backspace", o.Shift)
		return nil
	case "local":
		if o.Zone != "left" && o.Zone != "right" && p.snapshot.State.RawInput != "" && p.snapshot.Modes.Input == "chinese" {
			if a.Key == "PageUp" {
				return p.page(-1)
			}
			if a.Key == "PageDown" {
				return p.page(1)
			}
			return fmt.Errorf("请先确认或取消组合，再编辑本地输出")
		}
		if a.Key == "Tab" {
			if p.emit != nil {
				return p.emitEdit(tk.Output{Key: "Tab", Shift: o.Shift})
			}
			p.editor.insert("\t")
			return nil
		}
		if p.emit != nil {
			return p.emitEdit(tk.Output{Key: a.Key, Shift: o.Shift})
		}
		p.editor.edit(a.Key, o.Shift)
	}
	return nil
}

func (p *preview) emitEdit(o tk.Output) error {
	p.sequence++
	err := p.emit(fmt.Sprintf("%s/edit-%d", p.snapshot.SessionID, p.sequence), o)
	if err != nil {
		p.fault = true
	}
	return err
}

// Retire without consuming any reply output, including when the display was
// invalidated while a response was pending. The service owns final cleanup.
func (p *preview) retire() {
	if p.snapshot.SessionID == "" {
		return
	}
	p.sequence++
	p.sessions.Dispatch(keyboardlab.Event{SessionID: p.snapshot.SessionID, EventID: fmt.Sprintf("retire-%d", p.sequence), BaseRevision: p.snapshot.Revision, Type: "close"})
	p.fault = true
}

// The controlled text sink edits Unicode code points (not UTF-16 halves).
// It is deliberately separate from both product editors and host edit sessions.
type previewEditor struct {
	text           []rune
	cursor, anchor int
}

func (e *previewEditor) bounds() (int, int) { return min(e.cursor, e.anchor), max(e.cursor, e.anchor) }
func (e *previewEditor) insert(s string) {
	if s == "" {
		return
	}
	l, r := e.bounds()
	n := []rune(s)
	e.text = append(append(append([]rune{}, e.text[:l]...), n...), e.text[r:]...)
	e.cursor, e.anchor = l+len(n), l+len(n)
}
func (e *previewEditor) edit(key string, shift bool) {
	l, r := e.bounds()
	switch key {
	case "Backspace", "Delete":
		if l == r {
			if key == "Backspace" {
				l = max(0, l-1)
			} else {
				r = min(len(e.text), r+1)
			}
		}
		e.text = append(e.text[:l], e.text[r:]...)
		e.cursor, e.anchor = l, l
		return
	case "ArrowLeft":
		if !shift && l != r {
			e.cursor = l
		} else {
			e.cursor = max(0, e.cursor-1)
		}
	case "ArrowRight":
		if !shift && l != r {
			e.cursor = r
		} else {
			e.cursor = min(len(e.text), e.cursor+1)
		}
	case "Home":
		e.cursor = 0
	case "End":
		e.cursor = len(e.text)
	default:
		return
	}
	if !shift {
		e.anchor = e.cursor
	}
}
func (e *previewEditor) display() string {
	l, r := e.bounds()
	// Keep the caret/selection visible even with a long in-memory transcript.
	start, end := max(0, l-80), min(len(e.text), r+80)
	if r-l > 160 {
		r = l + 160
		end = r
	}
	if l == r {
		return string(e.text[start:l]) + "│" + string(e.text[r:end])
	}
	return string(e.text[start:l]) + "⟦" + string(e.text[l:r]) + "⟧" + string(e.text[r:end])
}
