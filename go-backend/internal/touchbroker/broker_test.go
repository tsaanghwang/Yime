package touchbroker

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	codemode "github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	bridge "github.com/tsaanghwang/Yime/go-backend/internal/touchhostbridge"
	"io"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func fixture(t *testing.T) (string, string) {
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

// Only tests inject tiny fixture identities. The command calls NewProduction.
func testConnection(t *testing.T) *connection {
	root, data := fixture(t)
	open := func(f bridge.Focus) (*bridge.Session, error) { return bridge.Open(root, data, "variable", f) }
	sample, e := open(bridge.Focus{Context: "probe", Epoch: 1})
	if e != nil {
		t.Fatal(e)
	}
	want := identity(sample.Identity())
	_ = sample.Close()
	service := &Service{open: open, expected: want}
	c, e := service.newConnection(yimebroker.TrustedClient{ID: "explicit-unit-owner"})
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(c.close)
	r := c.dispatch(c.owner, Request{Version: 2, Sequence: 1, Operation: "open", Product: Product, Focus: Focus{Context: "real-tip-lease-placeholder", Epoch: 1}})
	if !r.OK {
		t.Fatal(r)
	}
	return c
}
func request(c *connection, op string) Request {
	id := c.service.expected
	return Request{Version: 2, Sequence: c.seq + 1, Operation: op, Product: Product, SessionID: c.id, Identity: &id, Focus: c.focus}
}
func action(t *testing.T, c *connection, kind string) Response {
	t.Helper()
	q := request(c, "action")
	q.Action = &Action{Kind: kind, Code: "a", Revision: c.session.Snapshot().Revision}
	if kind == "select" {
		q.Action.Code = ""
		q.Action.CandidateID = c.session.Snapshot().State.Candidates[0].ID
	}
	r := c.dispatch(c.owner, q)
	if !r.OK {
		t.Fatal(r)
	}
	return r
}
func TestTIPConnectionCommitRequiresActualOwnerReceipt(t *testing.T) {
	c := testConnection(t)
	action(t, c, "input")
	r := action(t, c, "select")
	if r.Commit == nil || r.Receipt == nil || r.Receipt.Outcome != bridge.Pending {
		t.Fatal("engine output not pending", r)
	}
	q := request(c, "action")
	q.Action = &Action{Kind: "input", Code: "a", Revision: c.session.Snapshot().Revision}
	if c.dispatch(c.owner, q).OK {
		t.Fatal("pending allowed another action")
	}
	q = request(c, "complete")
	q.CommitID = r.Commit.ID
	q.Outcome = bridge.Applied
	forged := c.owner
	forged.ConnectionID = "another-connection"
	if c.dispatch(forged, q).OK || c.session.Receipt().Outcome != bridge.Pending {
		t.Fatal("foreign connection forged Applied")
	}
	if got := c.dispatch(c.owner, q); !got.OK || got.Receipt.Outcome != bridge.Applied {
		t.Fatal(got)
	}
	q.Sequence = c.seq + 1
	if c.dispatch(c.owner, q).OK {
		t.Fatal("duplicate receipt accepted")
	}
}
func TestTIPRejectsForeignSessionIdentityFocusSequenceAndRevision(t *testing.T) {
	c := testConnection(t)
	action(t, c, "input")
	for _, mutate := range []func(*Request){func(q *Request) { q.SessionID = "foreign" }, func(q *Request) { q.Identity.Dictionary = "foreign" }, func(q *Request) { q.Focus.Epoch++ }, func(q *Request) { q.Sequence-- }, func(q *Request) { q.Action.Revision++ }} {
		q := request(c, "action")
		q.Action = &Action{Kind: "clear", Revision: c.session.Snapshot().Revision}
		mutate(&q)
		if c.dispatch(c.owner, q).OK {
			t.Fatal("invalid request accepted")
		}
		if c.session.Snapshot().State.RawInput != "a" {
			t.Fatal("invalid request mutated engine")
		}
	}
	other := testConnection(t)
	q := request(other, "action")
	q.SessionID = c.id
	q.Action = &Action{Kind: "clear", Revision: c.session.Snapshot().Revision}
	if other.dispatch(other.owner, q).OK {
		t.Fatal("session ID granted cross-connection access")
	}
	q = request(c, "action")
	q.Action = &Action{Kind: "setModes", Revision: c.session.Snapshot().Revision}
	if c.dispatch(c.owner, q).OK {
		t.Fatal("standard/mode route exposed")
	}
}
func TestTIPDisconnectPendingUnknownNoReplay(t *testing.T) {
	c := testConnection(t)
	action(t, c, "input")
	r := action(t, c, "select")
	c.close()
	if c.session.Receipt().Outcome != bridge.Unknown {
		t.Fatal("disconnect became success")
	}
	q := request(c, "complete")
	q.CommitID = r.Commit.ID
	q.Outcome = bridge.Applied
	if c.dispatch(c.owner, q).OK {
		t.Fatal("late completion resumed disconnected session")
	}
}
func TestTIPResourceMismatchAndStrictWire(t *testing.T) {
	c := testConnection(t)
	c.service.expected.Dictionary = "wrong"
	other, e := c.service.newConnection(c.owner)
	if e != nil {
		t.Fatal(e)
	}
	defer other.close()
	if other.dispatch(other.owner, Request{Version: 2, Sequence: 1, Operation: "open", Product: Product, Focus: Focus{"new", 2}}).OK {
		t.Fatal("self-claimed resource accepted")
	}
	var out bytes.Buffer
	if e = c.service.ServeConnection(context.Background(), bytes.NewBufferString(`{"version":2,"owner":"forged"}`), &out, c.owner); e == nil {
		t.Fatal("JSON owner accepted")
	}
	if _, e = NewProduction(t.TempDir(), t.TempDir()); e == nil {
		t.Fatal("missing product descriptor accepted")
	}
}

// Full shipped resource validation, not native-host evidence: the final receipt
// here is an explicit simulated trusted TIP completion for protocol testing.
func TestFullResourceDedicatedBroker(t *testing.T) {
	data := os.Getenv("YIME_18U_FULL_DATA")
	if data == "" {
		t.Skip("explicit full dedicated data not configured")
	}
	root, e := filepath.Abs("../../..")
	if e != nil {
		t.Fatal(e)
	}
	service, e := NewProduction(root, data)
	if e != nil {
		t.Fatal(e)
	}
	c, e := service.newConnection(yimebroker.TrustedClient{ID: "explicit-full-resource-unit-TIP"})
	if e != nil {
		t.Fatal(e)
	}
	defer c.close()
	r := c.dispatch(c.owner, Request{Version: 2, Sequence: 1, Product: Product, Operation: "open", Focus: Focus{"full-resource-test-lease", 1}})
	if !r.OK || r.Identity == nil || r.Identity.Dictionary != DictionarySHA || r.Identity.Layout != LayoutSHA {
		t.Fatal(r)
	}
	var layout struct {
		Keys map[string]string `json:"yinyuan_id_to_key"`
	}
	raw, e := os.ReadFile(filepath.Join(root, "prototypes/touch-terminal/encoding/yime_yinyuan_layout.json"))
	if e != nil {
		t.Fatal(e)
	}
	if e = json.Unmarshal(raw, &layout); e != nil {
		t.Fatal(e)
	}
	f, e := os.Open(filepath.Join(root, "internal_data/yime_syllable_decomposition.tsv"))
	if e != nil {
		t.Fatal(e)
	}
	defer f.Close()
	reader := csv.NewReader(f)
	reader.Comma = '\t'
	header, e := reader.Read()
	if e != nil {
		t.Fatal(e)
	}
	columns := map[string]int{}
	for i, k := range header {
		columns[k] = i
	}
	code := ""
	for {
		row, e := reader.Read()
		if e == io.EOF {
			break
		}
		if e != nil {
			t.Fatal(e)
		}
		if row[columns["pinyin_tone"]] != "ni3" {
			continue
		}
		if row[columns["status"]] != "ok" {
			t.Fatal("canonical ni3 unavailable")
		}
		full := ""
		for _, k := range []string{"shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
			part := layout.Keys[row[columns[k]]]
			if len(part) != 1 {
				t.Fatal("projection missing")
			}
			full += part
		}
		record, e := codemode.BuildRecord(full)
		if e != nil {
			t.Fatal(e)
		}
		code = record.Variable
		break
	}
	if code == "" {
		t.Fatal("canonical probe not found")
	}
	for _, key := range code {
		q := request(c, "action")
		q.Action = &Action{Kind: "input", Code: string(key), Revision: c.session.Snapshot().Revision}
		if r = c.dispatch(c.owner, q); !r.OK {
			t.Fatal(r)
		}
	}
	candidate := ""
	for _, v := range c.session.Snapshot().State.Candidates {
		if v.Text == "你" {
			candidate = v.ID
			break
		}
	}
	if candidate == "" {
		t.Fatal("ni3 candidate missing from actual dedicated resource")
	}
	q := request(c, "action")
	q.Action = &Action{Kind: "select", CandidateID: candidate, Revision: c.session.Snapshot().Revision}
	r = c.dispatch(c.owner, q)
	if !r.OK || r.Commit == nil || r.Commit.Text != "你" || r.Receipt.Outcome != bridge.Pending {
		t.Fatal("full resource did not prepare unique pending commit")
	}
	q = request(c, "complete")
	q.CommitID = r.Commit.ID
	q.Outcome = bridge.Applied
	r = c.dispatch(c.owner, q)
	if !r.OK || r.Receipt.Outcome != bridge.Applied {
		t.Fatal("simulated owner completion rejected")
	}
}

func TestTIPWireEOFTerminatesPendingAsUnknown(t *testing.T) {
	fixtureConn := testConnection(t)
	service := *fixtureConn.service
	open := service.open
	var loaded *bridge.Session
	service.open = func(f bridge.Focus) (*bridge.Session, error) { s, e := open(f); loaded = s; return s, e }
	server, client := net.Pipe()
	defer client.Close()
	done := make(chan error, 1)
	go func() {
		defer server.Close()
		done <- service.ServeConnection(context.Background(), server, server, yimebroker.TrustedClient{ID: "explicit-wire-unit-owner"})
	}()
	reader := bufio.NewReader(client)
	exchange := func(q Request) Response {
		t.Helper()
		b, _ := json.Marshal(q)
		if _, e := client.Write(append(b, '\n')); e != nil {
			t.Fatal(e)
		}
		b, e := reader.ReadBytes('\n')
		if e != nil {
			t.Fatal(e)
		}
		var r Response
		if e = json.Unmarshal(b, &r); e != nil || !r.OK {
			t.Fatal(e, r)
		}
		return r
	}
	focus := Focus{"wire-lease", 1}
	r := exchange(Request{Version: 2, Sequence: 1, Operation: "open", Product: Product, Focus: focus})
	q := Request{Version: 2, Sequence: 2, Operation: "action", Product: Product, Focus: focus, SessionID: r.SessionID, Identity: r.Identity, Action: &Action{Kind: "input", Code: "a", Revision: r.Snapshot.Revision}}
	r = exchange(q)
	q.Sequence++
	q.Action = &Action{Kind: "select", Revision: r.Snapshot.Revision, CandidateID: r.Snapshot.State.Candidates[0].ID}
	r = exchange(q)
	if r.Receipt == nil || r.Receipt.Outcome != bridge.Pending {
		t.Fatal("wire commit not pending")
	}
	_ = client.Close()
	select {
	case e := <-done:
		if e != nil {
			t.Fatal(e)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("EOF did not close session")
	}
	if loaded == nil || loaded.Receipt().Outcome != bridge.Unknown {
		t.Fatal("EOF did not preserve Unknown")
	}
}
