package syllableinspector

import (
	"fmt"
	"strings"
	"unicode/utf8"
)

func (inventory Inventory) Filter(query, category string) []int {
	query = strings.ToLower(strings.TrimSpace(query))
	category = strings.TrimSpace(category)
	result := make([]int, 0, len(inventory.Rows))
	for index, row := range inventory.Rows {
		if category != "" && category != "全部类别" && row.RuleID != category {
			continue
		}
		text := strings.ToLower(strings.Join([]string{
			row.PinyinTone, row.MarkedPinyin, row.Normalized, row.ShouyinLabel, row.GanyinLabel,
			row.RuleID, strings.Join(row.IDs[:], " "), strings.Join(row.Names[:], " "), row.Aliases, row.Status,
		}, " "))
		if query == "" || strings.Contains(text, query) {
			result = append(result, index)
		}
	}
	return result
}

func (row Row) Summary() string {
	return fmt.Sprintf("%-8s  %-8s  %-18s  %s", row.PinyinTone, row.MarkedPinyin, row.RuleID, strings.Join(row.IDs[:], " "))
}

func (row Row) ProjectedCode(layout map[string]string) string {
	var result strings.Builder
	for _, id := range row.IDs {
		key := layout[id]
		if key == "" {
			return "（布局缺少 " + id + "）"
		}
		result.WriteString(key)
	}
	return result.String()
}

func (row Row) Trace(layout map[string]string) string {
	positions := []string{"首音", "呼音", "主音", "末音"}
	var builder strings.Builder
	fmt.Fprintf(&builder, "输入：%s（%s）\r\n规范化：%s\r\n命中规则：%s\r\n切分：%s + %s\r\n\r\n", row.PinyinTone, row.MarkedPinyin, row.Normalized, row.RuleID, row.ShouyinLabel, row.GanyinLabel)
	for index, name := range positions {
		symbol, codepoint := row.Symbols[index], ""
		if symbol != "" {
			if value, _ := utf8.DecodeRuneInString(symbol); value != utf8.RuneError {
				codepoint = fmt.Sprintf("U+%04X", value)
			}
		}
		fmt.Fprintf(&builder, "%s：%s  %s  %s  %s\r\n", name, row.IDs[index], row.Names[index], symbol, codepoint)
	}
	fmt.Fprintf(&builder, "\r\n当前布局键码：%s\r\n导出时键码：%s\r\n同码/别名组：%s\r\n校验状态：%s", row.ProjectedCode(layout), row.LayoutCode, row.Aliases, row.Status)
	return builder.String()
}
