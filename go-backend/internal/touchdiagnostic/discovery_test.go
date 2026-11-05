package touchdiagnostic

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

func discoveryTestFrame(body string) []byte {
	return []byte("{\"operation\":\"diagnostic\",\"version\":1,\"diagnostic\":" + body + "}")
}

func TestDiscoveryFrameAcceptsOnlyApplicableCodes(t *testing.T) {
	for _, tc := range []struct {
		reason string
		codes  string
	}{
		{"tip-not-focused", ""},
		{"foreground-missing", ""},
		{"foreground-query-failed", ""},
		{"foreground-other-process", ""},
		{"foreground-thread-mismatch", ""},
		{"tsf-document-missing", ""},
		{"tsf-context-missing", ""},
		{"get-focus-failed", ",\"hresult\":2147500037"},
		{"get-top-failed", ",\"hresult\":2147483648"},
		{"tip-endpoint-unavailable", ",\"win32\":2"},
	} {
		t.Run(tc.reason, func(t *testing.T) {
			body := "{\"stage\":\"tip-discovery\",\"reason\":\"" + tc.reason + "\"" + tc.codes + "}"
			var expected Diagnostic
			if err := json.Unmarshal([]byte(body), &expected); err != nil {
				t.Fatal(err)
			}
			d, ok := DecodeDiscoveryFrame(discoveryTestFrame(body))
			if !ok || !reflect.DeepEqual(d, expected) || d.Reported != nil {
				t.Fatalf("valid report changed or acquired untrusted origin: %#v, %v", d, ok)
			}
		})
	}
}

func TestDiscoveryFrameRejectsCrossReasonCodes(t *testing.T) {
	for _, reason := range []string{"tip-not-focused", "foreground-missing", "foreground-query-failed", "foreground-other-process", "foreground-thread-mismatch", "tsf-document-missing", "tsf-context-missing"} {
		for _, codes := range []string{",\"win32\":0", ",\"win32\":5", ",\"hresult\":2147500037", ",\"win32\":5,\"hresult\":2147500037"} {
			body := "{\"stage\":\"tip-discovery\",\"reason\":\"" + reason + "\"" + codes + "}"
			if _, ok := DecodeDiscoveryFrame(discoveryTestFrame(body)); ok {
				t.Fatalf("code accepted for %s", reason)
			}
		}
	}
	for _, reason := range []string{"get-focus-failed", "get-top-failed"} {
		for _, codes := range []string{"", ",\"hresult\":0", ",\"hresult\":1", ",\"hresult\":2147483647", ",\"win32\":5", ",\"win32\":5,\"hresult\":2147500037"} {
			body := "{\"stage\":\"tip-discovery\",\"reason\":\"" + reason + "\"" + codes + "}"
			if _, ok := DecodeDiscoveryFrame(discoveryTestFrame(body)); ok {
				t.Fatalf("missing, successful, or mismatched HRESULT accepted for %s", reason)
			}
		}
	}
	for _, codes := range []string{"", ",\"hresult\":2147500037", ",\"win32\":5,\"hresult\":2147500037"} {
		body := "{\"stage\":\"tip-discovery\",\"reason\":\"tip-endpoint-unavailable\"" + codes + "}"
		if _, ok := DecodeDiscoveryFrame(discoveryTestFrame(body)); ok {
			t.Fatal("endpoint report accepted without its exclusive Win32 code")
		}
	}
}

func TestDiscoveryFrameRejectsUntrustedFieldsAndValues(t *testing.T) {
	const body = "{\"stage\":\"tip-discovery\",\"reason\":\"tip-not-focused\"}"
	valid := string(discoveryTestFrame(body))
	cases := map[string]string{
		"missing-operation":    "{\"version\":1,\"diagnostic\":" + body + "}",
		"missing-version":      "{\"operation\":\"diagnostic\",\"diagnostic\":" + body + "}",
		"missing-diagnostic":   "{\"operation\":\"diagnostic\",\"version\":1}",
		"duplicate-operation":  strings.Replace(valid, "\"operation\":", "\"operation\":\"diagnostic\",\"operation\":", 1),
		"duplicate-version":    strings.Replace(valid, "\"version\":1", "\"version\":1,\"version\":1", 1),
		"duplicate-diagnostic": strings.TrimSuffix(valid, "}") + ",\"diagnostic\":" + body + "}",
		"extra-field":          strings.TrimSuffix(valid, "}") + ",\"private\":\"PRIVATE\"}",
		"null-operation":       strings.Replace(valid, "\"operation\":\"diagnostic\"", "\"operation\":null", 1),
		"null-diagnostic":      "{\"operation\":\"diagnostic\",\"version\":1,\"diagnostic\":null}",
		"wrong-operation":      strings.Replace(valid, "\"operation\":\"diagnostic\"", "\"operation\":\"next\"", 1),
		"array":                "[" + valid + "]",
		"pasted-frames":        valid + "\n" + valid,
		"trailing-null":        valid + " null",
		"truncated":            strings.TrimSuffix(valid, "}"),
	}
	for _, version := range []string{"null", "0", "2", "-1", "1.5", "4294967296", "\"1\"", "true", "{}"} {
		cases["version-"+version] = strings.Replace(valid, "\"version\":1", "\"version\":"+version, 1)
	}
	for name, frame := range cases {
		t.Run(name, func(t *testing.T) {
			if _, ok := DecodeDiscoveryFrame([]byte(frame)); ok {
				t.Fatal("malformed or non-version-1 frame accepted")
			}
		})
	}
	for _, invalid := range []string{
		"{\"stage\":null,\"reason\":\"tip-not-focused\"}",
		"{\"stage\":\"tip-discovery\",\"reason\":null}",
		"{\"stage\":\"tip-discovery\"}",
		"{\"reason\":\"tip-not-focused\"}",
		"{\"stage\":\"broker-select\",\"reason\":\"tip-not-focused\"}",
		"{\"stage\":\"tip-discovery\",\"reason\":\"operation-failed\"}",
		"{\"stage\":\"PRIVATE\",\"reason\":\"PRIVATE\"}",
		"{\"stage\":\"tip-discovery\",\"stage\":\"tip-discovery\",\"reason\":\"tip-not-focused\"}",
		"{\"stage\":\"tip-discovery\",\"reason\":\"tip-not-focused\",\"reason\":\"tip-not-focused\"}",
		"{\"stage\":\"tip-discovery\",\"reason\":\"tip-not-focused\",\"text\":\"PRIVATE\"}",
		"{\"stage\":\"tip-discovery\",\"reason\":\"tip-not-focused\",\"reported\":null}",
		"{\"stage\":\"tip-discovery\",\"reason\":\"tip-not-focused\",\"reported\":{\"at\":1793793600000,\"event\":\"0123456789abcdef0123456789abcdef\",\"pid\":1234,\"created\":134545038867431425}}",
		"{\"stage\":\"tip-discovery\",\"reason\":\"tip-endpoint-unavailable\",\"win32\":2,\"win32\":2}",
		"{\"stage\":\"tip-discovery\",\"reason\":\"get-focus-failed\",\"hresult\":2147500037,\"hresult\":2147500037}",
	} {
		if _, ok := DecodeDiscoveryFrame(discoveryTestFrame(invalid)); ok {
			t.Fatal("invalid diagnostic object or client-supplied origin accepted")
		}
	}
	for _, code := range []string{"null", "-1", "4294967296", "5.5", "\"5\"", "true", "[]"} {
		for _, tc := range []struct{ reason, field string }{{"get-top-failed", "hresult"}, {"tip-endpoint-unavailable", "win32"}} {
			body := "{\"stage\":\"tip-discovery\",\"reason\":\"" + tc.reason + "\",\"" + tc.field + "\":" + code + "}"
			if _, ok := DecodeDiscoveryFrame(discoveryTestFrame(body)); ok {
				t.Fatalf("invalid numeric code accepted for %s", tc.reason)
			}
		}
	}
}

func TestDiscoveryFrameBoundsOuterAndInnerObjects(t *testing.T) {
	const body = "{\"stage\":\"tip-discovery\",\"reason\":\"tip-not-focused\"}"
	frame := discoveryTestFrame(body)
	frame = append(frame, []byte(strings.Repeat(" ", MaxLine+64-len(frame)))...)
	if len(frame) != MaxLine+64 {
		t.Fatal("invalid boundary fixture")
	}
	if _, ok := DecodeDiscoveryFrame(frame); !ok {
		t.Fatal("valid frame at byte limit rejected")
	}
	if _, ok := DecodeDiscoveryFrame(append(frame, ' ')); ok {
		t.Fatal("oversized frame accepted")
	}
	inner := strings.TrimSuffix(body, "}") + strings.Repeat(" ", MaxLine+1-len(body)) + "}"
	if len(inner) != MaxLine+1 || len(discoveryTestFrame(inner)) > MaxLine+64 {
		t.Fatal("invalid inner boundary fixture")
	}
	if _, ok := DecodeDiscoveryFrame(discoveryTestFrame(inner)); ok {
		t.Fatal("oversized diagnostic accepted inside bounded frame")
	}
}
