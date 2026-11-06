//go:build windows && amd64

package touchhostbridge

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
)

// This gate starts actual separately built 18u TIP/Broker binaries. No registry
// writes, installed-profile activation, existing document or user process target.
// Run only in isolated Windows CI. These are not registered-host acceptance tests.
func TestNativeFormal18uTIP(t *testing.T) {
	testNativeFormal18uTIP(t, false)
}

// Separate opt-in gate for an already provisioned disposable registration.
// This test does not register/enable anything and never falls back to direct load.
func TestNativeRegisteredFormal18uTIP(t *testing.T) {
	if os.Getenv("YIME_REGISTERED_FORMAL_18U_HOST") == "" {
		t.Skip("registered native gate not selected; provisioning and execution require separate authorization")
	}
	testNativeFormal18uTIP(t, true)
}

func testNativeFormal18uTIP(t *testing.T, registered bool) {
	names := []string{"YIME_FORMAL_18U_HOST", "YIME_FORMAL_18U_DLL", "YIME_FORMAL_18U_BROKER", "YIME_FORMAL_18U_DATA"}
	if registered {
		names[0] = "YIME_REGISTERED_FORMAL_18U_HOST"
	}
	enabled := false
	for _, n := range names {
		enabled = enabled || os.Getenv(n) != ""
	}
	if !enabled {
		t.Skip("formal native gate not selected; CI must provide all four explicit absolute inputs")
	}
	paths := map[string]string{}
	for _, n := range names {
		p := os.Getenv(n)
		if p == "" || !filepath.IsAbs(p) {
			t.Fatalf("%s must be explicitly absolute", n)
		}
		st, e := os.Stat(p)
		if e != nil {
			t.Fatalf("%s missing", n)
		}
		if n == "YIME_FORMAL_18U_DATA" {
			if !st.IsDir() {
				t.Fatal("data must be directory")
			}
		} else if !st.Mode().IsRegular() {
			t.Fatalf("%s not regular file", n)
		}
		paths[n] = p
	}
	root, e := os.Getwd()
	if e != nil {
		t.Fatal(e)
	}
	for {
		if _, e = os.Stat(filepath.Join(root, "tools/yimecore/18u-touch-product.json")); e == nil {
			break
		}
		up := filepath.Dir(root)
		if up == root {
			t.Fatal("dedicated source root missing")
		}
		root = up
	}
	code, e := formalCanonicalNi(root)
	if e != nil {
		t.Fatal(e)
	}
	for _, scenario := range formalScenarios {
		t.Run(scenario, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
			defer cancel()
			dir := t.TempDir()
			host := exec.CommandContext(ctx, paths[names[0]])
			host.Dir = dir
			hin, e := host.StdinPipe()
			if e != nil {
				t.Fatal(e)
			}
			hout, e := host.StdoutPipe()
			if e != nil {
				t.Fatal(e)
			}
			var hostErr limitedOutput
			host.Stderr = &hostErr
			if e = host.Start(); e != nil {
				t.Fatal("native host did not start")
			}
			hostDone := false
			defer func() {
				hin.Close()
				if !hostDone {
					_ = host.Process.Kill()
					_ = host.Wait()
				}
			}()
			pipe := fmt.Sprintf(`\\.\pipe\YimeBroker.18uTouch.v1.gate-%d-%d`, os.Getpid(), time.Now().UnixNano())
			broker := exec.CommandContext(ctx, paths[names[2]], "--root", root, "--data-dir", paths[names[3]], "--pipe-name", pipe, "--tip-host-pid", strconv.Itoa(host.Process.Pid))
			broker.Dir = dir
			bout, e := broker.StdoutPipe()
			if e != nil {
				t.Fatal(e)
			}
			var brokerErr limitedOutput
			broker.Stderr = &brokerErr
			if e = broker.Start(); e != nil {
				t.Fatal("dedicated broker did not start")
			}
			brokerDone := false
			defer func() {
				if !brokerDone {
					_ = broker.Process.Kill()
					_ = broker.Wait()
				}
			}()
			br := bufio.NewReaderSize(bout, 65537)
			if line, e := formalReadLine(ctx, br); e != nil || string(line) != "READY yimebroker-18u" {
				t.Fatal("dedicated broker readiness failed (raw output withheld)")
			}
			config := map[string]any{"scenario": scenario, "dll": paths[names[1]], "pipe": pipe, "brokerPID": broker.Process.Pid, "brokerImage": paths[names[2]], "code": code}
			if e = json.NewEncoder(hin).Encode(config); e != nil {
				t.Fatal("native configuration write")
			}
			hr := bufio.NewReaderSize(hout, 65537)
			line, e := formalReadLine(ctx, hr)
			if e != nil {
				_ = host.Wait() // joins stderr copier before reading the bounded buffer
				hostDone = true
				t.Fatalf("native connect response missing: %s", formalFailureSummary(hostErr.Bytes()))
			}
			var connected struct {
				Stage    string `json:"stage"`
				Accepted bool   `json:"accepted"`
			}
			if e = json.Unmarshal(line, &connected); e != nil || connected.Stage != "connected" {
				t.Fatal("native connect response malformed")
			}
			if connected.Accepted != (scenario != "wrong-server-pid" && scenario != "wrong-server-image") {
				t.Fatal("server identity acceptance mismatch")
			}
			if scenario == "disconnect-before-action" {
				_ = broker.Process.Kill()
				_ = broker.Wait()
				brokerDone = true
			}
			if e = json.NewEncoder(hin).Encode(map[string]bool{"proceed": true}); e != nil {
				t.Fatal("native continuation write")
			}
			if scenario == "disconnect-after-edit" {
				barrier, err := formalReadLine(ctx, hr)
				if err != nil || validateFormalPostWriteBarrier(barrier) != nil {
					t.Fatal("actual edit/readback barrier missing; no forced disconnect or replay")
				}
				// Only our own broker child, after the host independently observed
				// its actual text. The TIP has not sent its completion yet.
				if err := broker.Process.Kill(); err != nil {
					t.Fatal("could not stop owned broker at post-write barrier")
				}
				_ = broker.Wait()
				brokerDone = true
				if err := json.NewEncoder(hin).Encode(map[string]bool{"brokerStopped": true}); err != nil {
					t.Fatal("post-write continuation failed")
				}
			}
			hin.Close()
			line, e = formalReadLine(ctx, hr)
			if e != nil {
				_ = host.Wait() // joins stderr copier; context bounds a stuck child
				hostDone = true
				t.Fatalf("native final result missing; no replay: %s", formalFailureSummary(hostErr.Bytes()))
			}
			if err := validateFormalResult(line, scenario, registered); err != nil {
				t.Fatal(err)
			}
			// Drain stdout before Wait closes StdoutPipe; the process deadline bounds EOF.
			if extra, e := hr.ReadByte(); e != io.EOF {
				_ = extra
				t.Fatal("extra native output")
			}
			if e = host.Wait(); e != nil {
				hostDone = true
				t.Fatalf("native host failed (stderr bytes=%d)", hostErr.Len())
			}
			hostDone = true
			if !brokerDone {
				if e = broker.Wait(); e != nil {
					brokerDone = true
					t.Fatal("broker did not exit normally after own host exit")
				}
				brokerDone = true
			}
		})
	}
}

func formalReadLine(ctx context.Context, r *bufio.Reader) ([]byte, error) {
	type answer struct {
		line []byte
		err  error
	}
	ch := make(chan answer, 1)
	go func() {
		b, e := r.ReadSlice('\n')
		if len(b) > 65536 {
			e = errors.New("bounded line exceeded")
		}
		if e == nil {
			b = b[:len(b)-1]
		}
		ch <- answer{append([]byte(nil), b...), e}
	}()
	select {
	case x := <-ch:
		return x.line, x.err
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

// Derive ni3 from admitted canonical decomposition and the actual isolated
// projection, never from output dictionary codes or a guessed keyboard string.
func formalCanonicalNi(root string) (string,error) { return installed18uhost.CanonicalNi(root) }

// Parse only the native harness's fixed diagnostic vocabulary, never echo raw stderr.
func formalFailureSummary(raw []byte) string {
	type diagnostic struct {
		Stage string  `json:"stage"`
		Kind  string  `json:"kind"`
		Code  *uint32 `json:"code"`
	}
	var d diagnostic
	decoder := json.NewDecoder(strings.NewReader(string(raw)))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&d) != nil || d.Code == nil {
		return "diagnostic unavailable"
	}
	var second diagnostic
	secondErr := decoder.Decode(&second)
	probeSummary := ""
	if secondErr != io.EOF {
		probes := map[string]bool{
			"activation-probe/null-manager":            true,
			"activation-probe/null-client":             true,
			"activation-probe/already-active":          true,
			"activation-probe/query-keystroke-manager": true,
			"activation-probe/advise-key-event-sink":   true,
			"activation-probe/thread-observer":         true,
			"activation-probe/function-provider":       true,
		}
		if secondErr != nil || !probes[d.Stage] || d.Kind != "hresult" || *d.Code < 0x80000000 || second.Stage != "actual TIP activation" || second.Kind != "hresult" || second.Code == nil || *second.Code != *d.Code {
			return "diagnostic unavailable"
		}
		var extra any
		if decoder.Decode(&extra) != io.EOF {
			return "diagnostic unavailable"
		}
		probeSummary = fmt.Sprintf("stage=%s kind=hresult code=0x%08X; ", d.Stage, *d.Code)
		d = second
	}
	allowed := map[string]bool{
		"action did not become pending":            true,
		"restore own focus":                        true,
		"post-write disconnect control":            true,
		"lost completion not unknown":              true,
		"unknown outcome replayed":                 true,
		"direct test bypass forbidden":             true,
		"registered profile manager":               true,
		"registered language manager":              true,
		"registered current language":              true,
		"registered language precondition":         true,
		"registered profile query":                 true,
		"registered profile disabled":              true,
		"registered profile activation":            true,
		"registered profile activation incomplete": true,
		"registered provider unavailable":          true,
		"registered active profile":                true,
		"registered profile mismatch":              true,
		"registered provider type":                 true,
		"registered provider mismatch":             true,
		"registered route lookup":                  true,
		"registered TIP interface":                 true,
		"registered DLL mismatch":                  true,
		"UTF8 conversion":                          true,
		"actual TIP activation":                    true,
		"actual TIP instance":                      true,
		"actual edit and completion":               true,
		"allocate dedicated service client ID":     true,
		"associate own window":                     true,
		"canonical ni candidate missing":           true,
		"change own focus":                         true,
		"class factory export":                     true,
		"connect actual Broker":                    true,
		"context":                                  true,
		"control":                                  true,
		"deactivate actual TIP":                    true,
		"dedicated class factory":                  true,
		"dedicated private interface":              true,
		"disconnected action accepted":             true,
		"document":                                 true,
		"duplicate rewrote":                        true,
		"engine input":                             true,
		"engine rejected input":                    true,
		"extended manager":                         true,
		"independent readback mismatch":            true,
		"initialize COM":                           true,
		"input bound":                              true,
		"invalid UTF8":                             true,
		"invalid response":                         true,
		"load dedicated DLL":                       true,
		"missing actual receipt":                   true,
		"missing input":                            true,
		"not actually applied":                     true,
		"open rejected":                            true,
		"own focus":                                true,
		"own foreground not granted; no bypass":    true,
		"own foreground window":                    true,
		"own manager activate":                     true,
		"push":                                     true,
		"query service client IDs":                 true,
		"read edit":                                true,
		"read not completed":                       true,
		"rejected operation wrote":                 true,
		"request read":                             true,
		"scenario":                                 true,
		"stale focus accepted":                     true,
		"thread manager":                           true,
		"unexpected":                               true,
		"wrong server accepted":                    true,
	}
	if !allowed[d.Stage] || (d.Kind != "hresult" && d.Kind != "win32" && d.Kind != "assertion" && d.Kind != "exception") {
		return "diagnostic unavailable"
	}
	return probeSummary + fmt.Sprintf("stage=%s kind=%s code=0x%08X", d.Stage, d.Kind, *d.Code)
}

func TestFormalFailureSummaryPrivacy(t *testing.T) {
	if got := formalFailureSummary([]byte(`{"stage":"actual TIP activation","kind":"hresult","code":2147500037}`)); got != "stage=actual TIP activation kind=hresult code=0x80004005" {
		t.Fatal("fixed diagnostic not retained")
	}
	for _, raw := range []string{`secret`, `{"stage":"C:/private/file","kind":"win32","code":1}`, `{"stage":"unexpected","kind":"exception","code":0,"text":"private"}`, `{"stage":"unexpected","kind":"exception","code":0} trailing`} {
		if formalFailureSummary([]byte(raw)) != "diagnostic unavailable" {
			t.Fatal("untrusted diagnostic escaped")
		}
	}
}

func TestFormalActivationProbePrivacy(t *testing.T) {
	probe := `{"stage":"activation-probe/advise-key-event-sink","kind":"hresult","code":2147942487}`
	final := `{"stage":"actual TIP activation","kind":"hresult","code":2147942487}`
	if got := formalFailureSummary([]byte(probe + "\n" + final)); got != "stage=activation-probe/advise-key-event-sink kind=hresult code=0x80070057; stage=actual TIP activation kind=hresult code=0x80070057" {
		t.Fatal("matched fixed probe not retained")
	}
	for _, raw := range []string{
		probe, final + "\n" + probe, probe + "\n" + final + "\n" + final,
		strings.Replace(probe, "advise-key-event-sink", "private/path", 1) + "\n" + final,
		strings.Replace(probe, "2147942487", "2147500037", 1) + "\n" + final,
		strings.Replace(probe, "hresult", "exception", 1) + "\n" + final,
		strings.Replace(probe, `"code":2147942487`, `"code":2147942487,"text":"private"`, 1) + "\n" + final,
		probe + "\n" + strings.Replace(final, "actual TIP activation", "actual TIP instance", 1),
		`{"stage":"actual TIP activation","kind":"hresult"}`,
	} {
		if formalFailureSummary([]byte(raw)) != "diagnostic unavailable" {
			t.Fatal("invalid probe escaped")
		}
	}
}
