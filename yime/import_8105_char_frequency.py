from __future__ import annotations

import sqlite3
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = Path(__file__).resolve().parent / "pinyin_hanzi.db"
SOURCE_PATH = WORKSPACE_ROOT / "external_data" / "8105.dict.yaml"
FREQUENCY_SOURCE = "external_data/8105.dict.yaml"


def parse_frequency_rows(path: Path) -> dict[str, int]:
    frequency_by_char: dict[str, int] = {}

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line in {"---", "..."}:
            continue
        if "\t" not in line:
            continue

        parts = line.split("\t")
        if len(parts) < 3:
            continue

        hanzi = parts[0].strip()
        frequency_text = parts[2].strip()
        if len(hanzi) != 1:
            continue

        try:
            absolute_frequency = int(frequency_text)
        except ValueError:
            continue

        previous = frequency_by_char.get(hanzi)
        if previous is None or absolute_frequency > previous:
            frequency_by_char[hanzi] = absolute_frequency

    return frequency_by_char


def import_frequency_rows(conn: sqlite3.Connection, frequency_by_char: dict[str, int]) -> tuple[int, int, int]:
    existing_chars = {
        row[0]: row[1]
        for row in conn.execute('SELECT "字符", "编号" FROM "汉字"')
    }

    if not frequency_by_char:
        return 0, 0, 0

    max_frequency = max(frequency_by_char.values())
    rows_to_insert: list[tuple[int, int, int, str]] = []
    skipped_missing_chars = 0

    # 最高频字为 10000，最低为 1，按比例分配
    for hanzi, absolute_frequency in frequency_by_char.items():
        char_id = existing_chars.get(hanzi)
        if char_id is None:
            skipped_missing_chars += 1
            continue

        if max_frequency:
            rel_freq = int(round(absolute_frequency / max_frequency * 9999)) + 1
        else:
            rel_freq = 1
        rows_to_insert.append((char_id, absolute_frequency, rel_freq, FREQUENCY_SOURCE))

    conn.executemany(
        '''
        INSERT OR REPLACE INTO "汉字频率" ("汉字编号", "绝对频率", "相对频率", "语料来源")
        VALUES (?, ?, ?, ?)
        ''',
        rows_to_insert,
    )

    return len(rows_to_insert), skipped_missing_chars, max_frequency


def write_import_metadata(conn: sqlite3.Connection, imported_count: int, skipped_count: int, max_frequency: int) -> None:
    rows = [
        ("prototype_8105_frequency_source", str(SOURCE_PATH), "8105 字频 YAML 导入来源"),
        ("prototype_8105_frequency_imported_rows", str(imported_count), "本次导入写入到汉字频率表的行数"),
        ("prototype_8105_frequency_skipped_rows", str(skipped_count), "源文件中因缺少对应汉字主表记录而跳过的行数"),
        ("prototype_8105_frequency_max_abs", str(max_frequency), "本次导入使用的最大绝对频率，用于相对频率归一化"),
    ]
    conn.executemany(
        '''
        INSERT OR REPLACE INTO prototype_metadata (key, value, note, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        rows,
    )


def main() -> None:
    frequency_by_char = parse_frequency_rows(SOURCE_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        imported_count, skipped_count, max_frequency = import_frequency_rows(conn, frequency_by_char)
        write_import_metadata(conn, imported_count, skipped_count, max_frequency)
        conn.commit()
    finally:
        conn.close()

    print(f"parsed unique chars: {len(frequency_by_char)}")
    print(f"imported frequency rows: {imported_count}")
    print(f"skipped missing chars: {skipped_count}")
    print(f"max absolute frequency: {max_frequency}")


if __name__ == "__main__":
    main()
