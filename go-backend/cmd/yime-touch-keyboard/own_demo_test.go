package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestOwnDemoReplyRequiresIdentityAndActualReadback(t *testing.T) {
	id := demoIdentity{"layout", "dictionary", "variable", "policy"}
	good := demoReply{Version: 2, Seq: 1, Op: "commit", Epoch: 2, Identity: id, Context: "own-demo-host", OK: true, Outcome: "applied", ReadbackMatch: true, TotalUTF16Units: 1, CallbackSeen: true, Active: true, ReadbackText: "你"}
	b, _ := json.Marshal(good)
	if _, e := decodeDemoReply(b, "commit", 1, 2, id); e != nil {
		t.Fatal(e)
	}
	for _, mutate := range []func(*demoReply){func(r *demoReply) { r.Identity.Dictionary = "foreign" }, func(r *demoReply) { r.Epoch++ }, func(r *demoReply) { r.CallbackSeen = false }, func(r *demoReply) { r.ReadbackMatch = false }, func(r *demoReply) { r.TotalUTF16Units = 0 }, func(r *demoReply) { r.Seq++ }, func(r *demoReply) { r.Context = "other" }} {
		r := good
		mutate(&r)
		b, _ = json.Marshal(r)
		if _, e := decodeDemoReply(b, "commit", 1, 2, id); e == nil {
			t.Fatal("accepted invalid reply")
		}
	}
	r := good
	r.OK = false
	r.Active = false
	r.Outcome = "failed"
	r.CallbackSeen = false
	b, _ = json.Marshal(r)
	if _, e := decodeDemoReply(b, "commit", 1, 2, id); e != nil {
		t.Fatal("known no-write rejection", e)
	}
	if _, e := decodeDemoReply([]byte(`{}`), "read", 1, 2, id); e == nil {
		t.Fatal("missing reply fields")
	}
}
func TestOwnDemoHostMustBeHashBound(t *testing.T) {
	root, digest := portableFixture(t)
	if _, e := demoHostPath(root, ""); e == nil {
		t.Fatal("unbound source accepted")
	}
	if _, e := demoHostPath(root, digest); e == nil {
		t.Fatal("host missing from inventory")
	}
	path := filepath.Join(root, "resources.json")
	b, _ := os.ReadFile(path)
	var inventory portableResources
	_ = json.Unmarshal(b, &inventory)
	host := []byte("explicit non-executable hash fixture")
	_ = os.WriteFile(filepath.Join(root, ownDemoHostName), host, 0600)
	sum := sha256.Sum256(host)
	inventory.Files[ownDemoHostName] = hex.EncodeToString(sum[:])
	b, _ = json.Marshal(inventory)
	_ = os.WriteFile(path, b, 0600)
	sum = sha256.Sum256(b)
	digest = hex.EncodeToString(sum[:])
	if p, e := demoHostPath(root, digest); e != nil || p != filepath.Join(root, ownDemoHostName) {
		t.Fatal(p, e)
	}
	_ = os.WriteFile(filepath.Join(root, ownDemoHostName), []byte("modified"), 0600)
	if _, e := demoHostPath(root, digest); e == nil {
		t.Fatal("modified host accepted")
	}
}
func TestOwnDemoPackageNeverFallsBack(t *testing.T) {
	old := ownTSFDemoPackage
	ownTSFDemoPackage = "1"
	defer func() { ownTSFDemoPackage = old }()
	for _, o := range []options{{}, {Host: true}, {Preview: true}, {EnglishOnly: true}, {OwnTSFDemoSmoke: true}, {OwnTSFDemo: true, Host: true}, {OwnTSFDemo: true, InputTrace: "x"}} {
		if e := execute(o); e == nil {
			t.Fatal("unsafe entry accepted", o)
		}
	}
	root, digest := portableFixture(t)
	o := options{OwnTSFDemo: true}
	if e := preparePortable(&o, root, digest); e != nil {
		t.Fatal(e)
	}
	if o.Host || o.DataDir != filepath.Join(root, "data") {
		t.Fatal("demo fell back to legacy host", o)
	}
	// Static modes can fail validation, but must not reach run/SendInput.
	for _, o := range []options{{CheckData: true, Host: true}, {CheckPackage: true, Host: true}} {
		e := execute(o)
		if e == nil || strings.Contains(e.Error(), "only supported on Windows") {
			t.Fatal("static mode reached execution", e)
		}
	}
}
