from __future__ import annotations

import sqlite3
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = Path(__file__).resolve().parent / "pinyin_hanzi.db"
SOURCE_PATH = WORKSPACE_ROOT / "external_data" / "xiandaihaiyuchangyongcibiao.txt"
FREQUENCY_SOURCE = "external_data/xiandaihaiyuchangyongcibiao.txt"

def parse_phrase_frequency(path: Path) -> dict[str, int]:
    freq_by_phrase: dict[str, int] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "\t" not in line:
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        phrase = parts[0].strip()
        freq_text = parts[2].strip()
        if len(phrase) <= 1:
            continue  # 跳过单字
        try:
            freq = int(freq_text)
        except ValueError:
            continue
        prev = freq_by_phrase.get(phrase)
        if prev is None or freq > prev:
            freq_by_phrase[phrase] = freq
    return freq_by_phrase

def update_phrase_frequencies(conn: sqlite3.Connection, freq_by_phrase: dict[str, int]) -> tuple[int, int]:
    # 只更新表中已有的多字词条
    phrase_id_map = {row[1]: row[0] for row in conn.execute('SELECT "编号", "词语" FROM "词汇" WHERE LENGTH("词语") > 1')}
    updated = 0
    skipped = 0
    for phrase, freq in freq_by_phrase.items():
        phrase_id = phrase_id_map.get(phrase)
        if phrase_id is None:
            skipped += 1
            continue
        conn.execute('UPDATE "词汇" SET "频率" = ? WHERE "编号" = ?', (freq, phrase_id))
        updated += 1
    return updated, skipped

def write_import_metadata(conn: sqlite3.Connection, updated: int, skipped: int) -> None:
    rows = [
        ("prototype_xiandaihaiyu_phrase_freq_source", str(SOURCE_PATH), "现代汉语常用词表词频导入来源"),
        ("prototype_xiandaihaiyu_phrase_freq_updated", str(updated), "本次更新到词汇表的多字词条数"),
        ("prototype_xiandaihaiyu_phrase_freq_skipped", str(skipped), "因词汇表无对应多字词而跳过的行数"),
    ]
    conn.executemany(
        '''
        INSERT OR REPLACE INTO prototype_metadata (key, value, note, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        rows,
    )

def main() -> None:
    freq_by_phrase = parse_phrase_frequency(SOURCE_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        updated, skipped = update_phrase_frequencies(conn, freq_by_phrase)
        write_import_metadata(conn, updated, skipped)
        conn.commit()
    finally:
        conn.close()
    print(f"parsed phrases: {len(freq_by_phrase)}")
    print(f"updated phrases: {updated}")
    print(f"skipped (not in db): {skipped}")

if __name__ == "__main__":
    main()
