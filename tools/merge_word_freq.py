#!/usr/bin/env python3
"""Merge BCC word-frequency channel downloads into merged word/single-char outputs."""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
WORD_FREQ_DIR = REPO_ROOT / "external_data" / "word_freq"
CHAR_FREQ_DIR = REPO_ROOT / "external_data" / "char_freq"

OUTPUT_SINGLE = CHAR_FREQ_DIR / "word_freq_merged_single_char_freq.txt"
OUTPUT_MULTI = WORD_FREQ_DIR / "merged_word_freq.txt"


def main() -> int:
    WORD_FREQ_DIR.mkdir(parents=True, exist_ok=True)
    CHAR_FREQ_DIR.mkdir(parents=True, exist_ok=True)
    single: dict[str, int] = {}
    multi: dict[str, int] = {}

    for path in sorted(WORD_FREQ_DIR.glob("*.txt")):
        if path.name.startswith("merged_"):
            continue
        print(f"读取: {path.name}")
        lines = path.read_text(encoding="utf-8").splitlines()
        for line in lines[1:]:
            line = line.strip()
            if not line or "," not in line:
                continue
            word, freq_str = line.rsplit(",", 1)
            word = word.strip()
            try:
                freq = int(freq_str.strip())
            except ValueError:
                continue
            if len(word) == 1:
                single[word] = max(single.get(word, 0), freq)
            else:
                multi[word] = max(multi.get(word, 0), freq)

    OUTPUT_SINGLE.write_text(
        "char,freq\n"
        + "\n".join(f"{c},{f}" for c, f in sorted(single.items(), key=lambda x: -x[1]))
        + "\n",
        encoding="utf-8",
    )
    OUTPUT_MULTI.write_text(
        "word,freq\n"
        + "\n".join(f"{w},{f}" for w, f in sorted(multi.items(), key=lambda x: -x[1]))
        + "\n",
        encoding="utf-8",
    )

    print(f"单字: {len(single):,} 条 -> {OUTPUT_SINGLE.name}")
    print(f"多字: {len(multi):,} 条 -> {OUTPUT_MULTI.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
