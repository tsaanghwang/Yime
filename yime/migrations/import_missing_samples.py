from pathlib import Path
import sys
ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT))

from pinyin_importer import PinyinImporter

SAMPLE = {999006: "abcc"}  # 只导入缺失项
p = PinyinImporter()
count = p.import_pinyin(SAMPLE)
print("import_pinyin returned:", count)
