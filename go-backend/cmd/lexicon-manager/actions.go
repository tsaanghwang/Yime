//go:build windows

package main

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/reverselookup"
	"github.com/EasyIME/pime-go/input_methods/yime/settings"
	"github.com/EasyIME/pime-go/input_methods/yime/systemlexicon"
	"github.com/EasyIME/pime-go/input_methods/yime/toolhub"
	"github.com/EasyIME/pime-go/input_methods/yime/userlexicon"
	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

var invokeRimeBuild = settings.InvokeRimeBuild

var errPhraseInSystemLexicon = errors.New("该词条已存在于系统词库中，无需重复添加")

func (state *appState) loadSourceEntries() ([]userlexicon.Entry, error) {
	return userlexicon.LoadSourceEntriesWithResolver(state.sourcePath, state.codeMap, state.mode)
}

func (state *appState) refreshList() {
	selected := state.selectedPhrases()
	entries, err := state.loadSourceEntries()
	if err != nil {
		setWindowText(state.statusHWND, err.Error())
		return
	}
	keyword := strings.TrimSpace(getWindowText(state.searchHWND))
	filtered := userlexicon.FilterEntries(entries, keyword)
	state.sortField = state.currentSortField()
	filtered = userlexicon.SortEntries(filtered, state.sortField, state.sortDescending)
	state.visibleEntries = filtered

	procSendMessageW.Call(uintptr(state.listHWND), lbResetcontent, 0, 0)
	selectedSet := map[string]bool{}
	for _, phrase := range selected {
		selectedSet[phrase] = true
	}
	maxExtent := int32(0)
	for _, entry := range filtered {
		line := fmt.Sprintf("%s    %s    %s", entry.Phrase, entry.Pinyin, entry.Weight)
		text, _ := syscall.UTF16PtrFromString(line)
		index, _, _ := procSendMessageW.Call(uintptr(state.listHWND), lbAddstring, 0, uintptr(unsafe.Pointer(text)))
		if selectedSet[entry.Phrase] {
			procSendMessageW.Call(uintptr(state.listHWND), lbSetsel, index, 1)
		}
		if extent := int32(len(line) * 7); extent > maxExtent {
			maxExtent = extent
		}
	}
	if maxExtent < 764 {
		maxExtent = 764
	}
	procSendMessageW.Call(uintptr(state.listHWND), lbSethorizontalextent, uintptr(maxExtent), 0)
	win32ui.RedrawChildrenNow(state.mainHWND)
	state.updateSummary(len(entries), len(filtered))
	state.updateSelectionSummary()
}

func (state *appState) currentSortField() userlexicon.SortField {
	index, _, _ := procSendMessageW.Call(uintptr(state.sortFieldHWND), 0x0147, 0, 0)
	switch index {
	case 1:
		return userlexicon.SortByPinyin
	case 2:
		return userlexicon.SortByWeight
	default:
		return userlexicon.SortByPhrase
	}
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
	pending := "状态：源词库与生成词库已同步。"
	if state.dirty {
		pending = "状态：源词库已修改，尚未应用。"
	}
	text := fmt.Sprintf("源词库：%s\r\n当前模式生成词库：%s    %s", state.sourcePath, state.rimeLexiconPath, pending)
	setWindowText(state.summaryHWND, text)

	sortLabel := "词条"
	switch state.sortField {
	case userlexicon.SortByPinyin:
		sortLabel = "拼音"
	case userlexicon.SortByWeight:
		sortLabel = "权重"
	}
	direction := "升序"
	if state.sortDescending {
		direction = "降序"
	}
	status := fmt.Sprintf("当前显示 %d / %d 条词条，按 %s %s 排序。", visibleCount, totalCount, sortLabel, direction)
	if state.dirty {
		status += " 源词库有未应用改动。"
	}
	setWindowText(state.statusHWND, status)
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

func (state *appState) saveUndoSnapshot(label string) {
	entries, err := state.loadSourceEntries()
	if err != nil {
		return
	}
	clones := make([]userlexicon.Entry, 0, len(entries))
	for _, entry := range entries {
		clones = append(clones, entry.Clone())
	}
	state.lastUndoEntries = clones
	state.lastUndoLabel = label
}

func (state *appState) addOperationHistory(text string) {
	entry := fmt.Sprintf("[%s] %s", time.Now().Format("15:04:05"), text)
	state.operationHistory = append([]string{entry}, state.operationHistory...)
	if len(state.operationHistory) > 12 {
		state.operationHistory = state.operationHistory[:12]
	}
}

func (state *appState) loadSystemLexicon() error {
	if state.systemLexiconOnce {
		return state.systemLexiconErr
	}
	state.systemLexiconOnce = true

	path := systemlexicon.DictPath(state.sharedDir, state.userDir, state.mode)
	entries, err := systemlexicon.LoadDictFile(path)
	if err != nil {
		state.systemLexiconErr = err
		return err
	}

	state.systemLexicon = make(map[string]struct{}, len(entries))
	for _, entry := range entries {
		phrase := strings.TrimSpace(entry.Text)
		if phrase == "" {
			continue
		}
		state.systemLexicon[phrase] = struct{}{}
	}
	return nil
}

func (state *appState) isSystemLexiconPhrase(phrase string) (bool, error) {
	if err := state.loadSystemLexicon(); err != nil {
		return false, err
	}
	_, ok := state.systemLexicon[strings.TrimSpace(phrase)]
	return ok, nil
}

func (state *appState) validateEntryForAdd(entry userlexicon.Entry) error {
	if err := userlexicon.AssertEntryFields(entry); err != nil {
		return err
	}
	exists, err := state.isSystemLexiconPhrase(entry.Phrase)
	if err != nil {
		return err
	}
	if exists {
		return errPhraseInSystemLexicon
	}
	return reverselookup.ValidateEntryForMode(state.codeMap, entry.Phrase, entry.Pinyin, state.mode)
}

func (state *appState) addEntry() {
	if err := state.requireCodeMap(); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	initial := userlexicon.Entry{Weight: userlexicon.DefaultEntryWeight}
	for {
		entry, result := showEntryDialog(state.mainHWND, initial, "添加用户词条", "保存")
		if result == entryDialogCanceled {
			return
		}
		if err := state.validateEntryForAdd(entry); err != nil {
			style := uintptr(0x10)
			if errors.Is(err, errPhraseInSystemLexicon) {
				style = 0x30
			}
			showMessageBox(err.Error(), style)
			initial = entry
			continue
		}
		state.saveUndoSnapshot("添加/更新词条")
		updated, err := userlexicon.UpsertSourceEntry(state.sourcePath, entry)
		if err != nil {
			showMessageBox(err.Error(), 0x10)
			return
		}
		state.dirty = true
		state.refreshList()
		if updated {
			state.addOperationHistory("更新词条：" + entry.Phrase)
			setWindowText(state.statusHWND, "已更新词条，点击“应用”生成三套用户词库。")
		} else {
			state.addOperationHistory("添加词条：" + entry.Phrase)
			setWindowText(state.statusHWND, "已添加词条，点击“应用”生成三套用户词库。")
		}
		initial = userlexicon.Entry{Weight: userlexicon.DefaultEntryWeight}
	}
}

func (state *appState) editSelected() {
	phrases := state.selectedPhrases()
	if len(phrases) == 0 {
		showNoticeDialog(state.mainHWND, "编辑", "请先在列表中选中要编辑的词条。")
		return
	}
	if len(phrases) > 1 {
		showNoticeDialog(state.mainHWND, "编辑", "编辑词条时请只选择一条。")
		return
	}
	if err := state.requireCodeMap(); err != nil {
		showNoticeDialog(state.mainHWND, "编辑失败", err.Error())
		return
	}
	entries, err := state.loadSourceEntries()
	if err != nil {
		showNoticeDialog(state.mainHWND, "编辑失败", err.Error())
		return
	}
	var existing *userlexicon.Entry
	for i := range entries {
		if entries[i].Phrase == phrases[0] {
			existing = &entries[i]
			break
		}
	}
	if existing == nil {
		showNoticeDialog(state.mainHWND, "编辑失败", "在源词库中找不到所选词条。")
		return
	}
	entry, result := showEntryDialog(state.mainHWND, existing.Clone(), "编辑用户词条", "保存修改")
	if result == entryDialogCanceled {
		return
	}
	if err := userlexicon.AssertEntryFields(entry); err != nil {
		showNoticeDialog(state.mainHWND, "编辑失败", err.Error())
		return
	}
	if err := reverselookup.ValidateEntryForMode(state.codeMap, entry.Phrase, entry.Pinyin, state.mode); err != nil {
		showNoticeDialog(state.mainHWND, "编辑失败", err.Error())
		return
	}
	state.saveUndoSnapshot("编辑词条")
	if entry.Phrase != existing.Phrase {
		if _, err := userlexicon.RemoveSourceEntry(state.sourcePath, existing.Phrase); err != nil {
			showNoticeDialog(state.mainHWND, "编辑失败", err.Error())
			return
		}
	}
	if _, err := userlexicon.UpsertSourceEntry(state.sourcePath, entry); err != nil {
		showNoticeDialog(state.mainHWND, "编辑失败", err.Error())
		return
	}
	state.dirty = true
	state.refreshList()
	state.addOperationHistory("编辑词条：" + entry.Phrase)
	setWindowText(state.statusHWND, "已编辑词条，点击“应用”生成三套用户词库。")
}

func (state *appState) deleteSelected() {
	phrases := state.selectedPhrases()
	if len(phrases) == 0 {
		showMessageBox("请先在列表中选中要删除的词条。", 0x10)
		return
	}
	message := fmt.Sprintf("确认要删除 %d 条词条吗？", len(phrases))
	if !showConfirmDialog(state.mainHWND, "删除词条", message) {
		return
	}
	state.saveUndoSnapshot("删除词条")
	for _, phrase := range phrases {
		if _, err := userlexicon.RemoveSourceEntry(state.sourcePath, phrase); err != nil {
			showMessageBox(err.Error(), 0x10)
			return
		}
	}
	state.dirty = true
	state.refreshList()
	state.addOperationHistory(fmt.Sprintf("删除词条 %d 条", len(phrases)))
	setWindowText(state.statusHWND, fmt.Sprintf("已从源词库删除 %d 条词条，点击“应用”生成三套用户词库。", len(phrases)))
}

func (state *appState) setSelectedWeights() {
	phrases := state.selectedPhrases()
	if len(phrases) == 0 {
		showMessageBox("请先选中要设置权重的词条。", 0x10)
		return
	}
	weight, ok := showWeightDialog(state.mainHWND, userlexicon.DefaultEntryWeight)
	if !ok {
		return
	}
	if _, err := strconv.Atoi(weight); err != nil {
		showMessageBox("权重必须是整数。", 0x10)
		return
	}
	entries, err := state.loadSourceEntries()
	if err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	selected := map[string]bool{}
	for _, phrase := range phrases {
		selected[phrase] = true
	}
	updated := 0
	for i := range entries {
		if !selected[entries[i].Phrase] {
			continue
		}
		entries[i].Weight = weight
		updated++
	}
	state.saveUndoSnapshot("批量设置权重 " + weight)
	if err := userlexicon.WriteSourceEntries(state.sourcePath, entries); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	state.dirty = true
	state.refreshList()
	state.addOperationHistory(fmt.Sprintf("批量设置权重 %d 条 -> %s", updated, weight))
	setWindowText(state.statusHWND, fmt.Sprintf("已将 %d 条词条的权重设为 %s。", updated, weight))
}

func (state *appState) undoLastChange() {
	if state.lastUndoEntries == nil {
		showNoticeDialog(state.mainHWND, "撤销", "当前没有可撤销的最近一次源词库改动。")
		return
	}
	if err := userlexicon.WriteSourceEntries(state.sourcePath, state.lastUndoEntries); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	state.dirty = true
	state.refreshList()
	setWindowText(state.statusHWND, "已撤销最近一次改动："+state.lastUndoLabel)
	state.addOperationHistory("撤销最近改动：" + state.lastUndoLabel)
	state.lastUndoEntries = nil
	state.lastUndoLabel = ""
}

func (state *appState) applyLexicon() {
	if err := state.requireCodeMap(); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	if err := state.rebuildAndDeployAllLexicons(); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	state.dirty = false
	state.refreshList()
	state.addOperationHistory("应用用户词库并重建三种模式")
	setWindowText(state.statusHWND, "已重建 variable / full / shorthand 三套用户词库。")
	showNoticeDialog(state.mainHWND, "应用完成", "用户词库格式校验通过，已重建 variable / full / shorthand 三套用户词库。")
}

func (state *appState) rebuildAllLexicons() error {
	for _, mode := range []reverselookup.Mode{
		reverselookup.ModeVariable,
		reverselookup.ModeFull,
		reverselookup.ModeShorthand,
	} {
		targetPath := userlexicon.RimeLexiconPath(state.userDir, string(mode))
		if err := userlexicon.RebuildRimeLexicon(state.sourcePath, targetPath, state.codeMap, mode); err != nil {
			return err
		}
	}
	return nil
}

func (state *appState) rebuildAndDeployAllLexicons() error {
	if err := state.rebuildAllLexicons(); err != nil {
		return err
	}
	return invokeRimeBuild(state.userDir, state.sharedDir)
}

func (state *appState) importLexicon() {
	if err := state.requireCodeMap(); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	path, ok := pickOpenFile(state.mainHWND, "导入用户词库", "文本文件 (*.txt;*.tsv)\x00*.txt;*.tsv\x00所有文件 (*.*)\x00*.*\x00")
	if !ok {
		return
	}
	importEntries, err := userlexicon.LoadSourceEntriesWithResolver(path, state.codeMap, state.mode)
	if err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	for _, entry := range importEntries {
		if err := reverselookup.ValidateEntryForMode(state.codeMap, entry.Phrase, entry.Pinyin, state.mode); err != nil {
			showMessageBox(err.Error(), 0x10)
			return
		}
	}
	currentEntries, err := state.loadSourceEntries()
	if err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	preview := userlexicon.BuildImportPreview(currentEntries, importEntries)
	message := fmt.Sprintf("导入词条数：%d\n新增：%d\n覆盖：%d\n相同：%d", len(importEntries), preview.NewCount, preview.ReplaceCount, preview.SameCount)
	if len(preview.Samples) > 0 {
		message += "\n示例：\n" + strings.Join(preview.Samples, "\n")
	}
	message += "\n\n请选择完全替换当前源词库，或按词条合并并覆盖同名项。"
	result := showImportModeDialog(state.mainHWND, message)
	if result == 0 {
		return
	}
	if result == idChoicePrimary {
		state.saveUndoSnapshot("导入词库（替换）")
		if err := userlexicon.WriteSourceEntries(state.sourcePath, importEntries); err != nil {
			showMessageBox(err.Error(), 0x10)
			return
		}
		state.dirty = true
		state.refreshList()
		state.addOperationHistory(fmt.Sprintf("替换导入词库：%d 条", len(importEntries)))
		setWindowText(state.statusHWND, "已替换当前源词库，点击“应用”生成三套用户词库。")
		return
	}
	selectedConflicts, ok := showImportPreviewDialog(state.mainHWND, preview)
	if !ok {
		return
	}
	filtered := userlexicon.FilterMergeImportEntries(currentEntries, importEntries, selectedConflicts)
	state.saveUndoSnapshot("导入词库（合并）")
	for _, entry := range filtered {
		if _, err := userlexicon.UpsertSourceEntry(state.sourcePath, entry); err != nil {
			showMessageBox(err.Error(), 0x10)
			return
		}
	}
	state.dirty = true
	state.refreshList()
	state.addOperationHistory(fmt.Sprintf("合并导入词库：新增/覆盖 %d 条", len(filtered)))
	setWindowText(state.statusHWND, "已合并导入到源词库，点击“应用”生成三套用户词库。")
}

func (state *appState) exportLexicon() {
	if err := userlexicon.EnsureSourceFile(state.sourcePath); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	path, ok := pickSaveFile(state.mainHWND, "导出用户词库", "yime_user_phrases.txt", "文本文件 (*.txt)\x00*.txt\x00TSV 文件 (*.tsv)\x00*.tsv\x00")
	if !ok {
		return
	}
	data, err := os.ReadFile(state.sourcePath)
	if err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	setWindowText(state.statusHWND, "已导出用户词库源文件。")
}

func (state *appState) openUserFolder() {
	if _, err := toolhub.Invoke(toolhub.Entry{ID: "open-folder", Label: "open", ActionType: toolhub.ActionOpenPath, TargetPath: state.userDir}); err != nil {
		showMessageBox(err.Error(), 0x10)
		return
	}
	setWindowText(state.statusHWND, "已打开用户词库目录。")
}
