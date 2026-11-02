//go:build windows && amd64

package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	bridge "github.com/tsaanghwang/Yime/go-backend/internal/touchhostbridge"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"syscall"
	"testing"
	"time"
	"unsafe"
)

type uiHostReply struct {
	Seq             uint64 `json:"seq"`
	Op              string `json:"op"`
	Epoch           uint64 `json:"epoch"`
	Context         string `json:"context"`
	OK              bool   `json:"ok"`
	Outcome         string `json:"outcome"`
	ReadbackMatch   bool   `json:"readbackMatch"`
	TotalUTF16Units int    `json:"totalUTF16Units"`
	CallbackSeen    bool   `json:"callbackSeen"`
}
type uiHostPipe struct {
	cmd        *exec.Cmd
	cancel     context.CancelFunc
	in         io.WriteCloser
	out        *bufio.Scanner
	seq, epoch uint64
	closed     bool
}
type uiBoundedLog struct{ n int }

func (b *uiBoundedLog) Write(p []byte) (int, error) {
	b.n += len(p)
	if b.n > 16384 {
		return 0, fmt.Errorf("native stderr limit")
	}
	return len(p), nil
}
func startUIHost(t *testing.T, path string) *uiHostPipe {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	cmd := exec.CommandContext(ctx, path)
	cmd.Dir = t.TempDir()
	cmd.Stderr = &uiBoundedLog{}
	in, e := cmd.StdinPipe()
	if e != nil {
		cancel()
		t.Fatal(e)
	}
	out, e := cmd.StdoutPipe()
	if e != nil {
		cancel()
		t.Fatal(e)
	}
	if e = cmd.Start(); e != nil {
		cancel()
		t.Fatal(e)
	}
	scanner := bufio.NewScanner(out)
	scanner.Buffer(make([]byte, 1024), 16384)
	h := &uiHostPipe{cmd: cmd, cancel: cancel, in: in, out: scanner}
	t.Cleanup(func() {
		if !h.closed {
			cancel()
			_ = cmd.Wait()
		}
		cancel()
	})
	r, e := h.call("init", nil)
	if e != nil || r.Epoch != 1 {
		t.Fatalf("native init: %v %+v", e, r)
	}
	h.epoch = r.Epoch
	return h
}
func (h *uiHostPipe) call(op string, c *bridge.Commit) (r uiHostReply, err error) {
	if h.closed {
		return r, fmt.Errorf("closed child; no restart")
	}
	timer := time.AfterFunc(5*time.Second, h.cancel)
	defer timer.Stop()
	defer func() {
		if err != nil && !h.closed {
			h.cancel()
			_ = h.cmd.Wait()
			h.closed = true
		}
	}()
	h.seq++
	q := map[string]any{"seq": h.seq, "op": op, "epoch": h.epoch}
	if c != nil {
		q["id"] = c.ID
		q["text"] = c.Text
		q["epoch"] = c.Focus.Epoch
	}
	b, e := json.Marshal(q)
	if e != nil || len(b) > 16382 {
		return r, fmt.Errorf("request bound")
	}
	if _, e = h.in.Write(append(b, '\n')); e != nil {
		return r, e
	}
	if !h.out.Scan() {
		return r, fmt.Errorf("native disconnected or timed out; outcome unknown")
	}
	d := json.NewDecoder(bytes.NewReader(h.out.Bytes()))
	d.DisallowUnknownFields()
	if e = d.Decode(&r); e != nil {
		return r, e
	}
	var extra any
	if d.Decode(&extra) != io.EOF {
		return r, fmt.Errorf("trailing reply")
	}
	expected := h.epoch
	if op == "init" {
		expected = 1
	}
	if op == "rebind" {
		expected++
	}
	if r.Seq != h.seq || r.Op != op || r.Epoch != expected || r.Context != "own-test-host" || !r.OK || !r.ReadbackMatch || r.TotalUTF16Units < 0 || r.TotalUTF16Units > 1024 {
		return r, fmt.Errorf("untrusted native reply")
	}
	if op == "commit" {
		if r.Outcome != "applied" || !r.CallbackSeen {
			return r, fmt.Errorf("edit not confirmed")
		}
	} else if r.Outcome != "" || r.CallbackSeen {
		return r, fmt.Errorf("unexpected completion")
	}
	return r, nil
}
func (h *uiHostPipe) submit(c bridge.Commit) (bridge.Outcome, error) {
	if c.Focus.Context != "own-test-host" || c.Focus.Epoch != h.epoch {
		return bridge.Failed, fmt.Errorf("foreign native context or epoch")
	}
	_, e := h.call("commit", &c)
	if e != nil {
		h.cancel()
		return bridge.Unknown, e
	}
	return bridge.Applied, nil
}
func (h *uiHostPipe) close() error {
	if _, e := h.call("close", nil); e != nil {
		return e
	}
	_ = h.in.Close()
	if h.out.Scan() || h.out.Err() != nil {
		return fmt.Errorf("extra output after close")
	}
	e := h.cmd.Wait()
	h.closed = true
	h.cancel()
	return e
}

// Real HWND + existing Win32 mouse handler/18u hit path, with synthetic
// messages, NOT physical acceptance, installed TIP, or a user-facing product.
// The child owns one TSF context for the whole sequence; no SendInput is used.
func TestTouchBridgePersistentOwnHostUI(t *testing.T) {
	path := os.Getenv("YIME_TOUCH_BRIDGE_UI_HOST")
	if path == "" {
		t.Skip("explicit isolated native own-host executable not configured")
	}
	if !filepath.IsAbs(path) {
		t.Fatal("native own-host path must be absolute")
	}
	if st, e := os.Stat(path); e != nil || st.IsDir() {
		t.Fatal("configured native own-host missing")
	}
	for _, name := range []string{"continuous-commit", "stale-candidate", "invalidate-rebind"} {
		t.Run(name, func(t *testing.T) {
			runtime.LockOSThread()
			defer runtime.UnlockOSThread()
			h := startUIHost(t, path)
			root, data := bridgeUIData(t)
			makePreview := func() *preview {
				p, e := newBridgePreview(root, data, bridge.Focus{Context: "own-test-host", Epoch: h.epoch}, h.submit)
				if e != nil {
					t.Fatal(e)
				}
				t.Cleanup(p.retire)
				return p
			}
			a := touchUIFixture(t)
			a.preview = makePreview()
			a.s.Original = true
			instance, _, _ := k32.NewProc("GetModuleHandleW").Call(0)
			class := wc{Proc: syscall.NewCallback(windowProc), Instance: instance, Name: str("YimeBridgeOwnHostUI_" + name)}
			class.Size = uint32(unsafe.Sizeof(class))
			if n, _, _ := U("RegisterClassExW").Call(uintptr(unsafe.Pointer(&class))); n == 0 {
				t.Fatal("register test window")
			}
			previous := active
			active = a
			defer func() { active = previous; U("UnregisterClassW").Call(ptr(class.Name), instance) }()
			hwnd, _, _ := U("CreateWindowExW").Call(0, ptr(class.Name), ptr(str("Isolated bridge UI test")), 0x00CF0000, 0, 0, 1600, 900, 0, 0, instance, 0)
			if hwnd == 0 {
				t.Fatal("create real UI window")
			}
			a.h = hwnd
			defer func() {
				if alive, _, _ := U("IsWindow").Call(hwnd); alive != 0 {
					U("DestroyWindow").Call(hwnd)
				}
				var m message
				U("PeekMessageW").Call(uintptr(unsafe.Pointer(&m)), 0, 0x0012, 0x0012, 1) // Remove only our WM_QUIT.
			}()
			mouse := func(msg uint32, x, y int32) {
				packed := uintptr(uint32(uint16(x)) | uint32(uint16(y))<<16)
				U("SendMessageW").Call(hwnd, uintptr(msg), 0, packed)
			}
			tap := func(x, y int32) { mouse(0x0201, x, y); mouse(0x0202, x, y) }
			input := func() {
				x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
				tap(x, y)
				if a.preview.snapshot.State.RawInput != "a" {
					t.Fatal("real UI input path did not compose", a.status)
				}
			}
			candidate := func() (int32, int32) { r := a.candidateRect(0); return (r.L + r.R) / 2, (r.T + r.B) / 2 }
			selectFirst := func() {
				x, y := candidate()
				tap(x, y)
				mouse(0x0202, x, y) // Duplicate UP must not submit a second native edit.
				if a.preview.fault || a.preview.bridge.session.Receipt().Outcome != bridge.Applied {
					t.Fatal("real candidate UI did not apply", a.status)
				}
			}
			readUnits := func(want int) {
				r, e := h.call("read", nil)
				if e != nil || r.TotalUTF16Units != want {
					t.Fatalf("native readback units want %d: %v %+v", want, e, r)
				}
			}
			input()
			selectFirst()
			readUnits(2)
			switch name {
			case "continuous-commit":
				input()
				selectFirst()
				readUnits(4)
			case "stale-candidate":
				input()
				x, y := candidate()
				mouse(0x0201, x, y)
				if e := a.preview.page(1); e != nil {
					t.Fatal(e)
				}
				mouse(0x0202, x, y)
				readUnits(2)
			case "invalidate-rebind":
				input()
				x, y := candidate()
				mouse(0x0201, x, y)
				if _, e := h.call("invalidate", nil); e != nil {
					t.Fatal(e)
				}
				old := a.preview
				old.retire()
				a.cancel()
				mouse(0x0202, x, y)
				readUnits(2)
				r, e := h.call("rebind", nil)
				if e != nil {
					t.Fatal(e)
				}
				h.epoch = r.Epoch
				a.preview = makePreview()
				a.cancel()
				input()
				selectFirst()
				readUnits(4)
				if old.bridge.session.Receipt().Outcome != bridge.Applied {
					t.Fatal("old completed receipt mutated")
				}
			}
			if len(a.preview.editor.text) != 0 || a.host != nil {
				t.Fatal("local editor/SendInput host fallback")
			}
			U("SendMessageW").Call(hwnd, 0x0010, 0, 0) // Existing WM_CLOSE/default window destruction path.
			if alive, _, _ := U("IsWindow").Call(hwnd); alive != 0 {
				t.Fatal("own UI did not close")
			}
			if e := h.close(); e != nil {
				t.Fatal("native normal close", e)
			}
		})
	}
}
