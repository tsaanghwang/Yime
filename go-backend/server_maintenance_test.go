package main

import (
	"github.com/tsaanghwang/Yime/go-backend/pime"
	"os"
	"testing"
)

type maintenanceService struct {
	pime.TextService
	ready  bool
	schema string
	calls  int
}

func (s *maintenanceService) MaintenanceReadiness() (bool, string) {
	s.calls++
	return s.ready, s.schema
}
func TestMaintenanceReadyRequiresInitializedCommandCapability(t *testing.T) {
	s := NewServer()
	service := &maintenanceService{ready: true, schema: "yime"}
	req := &pime.Request{Method: "maintenanceReady", SeqNum: 7}
	for _, client := range []*Client{nil, {Service: service, AllowCommands: false}} {
		if client != nil {
			s.clients["probe"] = client
		}
		got := s.handleRequest("probe", req)
		if got["success"] != false || got["errorCode"] != "authorization_denied" || service.calls != 0 {
			t.Fatalf("unauthorized probe: %#v", got)
		}
	}
	s.clients["probe"] = &Client{Service: service, AllowCommands: true}
	got := s.handleRequest("probe", req)
	if got["success"] != true || got["native_rime_ready"] != true || got["schema_id"] != "yime" || got["backend_pid"] != os.Getpid() || got["seqNum"] != 7 || service.calls != 1 {
		t.Fatalf("bad readiness: %#v", got)
	}
}
func TestMaintenanceReadyRejectsIncompleteNativeReadiness(t *testing.T) {
	for _, c := range []struct {
		ready  bool
		schema string
	}{{false, "yime"}, {true, ""}, {true, ".default"}} {
		s := NewServer()
		s.clients["probe"] = &Client{Service: &maintenanceService{ready: c.ready, schema: c.schema}, AllowCommands: true}
		got := s.handleRequest("probe", &pime.Request{Method: "maintenanceReady"})
		if got["success"] != false || got["native_rime_ready"] != false || got["schema_id"] != "" {
			t.Fatalf("false positive readiness: %#v", got)
		}
	}
}
