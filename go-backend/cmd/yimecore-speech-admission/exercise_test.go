package main

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

type fixtureWriteCloser struct{ bytes.Buffer }

func (*fixtureWriteCloser) Close() error { return nil }

func TestSpeechExerciseReopenStartsNewSessionSequence(t *testing.T) {
	input := &fixtureWriteCloser{}
	child := &brokerChild{input: input, output: bufio.NewScanner(strings.NewReader("{\"version\":1,\"sequence\":1,\"session_id\":\"fixture\"}\n")), sequence: 99}
	if _, err := child.request(yimebroker.Request{Operation: yimebroker.OpenSession, Mode: "variable"}); err != nil {
		t.Fatal(err)
	}
	request, err := yimebroker.DecodeRequest(bytes.TrimSpace(input.Bytes()))
	if err != nil || request.Sequence != 1 {
		t.Fatal("reopened session inherited previous sequence")
	}
}

func TestSpeechExerciseRejectsFalsePositiveProcessFailures(t *testing.T) {
	failure := errors.New("child failed")
	for _, tc := range []struct {
		name     string
		code     int
		ctx, err error
		want     bool
	}{
		{"confirmed", 42, nil, failure, true},
		{"generic_failure", 1, nil, failure, false},
		{"crash", -1, nil, failure, false},
		{"timeout", 42, context.DeadlineExceeded, failure, false},
		{"cancelled", 42, context.Canceled, failure, false},
		{"success", 0, nil, nil, false},
		{"no_exit_error", 42, nil, nil, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if confirmedAdmissionRejection(tc.code, tc.ctx, tc.err) != tc.want {
				t.Fatal("incorrect rejection classification")
			}
		})
	}
}

func TestSpeechExerciseGenerationCheckDoesNotRepairOrCheckpoint(t *testing.T) {
	root := filepath.Join(t.TempDir(), "speech-admission-fixture-5678")
	state := filepath.Join(root, "state")
	if err := os.MkdirAll(state, 0700); err != nil {
		t.Fatal(err)
	}
	model, err := yimecore.NewUserModel(speechruntime.ModelNamespace)
	if err != nil {
		t.Fatal(err)
	}
	if err := model.SaveTo(filepath.Join(state, "model.json")); err != nil {
		t.Fatal(err)
	}
	journal := filepath.Join(state, "model.journal")
	if err := os.WriteFile(journal, []byte("unrecovered-fixture-tail"), 0600); err != nil {
		t.Fatal(err)
	}
	before, _ := speechruntime.HashFile(journal)
	if generation, err := ownModelGeneration(root); err != nil || generation != 0 {
		t.Fatal("read-only snapshot count failed")
	}
	after, _ := speechruntime.HashFile(journal)
	if before == "" || before != after {
		t.Fatal("count repaired or checkpointed journal")
	}
}

func TestSpeechExerciseRefusesUnownedImageAndEvidenceOverwrite(t *testing.T) {
	root := filepath.Join(t.TempDir(), "speech-admission-fixture-1234")
	if err := os.Mkdir(root, 0700); err != nil {
		t.Fatal(err)
	}
	if err := exercise(root, filepath.Join(root, "outside.exe"), ""); err == nil {
		t.Fatal("unowned image accepted")
	}
	if _, err := os.Stat(filepath.Join(root, "state")); !os.IsNotExist(err) {
		t.Fatal("failed image guard created durable state")
	}
	path := filepath.Join(root, "outcome.json")
	if err := writeNew(path, map[string]bool{"original": true}); err != nil {
		t.Fatal(err)
	}
	if err := writeNew(path, map[string]bool{"original": false}); err == nil {
		t.Fatal("evidence overwritten")
	}
}
