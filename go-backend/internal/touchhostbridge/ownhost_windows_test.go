//go:build windows && amd64

package touchhostbridge

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

// This opt-in native test requires a separately built, reviewed native harness.
// Ordinary suites skip without the environment variable. Explicitly setting it
// to a missing/relative path fails rather than converting the gate into a skip.
// It creates no registered TIP and never explicitly activates a product.
// Run only in isolated Windows CI, not on a user machine: the TSF activation
// suppression flags do not guarantee absence of every later asynchronous TIP.
func TestNativeOwnTSFCommit(t *testing.T) {
	path := os.Getenv("YIME_TOUCH_BRIDGE_OWN_HOST")
	if path == "" {
		t.Skip("native S2a gate not requested: set absolute YIME_TOUCH_BRIDGE_OWN_HOST executable path")
	}
	if !filepath.IsAbs(path) {
		t.Fatal("harness path must be absolute")
	}
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() {
		t.Fatalf("native harness unavailable: %v", err)
	}
	for _, scenario := range []string{"commit", "duplicate", "focus-lost", "async-commit", "async-focus-lost", "async-cancel", "async-old-epoch"} {
		t.Run(scenario, func(t *testing.T) {
			s := session(t)
			ticket := commit(t, s)
			request := struct {
				ID       string `json:"id"`
				Text     string `json:"text"`
				Context  string `json:"context"`
				Epoch    uint64 `json:"epoch"`
				Scenario string `json:"scenario"`
			}{ticket.ID, ticket.Text, ticket.Focus.Context, ticket.Focus.Epoch, scenario}
			input, err := json.Marshal(request)
			if err != nil {
				t.Fatal(err)
			}
			input = append(input, '\n')
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			cmd := exec.CommandContext(ctx, path)
			cmd.Dir = t.TempDir()
			cmd.Stdin = bytes.NewReader(input)
			var stdout, stderr limitedOutput
			cmd.Stdout = &stdout
			cmd.Stderr = &stderr
			var next *Session
			if scenario == "async-old-epoch" {
				s.Invalidate()
				next = session(t) // new logical activation exists before old native receipt arrives
			}
			if err = cmd.Run(); err != nil {
				_ = s.Complete(ticket.ID, Unknown)
				// Do not print raw child logs or candidate/host text into the test report.
				t.Fatalf("native child failed; edit outcome unknown: %v (stderr bytes=%d)", err, stderr.Len())
			}
			var result struct {
				ID                     string  `json:"id"`
				Outcome                Outcome `json:"outcome"`
				ReadbackMatches        bool    `json:"readbackMatches"`
				ReadbackEmpty          bool    `json:"readbackEmpty"`
				ActualEditRequests     uint    `json:"actualEditRequests"`
				EditCompleted          bool    `json:"editCompleted"`
				DuplicateRejected      bool    `json:"duplicateRejected"`
				Registered             bool    `json:"registered"`
				SendInput              bool    `json:"sendInput"`
				NewContextChecked      bool    `json:"newContextChecked"`
				NewContextEmpty        bool    `json:"newContextEmpty"`
				AsyncRequested         bool    `json:"asyncRequested"`
				QueuedBeforeCompletion bool    `json:"queuedBeforeCompletion"`
				ControlledDelay        bool    `json:"controlledDelay"`
				GuardChecks            uint    `json:"guardChecks"`
				GuardDenied            uint    `json:"guardDenied"`
				CompletionEpoch        uint    `json:"completionEpoch"`
				ActiveEpoch            uint    `json:"activeEpoch"`
			}
			decoder := json.NewDecoder(bytes.NewReader(stdout.Bytes()))
			decoder.DisallowUnknownFields()
			if err = decoder.Decode(&result); err != nil {
				_ = s.Complete(ticket.ID, Unknown)
				t.Fatalf("invalid native receipt: %v", err)
			}
			var extra any
			if err = decoder.Decode(&extra); !errors.Is(err, io.EOF) {
				_ = s.Complete(ticket.ID, Unknown)
				t.Fatal("extra native output")
			}
			if result.ID != ticket.ID || result.Registered || result.SendInput {
				_ = s.Complete(ticket.ID, Unknown)
				t.Fatal("receipt identity or boundary mismatch")
			}
			switch scenario {
			case "focus-lost":
				if result.Outcome != Failed || !result.ReadbackEmpty || result.EditCompleted || result.ActualEditRequests != 0 || result.AsyncRequested || !result.NewContextChecked || !result.NewContextEmpty {
					t.Fatal("prequeue focus loss wrote or completed")
				}
			case "async-focus-lost", "async-cancel", "async-old-epoch":
				if result.Outcome != Failed || !result.ReadbackEmpty || !result.EditCompleted || result.ActualEditRequests != 1 || !result.AsyncRequested || !result.QueuedBeforeCompletion || !result.ControlledDelay || result.GuardChecks != 1 || result.GuardDenied != 1 || result.CompletionEpoch != 1 || !result.NewContextChecked || !result.NewContextEmpty {
					t.Fatal("execution guard did not reject actual queued edit")
				}
				if scenario == "async-old-epoch" && result.ActiveEpoch != 2 {
					t.Fatal("new activation epoch changed by old callback")
				}
			default:
				if result.Outcome != Applied || !result.ReadbackMatches || !result.EditCompleted || result.ActualEditRequests != 1 || (scenario == "duplicate" && !result.DuplicateRejected) {
					t.Fatal("native edit/readback or no replay failed")
				}
				if scenario == "async-commit" && (!result.AsyncRequested || !result.QueuedBeforeCompletion || result.ControlledDelay || result.GuardChecks != 1 || result.GuardDenied != 0 || result.ActiveEpoch != 1 || result.CompletionEpoch != 1) {
					t.Fatal("actual async completion not established")
				}
			}
			if scenario == "async-old-epoch" {
				// The old native request completes after logical invalidation.
				// Neither its failure nor a hypothetical success may update a
				// new Go activation or change the old Unknown receipt.
				if err = s.Complete(ticket.ID, result.Outcome); err == nil {
					t.Fatal("late old receipt accepted")
				}
				if err = next.Complete(ticket.ID, result.Outcome); err == nil {
					t.Fatal("old receipt accepted by new activation")
				}
				if s.Receipt().Outcome != Unknown || next.Receipt().ID != "" {
					t.Fatal("late completion contaminated activation state")
				}
			} else if err = s.Complete(ticket.ID, result.Outcome); err != nil {
				t.Fatal(err)
			}

		})
	}
}

type limitedOutput struct{ bytes.Buffer }

func (b *limitedOutput) Write(p []byte) (int, error) {
	if b.Len()+len(p) > 16384 {
		return 0, errors.New("native output limit exceeded")
	}
	return b.Buffer.Write(p)
}
