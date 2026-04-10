from __future__ import annotations

import json
import sqlite3
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = Path(__file__).resolve().parent / "pinyin_hanzi.db"
DUOZI_JSON_PATH = WORKSPACE_ROOT / "pinyin" / "hanzi_pinyin" / "duozi_pinyin.json"


def load_duozi_data(path: Path) -> dict[str, list[str]]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def ensure_numeric_pinyin_rows(conn: sqlite3.Connection, duozi_data: dict[str, list[str]]) -> None:
    existing = {row[0] for row in conn.execute('SELECT "全拼" FROM "数字标调拼音"')}
    missing_rows: list[tuple[str, str | None, str, int]] = []

    for phrase_readings in duozi_data.values():
        for phrase_pinyin in phrase_readings:
            for syllable in phrase_pinyin.split():
                if syllable in existing:
                    continue
                tone_number = int(syllable[-1]) if syllable and syllable[-1].isdigit() else 5
                base_pinyin = syllable[:-1] if syllable and syllable[-1].isdigit() else syllable
                missing_rows.append((syllable, None, base_pinyin, tone_number))
                existing.add(syllable)

    if missing_rows:
        conn.executemany(
            '''
            INSERT OR IGNORE INTO "数字标调拼音" ("全拼", "声母", "韵母", "声调")
            VALUES (?, ?, ?, ?)
            ''',
            missing_rows,
        )


def build_phrase_yime_code(phrase_pinyin: str, numeric_pinyin_by_text: dict[str, tuple[int, int | None]], yime_by_mapping_id: dict[int, str]) -> str | None:
    syllable_codes: list[str] = []
    for syllable in phrase_pinyin.split():
        numeric_row = numeric_pinyin_by_text.get(syllable)
        if numeric_row is None:
            return None

        _, mapping_id = numeric_row
        if mapping_id is None:
            return None

        yime_code = yime_by_mapping_id.get(mapping_id)
        if yime_code is None:
            return None

        syllable_codes.append(yime_code)

    return " ".join(syllable_codes)


def import_phrases_and_mappings(conn: sqlite3.Connection, duozi_data: dict[str, list[str]]) -> tuple[int, int]:
    numeric_pinyin_rows = conn.execute(
        'SELECT "编号", "全拼", "映射编号" FROM "数字标调拼音"'
    ).fetchall()
    numeric_pinyin_by_text = {row[1]: (row[0], row[2]) for row in numeric_pinyin_rows}

    yime_by_mapping_id = {
        row[0]: row[1]
        for row in conn.execute('SELECT "映射编号", "全拼" FROM "音元拼音" WHERE "映射编号" IS NOT NULL')
    }

    phrase_rows: list[tuple[str, str | None, float, int, int]] = []
    phrase_map_rows: list[tuple[int, str, int, str, str]] = []

    for phrase, phrase_pinyin_list in duozi_data.items():
        phrase_length = len(phrase)
        primary_pinyin_tone = phrase_pinyin_list[0] if phrase_pinyin_list else ""
        primary_yime_code = build_phrase_yime_code(primary_pinyin_tone, numeric_pinyin_by_text, yime_by_mapping_id) if primary_pinyin_tone else None
        # 复用现有“词汇”表时，音元拼音列不能为空。
        # 若整词音元拼音暂时无法拼出，则先写入数字标调拼音串作占位，后续可批量回填真实编码。
        stored_phrase_code = primary_yime_code or primary_pinyin_tone
        phrase_rows.append((phrase, stored_phrase_code, 1.0, phrase_length, 1))

    conn.executemany(
        '''
        INSERT OR IGNORE INTO "词汇" ("词语", "音元拼音", "频率", "长度", "常用词语")
        VALUES (?, ?, ?, ?, ?)
        ''',
        phrase_rows,
    )

    phrase_id_by_text = {
        row[1]: row[0]
        for row in conn.execute('SELECT "编号", "词语" FROM "词汇"')
    }

    for phrase, phrase_pinyin_list in duozi_data.items():
        phrase_id = phrase_id_by_text[phrase]
        for index, phrase_pinyin in enumerate(phrase_pinyin_list, start=1):
            phrase_map_rows.append((
                phrase_id,
                phrase_pinyin,
                index,
                DUOZI_JSON_PATH.name,
                "多字拼音 JSON 导入",
            ))

    conn.executemany(
        '''
        INSERT OR REPLACE INTO phrase_pinyin_map (phrase_id, pinyin_tone, reading_rank, source_file, source_note)
        VALUES (?, ?, ?, ?, ?)
        ''',
        phrase_map_rows,
    )

    return len(phrase_rows), len(phrase_map_rows)


def write_import_metadata(conn: sqlite3.Connection, phrase_count: int, phrase_map_count: int) -> None:
    rows = [
        ("prototype_duozi_import_source", str(DUOZI_JSON_PATH), "词语拼音 JSON 导入来源"),
        ("prototype_duozi_phrase_rows", str(phrase_count), "本次导入覆盖的词语行数"),
        ("prototype_duozi_phrase_map_rows", str(phrase_map_count), "本次导入的词语到数字标调拼音映射行数"),
    ]
    conn.executemany(
        '''
        INSERT OR REPLACE INTO prototype_metadata (key, value, note, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        rows,
    )


def main() -> None:
    duozi_data = load_duozi_data(DUOZI_JSON_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('PRAGMA foreign_keys = ON')
        ensure_numeric_pinyin_rows(conn, duozi_data)
        phrase_count, phrase_map_count = import_phrases_and_mappings(conn, duozi_data)
        write_import_metadata(conn, phrase_count, phrase_map_count)
        conn.commit()
    finally:
        conn.close()

    print(f"imported phrases: {phrase_count}")
    print(f"phrase pinyin mappings: {phrase_map_count}")


if __name__ == "__main__":
    main()
