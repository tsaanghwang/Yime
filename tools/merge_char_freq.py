#!/usr/bin/env python3
"""Merge BCC char-frequency channel downloads into merged_char_freq.txt."""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CHAR_FREQ_DIR = REPO_ROOT / "external_data" / "char_freq"
OUTPUT = CHAR_FREQ_DIR / "merged_char_freq.txt"


def main() -> int:
    CHAR_FREQ_DIR.mkdir(parents=True, exist_ok=True)
    merged: dict[str, int] = {}

    for path in sorted(CHAR_FREQ_DIR.glob("*.txt")):
        if path.name.startswith("merged_") or path.name.startswith("word_freq_"):
            continue
        print(f"读取: {path.name}")
        lines = path.read_text(encoding="utf-8").splitlines()
        for line in lines[1:]:
            line = line.strip()
            if not line or "," not in line:
                continue
            char, freq_str = line.rsplit(",", 1)
            char = char.strip()
            try:
                freq = int(freq_str.strip())
            except ValueError:
                continue
            merged[char] = max(merged.get(char, 0), freq)

    OUTPUT.write_text(
        "char,freq\n"
        + "\n".join(f"{c},{f}" for c, f in sorted(merged.items(), key=lambda x: -x[1]))
        + "\n",
        encoding="utf-8",
    )

    print(f"合并: {len(merged):,} 条 -> {OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
