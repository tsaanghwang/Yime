"""Generate a Qin-seal (小篆) style 音 icon on a transparent canvas.

The icon uses the project's blue palette to match existing language-bar icons.
Output: yime_qin_seal_yin.ico with 256/48/32/16 sizes.

秦篆 "音" structure (说文解字):
  辛 (upper): 短横 + 丷 + 竖 + 长横
  日 (lower): 圆角矩形 + 中横
Key style: uniform stroke width, rounded turns, symmetric.
"""
from PIL import Image, ImageDraw
import math

STROKE = (46, 109, 164, 255)
FILL = (182, 208, 232, 255)
HILITE = (244, 247, 251, 255)

S = 256
SW = 11


def new_canvas():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def rounded_h_line(d, x1, x2, y, width=SW, color=STROKE):
    """Horizontal line with rounded caps."""
    d.line([(x1, y), (x2, y)], fill=color, width=width)
    r = width // 2
    d.ellipse([x1 - r, y - r, x1 + r, y + r], fill=color)
    d.ellipse([x2 - r, y - r, x2 + r, y + r], fill=color)


def rounded_v_line(d, x, y1, y2, width=SW, color=STROKE):
    """Vertical line with rounded caps."""
    d.line([(x, y1), (x, y2)], fill=color, width=width)
    r = width // 2
    d.ellipse([x - r, y1 - r, x + r, y1 + r], fill=color)
    d.ellipse([x - r, y2 - r, x + r, y2 + r], fill=color)


def rounded_diag(d, p1, p2, width=SW, color=STROKE):
    """Diagonal line with rounded caps."""
    d.line([p1, p2], fill=color, width=width, joint="curve")
    r = width // 2
    d.ellipse([p1[0] - r, p1[1] - r, p1[0] + r, p1[1] + r], fill=color)
    d.ellipse([p2[0] - r, p2[1] - r, p2[0] + r, p2[1] + r], fill=color)


def draw_seal_yin(img, d):
    cx = S // 2

    # --- 辛 (upper portion) ---
    top_y = 28
    diag_top_y = top_y + 20
    diag_bottom_y = 82
    mid_bar_y = 100
    sep_bar_y = 142

    # Top short horizontal stroke
    rounded_h_line(d, cx - 24, cx + 24, top_y)

    # 丷 shape: two diagonal strokes spreading downward from center
    left_p1 = (cx - 5, diag_top_y)
    left_p2 = (cx - 40, diag_bottom_y)
    right_p1 = (cx + 5, diag_top_y)
    right_p2 = (cx + 40, diag_bottom_y)
    rounded_diag(d, left_p1, left_p2)
    rounded_diag(d, right_p1, right_p2)

    # Vertical stroke from top through 丷 to middle bar
    rounded_v_line(d, cx, top_y + 6, mid_bar_y + 4)

    # Middle horizontal stroke (part of 辛)
    rounded_h_line(d, cx - 44, cx + 44, mid_bar_y)

    # Separator bar between 辛 and 日
    rounded_h_line(d, cx - 54, cx + 54, sep_bar_y)

    # --- 日 (lower portion) with rounded corners ---
    box_top = sep_bar_y + 8
    box_bottom = S - 28
    box_left = cx - 50
    box_right = cx + 50
    r = 12  # corner radius for 篆书 style

    # Fill background of 日 with light color
    d.rounded_rectangle([box_left, box_top, box_right, box_bottom], radius=r, fill=HILITE)

    # Draw rounded rectangle outline
    d.rounded_rectangle([box_left, box_top, box_right, box_bottom], radius=r, outline=STROKE, width=SW)

    # Middle horizontal bar inside 日
    bar_y = (box_top + box_bottom) // 2
    rounded_h_line(d, box_left + 16, box_right - 16, bar_y)


def save_ico(img, path):
    img.save(path, format="ICO", sizes=[(256, 256), (48, 48), (32, 32), (16, 16)])


if __name__ == "__main__":
    import sys

    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    img, d = new_canvas()
    draw_seal_yin(img, d)
    out_path = f"{outdir}/yime_qin_seal_yin.ico"
    save_ico(img, out_path)
    png_path = f"{outdir}/yime_qin_seal_yin.png"
    img.save(png_path, format="PNG")
    print(f"wrote {out_path} and {png_path}")
