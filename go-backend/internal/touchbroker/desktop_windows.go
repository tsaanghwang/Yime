//go:build windows

package touchbroker

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
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
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
)

var desktopKernel = syscall.NewLazyDLL("kernel32.dll")
var desktopUser = syscall.NewLazyDLL("user32.dll")

func DesktopPipeName() (string, error) {
	var session uint32
	ok, _, e := desktopKernel.NewProc("ProcessIdToSessionId").Call(uintptr(os.Getpid()), uintptr(unsafe.Pointer(&session)))
	if ok == 0 {
		return "", touchdiagnostic.FromError(e, "transport-connect", "operation-failed")
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
func actualForeground(owner yimebroker.TrustedClient, window uint64, thread uint32) bool {
	if window == 0 || thread == 0 {
		return false
	}
	w, _, _ := desktopUser.NewProc("GetForegroundWindow").Call()
	if uint64(w) != window {
		return false
	}
	var pid uint32
	t, _, _ := desktopUser.NewProc("GetWindowThreadProcessId").Call(w, uintptr(unsafe.Pointer(&pid)))
	return uint32(t) == thread && pid != 0 && pid == peerPID(owner)
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

// Check the shared first-frame envelope before either protocol decoder runs.
// The ordinary decoder accepts case-insensitive field names and last-key wins;
// neither repeated keys nor case aliases may turn a rejected report into next.
// Keep schema validation in the existing decoders and later frames unchanged.
func uniqueTIPFirstFrameFields(raw []byte) bool {
	d := json.NewDecoder(bytes.NewReader(raw))
	token, err := d.Token()
	if err != nil || token != json.Delim('{') {
		return false
	}
	var seen []string
	for d.More() {
		token, err = d.Token()
		key, ok := token.(string)
		if err != nil || !ok {
			return false
		}
		for _, previous := range seen {
			if strings.EqualFold(previous, key) {
				return false
			}
		}
		seen = append(seen, key)
		var value json.RawMessage
		if d.Decode(&value) != nil {
			return false
		}
	}
	token, err = d.Token()
	return err == nil && token == json.Delim('}') && d.Decode(new(any)) == io.EOF
}

func desktopLines(ctx context.Context, in io.Reader, out io.Writer, fn func([]byte) (any, error)) error {
	s := bufio.NewScanner(in)
	s.Buffer(make([]byte, 4096), MaxFrame+1)
	for s.Scan() {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if len(s.Bytes()) > MaxFrame {
			return touchdiagnostic.New("broker-request", "request-too-large")
		}
		v, e := fn(s.Bytes())
		if e != nil {
			return e
		}
		raw, e := json.Marshal(v)
		if e != nil {
			return touchdiagnostic.New("transport-response", "invalid-response")
		}
		if len(raw) > MaxFrame {
			return touchdiagnostic.New("transport-response", "response-too-large")
		}
		raw = append(raw, '\n')
		n, e := out.Write(raw)
		if e != nil {
			// Preserve the transport's errors.Is(ERROR_BROKEN_PIPE) suppression.
			// The connection callback safely extracts any typed system code.
			return e
		}
		if n != len(raw) {
			return io.ErrShortWrite
		}
	}
	return s.Err()
}

// writeDesktopConnectionDiagnostic is a best-effort, single bounded write.
// The original connection error still closes the connection. Only discovery
// reports carry the server-added PID/creation identity, receive time and event
// ID. No SID/logon text, path, arbitrary error text or protocol frame is recorded.
func writeDesktopConnectionDiagnostic(w io.Writer, err error) {
	defer func() { _ = recover() }()
	if err == nil || errors.Is(err, errDiagnosticDropped) {
		return
	}
	d := touchdiagnostic.FromError(err, "broker-connection", "unknown")
	raw, e := json.Marshal(d)
	if e != nil || len(raw) >= 256 {
		return
	}
	_, _ = w.Write(append(raw, '\n'))
}

type desktopHandler = func(context.Context, io.Reader, io.Writer, yimebroker.TrustedClient) error
type desktopServer = func(context.Context, yimebroker.NamedPipeConfig, desktopHandler) error

// Both production and offline handler tests pass through this configuration.
// The transport owns calling OnConnectionError once after rejection/closure.
func serveDesktopPipe(ctx context.Context, name string, onListening func(), handler desktopHandler, diagnostic io.Writer, serve desktopServer) error {
	return serve(ctx, yimebroker.NamedPipeConfig{
		Name: name, RequireSameLogon: true, MaxConnections: 32, MaxConnectionsPerClient: 8,
		OnListening:       onListening,
		OnConnectionError: func(err error) { writeDesktopConnectionDiagnostic(diagnostic, err) },
	}, handler)
}

func (relay *DesktopRelay) serveTIP(ctx context.Context, in io.Reader, out io.Writer, owner yimebroker.TrustedClient) error {
	deadline, ok := in.(interface{ SetReadDeadline(time.Time) error })
	if !ok {
		return touchdiagnostic.New("broker-request", "invalid-response")
	}
	if err := deadline.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
		return touchdiagnostic.FromError(err, "transport-read", "read-failed")
	}
	var p *tipPeer
	defer func() {
		if p != nil {
			relay.closePeer(p)
		}
	}()
	return desktopLines(ctx, in, out, func(raw []byte) (any, error) {
		// Only a standalone first frame can report a discovery rejection. Return
		// it through the existing authenticated connection-error recorder. No
		// peer, lease, queue, session or successful storage receipt is created.
		if p == nil {
			if len(raw) > touchdiagnostic.MaxLine+64 {
				return nil, touchdiagnostic.New("broker-request", "request-too-large")
			}
			if !uniqueTIPFirstFrameFields(raw) {
				return nil, touchdiagnostic.New("broker-request", "invalid-response")
			}
			if diagnostic, ok := touchdiagnostic.DecodeDiscoveryFrame(raw); ok {
				if !relay.diagnosticBudget.allow(time.Now()) {
					return nil, errDiagnosticDropped
				}
				return nil, receivedDiscovery(diagnostic, owner, time.Now())
			}
		}
		var q tipRequest
		if e := decodeDesktop(raw, &q); e != nil {
			return nil, touchdiagnostic.New("broker-request", "invalid-response")
		}
		if p == nil {
			// Match the old rejection reasons without creating a business peer
			// for a malformed first poll or a completion with no prior request.
			if q.Operation == "complete" {
				return nil, touchdiagnostic.New("broker-receipt", "pending-action-mismatch")
			}
			if q.Operation != "next" {
				return nil, touchdiagnostic.New("broker-request", "invalid-operation")
			}
			if q.Window == 0 || q.Thread == 0 || q.Generation == 0 || q.Ticket != "" || len(q.Result) != 0 {
				return nil, touchdiagnostic.New("broker-request", "invalid-poll")
			}
			if err := deadline.SetReadDeadline(time.Time{}); err != nil {
				return nil, touchdiagnostic.FromError(err, "transport-read", "read-failed")
			}
			p = relay.newPeer(owner)
		}
		v := relay.tip(ctx, p, q)
		if !v.OK {
			if v.Diagnostic != nil {
				return nil, touchdiagnostic.Sanitize(*v.Diagnostic)
			}
			return nil, touchdiagnostic.New("broker-request", "unknown")
		}
		return v, nil
	})
}

// The OS transport has already authenticated user/session/logon and holds this
// process object. Copy only PID and creation identity from that trusted token;
// never accept origin fields from the client's diagnostic frame.
func receivedDiscovery(d touchdiagnostic.Diagnostic, owner yimebroker.TrustedClient, now time.Time) error {
	parts := strings.SplitN(owner.ID, ":pid:", 2)
	if len(parts) != 2 {
		return touchdiagnostic.New("broker-auth", "request-identity-unavailable")
	}
	identity := strings.Split(parts[1], ":created:")
	if len(identity) != 2 || len(identity[1]) != 16 {
		return touchdiagnostic.New("broker-auth", "request-identity-unavailable")
	}
	pid, err := strconv.ParseUint(identity[0], 10, 32)
	if err != nil {
		return touchdiagnostic.New("broker-auth", "request-identity-unavailable")
	}
	created, err := strconv.ParseUint(identity[1], 16, 64)
	if err != nil {
		return touchdiagnostic.New("broker-auth", "request-identity-unavailable")
	}
	d.Reported = &touchdiagnostic.ReportOrigin{ReceivedMS: now.UnixMilli(), Event: newDesktopID(), PID: uint32(pid), Created: created}
	if !d.Reported.Valid() {
		return touchdiagnostic.New("broker-auth", "request-identity-unavailable")
	}
	return d
}

func (relay *DesktopRelay) serveUI(ctx context.Context, in io.Reader, out io.Writer, owner yimebroker.TrustedClient) error {
	if !relay.frontend(owner) {
		return touchdiagnostic.New("broker-auth", "frontend-not-authorized")
	}
	var sequence uint64
	return desktopLines(ctx, in, out, func(raw []byte) (any, error) {
		var q DesktopRequest
		if e := decodeDesktop(raw, &q); e != nil {
			return nil, touchdiagnostic.New("broker-request", "invalid-response")
		}
		if q.Sequence != sequence+1 {
			return nil, touchdiagnostic.New("broker-request", "sequence-mismatch")
		}
		sequence = q.Sequence
		return relay.call(ctx, owner, q), nil
	})
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
	diagnosticSink := newDesktopDiagnosticSink(ctx, os.Stderr)
	ready := make(chan struct{}, 3)
	done := make(chan error, 3)
	serve := func(suffix string, handler func(context.Context, io.Reader, io.Writer, yimebroker.TrustedClient) error) {
		done <- serveDesktopPipe(ctx, base+suffix, func() { ready <- struct{}{} }, handler, diagnosticSink, yimebroker.ServeNamedPipeHandler)
	}
	go serve("-engine", s.ServeConnection)
	go serve("-tip", relay.serveTIP)
	go serve("-ui", relay.serveUI)
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

// The transport interface also supports offline fault injection without opening
// a named pipe, loading a TIP, or contacting an installed product.
type desktopPipe interface {
	io.Writer
	SetDeadline(time.Time) error
	Close() error
}

type DesktopClient struct {
	mu       sync.Mutex
	file     desktopPipe
	reader   *bufio.Reader
	sequence uint64
	failed   bool
}

func OpenDesktopClient(base string, pid uint32, image string) (*DesktopClient, error) {
	if pid == 0 || !filepath.IsAbs(image) {
		return nil, touchdiagnostic.New("transport-connect", "broker-required")
	}
	name, e := syscall.UTF16PtrFromString(base + "-ui")
	if e != nil {
		return nil, touchdiagnostic.FromError(e, "transport-connect", "pipe-name-invalid")
	}
	h, e := syscall.CreateFile(name, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, syscall.OPEN_EXISTING, syscall.FILE_FLAG_OVERLAPPED|0x00110000, 0)
	if e != nil {
		return nil, touchdiagnostic.FromError(e, "transport-connect", "pipe-open-failed")
	}
	var actualPID uint32
	ok, _, e := desktopKernel.NewProc("GetNamedPipeServerProcessId").Call(uintptr(h), uintptr(unsafe.Pointer(&actualPID)))
	actual, ie := processImage(actualPID)
	if ok == 0 || actualPID != pid || ie != nil || !strings.EqualFold(actual, image) {
		syscall.CloseHandle(h)
		if ok == 0 {
			return nil, touchdiagnostic.FromError(e, "transport-connect", "server-pid-query-failed")
		}
		if actualPID != pid {
			return nil, touchdiagnostic.New("transport-connect", "identity-mismatch")
		}
		if ie != nil {
			return nil, touchdiagnostic.FromError(ie, "transport-connect", "server-image-query-failed")
		}
		return nil, touchdiagnostic.New("transport-connect", "identity-mismatch")
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
		return result, touchdiagnostic.New("transport-write", "connection-stopped")
	}
	c.sequence++
	q.Sequence = c.sequence
	raw, e := json.Marshal(q)
	if e != nil {
		return result, touchdiagnostic.FromError(e, "transport-write", "request-encoding-failed")
	}
	if len(raw) > MaxFrame {
		return result, touchdiagnostic.New("transport-write", "request-too-large")
	}
	_ = c.file.SetDeadline(time.Now().Add(80 * time.Second))
	if _, e = c.file.Write(append(raw, '\n')); e != nil {
		c.failed = true
		return result, touchdiagnostic.FromError(e, "transport-write", "write-failed")
	}
	line, e := c.reader.ReadSlice('\n')
	if e != nil || len(line) > MaxFrame {
		c.failed = true
		if e != nil {
			return result, touchdiagnostic.FromError(e, "transport-read", "read-failed")
		}
		return result, touchdiagnostic.New("transport-read", "response-too-large")
	}
	if e = decodeDesktop(line, &result); e != nil {
		c.failed = true
		return DesktopResponse{}, touchdiagnostic.New("transport-response", "invalid-response")
	}
	if result.Diagnostic != nil {
		d := touchdiagnostic.Sanitize(*result.Diagnostic)
		result.Diagnostic = &d
	}
	if !result.OK {
		d := touchdiagnostic.New("transport-response", "operation-failed")
		if result.Diagnostic != nil {
			d = *result.Diagnostic
		}
		// Do not return a peer's arbitrary error text, even as an auxiliary field.
		result.Error = d.Error()
		result.Diagnostic = &d
		return result, d
	}
	result.Error = ""
	result.Diagnostic = nil
	return result, nil
}
