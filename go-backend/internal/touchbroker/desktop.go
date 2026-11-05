package touchbroker

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"sync"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
	bridge "github.com/tsaanghwang/Yime/go-backend/internal/touchhostbridge"
)

var DesktopDictionaryHashes = map[string]string{
	"variable":  DictionarySHA,
	"full":      "85ff8a88dfe5a66a22429c9551c2625815af83351973db30f8faeb52fced3790",
	"shorthand": "b58c85d6b1d18fa72d8134b581ccdec71e434d8ec20d086306ff8b4f94a23d49",
}

// NewDesktopProduction uses only the full installed 18u package. The shared
// runtime contains immutable indexes; composition state belongs to each TIP.
func NewDesktopProduction(root, anchor string) (*Service, func() error, error) {
	if _, err := installed18uhost.VerifyDesktopInstallation(root, anchor); err != nil {
		return nil, nil, err
	}
	r, err := keyboardlab.OpenRuntime(filepath.Join(root, "source"), filepath.Join(root, "data"))
	if err != nil {
		return nil, nil, err
	}
	expected := map[string]Identity{}
	for mode, hash := range DesktopDictionaryHashes {
		if r.LayoutID != LayoutSHA || r.Builds[mode].SourceSHA256 != hash {
			_ = r.Close()
			return nil, nil, errors.New("desktop dictionary identity mismatch")
		}
		expected[mode] = Identity{LayoutSHA, hash, mode, keyboardlab.SessionPolicy}
	}
	return &Service{expectedModes: expected, openMode: func(mode string, f bridge.Focus) (*bridge.Session, error) {
		return bridge.OpenDesktopRuntime(r, mode, f)
	}}, r.Close, nil
}

type DesktopRequest struct {
	Sequence  uint64          `json:"sequence"`
	Operation string          `json:"operation"`
	Lease     string          `json:"lease,omitempty"`
	Mode      string          `json:"mode,omitempty"`
	Action    json.RawMessage `json:"action,omitempty"`
}
type DesktopResponse struct {
	OK         bool                        `json:"ok"`
	Error      string                      `json:"error,omitempty"`
	Diagnostic *touchdiagnostic.Diagnostic `json:"diagnostic,omitempty"`
	Lease      string                      `json:"lease,omitempty"`
	Result     json.RawMessage             `json:"result,omitempty"`
}

func desktopFailure(stage, reason string) DesktopResponse {
	d := touchdiagnostic.New(stage, reason)
	return DesktopResponse{Error: d.Error(), Diagnostic: &d}
}

type tipRequest struct {
	Operation  string          `json:"operation"`
	Window     uint64          `json:"window,omitempty"`
	Thread     uint32          `json:"thread,omitempty"`
	Generation uint64          `json:"generation,omitempty"`
	Ticket     string          `json:"ticket,omitempty"`
	Result     json.RawMessage `json:"result,omitempty"`
}
type tipResponse struct {
	OK         bool                        `json:"ok"`
	Error      string                      `json:"error,omitempty"`
	Ticket     string                      `json:"ticket,omitempty"`
	Operation  string                      `json:"operation,omitempty"`
	Mode       string                      `json:"mode,omitempty"`
	Action     json.RawMessage             `json:"action,omitempty"`
	Diagnostic *touchdiagnostic.Diagnostic `json:"diagnostic,omitempty"`
}

func tipFailure(stage, reason string) tipResponse {
	d := touchdiagnostic.New(stage, reason)
	return tipResponse{Error: d.Error(), Diagnostic: &d}
}

type desktopCall struct {
	ticket, lease string
	request       DesktopRequest
	result        chan DesktopResponse
}
type tipPeer struct {
	owner      yimebroker.TrustedClient
	window     uint64
	thread     uint32
	generation uint64
	lease      string
	queue      chan *desktopCall
	pending    *desktopCall
	closed     bool
}

// DesktopRelay transports actions to an already activated TIP. The OS peer
// identity and current foreground are checked separately from client JSON.
// It cannot write text or fabricate an edit completion.
type DesktopRelay struct {
	mu         sync.Mutex
	peers      map[*tipPeer]bool
	foreground func(yimebroker.TrustedClient, uint64, uint32) bool
	frontend   func(yimebroker.TrustedClient) bool
}

func NewDesktopRelay(foreground func(yimebroker.TrustedClient, uint64, uint32) bool, frontend func(yimebroker.TrustedClient) bool) *DesktopRelay {
	return &DesktopRelay{peers: map[*tipPeer]bool{}, foreground: foreground, frontend: frontend}
}
func newDesktopID() string {
	var b [16]byte
	if _, e := rand.Read(b[:]); e != nil {
		return ""
	}
	return hex.EncodeToString(b[:])
}
func (r *DesktopRelay) newPeer(owner yimebroker.TrustedClient) *tipPeer {
	p := &tipPeer{owner: owner, queue: make(chan *desktopCall, 1)}
	r.mu.Lock()
	r.peers[p] = true
	r.mu.Unlock()
	return p
}
func (r *DesktopRelay) closePeer(p *tipPeer) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.revoke(p)
	p.closed = true
	delete(r.peers, p)
}
func (r *DesktopRelay) revoke(p *tipPeer) {
	p.lease = ""
	if p.pending != nil {
		select {
		case p.pending.result <- desktopFailure("broker-session", "focus-revoked"):
		default:
		}
		p.pending = nil
	}
	select {
	case c := <-p.queue:
		select {
		case c.result <- desktopFailure("broker-session", "lease-revoked"):
		default:
		}
	default:
	}
}
func (r *DesktopRelay) tip(ctx context.Context, p *tipPeer, q tipRequest) tipResponse {
	if q.Operation == "complete" {
		r.mu.Lock()
		defer r.mu.Unlock()
		if p.closed || p.pending == nil || q.Ticket != p.pending.ticket || len(q.Result) == 0 || q.Window != 0 || q.Thread != 0 || q.Generation != 0 {
			return tipFailure("broker-receipt", "pending-action-mismatch")
		}
		c := p.pending
		p.pending = nil
		if p.lease != c.lease || !r.foreground(p.owner, p.window, p.thread) {
			r.revoke(p)
			c.result <- desktopFailure("broker-receipt", "focus-changed")
			return tipResponse{OK: true}
		}
		var result map[string]json.RawMessage
		if json.Unmarshal(q.Result, &result) != nil || result == nil {
			r.revoke(p)
			c.result <- desktopFailure("broker-receipt", "invalid-response")
			return tipFailure("broker-receipt", "invalid-response")
		}
		// Commit text and private edit receipts are never a frontend capability.
		delete(result, "commit")
		delete(result, "receipt")
		raw, _ := json.Marshal(result)
		c.result <- DesktopResponse{OK: true, Lease: p.lease, Result: raw}
		return tipResponse{OK: true}
	}
	if q.Operation != "next" || q.Ticket != "" || len(q.Result) != 0 || q.Generation == 0 {
		return tipFailure("broker-request", "invalid-poll")
	}
	r.mu.Lock()
	if p.closed || p.pending != nil {
		r.mu.Unlock()
		return tipFailure("broker-queue", "previous-action-pending")
	}
	if !r.foreground(p.owner, q.Window, q.Thread) {
		r.revoke(p)
		r.mu.Unlock()
		return tipResponse{OK: true}
	}
	if p.generation != q.Generation || p.window != q.Window || p.thread != q.Thread || p.lease == "" {
		r.revoke(p)
		p.generation, p.window, p.thread = q.Generation, q.Window, q.Thread
		p.lease = newDesktopID()
	}
	lease := p.lease
	r.mu.Unlock()
	select {
	case c := <-p.queue:
		r.mu.Lock()
		defer r.mu.Unlock()
		if p.closed || lease == "" || lease != p.lease || c.lease != lease || !r.foreground(p.owner, p.window, p.thread) {
			c.result <- desktopFailure("broker-session", "stale-focus")
			return tipResponse{OK: true}
		}
		// Every bind starts a new input session, even in the same TSF context.
		// Retire the old frontend capability before dispatching it so a delayed
		// action at revision zero cannot enter the new mode/session.
		if c.request.Operation == "bind" {
			fresh := newDesktopID()
			if fresh == "" {
				r.revoke(p)
				c.result <- desktopFailure("broker-session", "lease-identity-unavailable")
				return tipResponse{OK: true}
			}
			p.lease = fresh
			c.lease = fresh
		}
		p.pending = c
		return tipResponse{OK: true, Ticket: c.ticket, Operation: c.request.Operation, Mode: c.request.Mode, Action: c.request.Action}
	case <-ctx.Done():
		return tipFailure("broker-session", "connection-closed")
	case <-time.After(200 * time.Millisecond):
		return tipResponse{OK: true}
	}
}
func (r *DesktopRelay) call(ctx context.Context, owner yimebroker.TrustedClient, q DesktopRequest) DesktopResponse {
	if !r.frontend(owner) {
		return desktopFailure("broker-auth", "frontend-not-authorized")
	}
	if q.Operation != "bind" && q.Operation != "action" && q.Operation != "close" {
		return desktopFailure("broker-request", "invalid-operation")
	}
	if q.Operation == "bind" {
		if q.Lease != "" || len(q.Action) != 0 || DesktopDictionaryHashes[q.Mode] == "" {
			return desktopFailure("broker-request", "invalid-bind")
		}
	} else if q.Lease == "" || q.Mode != "" || q.Operation == "close" && len(q.Action) != 0 || q.Operation == "action" && len(q.Action) == 0 {
		return desktopFailure("broker-request", "invalid-action-lease")
	}
	r.mu.Lock()
	var selected *tipPeer
	for p := range r.peers {
		if p.closed || p.lease == "" || !r.foreground(p.owner, p.window, p.thread) {
			continue
		}
		if q.Operation != "bind" && p.lease != q.Lease {
			continue
		}
		if selected != nil {
			r.mu.Unlock()
			return desktopFailure("broker-select", "ambiguous-tip")
		}
		selected = p
	}
	if selected == nil {
		r.mu.Unlock()
		return desktopFailure("broker-select", "no-eligible-tip")
	}
	if selected.pending != nil {
		r.mu.Unlock()
		return desktopFailure("broker-queue", "edit-pending")
	}
	c := &desktopCall{ticket: newDesktopID(), lease: selected.lease, request: q, result: make(chan DesktopResponse, 1)}
	if c.ticket == "" {
		r.mu.Unlock()
		return desktopFailure("broker-queue", "request-identity-unavailable")
	}
	select {
	case selected.queue <- c:
	default:
		r.mu.Unlock()
		return desktopFailure("broker-queue", "action-queued")
	}
	r.mu.Unlock()
	select {
	case result := <-c.result:
		return result
	case <-ctx.Done():
		r.mu.Lock()
		r.revoke(selected)
		r.mu.Unlock()
		return desktopFailure("broker-session", "frontend-disconnected")
	case <-time.After(75 * time.Second):
		r.mu.Lock()
		r.revoke(selected)
		r.mu.Unlock()
		return desktopFailure("broker-receipt", "completion-unknown")
	}
}

func DesktopPipeBase(session uint32) string {
	return fmt.Sprintf(`\\.\pipe\YimeBroker.18uTouch.v1.desktop-%d`, session)
}
