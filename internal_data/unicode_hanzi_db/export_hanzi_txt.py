import argparse
import csv
import sqlite3
from pathlib import Path


DB_FILE = Path(__file__).resolve().with_name("unicode_hanzi.db")
DEFAULT_OUTPUT_FILE = Path("C:/dev/Word-frequency/unicode_hanzi.txt")
DELIMITER = "\t"
OUTPUT_COMMENT = "# 本拼音库，绝大多数拼音由 pypinyin 生成，极少部分拼音抓取自汉典网(zdic.net)。"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export unicode_hanzi.db to a provided unicode_hanzi.txt output file.")
    parser.add_argument("--db", default=str(DB_FILE), help="Source unicode_hanzi.db path")
    parser.add_argument(
        "--output-file",
        default=str(DEFAULT_OUTPUT_FILE),
        help="Destination unicode_hanzi.txt path",
    )
    return parser.parse_args()


def export_hanzi_table(db_file: Path, output_file: Path) -> None:
    """导出 hanzi 表为制表符分隔文本。"""
    if not db_file.exists():
        raise FileNotFoundError(f"未找到数据库文件: {db_file}")

    output_file.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_file)
    cur = conn.cursor()

    cur.execute(
        """
        SELECT codepoint, hanzi, pinyin, pinyin_candidates
        FROM hanzi
        ORDER BY codepoint ASC
        """
    )

    with output_file.open("w", encoding="utf-8", newline="") as file_obj:
        file_obj.write(f"{OUTPUT_COMMENT}\n")
        writer = csv.writer(file_obj, delimiter=DELIMITER, lineterminator="\n")
        writer.writerow(["codepoint", "hanzi", "pinyin", "pinyin_candidates"])
        writer.writerows(cur)

    conn.close()

    print(f"导出完成: {output_file}")
    print("字段顺序: codepoint, hanzi, pinyin, pinyin_candidates")
    print(r"分隔符: \t")


if __name__ == "__main__":
    args = parse_args()
    export_hanzi_table(Path(args.db), Path(args.output_file))
