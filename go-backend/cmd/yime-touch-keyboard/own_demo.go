package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	bridge "github.com/tsaanghwang/Yime/go-backend/internal/touchhostbridge"
	"io"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"
	"time"
	"unicode/utf16"
)

const ownDemoHostName = "YimeTouchBridgeDemoHost.exe"

type demoIdentity struct {
	Layout     string `json:"layoutSHA256"`
	Dictionary string `json:"dictionarySHA256"`
	Mode       string `json:"mode"`
	Policy     string `json:"sessionPolicy"`
}

func demoID(i bridge.Identity) demoIdentity {
	return demoIdentity{i.LayoutSHA256, i.DictionarySHA256, i.Mode, i.SessionPolicy}
}

type demoReply struct {
	Version         int          `json:"version"`
	Seq             uint64       `json:"seq"`
	Op              string       `json:"op"`
	Epoch           uint64       `json:"epoch"`
	Identity        demoIdentity `json:"identity"`
	Context         string       `json:"context"`
	OK              bool         `json:"ok"`
	Outcome         string       `json:"outcome"`
	ReadbackMatch   bool         `json:"readbackMatch"`
	TotalUTF16Units int          `json:"totalUTF16Units"`
	CallbackSeen    bool         `json:"callbackSeen"`
	Active          bool         `json:"active"`
	ReadbackText    string       `json:"readbackText"`
}

// Only the package-pinned child is launched. This is an isolated development
// demo, not a registered IME or a transport accepting arbitrary commands/HWNDs.
type demoClient struct {
	cmd        *exec.Cmd
	cancel     context.CancelFunc
	in         io.WriteCloser
	out        *bufio.Scanner
	identity   demoIdentity
	seq, epoch uint64
	closed     bool
	last       demoReply
}
type demoDiscardLog struct {
	mu sync.Mutex
	n  int
}

func (b *demoDiscardLog) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.n += len(p)
	if b.n > 16384 {
		return 0, fmt.Errorf("demo stderr bound exceeded")
	}
	return len(p), nil
}
func demoHostPath(root, expected string) (string, error) {
	if expected == "" {
		return "", fmt.Errorf("own TSF demo requires a hash-bound complete portable build")
	}
	r, e := verifyPortableResources(root, expected)
	if e != nil {
		return "", e
	}
	if len(r.Files[ownDemoHostName]) != 64 {
		return "", fmt.Errorf("own TSF demo host absent from bound resource inventory")
	}
	return filepath.Join(root, ownDemoHostName), nil
}
func startDemoClient(root string, identity bridge.Identity, selfTest bool) (*demoClient, error) {
	if runtime.GOOS != "windows" || runtime.GOARCH != "amd64" {
		return nil, fmt.Errorf("own TSF demo is Windows native x64 only")
	}
	path, e := demoHostPath(root, portableResourcesSHA256)
	if e != nil {
		return nil, e
	}
	ctx, cancel := context.WithCancel(context.Background())
	cmd := exec.CommandContext(ctx, path, demoHostArgs(selfTest)...)
	cmd.Dir = root
	cmd.Stderr = &demoDiscardLog{}
	in, e := cmd.StdinPipe()
	if e != nil {
		cancel()
		return nil, e
	}
	out, e := cmd.StdoutPipe()
	if e != nil {
		cancel()
		return nil, e
	}
	if e = cmd.Start(); e != nil {
		cancel()
		return nil, e
	}
	s := bufio.NewScanner(out)
	s.Buffer(make([]byte, 1024), 16384)
	c := &demoClient{cmd: cmd, cancel: cancel, in: in, out: s, identity: demoID(identity)}
	if _, e = c.call("init", nil); e != nil {
		return nil, e
	}
	return c, nil
}
func (c *demoClient) stop() {
	if !c.closed {
		c.cancel()
		_ = c.in.Close()
		_ = c.cmd.Wait()
		c.closed = true
	}
}
func (c *demoClient) call(op string, ticket *bridge.Commit) (r demoReply, err error) {
	if c.closed {
		return r, fmt.Errorf("own host disconnected; no automatic restart")
	}
	timer := time.AfterFunc(5*time.Second, c.cancel)
	defer timer.Stop()
	defer func() {
		if err != nil {
			c.stop()
		}
	}()
	c.seq++
	q := map[string]any{"version": 2, "seq": c.seq, "op": op, "epoch": c.epoch, "identity": c.identity}
	if ticket != nil {
		if ticket.Focus.Context != "own-demo-host" || ticket.Focus.Epoch != c.epoch || demoID(ticket.Identity) != c.identity {
			return r, fmt.Errorf("foreign commit identity")
		}
		q["id"] = ticket.ID
		q["text"] = ticket.Text
	}
	b, e := json.Marshal(q)
	if e != nil || len(b) > 16382 {
		return r, fmt.Errorf("request exceeds bound")
	}
	if _, e = c.in.Write(append(b, '\n')); e != nil {
		return r, fmt.Errorf("host write failed; outcome unknown")
	}
	if !c.out.Scan() {
		return r, fmt.Errorf("host disconnected or timed out; outcome unknown")
	}
	r, e = decodeDemoReply(c.out.Bytes(), op, c.seq, c.epoch, c.identity)
	if e != nil {
		return r, e
	}
	c.epoch = r.Epoch
	c.last = r
	return r, nil
}
func decodeDemoReply(b []byte, op string, seq, epoch uint64, id demoIdentity) (r demoReply, err error) {
	var fields map[string]json.RawMessage
	if json.Unmarshal(b, &fields) != nil || len(fields) != 13 {
		return r, fmt.Errorf("incomplete host response")
	}
	d := json.NewDecoder(bytes.NewReader(b))
	d.DisallowUnknownFields()
	if e := d.Decode(&r); e != nil {
		return r, fmt.Errorf("invalid host response")
	}
	var tail any
	if d.Decode(&tail) != io.EOF {
		return r, fmt.Errorf("trailing host response")
	}
	wantEpoch := epoch
	if op == "init" {
		wantEpoch = 1
	}
	if op == "rebind" {
		wantEpoch++
	}
	if r.Version != 2 || r.Seq != seq || r.Op != op || r.Epoch != wantEpoch || r.Context != "own-demo-host" || r.Identity != id || !r.ReadbackMatch || r.TotalUTF16Units != len(utf16.Encode([]rune(r.ReadbackText))) || r.TotalUTF16Units > 1024 {
		return r, fmt.Errorf("host response identity/readback mismatch")
	}
	if op == "commit" {
		if r.OK {
			if r.Outcome != "applied" || !r.CallbackSeen {
				return r, fmt.Errorf("unconfirmed host edit")
			}
		} else if r.Outcome != "failed" || r.Active {
			return r, fmt.Errorf("unknown host edit outcome")
		}
	} else if !r.OK || r.Outcome != "" || r.CallbackSeen {
		return r, fmt.Errorf("invalid host acknowledgement")
	}
	if (op == "init" || op == "invalidate" || op == "close" || op == "test-focus-away") && r.Active {
		return r, fmt.Errorf("host unexpectedly active")
	}
	if op == "rebind" && !r.Active {
		return r, fmt.Errorf("host did not acquire focus")
	}
	return r, nil
}
func (c *demoClient) submit(ticket bridge.Commit) (bridge.Outcome, error) {
	r, e := c.call("commit", &ticket)
	if e != nil {
		return bridge.Unknown, e
	}
	if !r.OK {
		return bridge.Failed, nil
	}
	return bridge.Applied, nil
}
func (c *demoClient) close() error {
	if c.closed {
		return nil
	}
	if _, e := c.call("close", nil); e != nil {
		return e
	}
	timer := time.AfterFunc(5*time.Second, c.cancel)
	defer timer.Stop()
	defer c.cancel()
	_ = c.in.Close()
	if c.out.Scan() || c.out.Err() != nil {
		c.stop()
		return fmt.Errorf("unexpected output while closing host")
	}
	e := c.cmd.Wait()
	c.closed = true
	if e != nil {
		return fmt.Errorf("own host did not exit normally")
	}
	return nil
}

// The only optional child argument is selected by the explicit CI self-test
// flag. Neither an arbitrary command line nor a target HWND is accepted.
func demoHostArgs(selfTest bool) []string {
	if selfTest {
		return []string{"--self-test"}
	}
	return nil
}
