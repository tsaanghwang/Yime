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

// MaxRuns includes active owners. Active runs are never pruned, so while an old
// run is active the remaining slots hold the newest inactive runs. Once those
// owners close, the next allocation again retains the newest MaxRuns identities.
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
		case "reported":
			origin, valid := decodeReportOrigin(raw)
			if !valid {
				return d, false
			}
			d.Reported = origin
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
	return d, seen["stage"] && seen["reason"] && (d.Reported == nil || d.Stage == "tip-discovery")
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
	active   *os.File
	dir      string
	name     string
	queue    chan Diagnostic
	done     chan struct{}
	closing  bool
	accepted int
	health   Health
	changed  chan struct{}
}

func OpenRecorder(dir string, directoryError error) *Recorder {
	return openRecorder(dir, directoryError, time.Now, rand.Reader)
}

// The clock and random source are per-open inputs so tests never replace process
// globals. A directory lock orders allocation and retention across processes.
func openRecorder(dir string, directoryError error, now func() time.Time, random io.Reader) *Recorder {
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
	lock, err := lockRecordDirectory(dir)
	if err != nil {
		r.fail(err, "storage-open-failed")
		return r
	}
	defer func() {
		if err := lock.Close(); err != nil && r.health.State != "failed" {
			r.fail(err, "storage-open-failed")
		}
	}()
	names, err := recordFiles(dir)
	if err != nil {
		r.fail(err, "storage-open-failed")
		return r
	}
	name, err := nextRecordName(names, now(), random)
	if err != nil {
		r.fail(err, "storage-open-failed")
		return r
	}
	if err := cleanupOrphanRecordMarkers(dir); err != nil {
		r.fail(err, "storage-cleanup-failed")
		return r
	}
	marker, err := lockRecordPath(activeRecordPath(dir, name), recordLockCreateNew)
	if err != nil {
		r.fail(err, "storage-open-failed")
		return r
	}
	var file *os.File
	keep := false
	defer func() {
		if keep {
			return
		}
		// Roll back only files created by this attempt. Prior evidence is never
		// removed merely because creating the new run failed.
		if file != nil {
			file.Close()
			if err := os.Remove(filepath.Join(dir, name)); err != nil && r.health.State != "failed" {
				r.fail(err, "storage-cleanup-failed")
			}
		}
		marker.Close()
		if err := os.Remove(activeRecordPath(dir, name)); err != nil && r.health.State != "failed" {
			r.fail(err, "storage-cleanup-failed")
		}
	}()
	if err = marker.Sync(); err != nil {
		r.fail(err, "storage-open-failed")
		return r
	}
	file, err = os.OpenFile(filepath.Join(dir, name), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		r.fail(err, "storage-open-failed")
		return r
	}
	// Both new files exist before considering any removal. Discover enough
	// inactive victims first, so contention cannot delete only part of history.
	// Protecting an older active run deliberately takes precedence over keeping
	// the newest MaxRuns identities; all-active capacity fails without eviction.
	needed := len(names) + 1 - MaxRuns
	type victim struct {
		name   string
		marker bool
	}
	var victims []victim
	for _, old := range names {
		if len(victims) >= needed {
			break
		}
		active, marked, err := activeRecord(dir, old)
		if err != nil {
			r.fail(err, "storage-cleanup-failed")
			return r
		}
		if !active {
			victims = append(victims, victim{old, marked})
		}
	}
	if len(victims) < needed {
		r.fail(ErrStorageBusy, "storage-cleanup-failed")
		return r
	}
	for _, old := range victims {
		if err = os.Remove(filepath.Join(dir, old.name)); err != nil {
			r.fail(err, "storage-cleanup-failed")
			return r
		}
		if old.marker {
			if err = os.Remove(activeRecordPath(dir, old.name)); err != nil {
				r.fail(err, "storage-cleanup-failed")
				return r
			}
		}
	}
	r.file, r.active, r.dir, r.name = file, marker, dir, name
	r.health.Run = name
	keep = true
	return r
}

const recordTimeLayout = "20060102T150405.000000000Z"
const maxRecordFuture = 24 * time.Hour

func recordTime(name string) (time.Time, error) {
	if !runName.MatchString(name) {
		return time.Time{}, errors.New("invalid diagnostic run name")
	}
	stamp := name[4:29]
	return time.Parse(recordTimeLayout, stamp[:15]+"."+stamp[15:])
}

func nextRecordName(names []string, now time.Time, random io.Reader) (string, error) {
	if err := validateRecordTimes(names, now); err != nil {
		return "", err
	}
	next := now.UTC()
	for _, name := range names {
		previous, err := recordTime(name)
		if err != nil {
			return "", errors.New("invalid diagnostic run time")
		}
		if !next.After(previous) {
			next = previous.Add(time.Nanosecond)
		}
	}
	if next.Year() < 0 || next.Year() > 9999 {
		return "", errors.New("diagnostic run time out of range")
	}
	if next.After(now.Add(maxRecordFuture)) {
		return "", errors.New("diagnostic logical time exceeds future limit")
	}
	var nonce [8]byte
	if _, err := io.ReadFull(random, nonce[:]); err != nil {
		return "", err
	}
	return "run-" + strings.ReplaceAll(next.Format(recordTimeLayout), ".", "") + "-" + hex.EncodeToString(nonce[:]) + ".jsonl", nil
}

func validateRecordTimes(names []string, now time.Time) error {
	if now.Year() < 0 || now.Year() > 9999 {
		return errors.New("diagnostic clock out of range")
	}
	for _, name := range names {
		stamp, err := recordTime(name)
		if err != nil {
			return errors.New("invalid diagnostic run time")
		}
		if stamp.After(now.Add(maxRecordFuture)) {
			return errors.New("diagnostic run time is unexpectedly far in the future")
		}
	}
	return nil
}

// Older files can share a timestamp; their original order cannot be recovered
// from random suffixes. Keep their existing lexical order, but allocate every
// new run strictly after all existing timestamps, even when the clock regresses.
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
			if _, err := recordTime(e.Name()); err != nil {
				return nil, errors.New("invalid diagnostic run time")
			}
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
	if errors.Is(err, ErrStorageBusy) {
		reason = "storage-busy"
	}
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
		lock, err := lockRecordDirectory(r.dir)
		if err != nil {
			r.storageFailure(err, "storage-write-failed")
			r.abandonRecord()
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
		if err != nil {
			// Publish incomplete status before another reader can obtain the
			// directory lock, including when a whole line failed to Sync.
			r.storageFailure(err, "storage-write-failed")
			r.abandonRecord()
		}
		if closeErr := lock.Close(); err == nil {
			err = closeErr
		}
		if err != nil {
			r.storageFailure(err, "storage-write-failed")
			r.abandonRecord()
			continue
		}
		r.mu.Lock()
		r.health.Saved++
		r.notify()
		r.mu.Unlock()
	}
	r.finishRecord()
}

func (r *Recorder) storageFailure(err error, reason string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.health.State != "failed" {
		r.fail(err, reason)
	}
}

// Only the disk worker owns this handle after OpenRecorder returns. Its marker
// stays on disk when a write or close is uncertain; there is no retry.
func (r *Recorder) abandonActive() {
	if r.active != nil {
		if err := r.active.Close(); err != nil {
			r.storageFailure(err, "storage-write-failed")
		}
		r.active = nil
	}
}

func (r *Recorder) abandonRecord() {
	if r.file != nil {
		if err := r.file.Close(); err != nil {
			r.storageFailure(err, "storage-write-failed")
		}
		r.file = nil
	}
	r.abandonActive()
}

func (r *Recorder) finishRecord() {
	if r.file == nil {
		return
	}
	lock, err := lockRecordDirectory(r.dir)
	if err != nil {
		r.storageFailure(err, "storage-write-failed")
		r.abandonRecord()
		return
	}
	if err := r.file.Sync(); err != nil {
		r.storageFailure(err, "storage-write-failed")
	}
	if err := r.file.Close(); err != nil {
		r.storageFailure(err, "storage-write-failed")
	}
	r.abandonActive()
	r.mu.Lock()
	complete := r.health.State != "failed"
	r.mu.Unlock()
	if complete {
		if err := os.Remove(activeRecordPath(r.dir, r.name)); err != nil {
			r.storageFailure(err, "storage-write-failed")
		}
	}
	if err := lock.Close(); err != nil {
		r.storageFailure(err, "storage-write-failed")
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
func ReadRecent(dir string) (result []Diagnostic, err error) {
	return readRecent(dir, time.Now, readRecordFile)
}

func readRecent(dir string, now func() time.Time, read func(string) ([]byte, error)) (result []Diagnostic, err error) {
	lock, err := lockRecordDirectory(dir)
	if err != nil {
		return nil, err
	}
	defer func() {
		if closeErr := lock.Close(); err == nil {
			err = closeErr
		}
	}()
	names, err := recordFiles(dir)
	if err != nil {
		return nil, err
	}
	if err := validateRecordTimes(names, now()); err != nil {
		return nil, err
	}
	if len(names) > MaxRuns {
		names = names[len(names)-MaxRuns:]
	}
	for _, name := range names {
		active, marked, err := activeRecord(dir, name)
		if err != nil {
			return nil, err
		}
		if marked && !active {
			return nil, ErrIncompleteRun
		}
		// An active writer can only Write+Sync while holding this same lock.
		// Its complete prefix is stable for the entire bounded read.
		raw, err := read(filepath.Join(dir, name))
		if err != nil {
			return nil, err
		}
		if len(raw) == 0 {
			continue
		}
		if len(raw) > MaxFile || raw[len(raw)-1] != '\n' {
			return nil, ErrIncompleteRun
		}
		lines := bytes.Split(raw[:len(raw)-1], []byte{'\n'})
		if len(lines) > MaxRecords {
			return nil, errors.New("diagnostic record limit")
		}
		for _, line := range lines {
			if len(line) > MaxLine {
				return nil, errors.New("diagnostic line exceeds limit")
			}
			if d, ok := DecodeLine(line); ok {
				result = append(result, d)
			}
		}
	}
	return result, nil
}

func readRecordFile(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() > MaxFile {
		f.Close()
		return nil, errors.New("diagnostic file exceeds limit")
	}
	raw, err := io.ReadAll(io.LimitReader(f, MaxFile+1))
	closeErr := f.Close()
	if err != nil {
		return nil, err
	}
	if closeErr != nil {
		return nil, closeErr
	}
	return raw, nil
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
