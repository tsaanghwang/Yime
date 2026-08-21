import argparse
import csv
import sqlite3
from pathlib import Path

DB_FILE = Path(__file__).resolve().with_name("hanzi_pinyin.db")
DEFAULT_OUTPUT_FILE = Path(__file__).resolve().with_name("pinyin.txt")
DELIMITER = "\t"
OUTPUT_COMMENT = (
    "# 本文件由 hanzi_pinyin.db 的 hanzi_pinyin 表导出（含合规读音汉字，以及保留字形但无合规读音的来源字）。"
    "数据源为 external_data/hanzi_pinyin.txt（Unihan mandarin_readings_merged 导出），"
    "经 pinyin_source_staging 导入后直接写入 hanzi_pinyin。"
    "构建流水线见 internal_data/hanzi_pinyin/build_valid_pinyin.py。"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export hanzi_pinyin table to tab-separated text.")
    parser.add_argument("--db", default=str(DB_FILE), help="Source hanzi_pinyin.db path")
    parser.add_argument(
        "--output-file",
        default=str(DEFAULT_OUTPUT_FILE),
        help="Destination pinyin.txt path",
    )
    return parser.parse_args()


def export_hanzi_table(db_file: Path, output_file: Path) -> None:
    """导出 hanzi_pinyin 表为制表符分隔文本。"""
    if not db_file.exists():
        raise FileNotFoundError(f"未找到数据库文件: {db_file}")

    output_file.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_file)
    cur = conn.cursor()

    cur.execute(
        """
        SELECT codepoint, hanzi, common_reading, readings, common_reading_source, is_single
        FROM hanzi_pinyin
        ORDER BY codepoint ASC
        """
    )
    rows = cur.fetchall()
    conn.close()

    header = [
        "codepoint",
        "hanzi",
        "common_reading",
        "readings",
        "common_reading_source",
        "is_single",
    ]

    with output_file.open("w", encoding="utf-8", newline="") as file_obj:
        file_obj.write(f"{OUTPUT_COMMENT}\n")
        writer = csv.writer(file_obj, delimiter=DELIMITER, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)

    print(f"导出完成: {output_file} ({len(rows):,} 条)")
    print("字段顺序: " + ", ".join(header))
    print(r"分隔符: \t")


if __name__ == "__main__":
    args = parse_args()
    export_hanzi_table(Path(args.db), Path(args.output_file))
