//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
	"os"
	"sync"
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
	}
	dir, err := touchdiagnostic.DefaultDirectory()
	a.diagnosticPages = []string{status + "\n查看诊断不恢复会话、不重放输入。线程信息未知；记事本失败原因尚未确定。"}
	if a.preview != nil && a.preview.lastDiagnostic != nil {
		a.diagnosticPages = append(a.diagnosticPages, "当前停止原因（不表示已保存）：\n"+a.preview.lastDiagnostic.Error())
	}
	if err != nil {
		a.diagnosticPages = append(a.diagnosticPages, "无法取得本用户的诊断目录。")
		return
	}
	a.diagnosticPages = append(a.diagnosticPages, "记录位置：\n"+dir+"\n权限继承本用户目录的 Windows ACL；每轮最多64条，每条最多256字节；最多保留16轮。关闭18u后可删除这些诊断文件。")
	records, err := touchdiagnostic.ReadRecent(dir)
	if err != nil {
		a.diagnosticPages = append(a.diagnosticPages, "最近记录读取失败；不表示没有发生错误。")
		return
	}
	if len(records) == 0 {
		a.diagnosticPages = append(a.diagnosticPages, "未读取到诊断记录；不能据此判断接入成功。")
		return
	}
	// Newest first. Only validated structured diagnostics enter the overlay.
	for i := len(records) - 1; i >= 0; i-- {
		a.diagnosticPages = append(a.diagnosticPages, records[i].Error())
	}
}
