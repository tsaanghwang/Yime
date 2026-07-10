//go:build windows

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/userblocklist"
	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

func (state *appState) loadEntries() ([]userblocklist.Entry, error) {
	return userblocklist.LoadEntries(state.sourcePath)
}

func (state *appState) refreshList() {
	entries, err := state.loadEntries()
	if err != nil {
		setWindowText(state.statusHWND, err.Error())
		return
	}
	keyword := strings.TrimSpace(getWindowText(state.searchHWND))
	filtered := userblocklist.FilterEntries(entries, keyword)
	state.visibleEntries = filtered

	selected := state.selectedPhrases()
	selectedSet := map[string]bool{}
	for _, phrase := range selected {
		selectedSet[phrase] = true
	}

	procSendMessageW.Call(uintptr(state.listHWND), lbResetcontent, 0, 0)
	maxExtent := int32(0)
	for _, entry := range filtered {
		line := entry.Phrase
		text, _ := syscall.UTF16PtrFromString(line)
		index, _, _ := procSendMessageW.Call(uintptr(state.listHWND), lbAddstring, 0, uintptr(unsafe.Pointer(text)))
		if selectedSet[entry.Phrase] {
			procSendMessageW.Call(uintptr(state.listHWND), lbSetsel, index, 1)
		}
		if extent := int32(len(line) * 7); extent > maxExtent {
			maxExtent = extent
		}
	}
	if maxExtent < 640 {
		maxExtent = 640
	}
	procSendMessageW.Call(uintptr(state.listHWND), lbSethorizontalextent, uintptr(maxExtent), 0)
	win32ui.RedrawChildrenNow(state.mainHWND)
	state.updateSummary(len(entries), len(filtered))
	state.updateSelectionSummary()
}

func (state *appState) selectedPhrases() []string {
	count, _, _ := procSendMessageW.Call(uintptr(state.listHWND), lbGetselcount, 0, 0)
	selCount := int32(count)
	if selCount <= 0 {
		return nil
	}
	items := make([]int32, selCount)
	procSendMessageW.Call(uintptr(state.listHWND), lbGetselitems, uintptr(selCount), uintptr(unsafe.Pointer(&items[0])))
	phrases := make([]string, 0, len(items))
	for _, index := range items {
		if index < 0 || int(index) >= len(state.visibleEntries) {
			continue
		}
		phrases = append(phrases, state.visibleEntries[index].Phrase)
	}
	return phrases
}

func (state *appState) updateSummary(totalCount, visibleCount int) {
	setWindowText(state.summaryHWND, fmt.Sprintf("词表文件: %s", state.sourcePath))
	setWindowText(state.statusHWND, fmt.Sprintf("当前显示 %d / %d 条屏蔽词。保存后立即生效。", visibleCount, totalCount))
}

func (state *appState) updateSelectionSummary() {
	phrases := state.selectedPhrases()
	if len(phrases) == 0 {
		setWindowText(state.selectionHWND, "未选中词条")
		return
	}
	preview := phrases
	if len(preview) > 3 {
		preview = append([]string(nil), preview[:3]...)
	}
	text := strings.Join(preview, "、")
	if len(phrases) > 3 {
		text += " 等"
	}
	setWindowText(state.selectionHWND, fmt.Sprintf("已选中 %d 条：%s", len(phrases), text))
}

func (state *appState) addEntry() {
	phrase, ok := showPhraseDialog(state.mainHWND, "", "添加屏蔽词", "保存")
	if !ok {
		return
	}
	if _, err := userblocklist.NormalizePhrase(phrase); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	updated, err := userblocklist.UpsertPhrase(state.sourcePath, phrase)
	if err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	state.refreshList()
	if updated {
		setWindowText(state.statusHWND, "该词条已在屏蔽词表中。")
	} else {
		setWindowText(state.statusHWND, "已添加屏蔽词，输入时将不再显示该候选。")
	}
}

func (state *appState) deleteSelected() {
	phrases := state.selectedPhrases()
	if len(phrases) == 0 {
		showMessageBox("请先在列表中选中要删除的词条。", 0x10)
		return
	}
	if err := userblocklist.RemovePhrases(state.sourcePath, phrases); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	state.refreshList()
	setWindowText(state.statusHWND, fmt.Sprintf("已删除 %d 条屏蔽词。", len(phrases)))
}

func (state *appState) importEntries() {
	path, ok := showOpenFileDialog(state.mainHWND, state.userDir, "文本文件 (*.txt)\x00*.txt\x00所有文件 (*.*)\x00*.*\x00")
	if !ok {
		return
	}
	lines, err := readLinesFromFile(path)
	if err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	added, skipped, err := userblocklist.ImportPhrases(state.sourcePath, lines)
	if err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	state.refreshList()
	setWindowText(state.statusHWND, fmt.Sprintf("导入完成：新增 %d 条，跳过 %d 条。", added, skipped))
}

func (state *appState) exportEntries() {
	entries, err := state.loadEntries()
	if err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	defaultName := filepath.Join(state.userDir, "yime_blocklist_export.txt")
	path, ok := showSaveFileDialog(state.mainHWND, defaultName, "文本文件 (*.txt)\x00*.txt\x00")
	if !ok {
		return
	}
	lines := make([]string, 0, len(entries))
	for _, entry := range entries {
		lines = append(lines, entry.Phrase)
	}
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\r\n")+"\r\n"), 0o644); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	setWindowText(state.statusHWND, fmt.Sprintf("已导出 %d 条到：%s", len(entries), path))
}
