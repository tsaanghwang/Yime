//go:build windows && (amd64 || arm64)

package main

// The two reviewed L-shaped keys have a full-height stem overlapping a wider
// lower foot. Insetting those overlapping rectangles preserves one continuous
// L contour; they are combined before any face or bevel is drawn.
type touchShapedKeycap struct {
	base, face []rect
	legend     rect
	bevel      int32
}

func touchShapedKeycapLayout(parts []rect, unit float64, pressed bool) touchShapedKeycap {
	var result touchShapedKeycap
	widest := int32(-1)
	for _, part := range parts {
		cap := touchKeycapLayout(part, unit, pressed)
		result.base = append(result.base, cap.base)
		result.face = append(result.face, cap.face)
		result.bevel = cap.bevel
		// A centered label belongs wholly inside the lower foot. Centering in
		// the L's bounding box can put Back Space into the concave notch.
		if width := part.R - part.L; width > widest {
			widest, result.legend = width, cap.legend
		}
	}
	return result
}

func shapedKeycapRegion(parts []rect) uintptr {
	region, _, _ := G("CreateRectRgn").Call(0, 0, 0, 0)
	if region == 0 {
		return 0
	}
	for _, r := range parts {
		part, _, _ := G("CreateRectRgn").Call(uintptr(r.L), uintptr(r.T), uintptr(r.R), uintptr(r.B))
		if part == 0 {
			G("DeleteObject").Call(region)
			return 0
		}
		combined, _, _ := G("CombineRgn").Call(region, region, part, 2) // RGN_OR
		G("DeleteObject").Call(part)
		if combined == 0 {
			G("DeleteObject").Call(region)
			return 0
		}
	}
	return region
}

func fillShapedKeycapRegion(dc, region, c uintptr) {
	brush, _, _ := G("CreateSolidBrush").Call(c)
	if brush != 0 {
		G("FillRgn").Call(dc, region, brush)
		G("DeleteObject").Call(brush)
	}
}

// Difference against a translated copy finds only the outside edges of the
// whole union, including its concave corner, without seams between its parts.
func shapedKeycapEdge(face uintptr, dx, dy int32) uintptr {
	edge, _, _ := G("CreateRectRgn").Call(0, 0, 0, 0)
	if edge == 0 {
		return 0
	}
	if copied, _, _ := G("CombineRgn").Call(edge, face, 0, 5); copied == 0 { // RGN_COPY
		G("DeleteObject").Call(edge)
		return 0
	}
	G("OffsetRgn").Call(edge, uintptr(dx), uintptr(dy))
	if combined, _, _ := G("CombineRgn").Call(edge, face, edge, 4); combined == 0 { // RGN_DIFF
		G("DeleteObject").Call(edge)
		return 0
	}
	return edge
}

func drawTouchShapedKeycap(dc uintptr, cap touchShapedKeycap, c uintptr, pressed bool) {
	base := shapedKeycapRegion(cap.base)
	if base == 0 {
		return
	}
	defer G("DeleteObject").Call(base)
	face := shapedKeycapRegion(cap.face)
	if face == 0 {
		return
	}
	defer G("DeleteObject").Call(face)
	fillShapedKeycapRegion(dc, base, keycapBlend(c, 0, 55))
	fillShapedKeycapRegion(dc, face, c)
	light, shade := keycapBlend(c, 0xffffff, 25), keycapBlend(c, 0, 28)
	if pressed {
		light, shade = shade, light
	}
	for _, edge := range []struct {
		delta int32
		color uintptr
	}{{-cap.bevel, shade}, {cap.bevel, light}} {
		region := shapedKeycapEdge(face, edge.delta, edge.delta)
		if region != 0 {
			fillShapedKeycapRegion(dc, region, edge.color)
			G("DeleteObject").Call(region)
		}
	}
}
