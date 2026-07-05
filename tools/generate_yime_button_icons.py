"""Generate blue-themed .ico assets for the 用户词库 and 工具 language-bar buttons.

Palette matches the existing layout_*.ico icons:
  outline/stroke : (46,109,164)
  fill (light)   : (182,208,232)
  highlight      : (244,247,251)
"""
from PIL import Image, ImageDraw

OUTLINE = (46, 109, 164, 255)
FILL = (182, 208, 232, 255)
HILITE = (244, 247, 251, 255)
ACCENT = (120, 169, 214, 255)

S = 256  # supersample canvas
SW = 14  # stroke width at supersample scale


def new_canvas():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save_ico(img, path):
    # Downscale to the sizes the language bar uses; keep 16 and 32 for crispness.
    img.save(path, format="ICO", sizes=[(32, 32), (16, 16)])


def draw_lexicon(path):
    """An open book / dictionary."""
    img, d = new_canvas()
    # page area spans roughly the middle 80%
    left, right = 30, S - 30
    top, bottom = 60, S - 50
    midx = S // 2
    spine_dip = 18

    # Two page polygons (slight upward fan at the outer edges).
    left_page = [
        (left, top + 10),
        (midx, top + spine_dip),
        (midx, bottom - spine_dip),
        (left, bottom - 4),
    ]
    right_page = [
        (midx, top + spine_dip),
        (right, top + 10),
        (right, bottom - 4),
        (midx, bottom - spine_dip),
    ]
    d.polygon(left_page, fill=HILITE, outline=OUTLINE)
    d.polygon(right_page, fill=HILITE, outline=OUTLINE)
    # Re-stroke outlines thicker.
    d.line(left_page + [left_page[0]], fill=OUTLINE, width=SW, joint="curve")
    d.line(right_page + [right_page[0]], fill=OUTLINE, width=SW, joint="curve")
    # Spine.
    d.line([(midx, top + spine_dip), (midx, bottom - spine_dip)], fill=OUTLINE, width=SW)

    # Text lines on each page.
    for i in range(3):
        y = top + 45 + i * 34
        d.line([(left + 22, y), (midx - 24, y - 6)], fill=ACCENT, width=8)
        d.line([(midx + 24, y - 6), (right - 22, y)], fill=ACCENT, width=8)

    save_ico(img.resize((S, S), Image.LANCZOS), path)


def draw_tools(path):
    """A single wrench laid diagonally."""
    img, d = new_canvas()
    # Handle as a thick rounded diagonal bar from lower-left to upper-right.
    d.line([(70, S - 60), (S - 78, 78)], fill=OUTLINE, width=40)
    d.line([(70, S - 60), (S - 78, 78)], fill=FILL, width=22)

    # Open-end head (upper-right): a "C" ring.
    hx, hy, r = S - 66, 66, 46
    d.ellipse([hx - r, hy - r, hx + r, hy + r], fill=None, outline=OUTLINE, width=SW)
    d.ellipse([hx - r + 12, hy - r + 12, hx + r - 12, hy + r - 12], fill=HILITE, outline=OUTLINE, width=SW - 4)
    # Cut the ring opening facing up-right.
    d.polygon([(hx, hy), (hx + r + 14, hy - r - 14), (hx + r + 14, hy + 4), (hx + 6, hy - 4)], fill=(0, 0, 0, 0))
    d.polygon([(hx, hy), (hx + 4, hy - r - 14), (hx + r + 14, hy - r - 14)], fill=(0, 0, 0, 0))

    # Closed head (lower-left): a hex nut grip.
    gx, gy, gr = 74, S - 66, 44
    hexagon = []
    import math
    for k in range(6):
        a = math.radians(60 * k + 15)
        hexagon.append((gx + gr * math.cos(a), gy + gr * math.sin(a)))
    d.polygon(hexagon, fill=HILITE, outline=OUTLINE)
    d.line(hexagon + [hexagon[0]], fill=OUTLINE, width=SW, joint="curve")
    # Inner hole.
    d.ellipse([gx - 16, gy - 16, gx + 16, gy + 16], fill=None, outline=OUTLINE, width=SW - 4)

    save_ico(img, path)


if __name__ == "__main__":
    import sys
    outdir = sys.argv[1]
    draw_lexicon(outdir + "/lexicon.ico")
    draw_tools(outdir + "/tools.ico")
    print("wrote lexicon.ico and tools.ico to", outdir)
