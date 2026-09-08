package yimebroker

import (
	"encoding/binary"
	"errors"
	"fmt"
	"strings"
	"time"
)

type HealthRole uint32

const (
	HealthRoleBroker  HealthRole = 1
	HealthRoleRuntime HealthRole = 2
)

// HealthState describes process/listener lifecycle, not engine readiness.
type HealthState uint32

const (
	HealthStateServing  HealthState = 1
	HealthStateStarting HealthState = 2
	HealthStateStopping HealthState = 3
)

const (
	healthRequestSize  = 48
	healthResponseSize = 80
	healthConnections  = 2
	healthIOBudget     = 1000 * time.Millisecond
	healthRequestMagic = "YIMEH01\x00"
	healthReplyMagic   = "YIMER01\x00"
)

// HealthSnapshot contains only an in-memory lifecycle snapshot. Runtime may
// identify its current Broker child; a Broker must leave both related facts zero.
// Neither this snapshot nor the response proves that an input engine is ready.
type HealthSnapshot struct {
	State                  HealthState
	BrokerPID              uint32
	BrokerCreationFiletime uint64
}

type HealthConfig struct {
	// Name is the ordinary Broker pipe base; StartHealthServer derives its
	// separate role-specific endpoint with HealthPipeName.
	Name string
	Role HealthRole
	// Snapshot must return promptly by reading memory only. It runs synchronously
	// on a bounded connection worker, never in an abandoned callback goroutine.
	// It must not call Close on this server, which waits for that worker to exit.
	Snapshot func() HealthSnapshot
}

func HealthPipeName(base string, role HealthRole) (string, error) {
	const prefix = `\\.\pipe\`
	if !strings.HasPrefix(base, prefix) {
		return "", errors.New("health pipe requires a local ordinary pipe base")
	}
	leaf := base[len(prefix):]
	if len(leaf) == 0 || len(leaf) > 128 {
		return "", errors.New("health pipe base leaf must contain 1-128 ASCII characters")
	}
	if c := leaf[0]; !(c >= 'a' && c <= 'z') && !(c >= 'A' && c <= 'Z') && !(c >= '0' && c <= '9') {
		return "", errors.New("health pipe base leaf must start with an ASCII letter or digit")
	}
	for _, c := range leaf {
		if !(c >= 'a' && c <= 'z') && !(c >= 'A' && c <= 'Z') && !(c >= '0' && c <= '9') && c != '.' && c != '_' && c != '-' {
			return "", errors.New("health pipe base contains an invalid leaf character")
		}
	}
	var suffix string
	switch role {
	case HealthRoleBroker:
		suffix = ".health-v1"
	case HealthRoleRuntime:
		suffix = ".runtime-health-v1"
	default:
		return "", errors.New("unknown health role")
	}
	if len(leaf)+len(suffix) > 128 {
		return "", errors.New("derived health pipe leaf exceeds 128 characters")
	}
	return base + suffix, nil
}

func decodeHealthRequest(frame []byte, role HealthRole) ([32]byte, error) {
	var nonce [32]byte
	if len(frame) != healthRequestSize || string(frame[:8]) != healthRequestMagic {
		return nonce, errors.New("invalid health request frame")
	}
	if (role != HealthRoleBroker && role != HealthRoleRuntime) || HealthRole(binary.LittleEndian.Uint32(frame[8:12])) != role || binary.LittleEndian.Uint32(frame[12:16]) != 0 {
		return nonce, errors.New("invalid health request role or reserved field")
	}
	copy(nonce[:], frame[16:48])
	if nonce == [32]byte{} {
		return nonce, errors.New("health nonce must not be zero")
	}
	return nonce, nil
}

func encodeHealthResponse(role HealthRole, nonce [32]byte, snapshot HealthSnapshot, pid uint32, creation uint64) ([healthResponseSize]byte, error) {
	var frame [healthResponseSize]byte
	if role != HealthRoleBroker && role != HealthRoleRuntime {
		return frame, errors.New("unknown health role")
	}
	if snapshot.State != HealthStateServing && snapshot.State != HealthStateStarting && snapshot.State != HealthStateStopping {
		return frame, errors.New("unknown health state")
	}
	if pid == 0 || creation == 0 || nonce == [32]byte{} {
		return frame, errors.New("missing native server identity or nonce")
	}
	if (snapshot.BrokerPID == 0) != (snapshot.BrokerCreationFiletime == 0) || (role == HealthRoleBroker && snapshot.BrokerPID != 0) {
		return frame, fmt.Errorf("invalid related process facts for health role %d", role)
	}
	if role == HealthRoleRuntime && snapshot.State == HealthStateServing && snapshot.BrokerPID == 0 {
		return frame, errors.New("serving Runtime requires related Broker identity")
	}
	copy(frame[:8], healthReplyMagic)
	binary.LittleEndian.PutUint32(frame[8:12], uint32(role))
	binary.LittleEndian.PutUint32(frame[12:16], uint32(snapshot.State))
	copy(frame[16:48], nonce[:])
	binary.LittleEndian.PutUint32(frame[48:52], pid)
	binary.LittleEndian.PutUint32(frame[52:56], snapshot.BrokerPID)
	binary.LittleEndian.PutUint64(frame[56:64], creation)
	binary.LittleEndian.PutUint64(frame[64:72], snapshot.BrokerCreationFiletime)
	return frame, nil
}
