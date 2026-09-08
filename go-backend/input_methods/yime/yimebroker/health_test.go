package yimebroker

import (
	"encoding/binary"
	"strings"
	"testing"
)

func healthTestRequest(role HealthRole, nonce byte) []byte {
	frame := make([]byte, healthRequestSize)
	copy(frame, healthRequestMagic)
	binary.LittleEndian.PutUint32(frame[8:12], uint32(role))
	for i := 16; i < len(frame); i++ {
		frame[i] = nonce + byte(i)
	}
	return frame
}

func TestHealthPipeName(t *testing.T) {
	for _, tc := range []struct {
		role   HealthRole
		suffix string
	}{{HealthRoleBroker, ".health-v1"}, {HealthRoleRuntime, ".runtime-health-v1"}} {
		base := `\\.\pipe\Yime_Broker-Test.1`
		name, err := HealthPipeName(base, tc.role)
		if err != nil || name != base+tc.suffix {
			t.Fatalf("derived name %q: %v", name, err)
		}
		limit := 128 - len(tc.suffix)
		if _, err := HealthPipeName(`\\.\pipe\`+strings.Repeat("x", limit), tc.role); err != nil {
			t.Fatal(err)
		}
		if _, err := HealthPipeName(`\\.\pipe\`+strings.Repeat("x", limit+1), tc.role); err == nil {
			t.Fatal("accepted oversized derived leaf")
		}
	}
	for _, name := range []string{"", `\\remote\pipe\a`, `\\.\pipe\`, `\\.\pipe\a\b`, `\\.\pipe\a/b`, `\\.\pipe\a:b`, `\\.\pipe\a b`, `\\.\pipe\音`, "\\\\.\\pipe\\a\x00b", `\\.\pipe\` + strings.Repeat("x", 129)} {
		if _, err := HealthPipeName(name, HealthRoleBroker); err == nil {
			t.Errorf("accepted invalid base %q", name)
		}
	}
	for _, name := range []string{`\\.\pipe\.a`, `\\.\pipe\_a`, `\\.\pipe\-a`} {
		if _, err := HealthPipeName(name, HealthRoleBroker); err == nil {
			t.Errorf("accepted noncanonical first character: %q", name)
		}
	}
	if _, err := HealthPipeName(`\\.\pipe\valid`, HealthRole(3)); err == nil {
		t.Fatal("accepted invalid role")
	}
}

func TestHealthRequestAndResponseContract(t *testing.T) {
	valid := healthTestRequest(HealthRoleBroker, 41)
	nonce, err := decodeHealthRequest(valid, HealthRoleBroker)
	if err != nil || string(nonce[:]) != string(valid[16:]) {
		t.Fatal("valid request or nonce rejected")
	}
	for length := 0; length < len(valid); length++ {
		if _, err := decodeHealthRequest(valid[:length], HealthRoleBroker); err == nil {
			t.Fatalf("accepted truncated request length %d", length)
		}
	}
	invalid := [][]byte{append(append([]byte{}, valid...), 1), healthTestRequest(HealthRoleRuntime, 41)}
	for _, index := range []int{0, 7, 12, 15} {
		changed := append([]byte{}, valid...)
		changed[index] ^= 1
		invalid = append(invalid, changed)
	}
	zero := append([]byte{}, valid...)
	clear(zero[16:])
	invalid = append(invalid, zero)
	for _, frame := range invalid {
		if _, err := decodeHealthRequest(frame, HealthRoleBroker); err == nil {
			t.Errorf("accepted malformed frame %x", frame)
		}
	}
	if _, err := decodeHealthRequest(valid, 0); err == nil {
		t.Fatal("accepted unknown expected role")
	}
	for _, state := range []HealthState{HealthStateServing, HealthStateStarting, HealthStateStopping} {
		frame, err := encodeHealthResponse(HealthRoleBroker, nonce, HealthSnapshot{State: state}, 123, 456)
		if err != nil || string(frame[:8]) != healthReplyMagic || binary.LittleEndian.Uint32(frame[8:12]) != 1 || binary.LittleEndian.Uint32(frame[12:16]) != uint32(state) || string(frame[16:48]) != string(nonce[:]) || binary.LittleEndian.Uint32(frame[48:52]) != 123 || binary.LittleEndian.Uint64(frame[56:64]) != 456 || binary.LittleEndian.Uint32(frame[52:56]) != 0 || binary.LittleEndian.Uint64(frame[64:72]) != 0 || binary.LittleEndian.Uint64(frame[72:]) != 0 {
			t.Fatalf("bad response contract: %x %v", frame, err)
		}
	}
	for _, snapshot := range []HealthSnapshot{{State: 0}, {State: 4}, {State: 1, BrokerPID: 4}, {State: 1, BrokerCreationFiletime: 8}, {State: 1, BrokerPID: 4, BrokerCreationFiletime: 8}} {
		if _, err := encodeHealthResponse(HealthRoleBroker, nonce, snapshot, 1, 2); err == nil {
			t.Errorf("accepted invalid Broker snapshot %+v", snapshot)
		}
	}
	if _, err := encodeHealthResponse(HealthRoleRuntime, nonce, HealthSnapshot{State: HealthStateServing}, 1, 2); err == nil {
		t.Fatal("serving Runtime without child accepted")
	}
	for _, snapshot := range []HealthSnapshot{{State: 1, BrokerPID: 4}, {State: 1, BrokerCreationFiletime: 8}} {
		if _, err := encodeHealthResponse(HealthRoleRuntime, nonce, snapshot, 1, 2); err == nil {
			t.Fatal("half-related identity accepted")
		}
	}
	for _, state := range []HealthState{HealthStateStarting, HealthStateStopping} {
		if _, err := encodeHealthResponse(HealthRoleRuntime, nonce, HealthSnapshot{State: state}, 1, 2); err != nil {
			t.Fatal(err)
		}
	}
	frame, err := encodeHealthResponse(HealthRoleRuntime, nonce, HealthSnapshot{State: 1, BrokerPID: 12, BrokerCreationFiletime: 34}, 56, 78)
	if err != nil || binary.LittleEndian.Uint32(frame[52:56]) != 12 || binary.LittleEndian.Uint64(frame[64:72]) != 34 {
		t.Fatal("related facts lost")
	}
	for _, tc := range []struct {
		role     HealthRole
		pid      uint32
		creation uint64
		nonce    [32]byte
	}{{0, 1, 2, nonce}, {1, 0, 2, nonce}, {1, 1, 0, nonce}, {1, 1, 2, [32]byte{}}} {
		if _, err := encodeHealthResponse(tc.role, tc.nonce, HealthSnapshot{State: 1}, tc.pid, tc.creation); err == nil {
			t.Fatal("invalid server identity accepted")
		}
	}
}
