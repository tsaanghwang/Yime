from pathlib import Path
import re
root = Path(__file__).parents[1]
patterns = [r"ord\(", r"isascii\(", r"PUA", r"normalize\(", r"re\.match", r"re\.fullmatch", r"\\u[0-9A-Fa-f]{4}", r"isalpha\(", r"encode\("]
for p in root.rglob("*.py"):
    txt = p.read_text(encoding="utf-8", errors="ignore")
    for pat in patterns:
        if re.search(pat, txt):
            print(p, "->", pat)
            break
