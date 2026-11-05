//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchbroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

type ordinaryReplyCase struct {
	name, reason string
	mutate       func(map[string]any)
}

func ordinaryReplyCases() []ordinaryReplyCase {
	return []ordinaryReplyCase{
		{"pending", "operation-pending", func(v map[string]any) { v["pending"] = true }},
		{"success-with-diagnostic", "invalid-response", func(v map[string]any) { v["diagnostic"] = touchdiagnostic.New("tip-completion", "operation-failed") }},
		{"success-with-error", "invalid-response", func(v map[string]any) { v["error"] = "PRIVATE正文组码候选" }},
		{"snapshot-with-error", "snapshot-invalid", func(v map[string]any) {
			s := v["snapshot"].(keyboardlab.Response)
			s.Error = "PRIVATE正文组码候选"
			v["snapshot"] = s
		}},
		// A successful relay envelope with a failed inner completion is legitimate
		// delivery of a failure. Preserve that failure; never adopt its snapshot.
		{"relayed-failure", "operation-failed", func(v map[string]any) {
			v["ok"] = false
			v["diagnostic"] = touchdiagnostic.New("tip-completion", "operation-failed")
		}},
	}
}
func ordinaryReply(t *testing.T, layout, mode string, snapshot keyboardlab.Response, change func(map[string]any)) touchbroker.DesktopResponse {
	t.Helper()
	body := map[string]any{"ok": true, "identity": touchbroker.Identity{Layout: layout, Dictionary: touchbroker.DesktopDictionaryHashes[mode], Mode: mode, Policy: keyboardlab.SessionPolicy}, "snapshot": snapshot}
	if change != nil {
		change(body)
	}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	return touchbroker.DesktopResponse{OK: true, Lease: "lease", Result: raw}
}
func assertOrdinaryStopped(t *testing.T, p *preview, s *installedPreviewSessions, beforeP, beforeS keyboardlab.Response, reason string, err error) {
	t.Helper()
	if err == nil || !p.fault || p.candidatesEnabled() || p.lastDiagnostic == nil || p.lastDiagnostic.Reason != reason || strings.Contains(err.Error(), "PRIVATE") || !reflect.DeepEqual(p.snapshot, beforeP) || !reflect.DeepEqual(s.snapshot, beforeS) {
		t.Fatalf("contradictory reply advanced state or lost stop: %v", err)
	}
}
func TestInstalledOrdinaryBindRejectsContradictionBeforeAdoptingLease(t *testing.T) {
	for _, tc := range ordinaryReplyCases() {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			s := &installedPreviewSessions{layout: "layout"}
			s.call = func(q touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
				calls++
				if q.Operation != "bind" {
					t.Fatal("binding continued into another request")
				}
				snapshot := diagnosticSnapshot()
				snapshot.Revision = 0
				return ordinaryReply(t, s.layout, q.Mode, snapshot, tc.mutate), nil
			}
			p := &preview{sessions: s, layout: s.layout, installed: true}
			beforeP, beforeS := p.snapshot, s.snapshot
			err := p.switchMode("variable")
			assertOrdinaryStopped(t, p, s, beforeP, beforeS, tc.reason, err)
			if calls != 1 || s.lease != "" || s.mode != "" || p.mode != "" {
				t.Fatal("failed bind adopted identity/mode or dispatched")
			}
			if p.dispatch(keyboardlab.Event{Type: "input", Code: "PRIVATE"}) == nil || calls != 1 {
				t.Fatal("failed bind replayed")
			}
		})
	}
}
func TestInstalledOrdinaryActionRejectsContradictionBeforeAdvancing(t *testing.T) {
	for _, tc := range ordinaryReplyCases() {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			s := &installedPreviewSessions{layout: "layout", mode: "variable", lease: "lease", snapshot: diagnosticSnapshot()}
			s.call = func(q touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
				calls++
				if q.Operation != "action" {
					t.Fatal("unexpected request")
				}
				snapshot := s.snapshot
				snapshot.Revision++
				return ordinaryReply(t, s.layout, s.mode, snapshot, tc.mutate), nil
			}
			p := &preview{sessions: s, layout: s.layout, mode: s.mode, installed: true, snapshot: s.snapshot}
			beforeP, beforeS := p.snapshot, s.snapshot
			err := p.dispatch(keyboardlab.Event{Type: "input", Code: "PRIVATE"})
			assertOrdinaryStopped(t, p, s, beforeP, beforeS, tc.reason, err)
			if calls != 1 || s.lease != "lease" || s.mode != "variable" || p.mode != "variable" {
				t.Fatal("failure changed session identity")
			}
			if p.dispatch(keyboardlab.Event{Type: "input", Code: "PRIVATE"}) == nil || calls != 1 {
				t.Fatal("failed action replayed")
			}
		})
	}
}
func TestInstalledOrdinaryHostEditRejectsContradictionInProductionEmitter(t *testing.T) {
	for _, tc := range ordinaryReplyCases() {
		t.Run(tc.name, func(t *testing.T) {
			a := touchUIFixture(t)
			calls := 0
			s := &installedPreviewSessions{layout: a.s.Board.LayoutID}
			a.installed = s
			s.call = func(q touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
				calls++
				snapshot := diagnosticSnapshot()
				snapshot.Revision = 0
				if q.Operation == "bind" {
					return ordinaryReply(t, s.layout, q.Mode, snapshot, nil), nil
				}
				var action touchbroker.Action
				if json.Unmarshal(q.Action, &action) != nil {
					t.Fatal("invalid action fixture")
				}
				snapshot = s.snapshot
				snapshot.Revision++
				if calls == 2 {
					if action.Kind != "setModes" {
						t.Fatal("setup was not setModes")
					}
					return ordinaryReply(t, s.layout, s.mode, snapshot, nil), nil
				}
				if q.Operation != "action" || action.Kind != "hostEdit" || action.Edit == nil || action.Edit.Key != "Delete" {
					t.Fatal("did not exercise production hostEdit")
				}
				return ordinaryReply(t, s.layout, s.mode, snapshot, tc.mutate), nil
			}
			if err := a.bindInstalled(); err != nil || calls != 2 {
				t.Fatalf("legal setup failed: %v", err)
			}
			p := a.preview
			beforeP, beforeS := p.snapshot, s.snapshot
			output := tk.Output{Action: tk.Action{Type: "local", Key: "Delete"}}
			err := p.apply(output, p.stamp())
			assertOrdinaryStopped(t, p, s, beforeP, beforeS, tc.reason, err)
			if calls != 3 || s.lease != "lease" {
				t.Fatal("failed host edit changed lease or retried")
			}
			if p.apply(output, p.stamp()) == nil || p.dispatch(keyboardlab.Event{Type: "input", Code: "PRIVATE"}) == nil || calls != 3 {
				t.Fatal("unknown host edit was replayed")
			}
		})
	}
}
func TestInstalledOrdinarySuccessDoesNotRequireEditReceipt(t *testing.T) {
	for _, mode := range []string{"variable", "full", "shorthand"} {
		for _, withNoEdit := range []bool{false, true} {
			t.Run(mode+map[bool]string{false: "-absent-edit", true: "-not-applied"}[withNoEdit], func(t *testing.T) {
				calls := 0
				s := &installedPreviewSessions{layout: "layout"}
				s.call = func(q touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
					calls++
					snapshot := diagnosticSnapshot()
					snapshot.Revision = 0
					if q.Operation == "action" {
						var action touchbroker.Action
						if json.Unmarshal(q.Action, &action) != nil || action.Kind != "setModes" {
							t.Fatal("unexpected non-edit request")
						}
						snapshot = s.snapshot
						snapshot.Revision++
					}
					return ordinaryReply(t, s.layout, mode, snapshot, func(v map[string]any) {
						if withNoEdit {
							v["edit"] = map[string]any{"applied": false}
						}
					}), nil
				}
				p := &preview{sessions: s, layout: s.layout, installed: true}
				if err := p.switchMode(mode); err != nil || p.fault || calls != 2 || p.mode != mode || s.mode != mode || s.lease != "lease" || p.snapshot.Revision != 1 || s.snapshot.Revision != 1 {
					t.Fatalf("legal no-edit success rejected: %v", err)
				}
			})
		}
	}
}
