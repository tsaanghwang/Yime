# 搜索 split_encoded_syllable 在 workspace 的引用
import pathlib, sys
root = pathlib.Path(r"C:\Users\Freeman Golden\OneDrive\Yime")
for p in root.rglob("*.py"):
    txt = p.read_text(encoding="utf-8", errors="ignore")
    if "split_encoded_syllable" in txt:
        print(p, txt.count("split_encoded_syllable"))