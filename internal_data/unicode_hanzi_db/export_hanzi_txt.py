import csv
import sqlite3
from shutil import copyfile
from pathlib import Path


DB_FILE = Path(__file__).resolve().with_name("unicode_hanzi.db")
TEMP_OUTPUT_FILE = Path(__file__).resolve().with_name("unicode_hanzi.export.txt")
MANUAL_SOURCE_FILE = Path(__file__).resolve().with_name("unicode_hanzi.txt")
DELIMITER = "\t"
OUTPUT_COMMENT = "# 本拼音库，绝大多数拼音由 pypinyin 生成，极少部分拼音抓取自汉典网(zdic.net)。"


def export_hanzi_table(output_file: Path) -> None:
    """导出 hanzi 表为制表符分隔文本。"""
    conn = sqlite3.connect(DB_FILE)
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


def promote_temp_export_to_manual_source() -> None:
    """把临时导出文件覆盖到手工维护源文件。"""
    if not TEMP_OUTPUT_FILE.exists():
        raise FileNotFoundError(f"未找到临时导出文件: {TEMP_OUTPUT_FILE}")

    copyfile(TEMP_OUTPUT_FILE, MANUAL_SOURCE_FILE)

    print(f"已更新手工维护源: {MANUAL_SOURCE_FILE}")
    print(f"来源临时导出文件: {TEMP_OUTPUT_FILE}")


def should_promote_temp_export() -> bool:
    """在终端中询问是否用临时导出文件覆盖手工维护源。"""
    print(f"临时导出文件: {TEMP_OUTPUT_FILE}")
    print(f"手工维护源文件: {MANUAL_SOURCE_FILE}")

    while True:
        answer = input("是否覆盖手工维护源文件？[y/N]: ").strip().lower()
        if answer in {"", "n", "no"}:
            return False
        if answer in {"y", "yes"}:
            return True
        print("请输入 y 或 n。")


if __name__ == "__main__":
    export_hanzi_table(TEMP_OUTPUT_FILE)
    if should_promote_temp_export():
        promote_temp_export_to_manual_source()
    else:
        print("已保留临时导出文件，未覆盖手工维护源文件。")
