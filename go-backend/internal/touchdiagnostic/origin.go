package touchdiagnostic

import (
	"bytes"
	"encoding/json"
	"io"
)

// ReportOrigin is added by the authenticated Broker, never accepted in a TIP
// diagnostic frame. At is actual server receive time, unlike a run filename's
// logical ordering time. PID plus creation FILETIME identifies the held peer
// process; it does not establish which DLL produced the self-report.
type ReportOrigin struct {
	ReceivedMS int64  `json:"at"`
	Event      string `json:"event"`
	PID        uint32 `json:"pid"`
	Created    uint64 `json:"created"`
}

func (r ReportOrigin) Valid() bool {
	if r.ReceivedMS <= 0 || r.ReceivedMS > 253402300799999 || r.PID == 0 || r.Created == 0 || len(r.Event) != 32 {
		return false
	}
	for _, c := range r.Event {
		if !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f') {
			return false
		}
	}
	return true
}

func decodeReportOrigin(raw []byte) (*ReportOrigin, bool) {
	d := json.NewDecoder(bytes.NewReader(raw))
	token, err := d.Token()
	if err != nil || token != json.Delim('{') {
		return nil, false
	}
	var result ReportOrigin
	seen := map[string]bool{}
	for d.More() {
		token, err = d.Token()
		key, ok := token.(string)
		if err != nil || !ok || seen[key] {
			return nil, false
		}
		seen[key] = true
		var value json.RawMessage
		if d.Decode(&value) != nil || bytes.Equal(value, []byte("null")) {
			return nil, false
		}
		switch key {
		case "at":
			err = json.Unmarshal(value, &result.ReceivedMS)
		case "event":
			err = json.Unmarshal(value, &result.Event)
		case "pid":
			err = json.Unmarshal(value, &result.PID)
		case "created":
			err = json.Unmarshal(value, &result.Created)
		default:
			return nil, false
		}
		if err != nil {
			return nil, false
		}
	}
	token, err = d.Token()
	return &result, err == nil && token == json.Delim('}') && d.Decode(new(any)) == io.EOF && len(seen) == 4 && result.Valid()
}
