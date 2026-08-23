// Package yimebroker defines the transport-neutral protocol and in-process
// dispatcher used by the E5-A YimeBroker experiment. It deliberately does not
// import PIME, Rime, Windows APIs, or a concrete transport.
package yimebroker

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

const (
	ProtocolVersion = 1
	MaxMessageBytes = 256 * 1024
)

type Operation string

const (
	OpenSession  Operation = "open"
	ApplyEvent   Operation = "apply"
	Select       Operation = "select"
	ResetSession Operation = "reset"
	CloseSession Operation = "close"
)

type ErrorCode string

const (
	CodeInvalidRequest     ErrorCode = "invalid_request"
	CodeUnsupportedVersion ErrorCode = "unsupported_version"
	CodeInvalidClient      ErrorCode = "invalid_client"
	CodeSessionNotFound    ErrorCode = "session_not_found"
	CodeSessionLimit       ErrorCode = "session_limit"
	CodeSequence           ErrorCode = "sequence_error"
	CodeTimeout            ErrorCode = "timeout"
	CodeEngine             ErrorCode = "engine_error"
	CodeEnginePanic        ErrorCode = "engine_panic"
)

// TrustedClient is supplied out of band by the future transport adapter. Its
// identity is intentionally absent from Request so wire data cannot impersonate
// another client.
type TrustedClient struct {
	ID string
}

type Request struct {
	Version     int             `json:"version"`
	Sequence    uint64          `json:"sequence"`
	SessionID   string          `json:"session_id,omitempty"`
	Operation   Operation       `json:"operation"`
	Event       engineapi.Event `json:"event,omitempty"`
	CandidateID string          `json:"candidate_id,omitempty"`
}

type ProtocolError struct {
	Code    ErrorCode `json:"code"`
	Message string    `json:"message"`
}

type Response struct {
	Version   int               `json:"version"`
	Sequence  uint64            `json:"sequence"`
	SessionID string            `json:"session_id,omitempty"`
	Result    *engineapi.Result `json:"result,omitempty"`
	Error     *ProtocolError    `json:"error,omitempty"`
}

func DecodeRequest(data []byte) (Request, error) {
	if len(data) == 0 {
		return Request{}, errors.New("empty request")
	}
	if len(data) > MaxMessageBytes {
		return Request{}, fmt.Errorf("request exceeds %d bytes", MaxMessageBytes)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var request Request
	if err := decoder.Decode(&request); err != nil {
		return Request{}, err
	}
	if err := ensureJSONEOF(decoder); err != nil {
		return Request{}, err
	}
	if request.Version != ProtocolVersion {
		return Request{}, fmt.Errorf("unsupported protocol version %d", request.Version)
	}
	if err := validateRequest(request); err != nil {
		return Request{}, err
	}
	return request, nil
}

func EncodeRequest(request Request) ([]byte, error) {
	if request.Version != ProtocolVersion {
		return nil, fmt.Errorf("unsupported protocol version %d", request.Version)
	}
	if err := validateRequest(request); err != nil {
		return nil, err
	}
	data, err := json.Marshal(request)
	if err != nil {
		return nil, err
	}
	if len(data) > MaxMessageBytes {
		return nil, fmt.Errorf("request exceeds %d bytes", MaxMessageBytes)
	}
	return data, nil
}

func EncodeResponse(response Response) ([]byte, error) {
	return json.Marshal(response)
}

func ensureJSONEOF(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		if err == nil {
			return errors.New("multiple JSON values")
		}
		return err
	}
	return nil
}

func validateRequest(request Request) error {
	if request.Sequence == 0 {
		return errors.New("sequence must be positive")
	}
	switch request.Operation {
	case OpenSession:
		if request.Sequence != 1 || request.SessionID != "" || request.Event.Operation != 0 || request.CandidateID != "" {
			return errors.New("open requires sequence 1 and no session payload")
		}
	case ApplyEvent:
		if request.SessionID == "" || request.Event.Operation == 0 || request.CandidateID != "" {
			return errors.New("apply requires session_id and event only")
		}
	case Select:
		if request.SessionID == "" || request.CandidateID == "" || request.Event.Operation != 0 {
			return errors.New("select requires session_id and candidate_id only")
		}
	case ResetSession, CloseSession:
		if request.SessionID == "" || request.Event.Operation != 0 || request.CandidateID != "" {
			return errors.New("reset and close require session_id only")
		}
	default:
		return fmt.Errorf("unsupported operation %q", request.Operation)
	}
	return nil
}

func errorResponse(sequence uint64, sessionID string, code ErrorCode, err error) Response {
	message := string(code)
	if err != nil {
		message = err.Error()
	}
	return Response{
		Version: ProtocolVersion, Sequence: sequence, SessionID: sessionID,
		Error: &ProtocolError{Code: code, Message: message},
	}
}
