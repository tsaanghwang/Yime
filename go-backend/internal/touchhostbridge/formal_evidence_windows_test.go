//go:build windows && amd64

package touchhostbridge

import (
	"bytes"
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"testing"
)

// One authoritative scenario list for both direct-load and registered gates.
var formalScenarios = []string{
	"commit", "duplicate", "wrong-server-pid", "wrong-server-image",
	"deactivated", "focus-lost", "disconnect-before-action",
	"pending-focus-away-back", "pending-deactivated", "disconnect-after-edit",
}

type formalResult struct {
	Stage                          string `json:"stage"`
	Scenario                       string `json:"scenario"`
	ActualDLLLoaded                bool   `json:"actualDLLLoaded"`
	ActivationIdentity             string `json:"activationIdentity"`
	Registered                     bool   `json:"registered"`
	SendInput                      bool   `json:"sendInput"`
	Outcome                        string `json:"outcome"`
	Rejected                       bool   `json:"rejected"`
	DuplicateRejected              bool   `json:"duplicateRejected"`
	ReadbackMatches                bool   `json:"readbackMatches"`
	ReadbackEmpty                  bool   `json:"readbackEmpty"`
	OtherContextEmpty              bool   `json:"otherContextEmpty"`
	UnknownAfterPendingEditCovered bool   `json:"unknownAfterPendingEditCovered"`
	OperationPendingObserved       bool   `json:"operationPendingObserved"`
	PostWriteDisconnectObserved    bool   `json:"postWriteDisconnectObserved"`
	ReplayRejected                 bool   `json:"replayRejected"`
}

// Missing false-valued fields, nulls and duplicate keys are not evidence.
// Tokenize the flat envelope before typed decoding; do not log payloads.
func decodeFormalEnvelope(raw []byte, value any) error {
	typ := reflect.TypeOf(value).Elem()
	fields := make(map[string]bool, typ.NumField())
	for i := 0; i < typ.NumField(); i++ {
		fields[typ.Field(i).Tag.Get("json")] = true
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	start, err := d.Token()
	if err != nil || start != json.Delim('{') {
		return errors.New("invalid formal evidence envelope")
	}
	seen := make(map[string]bool)
	for d.More() {
		key, err := d.Token()
		name, ok := key.(string)
		if err != nil || !ok || seen[name] || !fields[name] {
			return errors.New("duplicate or invalid formal evidence field")
		}
		seen[name] = true
		var field json.RawMessage
		if d.Decode(&field) != nil || bytes.Equal(bytes.TrimSpace(field), []byte("null")) {
			return errors.New("null or invalid formal evidence field")
		}
	}
	if _, err = d.Token(); err != nil || len(seen) != len(fields) {
		return errors.New("incomplete formal evidence")
	}
	// Unmarshal verifies EOF; DisallowUnknownFields then verifies field names.
	if !json.Valid(raw) {
		return errors.New("trailing or malformed formal evidence")
	}
	d = json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if d.Decode(value) != nil {
		return errors.New("invalid formal evidence type or field")
	}
	return nil
}

func validateFormalPostWriteBarrier(raw []byte) error {
	var barrier struct {
		Stage            string `json:"stage"`
		ReadbackMatches  bool   `json:"readbackMatches"`
		OperationPending bool   `json:"operationPending"`
	}
	if err := decodeFormalEnvelope(raw, &barrier); err != nil {
		return err
	}
	if barrier.Stage != "edit-written" || !barrier.ReadbackMatches || !barrier.OperationPending {
		return errors.New("actual write before completion not proven")
	}
	return nil
}

func validateFormalResult(raw []byte, scenario string, registered bool) error {
	known := false
	for _, name := range formalScenarios {
		known = known || name == scenario
	}
	if !known {
		return errors.New("unknown formal scenario")
	}
	var r formalResult
	if err := decodeFormalEnvelope(raw, &r); err != nil {
		return err
	}
	activation := "owned-host-activation-client"
	if registered {
		activation = "windows-activated-profile"
	}
	unknown := scenario == "disconnect-after-edit"
	pending := unknown || scenario == "pending-focus-away-back" || scenario == "pending-deactivated"
	if r.Stage != "result" || r.Scenario != scenario || !r.ActualDLLLoaded ||
		r.ActivationIdentity != activation || r.Registered != registered ||
		r.SendInput || !r.OtherContextEmpty ||
		r.UnknownAfterPendingEditCovered != unknown ||
		r.OperationPendingObserved != pending || r.PostWriteDisconnectObserved != unknown ||
		r.ReplayRejected != unknown || r.DuplicateRejected != (scenario == "duplicate") {
		return errors.New("formal scope, identity or execution evidence mismatch")
	}
	if scenario == "commit" || scenario == "duplicate" || unknown {
		want := "applied"
		if unknown {
			want = "unknown"
		}
		if r.Outcome != want || !r.ReadbackMatches || r.Rejected || r.ReadbackEmpty {
			return errors.New("formal actual write or terminal outcome not proven")
		}
	} else if !r.Rejected || !r.ReadbackEmpty || r.ReadbackMatches || r.Outcome != "not-applied" {
		return errors.New("formal negative case wrote or was accepted")
	}
	return nil
}

func validFormalFixture(scenario string, registered bool) formalResult {
	r := formalResult{Stage: "result", Scenario: scenario, ActualDLLLoaded: true,
		ActivationIdentity: "owned-host-activation-client", Registered: registered,
		OtherContextEmpty: true, Outcome: "not-applied", Rejected: true, ReadbackEmpty: true}
	if registered {
		r.ActivationIdentity = "windows-activated-profile"
	}
	switch scenario {
	case "commit", "duplicate", "disconnect-after-edit":
		r.Outcome, r.Rejected, r.ReadbackEmpty, r.ReadbackMatches = "applied", false, false, true
		r.DuplicateRejected = scenario == "duplicate"
		if scenario == "disconnect-after-edit" {
			r.Outcome = "unknown"
			r.UnknownAfterPendingEditCovered, r.OperationPendingObserved = true, true
			r.PostWriteDisconnectObserved, r.ReplayRejected = true, true
		}
	case "pending-focus-away-back", "pending-deactivated":
		r.OperationPendingObserved = true
	}
	return r
}

func TestFormalResultEvidence(t *testing.T) {
	for _, registered := range []bool{false, true} {
		for _, scenario := range formalScenarios {
			r := validFormalFixture(scenario, registered)
			raw, err := json.Marshal(r)
			if err != nil || validateFormalResult(raw, scenario, registered) != nil {
				t.Fatal("valid fixed evidence rejected", scenario, registered)
			}
			if validateFormalResult(raw, scenario, !registered) == nil {
				t.Fatal("direct/registered evidence conflated", scenario)
			}
			var fields map[string]json.RawMessage
			_ = json.Unmarshal(raw, &fields)
			for key, original := range fields {
				delete(fields, key)
				missing, _ := json.Marshal(fields)
				if validateFormalResult(missing, scenario, registered) == nil {
					t.Fatal("missing field accepted", key)
				}
				fields[key] = json.RawMessage("null")
				null, _ := json.Marshal(fields)
				if validateFormalResult(null, scenario, registered) == nil {
					t.Fatal("null field accepted", key)
				}
				fields[key] = original
				wrongCase := bytes.Replace(raw, mustJSON(key), mustJSON(strings.ToUpper(key)), 1)
				if validateFormalResult(wrongCase, scenario, registered) == nil {
					t.Fatal("wrong-case field accepted", key)
				}
				duplicate := append(append([]byte{}, raw[:len(raw)-1]...), []byte(","+string(mustJSON(key))+":"+string(original)+"}")...)
				if validateFormalResult(duplicate, scenario, registered) == nil {
					t.Fatal("duplicate field accepted", key)
				}
				if bytes.Equal(original, []byte("true")) || bytes.Equal(original, []byte("false")) {
					fields[key] = json.RawMessage("true")
					if bytes.Equal(original, []byte("true")) {
						fields[key] = json.RawMessage("false")
					}
					flipped, _ := json.Marshal(fields)
					if validateFormalResult(flipped, scenario, registered) == nil {
						t.Fatal("contradictory boolean accepted", key, scenario)
					}
					fields[key] = original
				}
			}
			for _, corrupt := range [][]byte{
				append(append([]byte{}, raw...), []byte(" {}")...),
				append(append([]byte{}, raw[:len(raw)-1]...), []byte(",\"private\":\"do-not-log\"}")...),
				bytes.Replace(raw, []byte("\"result\""), []byte("\"private-value\""), 1),
			} {
				if validateFormalResult(corrupt, scenario, registered) == nil {
					t.Fatal("malformed evidence accepted")
				}
			}
		}
	}
	if validateFormalResult(mustJSON(validFormalFixture("commit", false)), "unknown", false) == nil {
		t.Fatal("unrecognized scenario accepted")
	}
	r := validFormalFixture("disconnect-after-edit", false)
	r.Outcome = "applied"
	if validateFormalResult(mustJSON(r), r.Scenario, false) == nil {
		t.Fatal("lost completion counted as applied")
	}
}
func mustJSON(value any) []byte {
	raw, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return raw
}
func TestFormalPostWriteBarrierEvidence(t *testing.T) {
	good := []byte(`{"stage":"edit-written","readbackMatches":true,"operationPending":true}`)
	if validateFormalPostWriteBarrier(good) != nil {
		t.Fatal("valid barrier rejected")
	}
	for _, raw := range []string{
		`{}`, `null`, `[]`,
		`{"stage":"edit-written","readbackMatches":true}`,
		`{"stage":"edit-written","readbackMatches":true,"operationPending":false}`,
		`{"stage":"edit-written","readbackMatches":false,"operationPending":true}`,
		`{"stage":"edit-written","readbackMatches":true,"operationPending":null}`,
		`{"stage":"edit-written","readbackMatches":true,"operationPending":true,"operationPending":true}`,
		string(good) + " trailing",
	} {
		if validateFormalPostWriteBarrier([]byte(raw)) == nil {
			t.Fatal("unproven barrier accepted")
		}
	}
}
