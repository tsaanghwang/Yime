"""Generate the Qin-seal 音 icons using icons/yin.png as the foreground.

Preserve the source glyph's shape and antialiased transparency, tint it with
the profile's vivid seal-vermilion palette, and center it on a transparent
256-pixel canvas.
Output: yime_qin_seal_yin.png and an ICO with 256/48/32/16-pixel sizes.

Run with no arguments to update the repository icons, or pass an output folder.
Requires Pillow.
"""

import argparse
from pathlib import Path

from PIL import Image, ImageOps


ICON_DIR = Path(__file__).resolve().parents[1] / "go-backend/input_methods/yime/icons"
SOURCE_PATH = ICON_DIR / "yin.png"
# Vivid seal vermilion stays legible against both the light input switcher and
# the dark taskbar, while keeping the profile icon visually distinct.
STROKE = (238, 48, 35, 255)
S = 256
PADDING = 24
ICO_SIZES = [(256, 256), (48, 48), (32, 32), (16, 16)]


def draw_seal_yin():
    """Use the source alpha mask as the sole definition of the seal glyph."""
    with Image.open(SOURCE_PATH) as source:
        mask = source.convert("RGBA").getchannel("A")

    bounds = mask.getbbox()
    if bounds is None:
        raise ValueError(f"Foreground image is fully transparent: {SOURCE_PATH}")

    # Remove source margins, retaining the glyph's proportions and soft edges.
    mask = ImageOps.contain(
        mask.crop(bounds),
        (S - 2 * PADDING, S - 2 * PADDING),
        method=Image.Resampling.LANCZOS,
    )
    foreground = Image.new("RGBA", mask.size, STROKE)
    foreground.putalpha(mask)

    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img.alpha_composite(foreground, ((S - mask.width) // 2, (S - mask.height) // 2))
    return img


def save_ico(img, path):
    img.save(path, format="ICO", sizes=ICO_SIZES)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "outdir", nargs="?", type=Path, default=ICON_DIR,
        help="output folder (default: the repository's Yime icons folder)",
    )
    args = parser.parse_args()
    img = draw_seal_yin()
    args.outdir.mkdir(parents=True, exist_ok=True)
    out_path = args.outdir / "yime_qin_seal_yin.ico"
    png_path = args.outdir / "yime_qin_seal_yin.png"
    save_ico(img, out_path)
    img.save(png_path, format="PNG")
    print(f"wrote {out_path} and {png_path}")


if __name__ == "__main__":
    main()
