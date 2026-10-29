//go:build windows && (amd64 || arm64)

package main

import (
	"path/filepath"
	"testing"
)

// Compare the actual bottom-legend path with the complete same-font glyph.
// This catches clipped private-font descenders even when the text rectangle
// itself remains within the key.
func TestBottomYinyuanLegendKeepsCompleteGlyph(t *testing.T) {
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	glyphs, err := loadPreviewGlyphs(root)
	if err != nil {
		t.Fatal(err)
	}
	fontPath := filepath.Join(root, "go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf")
	if n, _, _ := G("AddFontResourceExW").Call(ptr(str(fontPath)), 0x10, 0); n == 0 {
		t.Fatal("load private font")
	}
	defer G("RemoveFontResourceExW").Call(ptr(str(fontPath)), 0x10, 0)
	dc, _, _ := G("CreateCompatibleDC").Call(0)
	defer G("DeleteDC").Call(dc)
	bitmap, _, _ := G("CreateCompatibleBitmap").Call(dc, 180, 180)
	oldBitmap, _, _ := G("SelectObject").Call(dc, bitmap)
	defer func() { G("SelectObject").Call(dc, oldBitmap); G("DeleteObject").Call(bitmap) }()
	G("SetTextColor").Call(dc, 0)
	G("SetBkMode").Call(dc, 1)
	ink := func() int {
		count := 0
		for y := uintptr(0); y < 180; y++ {
			for x := uintptr(0); x < 180; x++ {
				v, _, _ := G("GetPixel").Call(dc, x, y)
				if v != 0xffffff {
					count++
				}
			}
		}
		return count
	}
	for _, pixels := range []int32{19, 36} {
		height := -pixels
		font, _, _ := G("CreateFontW").Call(uintptr(height), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str("YinYuan")))
		previous, _, _ := G("SelectObject").Call(dc, font)
		for _, id := range []string{"N12", "M12", "M05"} {
			glyph := glyphs[id]
			if glyph == "" {
				t.Fatal("missing fixture glyph", id)
			}
			fill(dc, rect{0, 0, 180, 180}, 0xffffff)
			text(dc, glyph, rect{8, 8, 172, 172}, 0x20)
			want := ink()
			for _, bottom := range []int32{160, 129} { // Classic 156px and touch 125px key heights.
				fill(dc, rect{0, 0, 180, 180}, 0xffffff)
				drawKeyLegend(dc, glyph, rect{4, 4, 160, bottom}, 6)
				if got := ink(); got != want || want == 0 {
					t.Errorf("%s at %dpx: bottom legend has %d ink pixels; complete glyph has %d", id, pixels, got, want)
				}
				for y := uintptr(0); y < 180; y++ {
					for x := uintptr(0); x < 180; x++ {
						if x >= 4 && x < 160 && y >= 4 && y < uintptr(bottom) {
							continue
						}
						v, _, _ := G("GetPixel").Call(dc, x, y)
						if v != 0xffffff {
							t.Fatalf("%s at %dpx: legend spills outside its key", id, pixels)
						}
					}
				}
			}
		}
		G("SelectObject").Call(dc, previous)
		G("DeleteObject").Call(font)
	}
}
