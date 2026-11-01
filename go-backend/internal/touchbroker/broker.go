// Package touchbroker is the dedicated, single-TIP-connection protocol. There
// is deliberately no frontend route or cross-connection session capability.
package touchbroker

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	bridge "github.com/tsaanghwang/Yime/go-backend/internal/touchhostbridge"
)

const Product = "YimeCore18uTouch"
const LayoutSHA = "995f1a74f129249febbd09ca11a8266f6e0c94bac8c05c57754859fc3be3349c"
const DictionarySHA = "43a74f4e47c7100f222a744f487762f1c31222c5f80b9a34fd24cbebc7e96353"
const MaxFrame = 64 * 1024

type Identity struct {
	Layout     string `json:"layoutSHA256"`
	Dictionary string `json:"dictionarySHA256"`
	Mode       string `json:"mode"`
	Policy     string `json:"sessionPolicy"`
}

func identity(i bridge.Identity) Identity {
	return Identity{i.LayoutSHA256, i.DictionarySHA256, i.Mode, i.SessionPolicy}
}

type Focus struct {
	Context string `json:"context"`
	Epoch   uint64 `json:"epoch"`
}
type Action struct {
	Kind        string `json:"kind"`
	Code        string `json:"code,omitempty"`
	CandidateID string `json:"candidateId,omitempty"`
	Revision    uint64 `json:"revision"`
	Delta       int    `json:"delta,omitempty"`
}
type Request struct {
	Version   int            `json:"version"`
	Sequence  uint64         `json:"sequence"`
	Operation string         `json:"operation"`
	Product   string         `json:"product"`
	SessionID string         `json:"sessionId,omitempty"`
	Focus     Focus          `json:"focus"`
	Identity  *Identity      `json:"identity,omitempty"`
	Action    *Action        `json:"action,omitempty"`
	CommitID  string         `json:"commitId,omitempty"`
	Outcome   bridge.Outcome `json:"outcome,omitempty"`
}
type Commit struct {
	ID    string `json:"id"`
	Text  string `json:"text"`
	Focus Focus  `json:"focus"`
}
type Receipt struct {
	ID      string         `json:"id"`
	Outcome bridge.Outcome `json:"outcome"`
}
type Response struct {
	Version   int                   `json:"version"`
	Sequence  uint64                `json:"sequence"`
	OK        bool                  `json:"ok"`
	Error     string                `json:"error,omitempty"`
	SessionID string                `json:"sessionId,omitempty"`
	Identity  *Identity             `json:"identity,omitempty"`
	Focus     *Focus                `json:"focus,omitempty"`
	Snapshot  *keyboardlab.Response `json:"snapshot,omitempty"`
	Commit    *Commit               `json:"commit,omitempty"`
	Receipt   *Receipt              `json:"receipt,omitempty"`
}
type Service struct {
	open     func(bridge.Focus) (*bridge.Session, error)
	expected Identity
}

// NewProduction checks the independent product descriptor and every session's
// actually loaded dictionary against source-pinned identity. No standard index
// fallback or persistent learning path is exposed.
func NewProduction(root, data string) (*Service, error) {
	if !filepath.IsAbs(root) || !filepath.IsAbs(data) {
		return nil, errors.New("absolute dedicated root and data directory required")
	}
	raw, e := os.ReadFile(filepath.Join(root, "tools/yimecore/18u-touch-product.json"))
	if e != nil {
		return nil, e
	}
	var product struct {
		Schema   string `json:"schema_version"`
		Identity struct {
			Key     string `json:"product_key"`
			CLSID   string `json:"clsid"`
			Profile string `json:"profile"`
		} `json:"identity"`
		Scope struct {
			Architecture string `json:"architecture"`
			Language     string `json:"language"`
			Mode         string `json:"mode"`
			Learning     bool   `json:"persistent_learning"`
		} `json:"scope"`
		Data struct {
			Layout     string `json:"layout_sha256"`
			Dictionary string `json:"dictionary_sha256"`
			Fallback   bool   `json:"standard_index_fallback"`
		} `json:"data"`
	}
	if json.Unmarshal(raw, &product) != nil || product.Schema != "yimecore-18u-touch-product-v1" || product.Identity.Key != Product || product.Identity.CLSID != "{6DFACE1F-562E-4773-A9D6-D5753A314711}" || product.Identity.Profile != "{1BD904AC-3194-4419-B70A-5574100F18B3}" || product.Data.Layout != LayoutSHA || product.Data.Dictionary != DictionarySHA || product.Data.Fallback || product.Scope.Architecture != "x64" || product.Scope.Language != "CN" || product.Scope.Mode != "variable" || product.Scope.Learning {
		return nil, errors.New("dedicated product identity mismatch")
	}
	return &Service{open: func(f bridge.Focus) (*bridge.Session, error) { return bridge.Open(root, data, "variable", f) }, expected: Identity{LayoutSHA, DictionarySHA, "variable", keyboardlab.SessionPolicy}}, nil
}

type connection struct {
	service         *Service
	owner           yimebroker.TrustedClient
	seq             uint64
	session         *bridge.Session
	focus           Focus
	id              string
	opened, stopped bool
}

func (s *Service) newConnection(owner yimebroker.TrustedClient) (*connection, error) {
	if owner.ID == "" {
		return nil, errors.New("authenticated transport owner required")
	}
	// Always mint a fresh connection binding; no request contains this value.
	var b [16]byte
	if _, e := rand.Read(b[:]); e != nil {
		return nil, e
	}
	owner.ConnectionID = fmt.Sprintf("18u-%x", b)
	return &connection{service: s, owner: owner}, nil
}
func (c *connection) close() {
	if c.session != nil {
		c.session.Invalidate()
		_ = c.session.Close()
	}
	c.stopped = true
}
func (c *connection) dispatch(owner yimebroker.TrustedClient, q Request) Response {
	r := Response{Version: 2, Sequence: q.Sequence}
	reject := func(reason string) Response { r.Error = reason; return r }
	if owner != c.owner {
		return reject("connection owner mismatch")
	}
	if q.Version != 2 || q.Product != Product || q.Sequence != c.seq+1 {
		return reject("protocol/product/sequence mismatch")
	}
	c.seq = q.Sequence
	if q.Focus.Context == "" || len(q.Focus.Context) > 256 || q.Focus.Epoch == 0 {
		return reject("invalid TIP focus lease")
	}
	if q.Operation == "open" {
		if c.opened || c.stopped || q.SessionID != "" || q.Identity != nil || q.Action != nil || q.CommitID != "" || q.Outcome != "" {
			return reject("invalid open")
		}
		s, e := c.service.open(bridge.Focus{Context: q.Focus.Context, Epoch: q.Focus.Epoch})
		if e != nil {
			return reject("dedicated runtime unavailable")
		}
		if identity(s.Identity()) != c.service.expected {
			_ = s.Close()
			return reject("loaded resource identity mismatch")
		}
		c.session = s
		c.focus = q.Focus
		c.id = s.Snapshot().SessionID
		c.opened = true
	} else {
		if !c.opened || q.SessionID != c.id || q.Identity == nil || *q.Identity != c.service.expected || q.Focus != c.focus {
			return reject("session identity or lease mismatch")
		}
		if c.stopped && q.Operation != "close" {
			return reject("session stopped; no replay")
		}
		switch q.Operation {
		case "action":
			if q.Action == nil || q.CommitID != "" || q.Outcome != "" {
				return reject("invalid action")
			}
			a := q.Action
			ticket, e := c.session.Dispatch(c.session.Identity(), bridge.Focus{Context: c.focus.Context, Epoch: c.focus.Epoch}, bridge.Action{SessionID: q.SessionID, Revision: a.Revision, Kind: a.Kind, Code: a.Code, CandidateID: a.CandidateID, Delta: a.Delta})
			if e != nil {
				return reject("action rejected")
			}
			if ticket != nil {
				r.Commit = &Commit{ticket.ID, ticket.Text, c.focus}
			}
		case "complete":
			if q.Action != nil || q.CommitID == "" {
				return reject("invalid completion")
			}
			if e := c.session.Complete(q.CommitID, q.Outcome); e != nil {
				return reject("completion rejected")
			}
			if q.Outcome != bridge.Applied {
				c.stopped = true
			}
		case "invalidate", "close":
			if q.Action != nil || q.CommitID != "" || q.Outcome != "" {
				return reject("invalid termination")
			}
			c.close()
		default:
			return reject("unsupported dedicated operation")
		}
	}
	st := c.session.Snapshot()
	id := c.service.expected
	f := c.focus
	receipt := c.session.Receipt()
	r.OK = true
	r.SessionID = c.id
	r.Identity = &id
	r.Focus = &f
	r.Snapshot = &st
	if receipt.ID != "" {
		r.Receipt = &Receipt{receipt.ID, receipt.Outcome}
	}
	return r
}

// ServeConnection must be called only by the OS-authenticated transport. It
// rejects client-claimed identity fields and closes any pending commit Unknown
// on EOF, malformed frame, write failure or cancellation. No text is logged.
func (s *Service) ServeConnection(ctx context.Context, in io.Reader, out io.Writer, owner yimebroker.TrustedClient) error {
	c, e := s.newConnection(owner)
	if e != nil {
		return e
	}
	defer c.close()
	scanner := bufio.NewScanner(in)
	scanner.Buffer(make([]byte, 4096), MaxFrame+1)
	for scanner.Scan() {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		b := scanner.Bytes()
		if len(b) > MaxFrame {
			return errors.New("dedicated frame limit")
		}
		var q Request
		d := json.NewDecoder(bytes.NewReader(b))
		d.DisallowUnknownFields()
		if e = d.Decode(&q); e != nil {
			return errors.New("invalid dedicated request")
		}
		var extra any
		if d.Decode(&extra) != io.EOF {
			return errors.New("trailing dedicated data")
		}
		r := c.dispatch(c.owner, q)
		raw, e := json.Marshal(r)
		if e != nil || len(raw) > MaxFrame {
			return errors.New("dedicated response limit")
		}
		frame := append(raw, '\n')
		n, e := out.Write(frame)
		if e != nil {
			return e
		}
		if n != len(frame) {
			return io.ErrShortWrite
		}
		if q.Operation == "close" && r.OK {
			return nil
		}
	}
	return scanner.Err()
}
