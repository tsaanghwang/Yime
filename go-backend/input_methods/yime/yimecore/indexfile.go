package yimecore

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	indexFileMagic      = "YIMEIDX1"
	indexFileVersion    = uint16(1)
	indexFileHeaderSize = 128
	indexModeSize       = 16
	recordHeaderSize    = 12
)

// IndexBuildResult is the deterministic build evidence emitted for one mode.
type IndexBuildResult struct {
	FormatVersion       uint16 `json:"format_version"`
	Mode                string `json:"mode"`
	SourcePath          string `json:"source_path"`
	SourceSHA256        string `json:"source_sha256"`
	SourceBytes         int64  `json:"source_bytes"`
	ParsedRecords       int    `json:"parsed_records"`
	IndexedRecords      int    `json:"indexed_records"`
	DuplicateRecords    int    `json:"duplicate_records"`
	IndexPath           string `json:"index_path"`
	IndexBytes          int64  `json:"index_bytes"`
	RecordPayloadSHA256 string `json:"record_payload_sha256"`
	IndexSHA256         string `json:"index_sha256"`
	BuildElapsedNS      int64  `json:"build_elapsed_ns"`
	PeakObservedHeap    uint64 `json:"peak_observed_heap_bytes"`
}

// FileIndex is an immutable E1 index backed by a validated read-only file and
// a compact uint32 offset table. Keeping the payload out of the Go heap makes
// the experiment comparable with Rime's demand-paged dictionary storage.
type FileIndex struct {
	file          *os.File
	data          []byte
	unmap         func() error
	closeOnce     sync.Once
	mode          string
	sourceHash    [sha256.Size]byte
	payloadHash   [sha256.Size]byte
	offsets       []uint32
	recordsEnd    uint32
	maxCodeBytes  int
	oneByteTop    [256]shortBucket
	twoByteTop    []shortBucket
	twoByteSparse map[uint16]shortBucket
}

type shortBucket struct {
	count     uint8
	positions [defaultCandidateLimit]uint32
}

// BuildIndexFile compiles a Rime dictionary into the independent E1 format.
func BuildIndexFile(mode, sourcePath, outputPath string) (IndexBuildResult, error) {
	started := time.Now()
	mode = strings.TrimSpace(mode)
	if mode == "" || len(mode) > indexModeSize {
		return IndexBuildResult{}, fmt.Errorf("mode must contain 1-%d bytes", indexModeSize)
	}
	if sourcePath == "" || outputPath == "" {
		return IndexBuildResult{}, fmt.Errorf("source and output paths are required")
	}

	entries, sourceHash, sourceBytes, peakHeap, err := readRimeDictionary(sourcePath)
	if err != nil {
		return IndexBuildResult{}, err
	}
	parsedRecords := len(entries)
	index, err := NewIndex(entries)
	if err != nil {
		return IndexBuildResult{}, fmt.Errorf("normalize dictionary: %w", err)
	}
	peakHeap = maxHeap(peakHeap)
	entries = nil

	payload := bytes.NewBuffer(make([]byte, 0, sourceBytes+int64(parsedRecords*recordHeaderSize)))
	offsets := make([]uint32, 0, len(index.records))
	for _, item := range index.records {
		if len(item.code) > math.MaxUint16 || len(item.text) > math.MaxUint16 {
			return IndexBuildResult{}, fmt.Errorf("record exceeds uint16 length: code=%d text=%d", len(item.code), len(item.text))
		}
		absoluteOffset := uint64(indexFileHeaderSize + payload.Len())
		if absoluteOffset > math.MaxUint32 {
			return IndexBuildResult{}, fmt.Errorf("index exceeds uint32 offset range")
		}
		offsets = append(offsets, uint32(absoluteOffset))
		var header [recordHeaderSize]byte
		binary.LittleEndian.PutUint16(header[0:2], uint16(len(item.code)))
		binary.LittleEndian.PutUint16(header[2:4], uint16(len(item.text)))
		binary.LittleEndian.PutUint64(header[4:12], uint64(item.weight))
		payload.Write(header[:])
		payload.WriteString(item.code)
		payload.WriteString(item.text)
	}
	recordsEnd := indexFileHeaderSize + payload.Len()
	for _, offset := range offsets {
		var encoded [4]byte
		binary.LittleEndian.PutUint32(encoded[:], offset)
		payload.Write(encoded[:])
	}
	peakHeap = maxHeap(peakHeap)
	payloadHash := sha256.Sum256(payload.Bytes())

	header := make([]byte, indexFileHeaderSize)
	copy(header[0:8], indexFileMagic)
	binary.LittleEndian.PutUint16(header[8:10], indexFileVersion)
	binary.LittleEndian.PutUint16(header[10:12], indexFileHeaderSize)
	copy(header[12:28], mode)
	copy(header[28:60], sourceHash[:])
	copy(header[60:92], payloadHash[:])
	binary.LittleEndian.PutUint64(header[92:100], uint64(len(offsets)))
	binary.LittleEndian.PutUint64(header[100:108], uint64(recordsEnd))
	binary.LittleEndian.PutUint64(header[108:116], uint64(payload.Len()))

	fileData := make([]byte, 0, len(header)+payload.Len())
	fileData = append(fileData, header...)
	fileData = append(fileData, payload.Bytes()...)
	fileHash := sha256.Sum256(fileData)
	peakHeap = maxHeap(peakHeap)
	if err := writeFileAtomic(outputPath, fileData); err != nil {
		return IndexBuildResult{}, err
	}

	return IndexBuildResult{
		FormatVersion:       indexFileVersion,
		Mode:                mode,
		SourcePath:          filepath.Clean(sourcePath),
		SourceSHA256:        hex.EncodeToString(sourceHash[:]),
		SourceBytes:         sourceBytes,
		ParsedRecords:       parsedRecords,
		IndexedRecords:      len(index.records),
		DuplicateRecords:    parsedRecords - len(index.records),
		IndexPath:           filepath.Clean(outputPath),
		IndexBytes:          int64(len(fileData)),
		RecordPayloadSHA256: hex.EncodeToString(payloadHash[:]),
		IndexSHA256:         hex.EncodeToString(fileHash[:]),
		BuildElapsedNS:      time.Since(started).Nanoseconds(),
		PeakObservedHeap:    peakHeap,
	}, nil
}

func readRimeDictionary(path string) ([]Entry, [sha256.Size]byte, int64, uint64, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, [sha256.Size]byte{}, 0, 0, fmt.Errorf("open dictionary: %w", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return nil, [sha256.Size]byte{}, 0, 0, fmt.Errorf("stat dictionary: %w", err)
	}

	hasher := sha256.New()
	scanner := bufio.NewScanner(io.TeeReader(file, hasher))
	scanner.Buffer(make([]byte, 64*1024), 16*1024*1024)
	inBody := false
	lineNumber := 0
	entries := make([]Entry, 0, 1_200_000)
	peakHeap := maxHeap(0)
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSuffix(scanner.Text(), "\r")
		if !inBody {
			if strings.TrimSpace(line) == "..." {
				inBody = true
			}
			continue
		}
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			return nil, [sha256.Size]byte{}, 0, peakHeap, fmt.Errorf("dictionary line %d has fewer than two tab-separated fields", lineNumber)
		}
		weight := int64(0)
		if len(fields) >= 3 && strings.TrimSpace(fields[2]) != "" {
			weight, err = strconv.ParseInt(strings.TrimSpace(fields[2]), 10, 64)
			if err != nil {
				return nil, [sha256.Size]byte{}, 0, peakHeap, fmt.Errorf("dictionary line %d has invalid integer weight: %w", lineNumber, err)
			}
		}
		entries = append(entries, Entry{Text: fields[0], Code: fields[1], Weight: weight})
		if len(entries)%100_000 == 0 {
			peakHeap = maxHeap(peakHeap)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, [sha256.Size]byte{}, 0, peakHeap, fmt.Errorf("scan dictionary: %w", err)
	}
	if !inBody {
		return nil, [sha256.Size]byte{}, 0, peakHeap, fmt.Errorf("dictionary body marker was not found")
	}
	var sourceHash [sha256.Size]byte
	copy(sourceHash[:], hasher.Sum(nil))
	return entries, sourceHash, info.Size(), maxHeap(peakHeap), nil
}

func writeFileAtomic(path string, data []byte) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("create index directory: %w", err)
	}
	temporary, err := os.CreateTemp(dir, ".yime-index-*.tmp")
	if err != nil {
		return fmt.Errorf("create temporary index: %w", err)
	}
	temporaryPath := temporary.Name()
	removeTemporary := true
	defer func() {
		if removeTemporary {
			_ = os.Remove(temporaryPath)
		}
	}()
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("write temporary index: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("sync temporary index: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close temporary index: %w", err)
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("publish index: %w", err)
	}
	removeTemporary = false
	return nil
}

func maxHeap(current uint64) uint64 {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	if stats.HeapAlloc > current {
		return stats.HeapAlloc
	}
	return current
}

// OpenFileIndex verifies and opens a versioned E1 index.
func OpenFileIndex(path string) (*FileIndex, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open index: %w", err)
	}
	closeOnError := true
	defer func() {
		if closeOnError {
			_ = file.Close()
		}
	}()
	info, err := file.Stat()
	if err != nil {
		return nil, fmt.Errorf("stat index: %w", err)
	}
	if info.Size() < indexFileHeaderSize {
		return nil, fmt.Errorf("invalid index magic or truncated header")
	}
	header := make([]byte, indexFileHeaderSize)
	if _, err := io.ReadFull(io.NewSectionReader(file, 0, indexFileHeaderSize), header); err != nil {
		return nil, fmt.Errorf("read index header: %w", err)
	}
	if string(header[0:8]) != indexFileMagic {
		return nil, fmt.Errorf("invalid index magic or truncated header")
	}
	if version := binary.LittleEndian.Uint16(header[8:10]); version != indexFileVersion {
		return nil, fmt.Errorf("unsupported index version %d", version)
	}
	if size := binary.LittleEndian.Uint16(header[10:12]); size != indexFileHeaderSize {
		return nil, fmt.Errorf("unexpected header size %d", size)
	}
	mode := strings.TrimRight(string(header[12:28]), "\x00")
	if mode == "" {
		return nil, fmt.Errorf("index mode is empty")
	}
	recordCount := binary.LittleEndian.Uint64(header[92:100])
	offsetsOffset := binary.LittleEndian.Uint64(header[100:108])
	payloadSize := binary.LittleEndian.Uint64(header[108:116])
	fileSize := uint64(info.Size())
	if payloadSize != fileSize-indexFileHeaderSize {
		return nil, fmt.Errorf("payload size mismatch")
	}
	if offsetsOffset < indexFileHeaderSize || offsetsOffset > fileSize {
		return nil, fmt.Errorf("invalid offset table position")
	}
	if recordCount > math.MaxInt || recordCount > math.MaxUint32 {
		return nil, fmt.Errorf("record count is unsupported: %d", recordCount)
	}
	if offsetsOffset+recordCount*4 != fileSize {
		return nil, fmt.Errorf("offset table size mismatch")
	}
	hasher := sha256.New()
	if _, err := io.Copy(hasher, io.NewSectionReader(file, indexFileHeaderSize, int64(payloadSize))); err != nil {
		return nil, fmt.Errorf("hash index payload: %w", err)
	}
	actualPayloadHash := [sha256.Size]byte{}
	copy(actualPayloadHash[:], hasher.Sum(nil))
	expectedPayloadHash := header[60:92]
	if !bytes.Equal(expectedPayloadHash, actualPayloadHash[:]) {
		return nil, fmt.Errorf("payload hash mismatch")
	}

	offsets := make([]uint32, int(recordCount))
	offsetReader := bufio.NewReaderSize(io.NewSectionReader(file, int64(offsetsOffset), int64(recordCount*4)), 64*1024)
	var encodedOffset [4]byte
	for i := range offsets {
		if _, err := io.ReadFull(offsetReader, encodedOffset[:]); err != nil {
			return nil, fmt.Errorf("read record offset %d: %w", i, err)
		}
		offsets[i] = binary.LittleEndian.Uint32(encodedOffset[:])
		if uint64(offsets[i]) < indexFileHeaderSize || uint64(offsets[i]) >= offsetsOffset {
			return nil, fmt.Errorf("record %d has invalid offset", i)
		}
		if i > 0 && offsets[i] <= offsets[i-1] {
			return nil, fmt.Errorf("record offsets are not strictly increasing")
		}
	}

	index := &FileIndex{file: file, mode: mode, offsets: offsets, recordsEnd: uint32(offsetsOffset)}
	if recordCount >= 1<<16 {
		index.twoByteTop = make([]shortBucket, 1<<16)
	} else {
		index.twoByteSparse = make(map[uint16]shortBucket)
	}
	copy(index.sourceHash[:], header[28:60])
	copy(index.payloadHash[:], actualPayloadHash[:])
	if err := index.validateRecordsAndBuildShortPrefixes(); err != nil {
		return nil, err
	}
	data, unmap, err := mapIndexFile(file, info.Size())
	if err != nil {
		return nil, fmt.Errorf("map index: %w", err)
	}
	index.data = data
	index.unmap = unmap
	closeOnError = false
	runtime.SetFinalizer(index, func(open *FileIndex) { _ = open.Close() })
	return index, nil
}

// Close releases the index file. Engines must stop using the index first.
func (idx *FileIndex) Close() error {
	if idx == nil {
		return nil
	}
	var err error
	idx.closeOnce.Do(func() {
		runtime.SetFinalizer(idx, nil)
		if idx.unmap != nil {
			err = idx.unmap()
		}
		if closeErr := idx.file.Close(); err == nil {
			err = closeErr
		}
		idx.data = nil
	})
	return err
}

func (idx *FileIndex) validateRecordsAndBuildShortPrefixes() error {
	reader := bufio.NewReaderSize(io.NewSectionReader(
		idx.file,
		indexFileHeaderSize,
		int64(idx.recordsEnd-indexFileHeaderSize),
	), 256*1024)
	current := uint32(indexFileHeaderSize)
	var header [recordHeaderSize]byte
	body := make([]byte, math.MaxUint16*2)
	var oneByteBuild [256][]shortBuildCandidate
	twoByteBuild := make(map[uint16][]shortBuildCandidate)
	for position, expectedOffset := range idx.offsets {
		if expectedOffset != current {
			return fmt.Errorf("record %d offset does not match sequential payload", position)
		}
		if _, err := io.ReadFull(reader, header[:]); err != nil {
			return fmt.Errorf("record %d header is truncated: %w", position, err)
		}
		codeLen := int(binary.LittleEndian.Uint16(header[0:2]))
		textLen := int(binary.LittleEndian.Uint16(header[2:4]))
		contentLen := codeLen + textLen
		if codeLen == 0 || uint64(current)+recordHeaderSize+uint64(contentLen) > uint64(idx.recordsEnd) {
			return fmt.Errorf("record %d content is truncated or has an empty code", position)
		}
		if _, err := io.ReadFull(reader, body[:contentLen]); err != nil {
			return fmt.Errorf("record %d content is truncated: %w", position, err)
		}
		code := body[:codeLen]
		if codeLen > idx.maxCodeBytes {
			idx.maxCodeBytes = codeLen
		}
		text := body[codeLen:contentLen]
		weight := int64(binary.LittleEndian.Uint64(header[4:12]))
		oneByteBuild[code[0]] = insertShortBuildCandidate(
			oneByteBuild[code[0]], uint32(position), code, text, weight, 1,
		)
		if len(code) >= 2 {
			key := uint16(code[0])<<8 | uint16(code[1])
			twoByteBuild[key] = insertShortBuildCandidate(
				twoByteBuild[key], uint32(position), code, text, weight, 2,
			)
		}
		current += uint32(recordHeaderSize + contentLen)
	}
	if current != idx.recordsEnd {
		return fmt.Errorf("record payload has unindexed trailing bytes")
	}
	for key, candidates := range oneByteBuild {
		for _, candidate := range candidates {
			bucket := &idx.oneByteTop[key]
			bucket.positions[bucket.count] = candidate.position
			bucket.count++
		}
	}
	for key, candidates := range twoByteBuild {
		if idx.twoByteTop != nil {
			for _, candidate := range candidates {
				bucket := &idx.twoByteTop[key]
				bucket.positions[bucket.count] = candidate.position
				bucket.count++
			}
			continue
		}
		bucket := shortBucket{}
		for _, candidate := range candidates {
			bucket.positions[bucket.count] = candidate.position
			bucket.count++
		}
		idx.twoByteSparse[key] = bucket
	}
	return nil
}

type shortBuildCandidate struct {
	position uint32
	code     string
	text     string
	weight   int64
}

func insertShortBuildCandidate(top []shortBuildCandidate, position uint32, code, text []byte, weight int64, prefixLen int) []shortBuildCandidate {
	if len(top) == defaultCandidateLimit && !betterShortBuildCandidate(code, text, weight, top[len(top)-1], prefixLen) {
		return top
	}
	item := shortBuildCandidate{position: position, code: string(code), text: string(text), weight: weight}
	if len(top) < defaultCandidateLimit {
		top = append(top, item)
	} else {
		top[len(top)-1] = item
	}
	for i := len(top) - 1; i > 0 && betterShortBuildCandidate([]byte(top[i].code), []byte(top[i].text), top[i].weight, top[i-1], prefixLen); i-- {
		top[i], top[i-1] = top[i-1], top[i]
	}
	return top
}

func betterShortBuildCandidate(code, text []byte, weight int64, right shortBuildCandidate, prefixLen int) bool {
	leftExact := len(code) == prefixLen
	rightExact := len(right.code) == prefixLen
	if leftExact != rightExact {
		return leftExact
	}
	if weight != right.weight {
		return weight > right.weight
	}
	if len(code) != len(right.code) {
		return len(code) < len(right.code)
	}
	if comparison := bytes.Compare(text, []byte(right.text)); comparison != 0 {
		return comparison < 0
	}
	return bytes.Compare(code, []byte(right.code)) < 0
}

// Mode returns the codemode recorded in the index header.
func (idx *FileIndex) Mode() string { return idx.mode }

// RecordCount returns the number of unique code/text records.
func (idx *FileIndex) RecordCount() int { return len(idx.offsets) }

// SourceID binds independent user data to the exact static-index provenance.
func (idx *FileIndex) SourceID() string { return idx.identity() }

func (idx *FileIndex) lookup(prefix string, limit int) []record {
	if idx == nil || prefix == "" || limit <= 0 {
		return nil
	}
	prefixBytes := []byte(prefix)
	if len(prefixBytes) == 1 {
		return idx.recordsFromShortBucket(&idx.oneByteTop[prefixBytes[0]], limit)
	}
	if len(prefixBytes) == 2 {
		key := uint16(prefixBytes[0])<<8 | uint16(prefixBytes[1])
		if idx.twoByteTop != nil {
			return idx.recordsFromShortBucket(&idx.twoByteTop[key], limit)
		}
		bucket := idx.twoByteSparse[key]
		return idx.recordsFromShortBucket(&bucket, limit)
	}
	start := sort.Search(len(idx.offsets), func(i int) bool {
		code, _, _, err := idx.recordAt(i)
		return err != nil || bytes.Compare(code, prefixBytes) >= 0
	})
	top := make([]fileRecord, 0, limit)
	for i := start; i < len(idx.offsets); i++ {
		code, text, weight, err := idx.recordAt(i)
		if err != nil || !bytes.HasPrefix(code, prefixBytes) {
			break
		}
		top = insertFileTop(top, fileRecord{code: code, text: text, weight: weight}, prefixBytes, limit)
	}
	result := make([]record, 0, len(top))
	for _, item := range top {
		result = append(result, record{code: string(item.code), text: string(item.text), weight: item.weight})
	}
	return result
}

func (idx *FileIndex) exact(code string, limit int) []record {
	if idx == nil || code == "" || limit <= 0 {
		return nil
	}
	codeBytes := []byte(code)
	start := sort.Search(len(idx.offsets), func(i int) bool {
		recordCode, _, _, err := idx.recordAt(i)
		return err != nil || bytes.Compare(recordCode, codeBytes) >= 0
	})
	result := make([]record, 0, limit)
	for i := start; i < len(idx.offsets) && len(result) < limit; i++ {
		recordCode, text, weight, err := idx.recordAt(i)
		if err != nil || !bytes.Equal(recordCode, codeBytes) {
			break
		}
		result = append(result, record{code: string(recordCode), text: string(text), weight: weight})
	}
	return result
}

func (idx *FileIndex) maximumCodeBytes() int { return idx.maxCodeBytes }

func (idx *FileIndex) identity() string {
	return "yime-index-v1:" + idx.mode + ":" + hex.EncodeToString(idx.sourceHash[:])
}

func (idx *FileIndex) recordsFromShortBucket(bucket *shortBucket, limit int) []record {
	count := int(bucket.count)
	if count > limit {
		count = limit
	}
	result := make([]record, 0, count)
	for i := 0; i < count; i++ {
		code, text, weight, err := idx.recordAt(int(bucket.positions[i]))
		if err != nil {
			break
		}
		result = append(result, record{code: string(code), text: string(text), weight: weight})
	}
	return result
}

func (idx *FileIndex) recordAt(position int) ([]byte, []byte, int64, error) {
	if position < 0 || position >= len(idx.offsets) {
		return nil, nil, 0, fmt.Errorf("record position out of range")
	}
	offset := int(idx.offsets[position])
	if offset+recordHeaderSize > int(idx.recordsEnd) {
		return nil, nil, 0, fmt.Errorf("record %d header is truncated", position)
	}
	codeLen := int(binary.LittleEndian.Uint16(idx.data[offset : offset+2]))
	textLen := int(binary.LittleEndian.Uint16(idx.data[offset+2 : offset+4]))
	weight := int64(binary.LittleEndian.Uint64(idx.data[offset+4 : offset+12]))
	end := offset + recordHeaderSize + codeLen + textLen
	if end > int(idx.recordsEnd) {
		return nil, nil, 0, fmt.Errorf("record %d content is truncated", position)
	}
	codeStart := offset + recordHeaderSize
	textStart := codeStart + codeLen
	return idx.data[codeStart:textStart], idx.data[textStart:end], weight, nil
}

type fileRecord struct {
	code   []byte
	text   []byte
	weight int64
}

func insertFileTop(top []fileRecord, item fileRecord, input []byte, limit int) []fileRecord {
	if len(top) == limit && !betterFileRecord(item, top[len(top)-1], input) {
		return top
	}
	if len(top) < limit {
		top = append(top, item)
	} else {
		top[len(top)-1] = item
	}
	for i := len(top) - 1; i > 0 && betterFileRecord(top[i], top[i-1], input); i-- {
		top[i], top[i-1] = top[i-1], top[i]
	}
	return top
}

func betterFileRecord(left, right fileRecord, input []byte) bool {
	leftExact := bytes.Equal(left.code, input)
	rightExact := bytes.Equal(right.code, input)
	if leftExact != rightExact {
		return leftExact
	}
	if left.weight != right.weight {
		return left.weight > right.weight
	}
	if len(left.code) != len(right.code) {
		return len(left.code) < len(right.code)
	}
	if comparison := bytes.Compare(left.text, right.text); comparison != 0 {
		return comparison < 0
	}
	return bytes.Compare(left.code, right.code) < 0
}
