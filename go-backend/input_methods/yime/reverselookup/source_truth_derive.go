package reverselookup

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

type SourceTruthDeriveSummary struct {
	AmbiguousFullCodes int
	AffectedEntries    int
	SourceRows         int
	UnresolvedEntries  int
}

type sourceTruthRecord struct {
	Text     string
	FullCode string
	Numeric  string
	Marked   string
}

// DeriveSourceTruth builds a partial reverse table only for runtime entries
// containing a canonical full-code syllable shared by different Pinyin.
func DeriveSourceTruth(codeMapPath, dictionaryPath, pronunciationEntriesPath, outputPath string) (SourceTruthDeriveSummary, error) {
	codeMap, canonicalRows, err := loadCanonicalCodeMapForTruth(codeMapPath)
	if err != nil {
		return SourceTruthDeriveSummary{}, err
	}
	ambiguous := map[string]bool{}
	byFull := map[string][]string{}
	for pinyin, record := range canonicalRows {
		byFull[record.Full] = append(byFull[record.Full], pinyin)
	}
	for code, pinyin := range byFull {
		if len(pinyin) > 1 {
			ambiguous[code] = true
		}
	}

	affected := map[string]bool{}
	affectedTexts := map[string]bool{}
	if err := scanTruthDictionary(dictionaryPath, func(text, code string) {
		parts := strings.Fields(code)
		for _, part := range parts {
			if !ambiguous[part] {
				continue
			}
			compact := strings.Join(parts, "")
			affected[text+"\x00"+compact] = true
			affectedTexts[text] = true
			break
		}
	}); err != nil {
		return SourceTruthDeriveSummary{}, err
	}

	records := map[string]sourceTruthRecord{}
	file, err := os.Open(pronunciationEntriesPath)
	if err != nil {
		return SourceTruthDeriveSummary{}, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 256*1024), 8*1024*1024)
	lineNumber := 0
	columns := map[string]int{}
	for scanner.Scan() {
		lineNumber++
		fields := strings.Split(strings.TrimPrefix(scanner.Text(), "\ufeff"), "\t")
		if lineNumber == 1 {
			for index, name := range fields {
				columns[strings.TrimSpace(name)] = index
			}
			for _, required := range []string{"text", "pinyin_marked", "pinyin_numeric"} {
				if _, ok := columns[required]; !ok {
					return SourceTruthDeriveSummary{}, fmt.Errorf("pronunciation entries are missing %s", required)
				}
			}
			continue
		}
		maxColumn := columns["text"]
		for _, name := range []string{"pinyin_marked", "pinyin_numeric"} {
			if columns[name] > maxColumn {
				maxColumn = columns[name]
			}
		}
		if len(fields) <= maxColumn {
			continue
		}
		text := strings.TrimSpace(fields[columns["text"]])
		if !affectedTexts[text] {
			continue
		}
		numeric := normalizeNumericTonePinyinSpacing(fields[columns["pinyin_numeric"]])
		fullCode := pinyinToCode(codeMap, numeric, "full")
		if fullCode == "" || !affected[text+"\x00"+fullCode] {
			continue
		}
		marked := strings.TrimSpace(fields[columns["pinyin_marked"]])
		key := text + "\x00" + fullCode + "\x00" + numeric
		records[key] = sourceTruthRecord{Text: text, FullCode: fullCode, Numeric: numeric, Marked: marked}
	}
	if err := scanner.Err(); err != nil {
		return SourceTruthDeriveSummary{}, err
	}

	covered := map[string]bool{}
	rows := make([]sourceTruthRecord, 0, len(records))
	for _, record := range records {
		covered[record.Text+"\x00"+record.FullCode] = true
		rows = append(rows, record)
	}
	unresolved := 0
	for key := range affected {
		if !covered[key] {
			unresolved++
		}
	}
	if unresolved > 0 {
		return SourceTruthDeriveSummary{AmbiguousFullCodes: len(ambiguous), AffectedEntries: len(affected), SourceRows: len(rows), UnresolvedEntries: unresolved}, fmt.Errorf("%d ambiguous runtime entries have no matching pronunciation source", unresolved)
	}
	sort.Slice(rows, func(i, j int) bool {
		left := rows[i].Text + "\x00" + rows[i].FullCode + "\x00" + rows[i].Numeric
		right := rows[j].Text + "\x00" + rows[j].FullCode + "\x00" + rows[j].Numeric
		return left < right
	})
	if err := writeSourceTruthAtomic(outputPath, rows); err != nil {
		return SourceTruthDeriveSummary{}, err
	}
	return SourceTruthDeriveSummary{AmbiguousFullCodes: len(ambiguous), AffectedEntries: len(affected), SourceRows: len(rows)}, nil
}

func loadCanonicalCodeMapForTruth(path string) (map[string]CodeRecord, map[string]CodeRecord, error) {
	all, err := loadCodeMap(path)
	if err != nil {
		return nil, nil, err
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, nil, err
	}
	defer file.Close()
	canonical := map[string]CodeRecord{}
	scanner := bufio.NewScanner(file)
	line := 0
	for scanner.Scan() {
		line++
		if line == 1 {
			continue
		}
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) < 2 {
			continue
		}
		pinyin := normalizeNumericTonePinyin(fields[0])
		if len(fields) >= 4 {
			canonical[pinyin] = CodeRecord{Full: strings.TrimSpace(fields[1]), Variable: strings.TrimSpace(fields[2]), Shorthand: strings.TrimSpace(fields[3])}
			continue
		}
		record, err := codemode.BuildRecord(fields[1])
		if err != nil {
			return nil, nil, err
		}
		canonical[pinyin] = CodeRecord{Full: record.Full, Variable: record.Variable, Shorthand: record.Shorthand}
	}
	return all, canonical, scanner.Err()
}

func scanTruthDictionary(path string, visit func(text, code string)) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 256*1024), 8*1024*1024)
	inData := false
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !inData {
			inData = line == "..."
			continue
		}
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) >= 2 {
			visit(strings.TrimSpace(fields[0]), strings.TrimSpace(fields[1]))
		}
	}
	return scanner.Err()
}

func writeSourceTruthAtomic(path string, rows []sourceTruthRecord) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".reverse-source-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	writer := bufio.NewWriterSize(temporary, 256*1024)
	if _, err := writer.WriteString("text\tsource_full_code\tnumeric_pinyin\tmarked_pinyin\n"); err != nil {
		temporary.Close()
		return err
	}
	for _, row := range rows {
		if strings.ContainsAny(row.Text+row.Numeric+row.Marked, "\t\r\n") {
			temporary.Close()
			return fmt.Errorf("reverse source row contains a tab or newline: %q", row.Text)
		}
		fmt.Fprintf(writer, "%s\t%s\t%s\t%s\n", row.Text, row.FullCode, row.Numeric, row.Marked)
	}
	if err := writer.Flush(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	backupPath := ""
	if _, err := os.Stat(path); err == nil {
		backup, createErr := os.CreateTemp(filepath.Dir(path), ".reverse-source-backup-*.tmp")
		if createErr != nil {
			return createErr
		}
		backupPath = backup.Name()
		if closeErr := backup.Close(); closeErr != nil {
			return closeErr
		}
		if removeErr := os.Remove(backupPath); removeErr != nil {
			return removeErr
		}
		if renameErr := os.Rename(path, backupPath); renameErr != nil {
			return renameErr
		}
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		if backupPath != "" {
			_ = os.Rename(backupPath, path)
		}
		return err
	}
	if backupPath != "" {
		_ = os.Remove(backupPath)
	}
	return nil
}
