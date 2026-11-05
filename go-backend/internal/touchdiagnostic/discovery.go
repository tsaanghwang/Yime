package touchdiagnostic

import (
	"bytes"
	"encoding/json"
	"io"
)

// DecodeDiscoveryFrame is a terminal, content-free self-report from an
// authenticated host process. It does not establish that a particular TIP DLL
// is loaded, create an eligible peer, or acknowledge a saved diagnostic.
func DecodeDiscoveryFrame(raw []byte) (Diagnostic, bool) {
	if len(raw) > MaxLine+64 {
		return Diagnostic{}, false
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	token, err := dec.Token()
	if err != nil || token != json.Delim('{') {
		return Diagnostic{}, false
	}
	seen := map[string]bool{}
	var diagnostic Diagnostic
	for dec.More() {
		token, err = dec.Token()
		key, ok := token.(string)
		if err != nil || !ok || seen[key] {
			return Diagnostic{}, false
		}
		seen[key] = true
		switch key {
		case "operation":
			var operation string
			if dec.Decode(&operation) != nil || operation != "diagnostic" {
				return Diagnostic{}, false
			}
		case "version":
			var version int
			if dec.Decode(&version) != nil || version != 1 {
				return Diagnostic{}, false
			}
		case "diagnostic":
			var data json.RawMessage
			if dec.Decode(&data) != nil {
				return Diagnostic{}, false
			}
			diagnostic, ok = DecodeLine(data)
			if !ok {
				return Diagnostic{}, false
			}
		default:
			return Diagnostic{}, false
		}
	}
	token, err = dec.Token()
	if err != nil || token != json.Delim('}') || dec.Decode(new(any)) != io.EOF || !seen["operation"] || !seen["version"] || !seen["diagnostic"] || diagnostic.Stage != "tip-discovery" || diagnostic.Reported != nil {
		return Diagnostic{}, false
	}
	switch diagnostic.Reason {
	case "get-focus-failed", "get-top-failed":
		return diagnostic, diagnostic.HRESULT != nil && *diagnostic.HRESULT&0x80000000 != 0 && diagnostic.Win32 == nil
	case "tip-endpoint-unavailable":
		return diagnostic, diagnostic.Win32 != nil && diagnostic.HRESULT == nil
	case "tip-not-focused", "foreground-missing", "foreground-query-failed", "foreground-other-process", "foreground-thread-mismatch", "tsf-document-missing", "tsf-context-missing":
		return diagnostic, diagnostic.HRESULT == nil && diagnostic.Win32 == nil
	}
	return Diagnostic{}, false
}
