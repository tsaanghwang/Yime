import argparse
import csv
import sqlite3
from pathlib import Path


DB_FILE = Path(__file__).resolve().with_name("hanzi_pinyin.db")
DEFAULT_OUTPUT_FILE = Path(__file__).resolve().with_name("pinyin.txt")
DELIMITER = "\t"
OUTPUT_COMMENT = "# 本拼音库，拼音原始数据绝大多数从 Unihan_Readings.txt 中提取，极小部分自汉典网 (zdic.net) 上抓取。目前数据库中包含了 Unicode 17.0 版的汉字及其对应的拼音，且每个汉字的拼音数据主要是采自汉典网的数据都经过了多轮人工校对和修正。强调说明，为便按照一字一音原则根据音元拼音编码输入单字双音汉字，这类汉字字音只取一个音节作为编码候选拼音。"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export hanzi_pinyin table to pinyin.txt.")
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
        SELECT codepoint, hanzi, common_reading, readings
        FROM hanzi_pinyin
        ORDER BY codepoint ASC
        """
    )

    with output_file.open("w", encoding="utf-8", newline="") as file_obj:
        file_obj.write(f"{OUTPUT_COMMENT}\n")
        writer = csv.writer(file_obj, delimiter=DELIMITER, lineterminator="\n")
        writer.writerow(["codepoint", "hanzi", "common_reading", "readings"])
        writer.writerows(cur)

    conn.close()

    print(f"导出完成: {output_file}")
    print("字段顺序: codepoint, hanzi, common_reading, readings")
    print(r"分隔符: \t")


if __name__ == "__main__":
    args = parse_args()
    export_hanzi_table(Path(args.db), Path(args.output_file))
