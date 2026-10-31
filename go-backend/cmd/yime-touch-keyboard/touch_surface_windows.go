//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"math"
	"unsafe"
)

type touchHeaderLayout struct {
	status, previous, next, candidates rect
	height                             int
	gap                                int32
}

// Scale the header with the calibrated board, so a high-density screen does
// not leave tiny text and pager targets above otherwise readable keycaps.
func (a *ui) touchHeaderLayout() touchHeaderLayout {
	u := tk.UnitMM * a.ppm
	margin := max(int32(6), int32(math.Round(.04*u)))
	line := max(int32(32), int32(math.Round(.30*u)))
	// Match the current ordinary body key: one column wide, compressed body
	// height. This is not the original design's square unit.
	pager := max(int32(1), int32(math.Round(u)))
	row := max(int32(1), int32(math.Round(touchBodyHeightScale*u)))
	width := a.previewWidth()
	top, bottom := line+margin, line+margin+row
	previous := rect{margin, top, margin + pager, bottom}
	next := rect{width - margin - pager, top, width - margin, bottom}
	return touchHeaderLayout{
		status: rect{margin, 0, width - margin, line}, previous: previous, next: next,
		candidates: rect{previous.R + margin, top, next.L - margin, bottom},
		height:     int(bottom + margin), gap: 3,
	}
}

const touchHelp = "触屏试用版\n\n顶部大键提供设置、帮助、绑定/清空、取消、CN/EN、左右移动、Home/End、选区、全选、退格、Delete、最小化与退出；三个空闲键暂不执行操作。F1–F12不在本视图中。\n中文组合在顶部显示；点候选、空格或Enter确认，左右‹/›翻页。主区1–9按实验规则选择候选，0保持字面输入；未标注标点入口默认关闭。取消只取消未确认组合，保留已确认正文。\n编辑前先确认或取消组合；英文暂停的中文组合也会阻止编辑。点选区后，再依次点左右/Home/End扩展选区，输入替换或Delete/退格删除。预览Home/End到全文首尾，真实宿主按应用行为处理。\n设置中切换编码模式、英文键帽偏好、标点入口、字形/ID、声音、配色、字号及屏幕校准。切换编码模式取消原组合；中文始终使用原盘面，英文保留键帽偏好。点左上返回继续输入。\n预览只写本窗口内存，关闭即丢弃；正式宿主入口请先在正文放置光标，再点绑定。失焦、最小化、帮助或发送异常后须核对正文并重新绑定。\n输入键高为本次触屏试用的明确尺寸，不用校准按钮缩放盘面来凑尺寸。参考尺在设置内展开。"

var touchSettings = []string{"variable", "full", "shorthand", "layout", "literal", "glyphs", "sound", "theme", "font", "smaller", "larger", "ruler"}

func (a *ui) keyPixelRect(k tk.Key) rect {
	u := tk.UnitMM * a.ppm
	return rect{int32(float64(a.border) + k.X*u), int32(float64(a.top) + k.Y*u), int32(float64(a.border) + (k.X+k.Width)*u), int32(float64(a.top) + (k.Y+k.Height)*u)}
}
func (a *ui) touchControlAt(x, y int32) (string, rect) {
	for _, k := range a.s.Board.Keys {
		if k.Action.Type == "touch-ui" {
			r := a.keyPixelRect(k)
			if inside(r, x, y) {
				return k.Action.Key, r
			}
		}
	}
	return "", rect{}
}
func (a *ui) touchSettingsTop() int32 { return int32(float64(a.top) + touchBodyTopU*tk.UnitMM*a.ppm) }
func (a *ui) touchSettingMetrics() (int32, int32, int32) {
	u := tk.UnitMM * a.ppm
	return max(int32(32), int32(u*.55)), max(int32(6), int32(u*.08)), max(int32(30), int32(u*.28))
}
func (a *ui) touchSettingRect(i int) rect {
	w := (a.previewWidth() - 48) / 3
	left := int32(16) + int32(i%3)*w
	h, gap, heading := a.touchSettingMetrics()
	top := a.touchSettingsTop() + heading + int32(i/3)*(h+gap)
	return rect{left, top, left + w - 12, top + h}
}
func (a *ui) touchUIActionAt(x, y int32) (string, rect, bool) {
	if action, r := a.touchControlAt(x, y); action != "" {
		if action == "reserved" {
			return "", r, true
		}
		return action, r, true
	}
	if a.touchHelpOpen && y >= a.touchSettingsTop() {
		for _, next := range []bool{false, true} {
			r := a.touchHelpPageRect(next)
			if inside(r, x, y) {
				action := "help-previous"
				if next {
					action = "help-next"
				}
				return action, r, true
			}
		}
		return "", rect{}, true // Never type through the help sheet.
	}
	if a.touchSettingsOpen && y >= a.touchSettingsTop() {
		for i, action := range touchSettings {
			r := a.touchSettingRect(i)
			if inside(r, x, y) {
				return action, r, true
			}
		}
		return "", rect{}, true // Never type through the settings sheet.
	}
	header := a.touchHeaderLayout()
	for _, next := range []bool{false, true} {
		r := header.previous
		action := "previous"
		enabled := a.preview.snapshot.State.HasPrevious
		if next {
			r = header.next
			action = "next"
			enabled = a.preview.snapshot.State.HasNext
		}
		if inside(r, x, y) {
			if enabled && a.preview.candidatesEnabled() {
				return action, r, true
			}
			return "", r, true
		}
	}
	return "", rect{}, false
}
func (a *ui) requiresHostTarget(action string) bool {
	return a.host != nil && action != "reset" && action != "sound" && !(a.o.TouchUI && touchLocalConfiguration(action))
}
func (a *ui) touchPressed(r rect) bool {
	if !a.o.TouchUI {
		return false
	}
	for _, g := range a.previewTouches {
		if !g.left && g.action != "key" && g.area == r {
			return true
		}
	}
	return false
}
func (a *ui) touchLabels(k tk.Key, labels []string) []string {
	if k.Action.Type != "touch-ui" {
		return labels
	}
	name := ""
	switch k.Action.Key {
	case "help":
		if a.touchHelpOpen {
			name = "返回"
		}
	case "settings":
		if a.touchSettingsOpen {
			name = "返回"
		}
	case "language":
		name = "CN"
		if a.preview.snapshot.Modes.Input == "english" {
			name = "EN"
		}
	case "select":
		name = "选区：关"
		if a.navSelecting {
			name = "选区：开"
		}
	case "reset":
		if a.host == nil {
			name = "清空"
		}
	}
	if name == "" {
		return labels
	}
	result := make([]string, 12)
	result[4] = name
	return result
}
func touchImmediateAction(action string) bool {
	switch action {
	case "settings", "help", "help-previous", "help-next", "minimize", "close", "theme", "font", "ruler", "smaller", "larger":
		return true
	}
	return false
}
func (a *ui) applyTouchImmediate(action string) error {
	switch action {
	case "settings":
		a.touchHelpOpen = false
		a.touchSettingsOpen = !a.touchSettingsOpen
	case "help":
		a.showHelp()
	case "help-previous", "help-next":
		if a.touchHelpOpen {
			delta := -1
			if action == "help-next" {
				delta = 1
			}
			a.touchHelpPage = max(0, min(len(touchHelpPages())-1, a.touchHelpPage+delta))
		}
	case "minimize":
		a.minimize()
	case "close":
		U("DestroyWindow").Call(a.h)
	case "theme":
		if a.o.Theme == "dark" {
			a.o.Theme = "original"
		} else {
			a.o.Theme = "dark"
		}
	case "ruler":
		a.touchRuler = !a.touchRuler
	case "font":
		old := a.touchFontLevel
		a.touchFontLevel = (old + 1) % 3
		if err := a.updateTouchFonts(); err != nil {
			a.touchFontLevel = old
			return err
		}
	case "smaller", "larger":
		oldPPM, oldTop := a.ppm, a.top
		factor := 1.01
		if action == "smaller" {
			factor = 1 / factor
		}
		a.ppm *= factor
		if !a.resize() {
			a.ppm, a.top = oldPPM, oldTop
			return fmt.Errorf("当前尺寸超出屏幕；校准未改变")
		}
		if err := a.updateTouchFonts(); err != nil {
			a.ppm, a.top = oldPPM, oldTop
			if !a.resize() {
				return fmt.Errorf("%w；无法恢复窗口尺寸，请关闭后重新打开", err)
			}
			return err
		}
		return nil
	}
	return nil
}
func (a *ui) updateTouchFonts() error {
	if a.font == 0 {
		return nil
	}
	scale := []float64{0.8, 0.9, 1}[a.touchFontLevel]
	create := func(name string, ratio float64) uintptr {
		height := -int32(math.Round(tk.UnitMM * a.ppm * ratio * scale))
		h, _, _ := G("CreateFontW").Call(uintptr(height), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str(name)))
		return h
	}
	key, glyph := create("Segoe UI", 0.20), create("YinYuan", 0.23)
	// Header text uses the same regular size as the controls. The fallback
	// for unusually long candidates also follows board calibration.
	candidate, fallback := create("Segoe UI", .20), create("Segoe UI", .16)
	if key == 0 || glyph == 0 || candidate == 0 || fallback == 0 {
		if key != 0 {
			G("DeleteObject").Call(key)
		}
		if glyph != 0 {
			G("DeleteObject").Call(glyph)
		}
		if candidate != 0 {
			G("DeleteObject").Call(candidate)
		}
		if fallback != 0 {
			G("DeleteObject").Call(fallback)
		}
		return fmt.Errorf("无法更新键面与候选字号")
	}
	if a.keyFont != 0 {
		G("DeleteObject").Call(a.keyFont)
	}
	if a.glyphFont != 0 {
		G("DeleteObject").Call(a.glyphFont)
	}
	if a.candidateFont != 0 {
		G("DeleteObject").Call(a.candidateFont)
	}
	if a.touchFont != 0 {
		G("DeleteObject").Call(a.touchFont)
	}
	a.keyFont, a.glyphFont, a.candidateFont, a.touchFont = key, glyph, candidate, fallback
	return nil
}

func (a *ui) touchCandidateFont(dc uintptr, label string, box rect) uintptr {
	if a.candidateFont == 0 {
		return a.touchFont
	}
	old, _, _ := G("SelectObject").Call(dc, a.candidateFont)
	defer G("SelectObject").Call(dc, old)
	measured := box
	// Measure with the same wrapping and prefix rules as the actual drawing.
	height, _, _ := U("DrawTextW").Call(dc, ptr(str(label)), ^uintptr(0), uintptr(unsafe.Pointer(&measured)), 0x411|drawTextNoPrefix)
	if height == 0 || measured.B > box.B || measured.R > box.R {
		// Keep long candidates inside the row when the regular font cannot fit.
		return a.touchFont
	}
	return a.candidateFont
}

func (a *ui) drawTouchCandidate(dc uintptr, label string, box rect) {
	old, _, _ := G("SelectObject").Call(dc, a.touchCandidateFont(dc, label, box))
	defer G("SelectObject").Call(dc, old)
	text(dc, label, box, 0x11)
}

func (a *ui) drawTouchHeader(dc uintptr, r rect) {
	p, palette := a.preview, a.palette()
	header := a.touchHeaderLayout()
	font := a.candidateFont
	if font == 0 {
		font = a.keyFont
	}
	old, _, _ := G("SelectObject").Call(dc, font)
	defer G("SelectObject").Call(dc, old)
	G("SetTextColor").Call(dc, palette.text)
	line := "CN"
	if p.snapshot.Modes.Input == "english" {
		line = "EN"
	}
	if raw := p.snapshot.State.RawInput; raw != "" {
		line = "组合：" + raw
		if p.snapshot.Modes.Input == "english" {
			line = "暂停组合：" + raw
		}
	}
	if p.snapshot.SymbolChoice {
		line += fmt.Sprintf("  |  省略号：%d次，请选候选", p.snapshot.PendingMiddleDots)
	} else if p.snapshot.PendingMiddleDots > 0 {
		line += fmt.Sprintf("  |  中点待合并：%d/3", p.snapshot.PendingMiddleDots)
	}
	if a.touchMessage != "" {
		line += "  |  " + a.touchMessage
	} else if a.host != nil {
		if a.host.target.Window == 0 {
			line += "  |  先在正文点光标，再点“绑定”"
		} else {
			line += "  |  已绑定目标"
		}
	} else {
		limit := header.status.R - header.status.L - previewTextWidth(dc, line+"  |  ")
		line += "  |  " + p.editor.fittedDisplay(func(s string) bool { return previewTextWidth(dc, s) < limit })
	}
	text(dc, line, header.status, 0x8024)
	for i := range p.snapshot.State.Candidates {
		box := a.candidateRect(i)
		bg := palette.candidate
		s := p.candidateLabel(i)
		if !p.candidatesEnabled() {
			bg = palette.disabled
			s += "（暂停）"
		}
		fill(dc, box, bg)
		a.drawTouchCandidate(dc, s, box)
	}
	for _, next := range []bool{false, true} {
		box := header.previous
		name := "‹"
		enabled := p.snapshot.State.HasPrevious
		if next {
			box = header.next
			name = "›"
			enabled = p.snapshot.State.HasNext
		}
		fill(dc, box, palette.panel)
		fg := palette.text
		if !enabled || !p.candidatesEnabled() {
			fg = palette.mutedText
		}
		G("SetTextColor").Call(dc, fg)
		text(dc, name, box, 0x25)
	}
}
func (a *ui) touchSettingLabel(action string) string {
	switch action {
	case "variable":
		return "变码"
	case "full":
		return "全码"
	case "shorthand":
		return "简码"
	case "layout":
		if a.preview.englishView {
			return "英文键帽：EN"
		}
		return "英文键帽：原盘面"
	case "literal":
		if a.preview.literalEntries {
			return "标点入口：开"
		}
		return "标点入口：关"
	case "glyphs":
		if a.showGlyphs {
			return "音元显示：字形"
		}
		return "音元显示：ID"
	case "sound":
		if a.o.KeySound == "click" {
			if a.soundUnavailable {
				return "按键音：不可用"
			}
			return "按键音：开"
		}
		return "按键音：关"
	case "theme":
		if a.o.Theme == "dark" {
			return "配色：深灰"
		}
		return "配色：原色"
	case "font":
		return "键面/候选字号：" + []string{"小", "中", "大"}[a.touchFontLevel]
	case "smaller":
		return "校准 −1%"
	case "larger":
		return "校准 +1%"
	case "ruler":
		if a.touchRuler {
			return "参考尺：显示"
		}
		return "参考尺：收起"
	}
	return action
}
func (a *ui) drawTouchSettings(dc uintptr, r rect) {
	p := a.palette()
	top := a.touchSettingsTop()
	fill(dc, rect{8, top, r.R - 8, r.B - 8}, p.background)
	old, _, _ := G("SelectObject").Call(dc, a.keyFont)
	defer G("SelectObject").Call(dc, old)
	G("SetTextColor").Call(dc, p.text)
	h, gap, heading := a.touchSettingMetrics()
	text(dc, "设置 · 点左上“返回”继续输入", rect{20, top + 4, r.R - 20, top + heading - 4}, 0x24)
	for i, action := range touchSettings {
		box := a.touchSettingRect(i)
		bg := p.panel
		if action == a.preview.mode || a.touchPressed(box) {
			bg = p.active
		}
		fill(dc, box, bg)
		text(dc, a.touchSettingLabel(action), box, 0x25)
	}
	y := top + heading + 4*(h+gap) + 8
	text(dc, "尺寸校准仅用于校准屏幕。视图：触屏试用 v2；字号、配色与声音仅本次运行有效。", rect{20, y, r.R - 20, y + 36}, 0x24)
	if a.touchRuler {
		right := int32(30 + math.Round(100*a.ppm))
		fill(dc, rect{30, y + 48, right, y + 51}, p.ruler)
		text(dc, "100 mm 参考线 · 用实体尺测量", rect{30, y + 56, right, min(r.B-8, y+96)}, 0x25)
	}
}
