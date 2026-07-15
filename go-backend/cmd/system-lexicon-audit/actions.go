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
	state.mu.Lock()
	if state.loading {
		state.mu.Unlock()
		return
	}
	state.loading = true
	state.mu.Unlock()
	state.setStatus("正在扫描系统词库，请稍候...")
	state.updateControlState()
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
	state.updateControlState()

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
	}
}

func (state *appState) handleNotify(lParam uintptr) {
	if lParam == 0 || state.suppressListNotify {
		return
	}
	header := win32ui.ReadMessageStruct[notifyHeader](lParam)
	if int(header.IDFrom) == idResultList && header.Code == -101 {
		state.updateDetail(-1)
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
	state.mu.Lock()
	state.visibleFindings = visible
	state.mu.Unlock()

	state.suppressListNotify = true
	procSendMessageW.Call(uintptr(state.resultHWND), lvmDeleteallitems, 0, 0)
	for index, finding := range visible {
		first, _ := syscall.UTF16PtrFromString(finding.RuleLabel)
		item := listViewItem{Mask: lvifText, Item: int32(index), Text: first}
		if inserted, _, _ := procSendMessageW.Call(uintptr(state.resultHWND), lvmInsertitemw, 0, uintptr(unsafe.Pointer(&item))); int32(inserted) < 0 {
			continue
		}
		for subItem, value := range []string{finding.Text, finding.Code, fmt.Sprintf("%d", finding.Weight)} {
			text, _ := syscall.UTF16PtrFromString(value)
			cell := listViewItem{Item: int32(index), SubItem: int32(subItem + 1), Text: text}
			procSendMessageW.Call(uintptr(state.resultHWND), lvmSetitemtextw, uintptr(index), uintptr(unsafe.Pointer(&cell)))
		}
	}
	state.suppressListNotify = false
	win32ui.RedrawChildrenNow(state.mainHWND)

	if len(visible) == 0 {
		state.setDetail("当前筛选条件下没有待审词条。")
	} else {
		selection := listViewItem{State: lvisSelected | lvisFocused, StateMask: lvisSelected | lvisFocused}
		procSendMessageW.Call(uintptr(state.resultHWND), lvmSetitemstate, 0, uintptr(unsafe.Pointer(&selection)))
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
		sel, _, _ := procSendMessageW.Call(uintptr(state.resultHWND), lvmGetnextitem, ^uintptr(0), lvniSelected)
		selected = int(int32(sel))
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
	showWin32Info(fmt.Sprintf("已导出 %d 条待审项。\n\nJSON：%s\nTSV：%s", len(findings), jsonPath, tsvPath))
}

func (state *appState) isLoading() bool {
	state.mu.Lock()
	defer state.mu.Unlock()
	return state.loading
}

func setControlEnabled(hwnd syscall.Handle, enabled bool) {
	value := uintptr(0)
	if enabled {
		value = 1
	}
	procEnableWindow.Call(uintptr(hwnd), value)
}

func (state *appState) updateControlState() {
	loading := state.isLoading()
	setControlEnabled(state.searchHWND, !loading)
	setControlEnabled(state.ruleHWND, !loading)
	setControlEnabled(state.modeHWND, !loading)
	setControlEnabled(state.refreshHWND, !loading)
	state.mu.Lock()
	canExport := state.summary.DictPath != ""
	state.mu.Unlock()
	setControlEnabled(state.exportHWND, !loading && canExport)
	if loading {
		setWindowText(state.refreshHWND, "扫描中…")
		procSendMessageW.Call(uintptr(state.progressHWND), pbmSetMarquee, 1, 30)
		procShowWindow.Call(uintptr(state.progressHWND), 5)
	} else {
		setWindowText(state.refreshHWND, "重新扫描")
		procSendMessageW.Call(uintptr(state.progressHWND), pbmSetMarquee, 0, 0)
		procShowWindow.Call(uintptr(state.progressHWND), 0)
	}
	state.layoutControls(state.layout.clientW, state.layout.clientH)
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
