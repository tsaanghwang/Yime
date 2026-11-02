package installed18uhost
import("bytes";"encoding/json";"errors";"reflect")
type formalResult struct {
	Stage                          string `json:"stage"`
	Scenario                       string `json:"scenario"`
	ActualDLLLoaded                bool   `json:"actualDLLLoaded"`
	ActivationIdentity             string `json:"activationIdentity"`
	Registered                     bool   `json:"registered"`
	SendInput                      bool   `json:"sendInput"`
	Outcome                        string `json:"outcome"`
	Rejected                       bool   `json:"rejected"`
	DuplicateRejected              bool   `json:"duplicateRejected"`
	ReadbackMatches                bool   `json:"readbackMatches"`
	ReadbackEmpty                  bool   `json:"readbackEmpty"`
	OtherContextEmpty              bool   `json:"otherContextEmpty"`
	UnknownAfterPendingEditCovered bool   `json:"unknownAfterPendingEditCovered"`
	OperationPendingObserved       bool   `json:"operationPendingObserved"`
	PostWriteDisconnectObserved    bool   `json:"postWriteDisconnectObserved"`
	ReplayRejected                 bool   `json:"replayRejected"`
}

// Missing false-valued fields, nulls and duplicate keys are not evidence.
// Tokenize the flat envelope before typed decoding; do not log payloads.
func decodeFormalEnvelope(raw []byte, value any) error {
	typ := reflect.TypeOf(value).Elem()
	fields := make(map[string]bool, typ.NumField())
	for i := 0; i < typ.NumField(); i++ {
		fields[typ.Field(i).Tag.Get("json")] = true
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	start, err := d.Token()
	if err != nil || start != json.Delim('{') {
		return errors.New("invalid formal evidence envelope")
	}
	seen := make(map[string]bool)
	for d.More() {
		key, err := d.Token()
		name, ok := key.(string)
		if err != nil || !ok || seen[name] || !fields[name] {
			return errors.New("duplicate or invalid formal evidence field")
		}
		seen[name] = true
		var field json.RawMessage
		if d.Decode(&field) != nil || bytes.Equal(bytes.TrimSpace(field), []byte("null")) {
			return errors.New("null or invalid formal evidence field")
		}
	}
	if _, err = d.Token(); err != nil || len(seen) != len(fields) {
		return errors.New("incomplete formal evidence")
	}
	// Unmarshal verifies EOF; DisallowUnknownFields then verifies field names.
	if !json.Valid(raw) {
		return errors.New("trailing or malformed formal evidence")
	}
	d = json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if d.Decode(value) != nil {
		return errors.New("invalid formal evidence type or field")
	}
	return nil
}


func ValidateCommit(raw []byte) error {
 var r formalResult
 if err:=decodeFormalEnvelope(raw,&r);err!=nil{return err}
 if r.Stage!="result"||r.Scenario!="commit"||!r.ActualDLLLoaded||r.ActivationIdentity!="windows-activated-profile"||!r.Registered||r.SendInput||r.Outcome!="applied"||r.Rejected||r.DuplicateRejected||!r.ReadbackMatches||r.ReadbackEmpty||!r.OtherContextEmpty||r.UnknownAfterPendingEditCovered||r.OperationPendingObserved||r.PostWriteDisconnectObserved||r.ReplayRejected{return errors.New("registered commit not proven")}
 return nil
}
