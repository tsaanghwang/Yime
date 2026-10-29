//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"math"
	"strings"
)

func touchHelpPages() []string {
	var paragraphs, pages []string
	for _, line := range strings.Split(touchHelp, "\n") {
		if strings.TrimSpace(line) != "" {
			paragraphs = append(paragraphs, line)
		}
	}
	// The title is painted separately; keep every instruction paragraph.
	for i := 1; i < len(paragraphs); i += 2 {
		pages = append(pages, strings.Join(paragraphs[i:min(i+2, len(paragraphs))], "\n\n"))
	}
	return pages
}
func (a *ui) touchHelpPageRect(next bool) rect {
	h, _, _ := a.touchSettingMetrics()
	bottom := int32(math.Ceil(a.s.Board.Bounds.Height*tk.UnitMM*a.ppm)) + int32(a.top+a.border) - 16
	middle := a.previewWidth() / 2
	if next {
		return rect{middle + 8, bottom - h, a.previewWidth() - 16, bottom}
	}
	return rect{16, bottom - h, middle - 8, bottom}
}
func (a *ui) drawTouchHelp(dc uintptr, r rect) {
	p := a.palette()
	top := a.touchSettingsTop()
	fill(dc, rect{8, top, r.R - 8, r.B - 8}, p.background)
	old, _, _ := G("SelectObject").Call(dc, a.keyFont)
	defer G("SelectObject").Call(dc, old)
	G("SetTextColor").Call(dc, p.text)
	_, _, heading := a.touchSettingMetrics()
	pages := touchHelpPages()
	page := max(0, min(len(pages)-1, a.touchHelpPage))
	text(dc, fmt.Sprintf("帮助 %d/%d · 点上方“返回”继续输入", page+1, len(pages)), rect{20, top + 4, r.R - 20, top + heading - 4}, 0x24)
	footer := a.touchHelpPageRect(false)
	text(dc, pages[page], rect{20, top + heading + 8, r.R - 20, footer.T - 12}, 0x10|drawTextNoPrefix)
	for _, next := range []bool{false, true} {
		box := a.touchHelpPageRect(next)
		label, enabled := "上一页", page > 0
		if next {
			label, enabled = "下一页", page+1 < len(pages)
		}
		bg, fg := p.panel, p.text
		if a.touchPressed(box) {
			bg = p.active
		}
		if !enabled {
			fg = p.mutedText
		}
		fill(dc, box, bg)
		G("SetTextColor").Call(dc, fg)
		text(dc, label, box, 0x25)
	}
}
