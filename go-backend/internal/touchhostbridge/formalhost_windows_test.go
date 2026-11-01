//go:build windows && amd64

package touchhostbridge

import (
	"bufio"
	"context"
	"encoding/csv"
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

	codemode "github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
)

// This gate starts actual separately built 18u TIP/Broker binaries. No registry
// writes, installed-profile activation, existing document or user process target.
// Run only in isolated Windows CI. These are not registered-host acceptance tests.
func TestNativeFormal18uTIP(t *testing.T) {
	names := []string{"YIME_FORMAL_18U_HOST", "YIME_FORMAL_18U_DLL", "YIME_FORMAL_18U_BROKER", "YIME_FORMAL_18U_DATA"}
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
	for _, scenario := range []string{"commit", "duplicate", "wrong-server-pid", "wrong-server-image", "deactivated", "focus-lost", "disconnect-before-action"} {
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
				t.Fatal("native connect response missing")
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
			hin.Close()
			line, e = formalReadLine(ctx, hr)
			if e != nil {
				t.Fatal("native final result missing; no replay")
			}
			var result struct {
				Stage                          string `json:"stage"`
				Scenario                       string `json:"scenario"`
				ActualDLLLoaded                bool   `json:"actualDLLLoaded"`
				Registered                     bool   `json:"registered"`
				SendInput                      bool   `json:"sendInput"`
				Outcome                        string `json:"outcome"`
				Rejected                       bool   `json:"rejected"`
				DuplicateRejected              bool   `json:"duplicateRejected"`
				ReadbackMatches                bool   `json:"readbackMatches"`
				ReadbackEmpty                  bool   `json:"readbackEmpty"`
				OtherContextEmpty              bool   `json:"otherContextEmpty"`
				UnknownAfterPendingEditCovered bool   `json:"unknownAfterPendingEditCovered"`
			}
			decoder := json.NewDecoder(strings.NewReader(string(line)))
			decoder.DisallowUnknownFields()
			if e = decoder.Decode(&result); e != nil {
				t.Fatal("invalid native result")
			}
			if result.Stage != "result" || result.Scenario != scenario || !result.ActualDLLLoaded || result.Registered || result.SendInput || !result.OtherContextEmpty || result.UnknownAfterPendingEditCovered {
				t.Fatal("native scope or identity mismatch")
			}
			if scenario == "commit" || scenario == "duplicate" {
				if result.Outcome != "applied" || !result.ReadbackMatches || result.Rejected || result.ReadbackEmpty || scenario == "duplicate" && !result.DuplicateRejected {
					t.Fatal("actual commit/readback or duplicate rejection not proven")
				}
			} else if !result.Rejected || !result.ReadbackEmpty || result.Outcome == "applied" {
				t.Fatal("negative case wrote or was accepted")
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
func formalCanonicalNi(root string) (string, error) {
	raw, e := os.ReadFile(filepath.Join(root, "prototypes/touch-terminal/encoding/yime_yinyuan_layout.json"))
	if e != nil {
		return "", e
	}
	var layout struct {
		Keys map[string]string `json:"yinyuan_id_to_key"`
	}
	if e = json.Unmarshal(raw, &layout); e != nil {
		return "", e
	}
	f, e := os.Open(filepath.Join(root, "internal_data/yime_syllable_decomposition.tsv"))
	if e != nil {
		return "", e
	}
	defer f.Close()
	r := csv.NewReader(f)
	r.Comma = '\t'
	head, e := r.Read()
	if e != nil {
		return "", e
	}
	cols := map[string]int{}
	for i, k := range head {
		cols[k] = i
	}
	for _, k := range []string{"pinyin_tone", "status", "shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
		if _, ok := cols[k]; !ok {
			return "", errors.New("canonical column missing")
		}
	}
	for {
		row, e := r.Read()
		if e != nil {
			if e == io.EOF {
				return "", errors.New("canonical ni3 absent")
			}
			return "", e
		}
		if row[cols["pinyin_tone"]] != "ni3" {
			continue
		}
		if row[cols["status"]] != "ok" {
			return "", errors.New("ni3 not admitted")
		}
		full := ""
		for _, k := range []string{"shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
			v := layout.Keys[row[cols[k]]]
			if len(v) != 1 {
				return "", errors.New("projection incomplete")
			}
			full += v
		}
		record, e := codemode.BuildRecord(full)
		return record.Variable, e
	}
}
