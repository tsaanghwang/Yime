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
	if response.Error != nil || response.SessionID == "" || dispatcher.ActiveSessions() != 0 {
		t.Fatalf("response = %+v", response)
	}
}

func TestServeLinesReleasesOnlySessionsOpenedByItsConnection(t *testing.T) {
	dispatcher := newMemoryDispatcher(t, Config{})
	client := TrustedClient{ID: "shared-process"}
	other := dispatcher.Dispatch(context.Background(), client, Request{
		Version: 1, Sequence: 1, Operation: OpenSession,
	})
	if other.Error != nil {
		t.Fatal(other.Error)
	}
	request, err := EncodeRequest(Request{Version: 1, Sequence: 1, Operation: OpenSession})
	if err != nil {
		t.Fatal(err)
	}
	if err := ServeLines(context.Background(), bytes.NewReader(append(request, '\n')), &bytes.Buffer{}, dispatcher, client); err != nil {
		t.Fatal(err)
	}
	if dispatcher.ActiveSessions() != 1 {
		t.Fatalf("connection cleanup removed another connection's session: active=%d", dispatcher.ActiveSessions())
	}
	dispatcher.CloseSession(client, other.SessionID)
}

func TestServeLinesRejectsOversizedFrame(t *testing.T) {
	dispatcher := newMemoryDispatcher(t, Config{})
	input := strings.NewReader(strings.Repeat("x", MaxMessageBytes+1) + "\n")
	if err := ServeLines(context.Background(), input, &bytes.Buffer{}, dispatcher, TrustedClient{ID: "pipe-client"}); err == nil {
		t.Fatal("oversized frame unexpectedly succeeded")
	}
}
