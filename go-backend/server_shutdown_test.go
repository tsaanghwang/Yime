package main

import (
	"bufio"
	"errors"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/pime"
)

type shutdownTrackingService struct {
	closeCount *int
	initResult bool
	closeErr   error
}

func (s *shutdownTrackingService) Init(*pime.Request) bool { return s.initResult }

func (s *shutdownTrackingService) HandleRequest(req *pime.Request) *pime.Response {
	return pime.NewResponse(req.SeqNum, true)
}

func (s *shutdownTrackingService) Close() { *s.closeCount++ }

func (s *shutdownTrackingService) CloseWithError() error {
	s.Close()
	return s.closeErr
}

func TestServerRunEOFClosesEveryTrackedService(t *testing.T) {
	server := NewServer()
	firstClosed, secondClosed := 0, 0
	server.clients["first"] = &Client{
		ID:      "first",
		Service: &shutdownTrackingService{closeCount: &firstClosed, initResult: true},
	}
	server.clients["second"] = &Client{
		ID:      "second",
		Service: &shutdownTrackingService{closeCount: &secondClosed, initResult: true},
	}
	server.reader = bufio.NewReader(strings.NewReader(""))

	if err := server.Run(); err != nil {
		t.Fatalf("Run on EOF: %v", err)
	}
	if firstClosed != 1 || secondClosed != 1 {
		t.Fatalf("EOF close counts = (%d, %d), want (1, 1)", firstClosed, secondClosed)
	}
	if len(server.clients) != 0 {
		t.Fatalf("EOF retained %d tracked services", len(server.clients))
	}
}

func TestServerInitNeverLosesAnOwnedService(t *testing.T) {
	server := NewServer()
	firstClosed, replacementClosed, failedClosed := 0, 0, 0
	services := []*shutdownTrackingService{
		{closeCount: &firstClosed, initResult: true},
		{closeCount: &replacementClosed, initResult: true},
		{closeCount: &failedClosed, initResult: false},
	}
	created := 0
	const guid = "{7207152E-77B1-4E9D-A728-A24798F28642}"
	server.RegisterService(guid, func(*pime.Client, string) pime.TextService {
		service := services[created]
		created++
		return service
	})
	request := &pime.Request{Method: "init", ID: pime.FlexibleID{String: guid}}

	if response := server.handleRequest("same-client", request); response["success"] != true {
		t.Fatalf("first init failed: %#v", response)
	}
	if response := server.handleRequest("same-client", request); response["success"] != true {
		t.Fatalf("replacement init failed: %#v", response)
	}
	if firstClosed != 1 || replacementClosed != 0 {
		t.Fatalf("replacement close counts = (%d, %d), want (1, 0)", firstClosed, replacementClosed)
	}
	if response := server.handleRequest("same-client", request); response["success"] != false {
		t.Fatalf("failed init unexpectedly succeeded: %#v", response)
	}
	if failedClosed != 1 {
		t.Fatalf("failed init service close count = %d, want 1", failedClosed)
	}
	if server.clients["same-client"].Service != services[1] {
		t.Fatal("failed replacement discarded the still-live prior service")
	}
	if err := server.closeAllClients(); err != nil {
		t.Fatalf("close remaining client: %v", err)
	}
	if replacementClosed != 1 {
		t.Fatalf("remaining replacement close count = %d, want 1", replacementClosed)
	}
}

func TestServerRunEOFReportsCloseFailureAfterTryingEveryService(t *testing.T) {
	server := NewServer()
	failedClosed, peerClosed := 0, 0
	server.clients["failed"] = &Client{ID: "failed", Service: &shutdownTrackingService{
		closeCount: &failedClosed, initResult: true, closeErr: errors.New("fixture close failed"),
	}}
	server.clients["peer"] = &Client{ID: "peer", Service: &shutdownTrackingService{
		closeCount: &peerClosed, initResult: true,
	}}
	server.reader = bufio.NewReader(strings.NewReader(""))

	err := server.Run()
	if err == nil || !strings.Contains(err.Error(), "fixture close failed") {
		t.Fatalf("Run close error = %v, want fixture failure", err)
	}
	if failedClosed != 1 || peerClosed != 1 {
		t.Fatalf("failure path close counts = (%d, %d), want (1, 1)", failedClosed, peerClosed)
	}
	if len(server.clients) != 0 {
		t.Fatalf("failure path retained %d tracked services", len(server.clients))
	}
}
