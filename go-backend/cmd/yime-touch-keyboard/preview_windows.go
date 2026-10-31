//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"unicode/utf16"
	"unsafe"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

const previewHelp = "中文受控预览\n\n所有确认只写入本窗口内存文本，不调用系统输入，不写剪贴板或用户数据。\n变码/全码/简码切换会取消旧组合；语言键随当前输入显示 CN 或 EN；点按同时切换输入与标点，保留原始组合；英文暂停的候选不可选择。\n中文始终显示 CN；英文时 Layout 切换 CN/EN 键帽，偏好在本次运行内保留。\n点候选、空格/Enter 确认；空组合时空格/Enter 直接输出，非空无候选不提交。Esc 取消，退格编辑组合；翻页后旧候选及非编码主区输入触点取消。\n输出栏右侧提供左/右、Home/End 和选区开关；单指/单笔依次点按可选择，再输入替换或退格删除。辅助导航不继承盘面修饰键；其他操作关闭选区开关。有中文组合（含暂停组合）时不可用。Home/End 在预览到全文首尾。编辑按 Unicode 码点；本地输出用 ↵/⇥ 显示换行/Tab，单行随光标截取。\n侧数字区保持 literal 旁路。未标注标点入口开关默认关闭。\n音元字形来自实验解析文件，字体只在本进程加载；ID 按钮可恢复 ID 键帽。\n关闭即丢弃本地文本。不能将鼠标或模拟触摸记录为真实手指/触控笔验收。"

type previewGesture struct {
	area             rect
	left             bool
	action           string
	stamp            previewStamp
	candidate        candidatePress
	delivery         deliveryTicket
	navigation       string
	cancelGeneration uint64
}

func inside(r rect, x, y int32) bool { return x >= r.L && x < r.R && y >= r.T && y < r.B }

var previewButtons = []toolButton{
	{8, 90, "variable", "变码"}, {95, 177, "full", "全码"}, {182, 264, "shorthand", "简码"},
	{275, 350, "language", ""}, {360, 485, "literal", ""}, {495, 610, "glyphs", ""},
	{620, 690, "previous", "上一页"}, {695, 765, "next", "下一页"}, {775, 865, "reset", "清空输出"},
	{875, 1010, "sound", ""},
}

func (a *ui) previewWidth() int32 {
	return int32(math.Ceil(a.s.Board.Bounds.Width*tk.UnitMM*a.ppm)) + int32(a.border*2)
}
func (a *ui) candidateRect(i int) rect {
	w := (a.previewWidth() - 20) / 9
	if a.o.TouchUI {
		h := a.touchHeaderLayout()
		w = (h.candidates.R - h.candidates.L) / 9
		return rect{h.candidates.L + int32(i)*w, h.candidates.T, h.candidates.L + int32(i+1)*w - h.gap, h.candidates.B}
	}
	return rect{10 + int32(i)*w, 184, 10 + int32(i+1)*w - 3, 234}
}
func (a *ui) previewDown(id uint32, x, y int32) {
	if a.hostBusy {
		return
	}
	if _, exists := a.previewTouches[id]; exists {
		return
	}
	if !a.o.TouchUI && y < 104 {
		a.toolbar(x, y)
		return
	}
	g := &previewGesture{stamp: a.preview.stamp()}
	if key, area := a.navigationAt(x, y); key != "" {
		// Serialize navigation against other contacts and clear virtual modifiers.
		// The selection latch is independent of Shift and supports a single pen.
		extend := a.navSelecting
		a.cancel()
		if !a.preview.navigationEnabled() {
			a.status = "请先确认或取消中文组合（含暂停组合），再使用辅助导航"
			if a.o.TouchUI {
				a.touchMessage = a.status
			}
			a.invalidate()
			return
		}
		a.navSelecting = extend
		if a.o.TouchUI {
			a.touchSettingsOpen = false
			a.touchHelpOpen = false
		}
		g.action, g.navigation, g.area = "navigation", key, area
	} else {
		if a.navSelecting || a.navigationPending() {
			a.cancel()
		}
		if a.o.TouchUI {
			action, area, blocked := a.touchUIActionAt(x, y)
			if blocked {
				if action == "" {
					a.invalidate()
					return
				}
				g.action, g.area = action, area
			}
		}
		if g.action == "" {
			if int(y) >= a.top {
				g.action = "key"
				g.area = rect{0, int32(a.top), a.previewWidth(), 1 << 30}
				a.s.Down(id, (float64(x)-float64(a.border))/(tk.UnitMM*a.ppm), (float64(y)-float64(a.top))/(tk.UnitMM*a.ppm))
			} else {
				if !a.o.TouchUI {
					for _, b := range previewButtons {
						r := rect{b.l, 110, b.r, 150}
						if inside(r, x, y) {
							g.action, g.area = b.action, r
							break
						}
					}
				}
				if g.action == "" && a.preview.candidatesEnabled() {
					for i := range a.preview.snapshot.State.Candidates {
						r := a.candidateRect(i)
						if inside(r, x, y) {
							g.action, g.area, g.candidate = "candidate", r, a.preview.candidate(i)
							break
						}
					}
				}
			}
		}
	}
	if g.action != "" {
		if a.requiresHostTarget(g.action) {
			g.delivery = a.host.ticket()
			if !a.host.valid(g.delivery) {
				a.loseHostFocus("请先在目标文本区放置光标，再点绑定目标")
				return
			}
		}
		g.cancelGeneration = a.cancelGeneration
		a.previewTouches[id] = g
	}
	a.invalidate()
}
func (a *ui) previewUp(id uint32, x, y int32) {
	if a.hostBusy {
		a.cancel()
		return
	}
	g := a.previewTouches[id]
	if g == nil {
		return
	}
	a.move(id, x, y)
	delete(a.previewTouches, id) // A duplicate UP has no action or commit.
	if g.action == "sound" {
		if !g.left {
			a.cancel()
			if a.o.KeySound == "click" {
				a.o.KeySound = "off"
				a.stopKeySound()
			} else {
				a.o.KeySound = "click"
				a.clickFeedback() // One sample when turning sound on; muting stays silent.
			}
		}
		a.invalidate()
		return
	}
	if a.o.TouchUI && touchImmediateAction(g.action) {
		if !g.left && g.stamp == a.preview.stamp() {
			a.cancel()
			a.touchMessage = ""
			if err := a.applyTouchImmediate(g.action); err != nil {
				a.touchMessage = err.Error()
			} else if g.action != "close" && g.action != "minimize" && g.action != "help" {
				a.clickFeedback()
			}
		}
		a.invalidate()
		return
	}
	if a.host != nil {
		if g.action == "reset" {
			if !g.left {
				if a.o.TouchUI {
					a.touchSettingsOpen = false
					a.touchHelpOpen = false
				}
				if err := a.bindHost(); err != nil {
					a.status = err.Error()
				} else {
					a.clickFeedback()
				}
			}
			a.invalidate()
			return
		}
	}
	if a.requiresHostTarget(g.action) {
		a.hostBusy = true
		defer func() { a.hostBusy = false }()
		if !pumpHostMessages() {
			a.loseHostFocus("消息队列未稳定；动作取消")
			return
		}
		if g.cancelGeneration != a.cancelGeneration {
			a.status = "动作已取消；不执行旧触点"
			a.invalidate()
			return
		}
		if !a.host.valid(g.delivery) {
			a.loseHostFocus("目标已变化；本次动作取消，请重新绑定")
			return
		}
		a.hostSink(g.delivery, g.cancelGeneration)
	}
	var err error
	accepted := false
	if g.action == "key" {
		before := localKeyState(a.s)
		out := a.s.Up(id, (float64(x)-float64(a.border))/(tk.UnitMM*a.ppm), (float64(y)-float64(a.top))/(tk.UnitMM*a.ppm))
		accepted = out == nil && !g.left && before != localKeyState(a.s)
		if out != nil && !g.left {
			err = a.preview.apply(*out, g.stamp)
			accepted = out.Action.Type != "unsupported" && out.Action.Type != "disabled"
			if out.Action.Type == "toggle-language" || out.Action.Type == "toggle-layout" {
				a.cancel()
			}
		}
	} else if !g.left {
		if g.stamp != a.preview.stamp() {
			err = fmt.Errorf("状态已更新；本次触点取消")
		} else {
			accepted = true
			switch g.action {
			case "navigation":
				if g.navigation == "select" {
					a.navSelecting = !a.navSelecting
				} else {
					err = a.preview.navigate(g.navigation, a.navSelecting, g.stamp)
				}
			case "candidate":
				err = a.preview.selectCandidate(g.candidate)
			case "previous":
				err = a.preview.page(-1)
			case "next":
				err = a.preview.page(1)
			case "variable", "full", "shorthand":
				a.cancel()
				err = a.preview.switchMode(g.action)
			case "language":
				a.cancel()
				err = a.preview.apply(tk.Output{Action: tk.Action{Type: "toggle-language"}}, g.stamp)
			case "cancel":
				a.cancel()
				err = a.preview.apply(tk.Output{Action: tk.Action{Type: "clear"}}, g.stamp)
			case "layout":
				a.cancel()
				a.preview.englishView = !a.preview.englishView
			case "literal":
				a.cancel()
				a.preview.literalEntries = !a.preview.literalEntries
			case "glyphs":
				a.cancel()
				a.showGlyphs = !a.showGlyphs
			case "reset":
				if a.o.TouchUI {
					a.touchSettingsOpen = false
					a.touchHelpOpen = false
				}
				a.cancel()
				err = a.preview.apply(tk.Output{Action: tk.Action{Type: "clear"}}, g.stamp)
				if err == nil {
					a.preview.editor = previewEditor{}
				}
			}
		}
	}
	a.s.Original = a.preview.original()
	if a.host != nil && a.preview.fault {
		a.loseHostFocus("会话/发送已停止；请核对正文后重新绑定")
	}
	if err != nil {
		if a.o.TouchUI {
			a.touchMessage = err.Error()
		}
		a.navSelecting = false
		a.status = err.Error()
	} else {
		if a.o.TouchUI {
			a.touchMessage = ""
		}
		a.status = "预览输出只在本窗口；真实手指/触控笔验收未记录。"
		if a.host != nil {
			a.status = a.host.last
		}
	}
	if accepted && err == nil && !a.preview.fault {
		a.acceptedInputSerial++
		a.clickFeedback()
	}
	a.invalidate()
}
func (a *ui) drawPreview(dc uintptr, r rect) {
	p := a.preview
	palette := a.palette()
	for _, b := range previewButtons {
		title := b.label
		c := palette.panel
		if b.action == p.mode {
			c = palette.active
		}
		switch b.action {
		case "language":
			title = map[bool]string{true: "CN 中文", false: "EN 英文"}[p.snapshot.Modes.Input == "chinese"]
		case "literal":
			title = map[bool]string{true: "标点入口：开", false: "标点入口：关"}[p.literalEntries]
		case "glyphs":
			title = map[bool]string{true: "字形 → ID", false: "ID → 字形"}[a.showGlyphs]
		case "reset":
			if a.host != nil {
				title = "绑定目标"
			}
		case "sound":
			title = "按键音：关"
			if a.o.KeySound == "click" {
				title = "按键音：开"
				if a.soundUnavailable {
					title = "按键音：不可用"
				}
			}
		}
		fill(dc, rect{b.l, 110, b.r, 150}, c)
		text(dc, title, rect{b.l, 111, b.r, 149}, 0x25)
	}
	raw := p.snapshot.State.RawInput
	if raw == "" {
		raw = "（空）"
	}
	if p.snapshot.Modes.Input == "english" && p.snapshot.State.RawInput != "" {
		raw = "[中文组合暂停] " + raw
	}
	text(dc, fmt.Sprintf("组合：%s    第 %d 页    rev %d", raw, p.snapshot.State.PageNumber+1, p.snapshot.Revision), rect{10, 155, r.R - 10, 181}, 0x24)
	for i := range p.snapshot.State.Candidates {
		box := a.candidateRect(i)
		color, label := palette.candidate, p.candidateLabel(i)
		if !p.candidatesEnabled() {
			color, label = palette.disabled, label+"（暂停）"
		}
		fill(dc, box, color)
		text(dc, label, box, 0x11) // wrap long candidates inside their own target
	}
	outputRight := a.navigationRect(navigationButtons[0]).L - 8
	fill(dc, rect{10, 240, outputRight, 290}, palette.output)
	output := ""
	if a.host != nil {
		output = fmt.Sprintf("目标 HWND %d / 焦点 %d / 世代 %d：%s", a.host.target.Window, a.host.target.Focus, a.host.epoch, a.host.last)
		text(dc, output, rect{14, 242, outputRight - 4, 288}, 0x10)
	} else {
		output = p.editor.fittedDisplay(func(s string) bool { return previewTextWidth(dc, s) <= outputRight-18 })
		text(dc, output, rect{14, 242, outputRight - 4, 288}, 0x24) // single line, vertically centered
	}
	a.drawNavigation(dc)
}

func previewTextWidth(dc uintptr, s string) int32 {
	v := utf16.Encode([]rune(s))
	if len(v) == 0 {
		return 0
	}
	size := point{}
	ok, _, _ := G("GetTextExtentPoint32W").Call(dc, uintptr(unsafe.Pointer(&v[0])), uintptr(len(v)), uintptr(unsafe.Pointer(&size)))
	if ok == 0 {
		return math.MaxInt32
	}
	return size.X
}

func loadPreviewGlyphs(root string) (map[string]string, error) {
	data, err := os.ReadFile(filepath.Join(root, "prototypes/touch-terminal/encoding/manual_key_layout.resolved.json"))
	if err != nil {
		return nil, err
	}
	var source struct {
		Layers []struct {
			ID     string `json:"yinyuan_id"`
			Symbol string `json:"symbol_char"`
		} `json:"layers"`
	}
	if err = json.Unmarshal(data, &source); err != nil {
		return nil, err
	}
	glyphs := map[string]string{}
	for _, layer := range source.Layers {
		if layer.ID != "" && layer.Symbol != "" {
			glyphs[layer.ID] = layer.Symbol
		}
	}
	if len(glyphs) != 60 {
		return nil, fmt.Errorf("实验解析文件应包含 60 个基础音元字形，实际 %d", len(glyphs))
	}
	return glyphs, nil
}
