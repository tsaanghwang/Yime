package touchdiagnostic

import (
	"bufio"
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

const MaxLine = 256
const MaxRecords = 64
const MaxRuns = 16
const MaxFile = MaxLine * MaxRecords

var runName = regexp.MustCompile(`^run-[0-9]{8}T[0-9]{15}Z-[a-f0-9]{16}\.jsonl$`)

// DefaultDirectory belongs to this initiating Windows user, never the install
// root or either standard input product's writable data.
func DefaultDirectory() (string, error) {
	base, err := os.UserCacheDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(base, "YimeCore 18u Touch", "Diagnostics"), nil
}

// DecodeLine rejects, rather than preserves, arbitrary peer text and fields.
// Duplicate keys, nulls, trailing data and invalid numeric codes are rejected.
func DecodeLine(line []byte) (Diagnostic, bool) {
	if len(line) > MaxLine {
		return Diagnostic{}, false
	}
	dec := json.NewDecoder(bytes.NewReader(line))
	token, err := dec.Token()
	if err != nil || token != json.Delim('{') {
		return Diagnostic{}, false
	}
	seen := map[string]bool{}
	var d Diagnostic
	for dec.More() {
		key, err := dec.Token()
		if err != nil {
			return d, false
		}
		k, ok := key.(string)
		if !ok || seen[k] {
			return d, false
		}
		seen[k] = true
		var raw json.RawMessage
		if dec.Decode(&raw) != nil || bytes.Equal(raw, []byte("null")) {
			return d, false
		}
		switch k {
		case "stage":
			if json.Unmarshal(raw, &d.Stage) != nil || !validStage(d.Stage) {
				return d, false
			}
		case "reason":
			if json.Unmarshal(raw, &d.Reason) != nil || !validReason(d.Reason) {
				return d, false
			}
		case "win32", "hresult":
			var n uint32
			if json.Unmarshal(raw, &n) != nil {
				return d, false
			}
			if k == "win32" {
				d.Win32 = &n
			} else {
				d.HRESULT = &n
			}
		default:
			return d, false
		}
	}
	token, err = dec.Token()
	if err != nil || token != json.Delim('}') {
		return d, false
	}
	if dec.Decode(new(any)) != io.EOF {
		return d, false
	}
	return d, seen["stage"] && seen["reason"]
}

// Health is a local launcher->UI status, not an input acknowledgement.
// Saved is increased only after a complete write and successful Sync.
type Health struct {
	State      string      `json:"state"`
	Run        string      `json:"run"`
	Saved      int         `json:"saved"`
	Diagnostic *Diagnostic `json:"diagnostic,omitempty"`
}

func (h Health) Valid() bool {
	return (h.State == "ready" || h.State == "failed" || h.State == "limit") && (h.Run == "" || runName.MatchString(h.Run)) && h.Saved >= 0 && h.Saved <= MaxRecords && (h.Diagnostic == nil || (h.Diagnostic.Stage == "diagnostic-storage" && validReason(h.Diagnostic.Reason)))
}

type Recorder struct {
	mu       sync.Mutex
	file     *os.File
	queue    chan Diagnostic
	done     chan struct{}
	closing  bool
	accepted int
	health   Health
	changed  chan struct{}
}

func OpenRecorder(dir string, directoryError error) *Recorder {
	r := &Recorder{health: Health{State: "ready"}, changed: make(chan struct{}, 1), queue: make(chan Diagnostic, MaxRecords), done: make(chan struct{})}
	defer func() { go r.run() }()
	if directoryError != nil {
		r.fail(directoryError, "storage-open-failed")
		return r
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		r.fail(err, "storage-open-failed")
		return r
	}
	info, err := os.Lstat(dir)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		r.fail(err, "storage-open-failed")
		return r
	}
	names, err := recordFiles(dir)
	if err != nil {
		r.fail(err, "storage-open-failed")
		return r
	}
	// Remove only this recorder's regular files, oldest first. No recursive delete.
	for len(names) >= MaxRuns {
		if err = os.Remove(filepath.Join(dir, names[0])); err != nil {
			r.fail(err, "storage-cleanup-failed")
			return r
		}
		names = names[1:]
	}
	var nonce [8]byte
	if _, err = rand.Read(nonce[:]); err != nil {
		r.fail(err, "storage-open-failed")
		return r
	}
	name := "run-" + strings.ReplaceAll(time.Now().UTC().Format("20060102T150405.000000000Z"), ".", "") + "-" + hex.EncodeToString(nonce[:]) + ".jsonl"
	r.file, err = os.OpenFile(filepath.Join(dir, name), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		r.fail(err, "storage-open-failed")
		return r
	}
	r.health.Run = name
	return r
}
func recordFiles(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if !runName.MatchString(e.Name()) {
			continue
		}
		info, err := e.Info()
		if err != nil {
			return nil, err
		}
		if info.Mode().IsRegular() {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names, nil
}
func (r *Recorder) notify() {
	select {
	case r.changed <- struct{}{}:
	default:
	}
}
func (r *Recorder) fail(err error, reason string) {
	d := FromError(err, "diagnostic-storage", reason)
	r.health.State = "failed"
	r.health.Diagnostic = &d
	r.notify()
}
func (r *Recorder) Health() Health {
	r.mu.Lock()
	defer r.mu.Unlock()
	h := r.health
	if h.Diagnostic != nil {
		d := Sanitize(*h.Diagnostic)
		h.Diagnostic = &d
	}
	return h
}
func (r *Recorder) Changed() <-chan struct{} { return r.changed }

// Enqueue is nonblocking and independent of the disk worker. There are at most
// MaxRecords accepted records across all streams; the queue has that capacity.
func (r *Recorder) append(d Diagnostic) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closing {
		if r.health.State != "failed" {
			r.fail(os.ErrClosed, "storage-write-failed")
		}
		return
	}
	if r.health.State != "ready" {
		return
	}
	if r.accepted >= MaxRecords {
		r.health.State = "limit"
		r.notify()
		return
	}
	select {
	case r.queue <- d:
		r.accepted++
	default:
		r.health.State = "limit"
		r.notify()
	}
}
func (r *Recorder) run() {
	defer close(r.done)
	for d := range r.queue {
		r.mu.Lock()
		failed := r.health.State == "failed"
		r.mu.Unlock()
		if failed {
			continue
		}
		line, _ := json.Marshal(d)
		line = append(line, '\n')
		n, err := r.file.Write(line)
		if err == nil && n != len(line) {
			err = io.ErrShortWrite
		}
		if err == nil {
			err = r.file.Sync()
		}
		r.mu.Lock()
		if err != nil {
			if r.health.State != "failed" {
				r.fail(err, "storage-write-failed")
			}
		} else {
			r.health.Saved++
			r.notify()
		}
		r.mu.Unlock()
	}
	if r.file != nil {
		if err := r.file.Close(); err != nil {
			r.mu.Lock()
			if r.health.State != "failed" {
				r.fail(err, "storage-write-failed")
			}
			r.mu.Unlock()
		}
	}
}

// Close is bounded even if storage stalls. A pending write is never reported as
// saved. The worker owns file lifetime and may finish later; inputs are not retried.
func (r *Recorder) Close() {
	r.mu.Lock()
	if !r.closing {
		r.closing = true
		close(r.queue)
	}
	r.mu.Unlock()
	select {
	case <-r.done:
	case <-time.After(time.Second):
		r.mu.Lock()
		if r.health.State != "failed" {
			r.fail(nil, "storage-close-pending")
		}
		r.mu.Unlock()
	}
}

// A distinct stream per child prevents interleaved/partial lines. Always accept
// all bytes, including after storage failure, so io.Copy keeps draining stderr.
func (r *Recorder) Stream() io.Writer { return &recordStream{recorder: r} }

type recordStream struct {
	recorder  *Recorder
	line      []byte
	oversized bool
}

func (s *recordStream) Write(p []byte) (int, error) {
	for _, b := range p {
		if b == '\n' {
			if !s.oversized {
				if d, ok := DecodeLine(s.line); ok {
					s.recorder.append(d)
				}
			}
			s.line = nil
			s.oversized = false
			continue
		}
		if s.oversized {
			continue
		}
		if len(s.line) >= MaxLine {
			s.line = nil
			s.oversized = true
			continue
		}
		s.line = append(s.line, b)
	}
	return len(p), nil
}

// ReadRecent bounds both file count and file bytes. It revalidates every record;
// a manually modified diagnostic file can never turn this viewer into a text log.
func ReadRecent(dir string) ([]Diagnostic, error) {
	names, err := recordFiles(dir)
	if err != nil {
		return nil, err
	}
	if len(names) > MaxRuns {
		names = names[len(names)-MaxRuns:]
	}
	var result []Diagnostic
	for _, name := range names {
		f, err := os.Open(filepath.Join(dir, name))
		if err != nil {
			return nil, err
		}
		info, err := f.Stat()
		if err != nil || !info.Mode().IsRegular() || info.Size() > MaxFile {
			f.Close()
			return nil, errors.New("diagnostic file exceeds limit")
		}
		scanner := bufio.NewScanner(io.LimitReader(f, MaxFile+1))
		scanner.Buffer(make([]byte, MaxLine+1), MaxLine+1)
		count := 0
		for scanner.Scan() {
			count++
			if count > MaxRecords {
				f.Close()
				return nil, errors.New("diagnostic record limit")
			}
			if d, ok := DecodeLine(scanner.Bytes()); ok {
				result = append(result, d)
			}
		}
		err = scanner.Err()
		closeErr := f.Close()
		if err != nil {
			return nil, err
		}
		if closeErr != nil {
			return nil, closeErr
		}
	}
	return result, nil
}

// Status transport is bounded and carries no path or arbitrary error text.
func ReadHealth(input io.Reader, accept func(Health)) {
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 1024), 1024)
	for scanner.Scan() {
		var h Health
		dec := json.NewDecoder(bytes.NewReader(scanner.Bytes()))
		dec.DisallowUnknownFields()
		if dec.Decode(&h) == nil && dec.Decode(new(any)) == io.EOF && h.Valid() {
			accept(h)
		}
	}
}
func WriteHealth(output io.Writer, h Health) error {
	if !h.Valid() {
		return fmt.Errorf("invalid diagnostic health")
	}
	return json.NewEncoder(output).Encode(h)
}
