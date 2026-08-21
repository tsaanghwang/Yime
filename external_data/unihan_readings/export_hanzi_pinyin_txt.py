import argparse
import csv
import sqlite3
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_EXTERNAL_DATA = SCRIPT_DIR.parent
DB_FILE = SCRIPT_DIR / "unihan_readings.db"
DEFAULT_OUTPUT_FILE = REPO_EXTERNAL_DATA / "hanzi_pinyin.txt"
DELIMITER = "\t"
OUTPUT_COMMENT = (
    "# 本文件由 unihan_readings.db 的 mandarin_readings_merged 表导出（external_data/hanzi_pinyin.txt）。"
    "读音来自 Unicode Unihan Database 五列普通话字段（kTGHZ2013、kHanyuPinlu、kXHC1983、"
    "kHanyuPinyin、kMandarin）全量合并；merge 后补充「〇」(U+3007)；"
    "再经 mandarin_readings_corrections.txt 中 status=approved 条目覆盖。"
    "common_reading 为多音字常用读音；common_reading_source 标明常用音来源列或 correction/supplement；"
    "is_single：1 为单音，0 为多音。"
    "构建流水线见 external_data/unihan_readings/README.md 与 build_all.py。"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export mandarin_readings_merged table to tab-separated text.",
    )
    parser.add_argument("--db", default=str(DB_FILE), help="Source unihan_readings.db path")
    parser.add_argument(
        "--output-file",
        default=str(DEFAULT_OUTPUT_FILE),
        help="Destination export path (default: external_data/hanzi_pinyin.txt)",
    )
    return parser.parse_args()


def export_merged_table(db_file: Path, output_file: Path) -> None:
    """导出 mandarin_readings_merged 表为制表符分隔文本。"""
    if not db_file.exists():
        raise FileNotFoundError(f"未找到数据库文件: {db_file}")

    output_file.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_file)
    cur = conn.cursor()

    cur.execute(
        """
        SELECT codepoint, hanzi, common_reading, readings,
               common_reading_source, is_single
        FROM mandarin_readings_merged
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
    export_merged_table(Path(args.db), Path(args.output_file))
