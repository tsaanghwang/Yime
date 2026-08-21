import argparse
import csv
import sqlite3
from pathlib import Path

DB_FILE = Path(__file__).resolve().with_name("phrase_pinyin.db")
DEFAULT_OUTPUT_FILE = Path(__file__).resolve().with_name("phrase_pinyin.txt")
DELIMITER = "\t"
OUTPUT_COMMENT = (
    "# 本文件由 phrase_pinyin.db 的 phrase_pinyin 表导出（经音节码表校验后的词语读音）。"
    "数据源为 external_data/phrase_pinyin.txt（phrase-pinyin-data 冒号格式）；"
    "readings 中多条读音以 | 分隔。"
    "构建流水线见 internal_data/phrase_pinyin/build_valid_pinyin.py。"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export phrase_pinyin table to tab-separated text.")
    parser.add_argument("--db", default=str(DB_FILE), help="Source phrase_pinyin.db path")
    parser.add_argument(
        "--output-file",
        default=str(DEFAULT_OUTPUT_FILE),
        help="Destination phrase_pinyin.txt path",
    )
    return parser.parse_args()


def export_phrase_table(db_file: Path, output_file: Path) -> None:
    """导出 phrase_pinyin 表为制表符分隔文本。"""
    if not db_file.exists():
        raise FileNotFoundError(f"未找到数据库文件: {db_file}")

    output_file.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_file)
    cur = conn.cursor()

    cur.execute(
        """
        SELECT phrase, phrase_len, common_reading, readings
        FROM phrase_pinyin
        ORDER BY phrase_len ASC, phrase ASC
        """
    )
    rows = cur.fetchall()
    conn.close()

    header = ["phrase", "phrase_len", "common_reading", "readings"]

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
    export_phrase_table(Path(args.db), Path(args.output_file))
