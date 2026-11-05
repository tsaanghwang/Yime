//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
	"os"
	"sync"
	"time"
)

var diagnosticHealth struct {
	sync.Mutex
	value touchdiagnostic.Health
}

func receiveDiagnosticHealth() {
	touchdiagnostic.ReadHealth(os.Stdin, func(h touchdiagnostic.Health) {
		diagnosticHealth.Lock()
		diagnosticHealth.value = h
		diagnosticHealth.Unlock()
	})
}
func (a *ui) settingsActions() []string {
	if a.installed == nil {
		return touchSettings
	}
	return append(append([]string{}, touchSettings...), "diagnostics")
}
func (a *ui) helpPages() []string {
	if a.diagnosticOpen {
		return a.diagnosticPages
	}
	return touchHelpPages()
}
func (a *ui) showDiagnostics() {
	a.cancel() // Cancel local contacts only; no close/bind/edit and no fault reset.
	a.diagnosticOpen = true
	a.touchHelpOpen = true
	a.touchSettingsOpen = false
	a.touchHelpPage = 0
	diagnosticHealth.Lock()
	h := diagnosticHealth.value
	diagnosticHealth.Unlock()
	var current *touchdiagnostic.Diagnostic
	if a.preview != nil {
		current = a.preview.lastDiagnostic
	}
	dir, err := touchdiagnostic.DefaultDirectory()
	a.diagnosticPages = installedDiagnosticPages(h, current, dir, err, touchdiagnostic.ReadRecent)
}

// Reading diagnostic pages cannot dispatch, reset a session, or consume output.
// The explicit reader keeps storage failures testable without lock timing races.
func installedDiagnosticPages(h touchdiagnostic.Health, current *touchdiagnostic.Diagnostic, dir string, directoryError error, read func(string) ([]touchdiagnostic.Diagnostic, error)) []string {
	status := "记录状态未知；不能确认已保存。"
	switch h.State {
	case "ready":
		status = fmt.Sprintf("本轮已确认保存 %d 条。", h.Saved)
	case "failed":
		status = "记录失败；不能确认其余错误已保存。"
	case "limit":
		status = fmt.Sprintf("本轮接收达到上限，已确认保存 %d 条；后续错误未保存。", h.Saved)
	}
	if h.Diagnostic != nil {
		status += "\n" + h.Diagnostic.Error()
		if h.Diagnostic.Reason == "storage-busy" {
			status += "\n诊断暂时不可读，请稍后查看"
		}
	}
	pages := []string{status + "\n查看诊断不恢复会话、不重放输入。线程信息未知；记事本失败原因尚未确定。"}
	if current != nil {
		pages = append(pages, "当前停止原因（不表示已保存）：\n"+installedDiagnosticText(*current))
	}
	if directoryError != nil {
		return append(pages, "无法取得本用户的诊断目录。")
	}
	pages = append(pages, "记录位置：\n"+dir+"\n权限继承本用户目录的 Windows ACL；每轮最多64条，每条最多256字节；最多保留16轮。关闭18u后可删除这些诊断文件。")
	records, err := read(dir)
	if err != nil {
		return append(pages, "诊断暂时不可读，请稍后查看")
	}
	if len(records) == 0 {
		if h.Diagnostic != nil && h.Diagnostic.Reason == "storage-busy" {
			return pages
		}
		return append(pages, "未读取到诊断记录；不能据此判断接入成功。")
	}
	// Newest first. Only validated structured diagnostics enter the overlay.
	for i := len(records) - 1; i >= 0; i-- {
		pages = append(pages, installedDiagnosticText(records[i]))
	}
	return pages
}

func installedDiagnosticText(d touchdiagnostic.Diagnostic) string {
	d = touchdiagnostic.Sanitize(d)
	if d.Stage != "tip-discovery" {
		return d.Error()
	}
	text := "客户端报告的拒绝原因：\n" + d.Error()
	if d.Reported == nil {
		return text + "\n缺少接收来源信息；不能验证报告来源。"
	}
	origin := d.Reported
	return text + fmt.Sprintf("\n接收时间（UTC）：%s\n报告进程：%d；事件：%s\n来源信息用于关联报告，不代表故障已查明。", time.UnixMilli(origin.ReceivedMS).UTC().Format("2006-01-02 15:04:05.000"), origin.PID, origin.Event)
}
