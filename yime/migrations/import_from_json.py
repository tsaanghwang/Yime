from pathlib import Path
import sys, json, sqlite3
ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT))

from pinyin_importer import PinyinImporter

json_path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "syllable_code.json"
if not json_path.exists():
    print("JSON not found:", json_path); sys.exit(1)

with open(json_path, "r", encoding="utf-8") as f:
    data = json.load(f)

p = PinyinImporter()
try:
    count = p.import_pinyin(data)
    print("import_pinyin returned:", count)
except sqlite3.IntegrityError as e:
    print("IntegrityError during import:", e)
    print("可能原因：导入的数据引用了在 表 '拼音映射关系' 中不存在的 映射编号，或外键约束不满足。")
    print("建议：")
    print("  1) 先运行 yime/Initialize_pinyin_mapping.py 填充/初始化 映射表：")
    print("     ./venv/Scripts/python.exe ./yime/Initialize_pinyin_mapping.py ./yime/syllable_code.json ./yime/pinyin_hanzi.db")
    print("  2) 或在导入前确保所有被引用的 映射编号 已存在于 表 '拼音映射关系'（可插入占位记录）。")
    print("  3) 若需我帮你生成占位映射插入脚本或定位触发错误的具体记录，请把完整 traceback 或 data 的示例片段贴上来。")
    sys.exit(2)
