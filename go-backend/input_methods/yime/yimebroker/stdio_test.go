package yimebroker

import (
	"bytes"
	"context"
	"encoding/json"
	"strings"
	"testing"
)

func TestServeLinesBindsOutOfBandClientAndFlushesResponses(t *testing.T) {
	dispatcher := newMemoryDispatcher(t, Config{})
	request, err := EncodeRequest(Request{Version: 1, Sequence: 1, Operation: OpenSession})
	if err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	if err := ServeLines(context.Background(), bytes.NewReader(append(request, '\n')), &output, dispatcher, TrustedClient{ID: "pipe-client"}); err != nil {
		t.Fatal(err)
	}
	var response Response
	if err := json.Unmarshal(bytes.TrimSpace(output.Bytes()), &response); err != nil {
		t.Fatal(err)
	}
	if response.Error != nil || response.SessionID == "" || dispatcher.ActiveSessions() != 1 {
		t.Fatalf("response = %+v", response)
	}
}

func TestServeLinesRejectsOversizedFrame(t *testing.T) {
	dispatcher := newMemoryDispatcher(t, Config{})
	input := strings.NewReader(strings.Repeat("x", MaxMessageBytes+1) + "\n")
	if err := ServeLines(context.Background(), input, &bytes.Buffer{}, dispatcher, TrustedClient{ID: "pipe-client"}); err == nil {
		t.Fatal("oversized frame unexpectedly succeeded")
	}
}
