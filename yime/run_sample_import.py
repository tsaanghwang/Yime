import argparse
from pathlib import Path
import sys

# 确保当前 yime/ 目录在 sys.path，使得 from pinyin_importer import PinyinImporter 能工作
ROOT = Path(__file__).parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from pinyin_importer import PinyinImporter  # 本地模块导入，适用于直接在 yime/ 目录运行

# 示例：小批量映射数据 {映射编号: 音元编码}
SAMPLE = {
    999001: "abcd",
    999002: "abce",
    999003: "abcf",
    # 新增样例：
    999004: "abbb",  # 后三字符相同
    999005: "abbc",  # 中间两个字符相同
    999006: "abcc",  # 后两个字符相同
}

def main():
    p = PinyinImporter()
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="真正写入数据库；默认仅 dry-run")
    args = parser.parse_args()

    # dry-run: 只生成默认字段并打印示例
    print("Running dry-run: 生成将要插入的记录（不写库）")
    to_insert = []
    for mid, code in SAMPLE.items():
        cols = p._generate_default_values(code)
        to_insert.append((mid, cols))
    print(f"Prepared {len(to_insert)} sample rows. 示例：")
    for mid, cols in to_insert[:20]:
        print(
            mid,
            {
                "全拼": cols.get("全拼"),
                "简拼": cols.get("简拼"),
                "干音": cols.get("干音"),
                "首音": cols.get("首音"),
                "呼音": cols.get("呼音"),
                "主音": cols.get("主音"),
                "末音": cols.get("末音"),
                "间音": cols.get("间音"),   # 中间两音
                "韵音": cols.get("韵音"),   # 后面两音
            },
        )

    if args.apply:
        print("WARNING: --apply 指定，开始将 SAMPLE 写入数据库（会清空音元拼音表）")
        confirm = input("确认继续并备份好数据库？输入 YES 才继续: ")
        if confirm.strip() == "YES":
            cnt = p.import_pinyin(SAMPLE)
            print("写入完成，新增记录数:", cnt)
        else:
            print("已取消。")

if __name__ == "__main__":
    main()
