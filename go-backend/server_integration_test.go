package main

import (
	"encoding/json"
	"io"
	"os"
	"strings"
	"testing"

	yimeime "github.com/EasyIME/pime-go/input_methods/yime"
	"github.com/EasyIME/pime-go/pime"
)

const testFixtureGUID = "{7A1C2E93-5B64-4F88-AE21-3D9C6B70F145}"
const testRimeGUID = "{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}"

type protocolFixtureIME struct {
	*pime.TextServiceBase
	composition string
	candidates  []string
}

func newProtocolFixtureIME(client *pime.Client) pime.TextService {
	return &protocolFixtureIME{TextServiceBase: pime.NewTextServiceBase(client)}
}

func (ime *protocolFixtureIME) HandleRequest(req *pime.Request) *pime.Response {
	resp := pime.NewResponse(req.SeqNum, true)
	switch req.Method {
	case "filterKeyDown":
		charCode := req.CharCode
		if charCode == 0 && req.KeyCode >= 0x41 && req.KeyCode <= 0x5A {
			charCode = req.KeyCode + 32
		}
		if (charCode >= 'a' && charCode <= 'z') || (req.KeyCode >= 0x31 && req.KeyCode <= 0x39 && len(ime.candidates) > 0) {
			resp.ReturnValue = 1
		}
	case "onKeyDown":
		if req.KeyCode >= 0x31 && req.KeyCode <= 0x39 && len(ime.candidates) > 0 {
			index := req.KeyCode - 0x31
			if index < len(ime.candidates) {
				resp.CommitString = ime.candidates[index]
				resp.ReturnValue = 1
				resp.ShowCandidates = false
				ime.composition = ""
				ime.candidates = nil
			}
			return resp
		}
		charCode := req.CharCode
		if charCode == 0 && req.KeyCode >= 0x41 && req.KeyCode <= 0x5A {
			charCode = req.KeyCode + 32
		}
		if charCode >= 'a' && charCode <= 'z' {
			ime.composition += string(rune(charCode))
			if ime.composition == "ni" {
				ime.candidates = []string{"你", "呢"}
			}
			resp.CompositionString = ime.composition
			resp.CandidateList = ime.candidates
			resp.ShowCandidates = len(ime.candidates) > 0
			resp.ReturnValue = 1
		}
	case "onCompositionTerminated":
		ime.composition = ""
		ime.candidates = nil
	}
	return resp
}

func newTestServerWithFixture() *Server {
	server := NewServer()
	server.RegisterService(testFixtureGUID, func(client *pime.Client, guid string) pime.TextService {
		return newProtocolFixtureIME(client)
	})
	return server
}

func newTestServerWithRime() *Server {
	server := NewServer()
	server.RegisterService(testRimeGUID, func(client *pime.Client, guid string) pime.TextService {
		return yimeime.New(client)
	})
	return server
}

func captureStdout(t *testing.T, fn func()) string {
	t.Helper()

	oldStdout := os.Stdout
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("create stdout pipe: %v", err)
	}

	os.Stdout = writer
	defer func() {
		os.Stdout = oldStdout
	}()

	fn()

	if err := writer.Close(); err != nil {
		t.Fatalf("close stdout writer: %v", err)
	}

	output, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("read captured stdout: %v", err)
	}
	if err := reader.Close(); err != nil {
		t.Fatalf("close stdout reader: %v", err)
	}

	return strings.TrimSpace(string(output))
}

func sendProtocolMessage(t *testing.T, server *Server, clientID string, payload map[string]interface{}) (string, map[string]interface{}) {
	t.Helper()

	data, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}

	line := clientID + "|" + string(data)
	output := captureStdout(t, func() {
		if err := server.handleMessage(line); err != nil {
			t.Fatalf("handleMessage failed: %v", err)
		}
	})

	prefix := pime.MsgPIME + "|" + clientID + "|"
	if !strings.HasPrefix(output, prefix) {
		t.Fatalf("expected %q prefix, got %q", prefix, output)
	}

	var response map[string]interface{}
	if err := json.Unmarshal([]byte(strings.TrimPrefix(output, prefix)), &response); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}

	return output, response
}

func TestServerHandleMessageInitUsesTopLevelID(t *testing.T) {
	server := newTestServerWithFixture()

	_, response := sendProtocolMessage(t, server, "client-1", map[string]interface{}{
		"method":          "init",
		"seqNum":          1,
		"id":              testFixtureGUID,
		"isWindows8Above": true,
		"isMetroApp":      false,
		"isUiLess":        false,
		"isConsole":       false,
	})

	if response["success"] != true {
		t.Fatalf("expected init success, got %#v", response)
	}
	if response["seqNum"] != float64(1) {
		t.Fatalf("expected seqNum 1, got %#v", response["seqNum"])
	}

	client := server.clients["client-1"]
	if client == nil {
		t.Fatal("expected client to be registered after init")
	}
	if client.GUID != strings.ToLower(testFixtureGUID) {
		t.Fatalf("expected guid %q, got %q", strings.ToLower(testFixtureGUID), client.GUID)
	}
}

func TestServerHandleMessageInitAcceptsLowercaseGUID(t *testing.T) {
	server := newTestServerWithFixture()

	_, response := sendProtocolMessage(t, server, "client-lower", map[string]interface{}{
		"method":          "init",
		"seqNum":          1,
		"id":              strings.ToLower(testFixtureGUID),
		"isWindows8Above": true,
		"isMetroApp":      false,
		"isUiLess":        false,
		"isConsole":       false,
	})

	if response["success"] != true {
		t.Fatalf("expected lowercase guid init success, got %#v", response)
	}
}

func TestServerHandleMessageFixtureRequestResponseFlow(t *testing.T) {
	server := newTestServerWithFixture()

	sendProtocolMessage(t, server, "client-2", map[string]interface{}{
		"method":          "init",
		"seqNum":          1,
		"id":              testFixtureGUID,
		"isWindows8Above": true,
		"isMetroApp":      false,
		"isUiLess":        false,
		"isConsole":       false,
	})

	_, filterResp := sendProtocolMessage(t, server, "client-2", map[string]interface{}{
		"method":   "filterKeyDown",
		"seqNum":   2,
		"keyCode":  0x4E,
		"charCode": 'n',
	})
	if filterResp["return"] != true {
		t.Fatalf("expected filterKeyDown to handle n, got %#v", filterResp)
	}

	_, firstKeyResp := sendProtocolMessage(t, server, "client-2", map[string]interface{}{
		"method":   "onKeyDown",
		"seqNum":   3,
		"keyCode":  0x4E,
		"charCode": 'n',
	})
	if firstKeyResp["compositionString"] != "n" {
		t.Fatalf("expected first key to build composition n, got %#v", firstKeyResp)
	}
	if firstKeyResp["return"] != true {
		t.Fatalf("expected first key return true, got %#v", firstKeyResp)
	}

	_, secondKeyResp := sendProtocolMessage(t, server, "client-2", map[string]interface{}{
		"method":   "onKeyDown",
		"seqNum":   4,
		"keyCode":  0x49,
		"charCode": 'i',
	})
	if secondKeyResp["compositionString"] != "ni" || secondKeyResp["showCandidates"] != true {
		t.Fatalf("expected second key to build ni and show candidates, got %#v", secondKeyResp)
	}
	candidateList, ok := secondKeyResp["candidateList"].([]interface{})
	if !ok {
		t.Fatalf("expected candidate list array, got %#v", secondKeyResp["candidateList"])
	}
	if len(candidateList) != 2 {
		t.Fatalf("expected 2 candidates, got %d", len(candidateList))
	}
	if candidateList[1] != "呢" {
		t.Fatalf("expected second candidate 呢, got %#v", candidateList[1])
	}

	_, selectResp := sendProtocolMessage(t, server, "client-2", map[string]interface{}{
		"method":  "onKeyDown",
		"seqNum":  5,
		"keyCode": 0x32,
	})
	if selectResp["commitString"] != "呢" {
		t.Fatalf("expected number key to commit 呢, got %#v", selectResp)
	}
	if selectResp["showCandidates"] != false {
		t.Fatalf("expected candidate window to close, got %#v", selectResp)
	}
	if selectResp["return"] != true {
		t.Fatalf("expected candidate selection return true, got %#v", selectResp)
	}
}

func TestServerHandleMessageUninitializedClientReturnsProtocolError(t *testing.T) {
	server := newTestServerWithFixture()

	_, response := sendProtocolMessage(t, server, "client-3", map[string]interface{}{
		"method":   "onKeyDown",
		"seqNum":   9,
		"keyCode":  0x4D,
		"charCode": 'm',
	})

	if response["success"] != false {
		t.Fatalf("expected uninitialized client to fail, got %#v", response)
	}
	if response["seqNum"] != float64(9) {
		t.Fatalf("expected seqNum 9, got %#v", response["seqNum"])
	}
	if response["error"] != "客户端未初始化" {
		t.Fatalf("expected protocol error for uninitialized client, got %#v", response["error"])
	}
}

func TestServerHandleMessageCloseSucceeds(t *testing.T) {
	server := newTestServerWithFixture()

	sendProtocolMessage(t, server, "client-close", map[string]interface{}{
		"method":          "init",
		"seqNum":          1,
		"id":              testFixtureGUID,
		"isWindows8Above": true,
		"isMetroApp":      false,
		"isUiLess":        false,
		"isConsole":       false,
	})

	_, response := sendProtocolMessage(t, server, "client-close", map[string]interface{}{
		"method": "close",
		"seqNum": 2,
	})

	if response["success"] != true {
		t.Fatalf("expected close success, got %#v", response)
	}
	if _, ok := server.clients["client-close"]; ok {
		t.Fatal("expected client to be removed after close")
	}
}

func TestServerHandleMessageRimeRequestResponseFlow(t *testing.T) {
	server := newTestServerWithRime()

	sendProtocolMessage(t, server, "client-6", map[string]interface{}{
		"method":          "init",
		"seqNum":          1,
		"id":              testRimeGUID,
		"isWindows8Above": true,
		"isMetroApp":      false,
		"isUiLess":        false,
		"isConsole":       false,
	})

	service, ok := server.clients["client-6"].Service.(*yimeime.IME)
	if !ok {
		t.Fatal("expected concrete Rime IME service")
	}
	if !service.BackendAvailable() {
		t.Skip("native Rime backend unavailable in test environment")
	}

	_, firstResp := sendProtocolMessage(t, server, "client-6", map[string]interface{}{
		"method":   "filterKeyDown",
		"seqNum":   2,
		"keyCode":  0x4E,
		"charCode": 'n',
	})
	if firstResp["return"] != true {
		t.Fatalf("expected first key return true, got %#v", firstResp)
	}

	_, firstKeyState := sendProtocolMessage(t, server, "client-6", map[string]interface{}{
		"method":   "onKeyDown",
		"seqNum":   3,
		"keyCode":  0x4E,
		"charCode": 'n',
	})
	if firstKeyState["compositionString"] != "n" {
		t.Fatalf("expected onKeyDown to expose n, got %#v", firstKeyState)
	}
	candidateList, ok := firstKeyState["candidateList"].([]interface{})
	if !ok || len(candidateList) == 0 {
		t.Fatalf("expected prefix candidates, got %#v", firstKeyState["candidateList"])
	}
	if candidateList[0] != "你" {
		t.Fatalf("expected first candidate 你, got %#v", candidateList[0])
	}

	_, secondResp := sendProtocolMessage(t, server, "client-6", map[string]interface{}{
		"method":   "filterKeyDown",
		"seqNum":   4,
		"keyCode":  0x49,
		"charCode": 'i',
	})
	if secondResp["return"] != true {
		t.Fatalf("expected second key return true, got %#v", secondResp)
	}

	_, secondKeyState := sendProtocolMessage(t, server, "client-6", map[string]interface{}{
		"method":   "onKeyDown",
		"seqNum":   5,
		"keyCode":  0x49,
		"charCode": 'i',
	})
	if secondKeyState["compositionString"] != "ni" {
		t.Fatalf("expected second key to build ni, got %#v", secondKeyState)
	}
	secondCandidates, ok := secondKeyState["candidateList"].([]interface{})
	if !ok || len(secondCandidates) == 0 {
		t.Fatalf("expected exact candidates after ni, got %#v", secondKeyState["candidateList"])
	}
	if secondCandidates[1] != "呢" {
		t.Fatalf("expected second candidate 呢, got %#v", secondCandidates[1])
	}

	_, selectFilterResp := sendProtocolMessage(t, server, "client-6", map[string]interface{}{
		"method":   "filterKeyDown",
		"seqNum":   6,
		"keyCode":  0xC0,
		"charCode": '`',
	})
	if selectFilterResp["return"] != true {
		t.Fatalf("expected backtick filter to be handled, got %#v", selectFilterResp)
	}

	_, selectResp := sendProtocolMessage(t, server, "client-6", map[string]interface{}{
		"method":   "onKeyDown",
		"seqNum":   7,
		"keyCode":  0xC0,
		"charCode": '`',
	})
	if selectResp["commitString"] != "呢" {
		t.Fatalf("expected backtick key to commit 呢, got %#v", selectResp)
	}
	if selectResp["return"] != true {
		t.Fatalf("expected candidate selection return true, got %#v", selectResp)
	}
}
