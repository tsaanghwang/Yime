package systemlexicon

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"
)

type Report struct {
	GeneratedAt string    `json:"generated_at"`
	Summary     Summary   `json:"summary"`
	Findings    []Finding `json:"findings"`
	Notes       []string  `json:"notes"`
}

func BuildReport(summary Summary, findings []Finding) Report {
	return Report{
		GeneratedAt: time.Now().Format(time.RFC3339),
		Summary:     summary,
		Findings:    append([]Finding(nil), findings...),
		Notes: []string{
			"本报告为只读审查结果，不会修改系统词库。",
			"如需调整系统词库，请在 Yime-python-prototype 管线中处理并发版。",
		},
	}
}

func WriteReportJSON(path string, report Report) error {
	payload, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, payload, 0o644)
}

func WriteReportTSV(path string, findings []Finding) error {
	var builder strings.Builder
	builder.WriteString("rule\ttext\tcode\tweight\tdetail\n")
	for _, item := range findings {
		builder.WriteString(fmt.Sprintf(
			"%s\t%s\t%s\t%d\t%s\n",
			item.Rule,
			item.Text,
			item.Code,
			item.Weight,
			strings.ReplaceAll(item.Detail, "\t", " "),
		))
	}
	return os.WriteFile(path, []byte(builder.String()), 0o644)
}
