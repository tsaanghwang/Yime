// Package syllableinspector reads the generated view of the real encoder chain.
package syllableinspector

import (
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const DataFileName = "yime_syllable_decomposition.tsv"

type Row struct {
	PinyinTone, MarkedPinyin, Normalized string
	ShouyinLabel, GanyinLabel, RuleID    string
	Symbols, IDs, Names                  [4]string
	LayoutCode, Aliases, Status          string
}

type Inventory struct {
	Rows                                                []Row
	Categories                                          []string
	RuntimeEntries, SourceOnly, RuntimeOnly, Mismatches int
}

var fields = []string{
	"pinyin_tone", "marked_pinyin", "normalized", "shouyin_label", "ganyin_label", "rule_id",
	"shouyin_symbol", "huyin_symbol", "zhuyin_symbol", "moyin_symbol",
	"shouyin_id", "huyin_id", "zhuyin_id", "moyin_id",
	"shouyin_name", "huyin_name", "zhuyin_name", "moyin_name", "layout_code", "aliases", "status",
}

func Load(dataDir string) (Inventory, error) {
	path := filepath.Join(dataDir, DataFileName)
	file, err := os.Open(path)
	if err != nil {
		return Inventory{}, fmt.Errorf("打开音节分解审计表 %s: %w", path, err)
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma, reader.FieldsPerRecord = '\t', -1
	header, err := reader.Read()
	if err != nil {
		return Inventory{}, fmt.Errorf("读取音节分解表头: %w", err)
	}
	columns := map[string]int{}
	for index, name := range header {
		columns[strings.TrimSpace(name)] = index
	}
	for _, name := range fields {
		if _, ok := columns[name]; !ok {
			return Inventory{}, fmt.Errorf("音节分解表缺少字段 %s", name)
		}
	}
	inventory, err := loadRows(reader, columns)
	if err != nil {
		return Inventory{}, err
	}
	if err := inventory.compareRuntime(filepath.Join(dataDir, "yime_pinyin_codes.tsv")); err != nil {
		return Inventory{}, err
	}
	return inventory, nil
}

func loadRows(reader *csv.Reader, columns map[string]int) (Inventory, error) {
	var rows []Row
	categories := map[string]struct{}{}
	for line := 2; ; line++ {
		record, readErr := reader.Read()
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return Inventory{}, fmt.Errorf("读取第 %d 行: %w", line, readErr)
		}
		value := func(name string) string {
			index := columns[name]
			if index < len(record) {
				return record[index]
			}
			return ""
		}
		row := rowFromValues(value)
		if row.PinyinTone == "" || row.RuleID == "" {
			return Inventory{}, fmt.Errorf("第 %d 行缺少拼音或规则类别", line)
		}
		for index, id := range row.IDs {
			if len(id) != 3 || (id[0] != 'N' && id[0] != 'M') {
				return Inventory{}, fmt.Errorf("%s 的第 %d 个 ID 无效: %q", row.PinyinTone, index+1, id)
			}
		}
		rows = append(rows, row)
		categories[row.RuleID] = struct{}{}
	}
	if len(rows) == 0 {
		return Inventory{}, fmt.Errorf("音节分解表没有数据")
	}
	list := make([]string, 0, len(categories))
	for category := range categories {
		list = append(list, category)
	}
	sort.Strings(list)
	return Inventory{Rows: rows, Categories: list}, nil
}

func rowFromValues(value func(string) string) Row {
	return Row{
		PinyinTone: value("pinyin_tone"), MarkedPinyin: value("marked_pinyin"), Normalized: value("normalized"),
		ShouyinLabel: value("shouyin_label"), GanyinLabel: value("ganyin_label"), RuleID: value("rule_id"),
		Symbols:    [4]string{value("shouyin_symbol"), value("huyin_symbol"), value("zhuyin_symbol"), value("moyin_symbol")},
		IDs:        [4]string{value("shouyin_id"), value("huyin_id"), value("zhuyin_id"), value("moyin_id")},
		Names:      [4]string{value("shouyin_name"), value("huyin_name"), value("zhuyin_name"), value("moyin_name")},
		LayoutCode: value("layout_code"), Aliases: value("aliases"), Status: value("status"),
	}
}

func (inventory *Inventory) compareRuntime(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("打开当前运行时拼音码表 %s: %w", path, err)
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma, reader.FieldsPerRecord = '\t', -1
	header, err := reader.Read()
	if err != nil || len(header) < 2 || header[0] != "pinyin_tone" || header[1] != "full" {
		return fmt.Errorf("当前运行时拼音码表表头无效: %s", path)
	}
	runtimeCodes := map[string]string{}
	for {
		record, readErr := reader.Read()
		if readErr == io.EOF {
			break
		}
		if readErr != nil || len(record) < 2 {
			return fmt.Errorf("读取当前运行时拼音码表失败: %w", readErr)
		}
		runtimeCodes[record[0]] = record[1]
	}
	inventory.RuntimeEntries = len(runtimeCodes)
	for index := range inventory.Rows {
		row := &inventory.Rows[index]
		code, exists := runtimeCodes[row.PinyinTone]
		switch {
		case !exists:
			row.Status = "source-only"
			inventory.SourceOnly++
		case code != row.LayoutCode:
			row.Status = "runtime-code-mismatch: " + code
			inventory.Mismatches++
		default:
			row.Status = "ok"
		}
		delete(runtimeCodes, row.PinyinTone)
	}
	inventory.RuntimeOnly = len(runtimeCodes)
	return nil
}
