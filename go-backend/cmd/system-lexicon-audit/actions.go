//go:build windows

package main

import (
	"fmt"
	"path/filepath"
	"syscall"
	"time"
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/reverselookup"
	"github.com/EasyIME/pime-go/input_methods/yime/systemlexicon"
	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

func (state *appState) startLoadAudit() {
	if state.loading {
		return
	}
	state.loading = true
	state.setStatus("正在扫描系统词库，请稍候...")
	mode := state.currentMode()
	dictPath := systemlexicon.DictPath(state.sharedDir, state.userDir, mode)
	go func() {
		entries, err := systemlexicon.LoadDictFile(dictPath)
		var findings []systemlexicon.Finding
		var summary systemlexicon.Summary
		if err == nil {
			findings, summary = systemlexicon.AuditEntries(entries)
			summary.DictPath = dictPath
			summary.Mode = string(mode)
		}
		state.mu.Lock()
		state.loadErr = err
		state.dictPath = dictPath
		state.mode = mode
		state.allFindings = findings
		state.summary = summary
		state.loading = false
		state.mu.Unlock()
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppLoadDone, 0, 0)
	}()
}

func (state *appState) onLoadDone() {
	state.mu.Lock()
	err := state.loadErr
	summary := state.summary
	state.mu.Unlock()

	if err != nil {
		showWin32Error(err.Error())
		state.setStatus("加载失败：" + err.Error())
		return
	}
	state.refreshVisibleList()
	state.setStatus(fmt.Sprintf(
		"已扫描 %s：共 %d 条词条，发现 %d 条待审项。本工具只读，不会修改系统词库。",
		filepath.Base(summary.DictPath),
		summary.TotalEntries,
		summary.FindingCount,
	))
}

func (state *appState) handleWMCommand(wParam, lParam uintptr) {
	commandID := int(wParam & 0xffff)
	notifyCode := int((wParam >> 16) & 0xffff)
	switch commandID {
	case idRefreshButton:
		if notifyCode == 0 {
			state.startLoadAudit()
		}
	case idExportButton:
		if notifyCode == 0 {
			state.exportReport()
		}
	case idSearchEdit:
		if notifyCode == enChange {
			procPostMessageW.Call(uintptr(state.mainHWND), wmAppRefresh, 0, 0)
		}
	case idRuleCombo, idModeCombo:
		if notifyCode == cbSelchange {
			if commandID == idModeCombo {
				state.startLoadAudit()
				return
			}
			procPostMessageW.Call(uintptr(state.mainHWND), wmAppRefresh, 0, 0)
		}
	case idResultList:
		if state.suppressListNotify {
			return
		}
		if notifyCode == lbnSelchange {
			state.updateDetail(-1)
		}
	}
}

func (state *appState) currentMode() reverselookup.Mode {
	index, _, _ := procSendMessageW.Call(uintptr(state.modeHWND), cbGetcursel, 0, 0)
	selected := int(index)
	if selected < 0 || selected >= len(state.modeOptions) {
		return state.mode
	}
	return state.modeOptions[selected].Value
}

func (state *appState) currentRule() systemlexicon.RuleID {
	index, _, _ := procSendMessageW.Call(uintptr(state.ruleHWND), cbGetcursel, 0, 0)
	selected := int(index)
	if selected < 0 || selected >= len(state.ruleOptions) {
		return systemlexicon.RuleAll
	}
	return state.ruleOptions[selected]
}

func (state *appState) refreshVisibleList() {
	state.mu.Lock()
	allFindings := append([]systemlexicon.Finding(nil), state.allFindings...)
	summary := state.summary
	state.mu.Unlock()

	keyword := getWindowText(state.searchHWND)
	visible := systemlexicon.FilterFindings(allFindings, state.currentRule(), keyword)
	state.visibleFindings = visible

	state.suppressListNotify = true
	procSendMessageW.Call(uintptr(state.resultHWND), lbResetcontent, 0, 0)
	maxExtent := int32(0)
	for _, item := range visible {
		line := fmt.Sprintf("%s | %s | %s | %d", item.RuleLabel, item.Text, item.Code, item.Weight)
		text, _ := syscall.UTF16PtrFromString(line)
		procSendMessageW.Call(uintptr(state.resultHWND), lbAddstring, 0, uintptr(unsafe.Pointer(text)))
		if extent := int32(len(line) * 7); extent > maxExtent {
			maxExtent = extent
		}
	}
	if maxExtent < state.layout.resultList.Right-state.layout.resultList.Left {
		maxExtent = state.layout.resultList.Right - state.layout.resultList.Left
	}
	procSendMessageW.Call(uintptr(state.resultHWND), lbSethorizontalextent, uintptr(maxExtent), 0)
	state.suppressListNotify = false
	win32ui.RedrawChildrenNow(state.mainHWND)

	if len(visible) == 0 {
		state.setDetail("当前筛选条件下没有待审词条。")
	} else {
		state.updateDetail(0)
	}

	state.setStatus(fmt.Sprintf(
		"显示 %d / %d 条待审项（词库共 %d 条）。路径：%s",
		len(visible),
		summary.FindingCount,
		summary.TotalEntries,
		summary.DictPath,
	))
}

func (state *appState) updateDetail(selected int) {
	if selected < 0 {
		sel, _, _ := procSendMessageW.Call(uintptr(state.resultHWND), lbGetcursel, 0, 0)
		selected = int(sel)
	}
	if selected < 0 || selected >= len(state.visibleFindings) {
		return
	}
	item := state.visibleFindings[selected]
	state.setDetail(fmt.Sprintf(
		"规则：%s\r\n词条：%s\r\n编码：%s\r\n权重：%d\r\n说明：%s",
		item.RuleLabel,
		item.Text,
		item.Code,
		item.Weight,
		item.Detail,
	))
}

func (state *appState) exportReport() {
	state.mu.Lock()
	findings := append([]systemlexicon.Finding(nil), state.visibleFindings...)
	summary := state.summary
	state.mu.Unlock()

	if summary.DictPath == "" {
		showWin32Error("尚未完成扫描，无法导出。")
		return
	}
	if state.userDir == "" {
		showWin32Error("缺少 UserDir，无法写入报告。")
		return
	}

	stamp := time.Now().Format("20060102_150405")
	jsonPath := filepath.Join(state.userDir, fmt.Sprintf("system_lexicon_audit_%s.json", stamp))
	tsvPath := filepath.Join(state.userDir, fmt.Sprintf("system_lexicon_audit_%s.tsv", stamp))
	report := systemlexicon.BuildReport(summary, findings)
	if err := systemlexicon.WriteReportJSON(jsonPath, report); err != nil {
		showWin32Error("导出 JSON 失败：" + err.Error())
		return
	}
	if err := systemlexicon.WriteReportTSV(tsvPath, findings); err != nil {
		showWin32Error("导出 TSV 失败：" + err.Error())
		return
	}
	state.setStatus(fmt.Sprintf("已导出 %d 条到：%s", len(findings), jsonPath))
}

func (state *appState) setStatus(text string) {
	setWindowText(state.statusHWND, text)
}

func (state *appState) setDetail(text string) {
	setWindowText(state.detailHWND, text)
}

func (state *appState) readQueuedError(_ uintptr) string {
	state.mu.Lock()
	defer state.mu.Unlock()
	if state.loadErr != nil {
		return state.loadErr.Error()
	}
	return "未知错误"
}

func setWindowText(hwnd syscall.Handle, text string) {
	ptr, _ := syscall.UTF16PtrFromString(text)
	procSetWindowTextW.Call(uintptr(hwnd), uintptr(unsafe.Pointer(ptr)))
}

func getWindowText(hwnd syscall.Handle) string {
	length, _, _ := procGetWindowTextLengthW.Call(uintptr(hwnd))
	if length == 0 {
		return ""
	}
	buf := make([]uint16, length+1)
	procGetWindowTextW.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&buf[0])), length+1)
	return syscall.UTF16ToString(buf)
}
