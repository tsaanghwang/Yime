//go:build windows

package touchbroker

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
)

var desktopKernel = syscall.NewLazyDLL("kernel32.dll")
var desktopUser = syscall.NewLazyDLL("user32.dll")

func DesktopPipeName() (string, error) {
	var session uint32
	ok, _, e := desktopKernel.NewProc("ProcessIdToSessionId").Call(uintptr(os.Getpid()), uintptr(unsafe.Pointer(&session)))
	if ok == 0 {
		return "", e
	}
	return DesktopPipeBase(session), nil
}
func peerPID(owner yimebroker.TrustedClient) uint32 {
	s := strings.SplitN(owner.ID, ":pid:", 2)
	if len(s) != 2 {
		return 0
	}
	n, e := strconv.ParseUint(strings.SplitN(s[1], ":", 2)[0], 10, 32)
	if e != nil {
		return 0
	}
	return uint32(n)
}
func processImage(pid uint32) (string, error) {
	h, e := syscall.OpenProcess(0x1000, false, pid)
	if e != nil {
		return "", e
	}
	defer syscall.CloseHandle(h)
	buffer := make([]uint16, 32768)
	n := uint32(len(buffer))
	ok, _, e := desktopKernel.NewProc("QueryFullProcessImageNameW").Call(uintptr(h), 0, uintptr(unsafe.Pointer(&buffer[0])), uintptr(unsafe.Pointer(&n)))
	if ok == 0 {
		return "", e
	}
	return syscall.UTF16ToString(buffer[:n]), nil
}

type desktopGUIThreadInfo struct {
	Size, Flags                uint32
	Active, Focus, Capture     uintptr
	MenuOwner, MoveSize, Caret uintptr
	CaretRect                  [4]int32
}

func actualForeground(owner yimebroker.TrustedClient, window, focus uint64, thread uint32) bool {
	pid := peerPID(owner)
	if pid == 0 || window == 0 || focus == 0 || thread == 0 {
		return false
	}
	w, _, _ := desktopUser.NewProc("GetForegroundWindow").Call()
	if uint64(w) != window {
		return false
	}
	var current desktopForegroundSnapshot
	current.Window = uint64(w)
	windowThread, _, _ := desktopUser.NewProc("GetWindowThreadProcessId").Call(w, uintptr(unsafe.Pointer(&current.WindowPID)))
	if windowThread == 0 {
		return false
	}
	gui := desktopGUIThreadInfo{}
	gui.Size = uint32(unsafe.Sizeof(gui))
	ok, _, _ := desktopUser.NewProc("GetGUIThreadInfo").Call(0, uintptr(unsafe.Pointer(&gui)))
	if ok == 0 || gui.Focus == 0 {
		return false
	}
	current.Focus = uint64(gui.Focus)
	t, _, _ := desktopUser.NewProc("GetWindowThreadProcessId").Call(gui.Focus, uintptr(unsafe.Pointer(&current.FocusPID)))
	current.FocusThread = uint32(t)
	root, _, _ := desktopUser.NewProc("GetAncestor").Call(gui.Focus, 2) // GA_ROOT
	current.Root = uint64(root)
	w, _, _ = desktopUser.NewProc("GetForegroundWindow").Call()
	current.FinalWindow = uint64(w)
	return matchesDesktopForeground(pid, window, focus, thread, current)
}
func decodeDesktop(raw []byte, v any) error {
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if e := d.Decode(v); e != nil {
		return e
	}
	if d.Decode(new(any)) != io.EOF {
		return errors.New("trailing frame")
	}
	return nil
}
func desktopLines(ctx context.Context, in io.Reader, out io.Writer, fn func([]byte) (any, error)) error {
	s := bufio.NewScanner(in)
	s.Buffer(make([]byte, 4096), MaxFrame+1)
	for s.Scan() {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if len(s.Bytes()) > MaxFrame {
			return errors.New("desktop frame too large")
		}
		v, e := fn(s.Bytes())
		if e != nil {
			return e
		}
		raw, e := json.Marshal(v)
		if e != nil || len(raw) > MaxFrame {
			return errors.New("desktop response too large")
		}
		raw = append(raw, '\n')
		n, e := out.Write(raw)
		if e != nil {
			return e
		}
		if n != len(raw) {
			return io.ErrShortWrite
		}
	}
	return s.Err()
}
func ServeDesktop(ctx context.Context, root, anchor string, onReady func()) error {
	s, closeRuntime, e := NewDesktopProduction(root, anchor)
	if e != nil {
		return e
	}
	defer closeRuntime()
	base, e := DesktopPipeName()
	if e != nil {
		return e
	}
	image := filepath.Join(root, filepath.FromSlash(installed18uhost.FrontendPath))
	relay := NewDesktopRelay(actualForeground, func(owner yimebroker.TrustedClient) bool {
		actual, e := processImage(peerPID(owner))
		return e == nil && strings.EqualFold(actual, image)
	})
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	ready := make(chan struct{}, 3)
	done := make(chan error, 3)
	serve := func(suffix string, handler func(context.Context, io.Reader, io.Writer, yimebroker.TrustedClient) error) {
		done <- yimebroker.ServeNamedPipeHandler(ctx, yimebroker.NamedPipeConfig{Name: base + suffix, RequireSameLogon: true, MaxConnections: 32, MaxConnectionsPerClient: 8, OnListening: func() { ready <- struct{}{} }}, handler)
	}
	go serve("-engine", s.ServeConnection)
	go serve("-tip", func(ctx context.Context, in io.Reader, out io.Writer, owner yimebroker.TrustedClient) error {
		p := relay.newPeer(owner)
		defer relay.closePeer(p)
		return desktopLines(ctx, in, out, func(raw []byte) (any, error) {
			var q tipRequest
			if e := decodeDesktop(raw, &q); e != nil {
				return nil, e
			}
			v := relay.tip(ctx, p, q)
			if !v.OK {
				return nil, errors.New(v.Error)
			}
			return v, nil
		})
	})
	go serve("-ui", func(ctx context.Context, in io.Reader, out io.Writer, owner yimebroker.TrustedClient) error {
		if !relay.frontend(owner) {
			return errors.New("unexpected frontend image")
		}
		var sequence uint64
		return desktopLines(ctx, in, out, func(raw []byte) (any, error) {
			var q DesktopRequest
			if e := decodeDesktop(raw, &q); e != nil {
				return nil, e
			}
			if q.Sequence != sequence+1 {
				return nil, errors.New("frontend sequence mismatch; no replay")
			}
			sequence = q.Sequence
			return relay.call(ctx, owner, q), nil
		})
	})
	for i := 0; i < 3; i++ {
		select {
		case <-ready:
		case e := <-done:
			cancel()
			for j := 0; j < 2; j++ {
				<-done
			}
			return e
		}
	}
	if onReady != nil {
		onReady()
	}
	e = <-done
	cancel()
	<-done
	<-done
	return e
}

type DesktopClient struct {
	mu       sync.Mutex
	file     *os.File
	reader   *bufio.Reader
	sequence uint64
	failed   bool
}

func OpenDesktopClient(base string, pid uint32, image string) (*DesktopClient, error) {
	if pid == 0 || !filepath.IsAbs(image) {
		return nil, errors.New("expected installed broker required")
	}
	name, e := syscall.UTF16PtrFromString(base + "-ui")
	if e != nil {
		return nil, e
	}
	h, e := syscall.CreateFile(name, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, syscall.OPEN_EXISTING, syscall.FILE_FLAG_OVERLAPPED|0x00110000, 0)
	if e != nil {
		return nil, e
	}
	var actualPID uint32
	ok, _, e := desktopKernel.NewProc("GetNamedPipeServerProcessId").Call(uintptr(h), uintptr(unsafe.Pointer(&actualPID)))
	actual, ie := processImage(actualPID)
	if ok == 0 || actualPID != pid || ie != nil || !strings.EqualFold(actual, image) {
		syscall.CloseHandle(h)
		return nil, fmt.Errorf("installed broker identity mismatch: %v", e)
	}
	f := os.NewFile(uintptr(h), base+"-ui")
	return &DesktopClient{file: f, reader: bufio.NewReaderSize(f, MaxFrame+1)}, nil
}
func (c *DesktopClient) Close() error { return c.file.Close() }
func (c *DesktopClient) Call(q DesktopRequest) (DesktopResponse, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	var result DesktopResponse
	if c.failed {
		return result, errors.New("desktop connection stopped; no replay")
	}
	c.sequence++
	q.Sequence = c.sequence
	raw, e := json.Marshal(q)
	if e != nil {
		return result, e
	}
	if len(raw) > MaxFrame {
		return result, errors.New("desktop request too large")
	}
	_ = c.file.SetDeadline(time.Now().Add(80 * time.Second))
	if _, e = c.file.Write(append(raw, '\n')); e != nil {
		c.failed = true
		return result, e
	}
	line, e := c.reader.ReadSlice('\n')
	if e != nil || len(line) > MaxFrame {
		c.failed = true
		return result, errors.New("TIP response missing; no replay")
	}
	if e = decodeDesktop(line, &result); e != nil {
		c.failed = true
		return result, e
	}
	if !result.OK {
		return result, errors.New(result.Error)
	}
	return result, nil
}
