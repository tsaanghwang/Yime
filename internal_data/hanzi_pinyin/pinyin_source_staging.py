import json
import re
import sqlite3
import sys
from pathlib import Path

DB_FILE = str(Path(__file__).parent / "hanzi_pinyin.db")
VALID_MARKED_PINYIN_PATH = Path(__file__).resolve().parents[2] / "internal_data" / "pinyin_source_db" / "lexicon_exports" / "pinyin_normalized.json"

TONE_CHAR_MAP = {
    "ā": "a1",
    "á": "a2",
    "ǎ": "a3",
    "à": "a4",
    "ē": "e1",
    "é": "e2",
    "ě": "e3",
    "è": "e4",
    "ế": "ê2",
    "ề": "ê4",
    "ī": "i1",
    "í": "i2",
    "ǐ": "i3",
    "ì": "i4",
    "ō": "o1",
    "ó": "o2",
    "ǒ": "o3",
    "ò": "o4",
    "ū": "u1",
    "ú": "u2",
    "ǔ": "u3",
    "ù": "u4",
    "ǖ": "ü1",
    "ǘ": "ü2",
    "ǚ": "ü3",
    "ǜ": "ü4",
    "ń": "n2",
    "ň": "n3",
    "ǹ": "n4",
    "ḿ": "m2",
}
NUMERIC_SYLLABLE_RE = re.compile(r"^[a-zêü]+[1-5]$")
TONE_MARK_CHARS = "āáǎàēéěèếềīíǐìōóǒòūúǔùǖǘǚǜńňǹḿ̄́̌̀"


def build_staging_table():
    conn = sqlite3.connect(DB_FILE)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS pinyin_source_staging (
            codepoint       TEXT PRIMARY KEY REFERENCES hanzi(codepoint) ON DELETE RESTRICT,
            hanzi           TEXT NOT NULL,
            common_reading  TEXT,
            readings        TEXT
        )
    """)

    conn.commit()

    count = cur.execute("SELECT COUNT(*) FROM pinyin_source_staging").fetchone()[0]

    conn.close()

    print(f"pinyin_source_staging 表已就绪，当前 {count:,} 条记录")
    print(f"数据库: {DB_FILE}")


def _is_untoned_pinyin(pinyin: str) -> bool:
    numeric = marked_syllable_to_numeric(pinyin)
    return numeric and numeric[-1] == '5'


def _reorder_candidates(candidates: list[str]) -> list[str]:
    if len(candidates) <= 1:
        return candidates
    toned = [p for p in candidates if not _is_untoned_pinyin(p)]
    untoned = [p for p in candidates if _is_untoned_pinyin(p)]
    return toned + untoned


def import_to_staging(source_path: str) -> None:
    path = Path(source_path)
    if not path.exists():
        raise FileNotFoundError(f"拼音源文件未找到: {path}")

    readings_map: dict[str, tuple[str, str]] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "#" in line:
            line = line.split("#", 1)[0].rstrip()
        if not line or ":" not in line:
            continue
        cp_part, rest = line.split(":", 1)
        codepoint = cp_part.strip().upper()
        if not codepoint.startswith("U+"):
            continue
        pinyin_part = rest.strip()
        if not pinyin_part:
            continue
        pinyin_list = [p.strip() for p in pinyin_part.split(",") if p.strip()]
        if not pinyin_list:
            continue
        pinyin_list = _reorder_candidates(pinyin_list)
        existing = readings_map.get(codepoint)
        if existing:
            merged = list(existing[1].split(",")) + pinyin_list
            seen: set[str] = set()
            deduped: list[str] = []
            for p in merged:
                if p not in seen:
                    seen.add(p)
                    deduped.append(p)
            deduped = _reorder_candidates(deduped)
            readings_map[codepoint] = (deduped[0], ",".join(deduped))
        else:
            readings_map[codepoint] = (pinyin_list[0], ",".join(pinyin_list))

    conn = sqlite3.connect(DB_FILE)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    cur.execute("DELETE FROM pinyin_source_staging")

    inserted = 0
    for codepoint, (common, readings) in readings_map.items():
        cur.execute("SELECT hanzi FROM hanzi WHERE codepoint = ?", (codepoint,))
        row = cur.fetchone()
        if not row:
            continue
        hanzi = row[0]
        cur.execute(
            "INSERT OR IGNORE INTO pinyin_source_staging (codepoint, hanzi, common_reading, readings) VALUES (?, ?, ?, ?)",
            (codepoint, hanzi, common, readings),
        )
        if cur.rowcount > 0:
            inserted += 1

    conn.commit()
    conn.close()

    print(f"staging 导入完成: {inserted:,} 条新记录 (来源: {path.name})")


def console_print(message: str) -> None:
    try:
        print(message)
    except UnicodeEncodeError:
        sys.stdout.buffer.write((message + "\n").encode(sys.stdout.encoding or "utf-8", errors="backslashreplace"))


def marked_syllable_to_numeric(marked: str) -> str:
    special_combining = {
        "ê̄": "ê1",
        "ê̌": "ê3",
        "ề": "ê4",
        "m̄": "m1",
        "m̌": "m3",
        "m̀": "m4",
        "n̄": "n1",
        "ň": "n3",
        "ǹ": "n4",
        "n̄g": "ng1",
        "ňg": "ng3",
        "ǹg": "ng4",
        "hm̄": "hm1",
        "hm̌": "hm3",
        "hm̀": "hm4",
        "hn̄": "hn1",
        "hň": "hn3",
        "hǹ": "hn4",
        "hn̄g": "hng1",
        "hňg": "hng3",
        "hǹg": "hng4",
    }
    if marked in special_combining:
        return special_combining[marked]

    numeric = marked + "5"
    for char in marked:
        if char in TONE_CHAR_MAP:
            replacement = TONE_CHAR_MAP[char]
            numeric = marked.replace(char, replacement[0]) + replacement[1]
            break
    return numeric


def load_valid_numeric_pinyin() -> list[str]:
    payload = json.loads(VALID_MARKED_PINYIN_PATH.read_text(encoding="utf-8"))
    return sorted(str(key).strip() for key in payload.keys() if str(key).strip())


def load_valid_plain_untoned_pinyin() -> set[str]:
    valid_numeric = getattr(load_valid_plain_untoned_pinyin, "_valid_plain_untoned", None)
    if valid_numeric is None:
        valid_numeric = {
            key[:-1]
            for key in load_valid_numeric_pinyin()
            if key and key[-1] in "12345"
        }
        setattr(load_valid_plain_untoned_pinyin, "_valid_plain_untoned", valid_numeric)
    return valid_numeric


def build_invalid_pinyin_rows(pinyin_candidates_str: str) -> list[tuple[str, str, str]]:
    valid_numeric = getattr(build_invalid_pinyin_rows, "_valid_numeric", None)
    if valid_numeric is None:
        valid_numeric = set(load_valid_numeric_pinyin())
        setattr(build_invalid_pinyin_rows, "_valid_numeric", valid_numeric)

    raw_candidates: list[str] = [c.strip() for c in pinyin_candidates_str.split(',') if c.strip()] if pinyin_candidates_str else []

    invalid_rows: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str, str]] = set()
    for marked in raw_candidates:
        if not marked:
            continue
        numeric = marked_syllable_to_numeric(marked)
        row = (marked, numeric, "")
        if row in seen:
            continue
        if not NUMERIC_SYLLABLE_RE.match(numeric):
            invalid_row = (marked, numeric, "invalid_numeric_shape")
            if invalid_row not in seen:
                seen.add(invalid_row)
                invalid_rows.append(invalid_row)
        elif numeric not in valid_numeric:
            invalid_row = (marked, numeric, "not_in_yinjie_codebook")
            if invalid_row not in seen:
                seen.add(invalid_row)
                invalid_rows.append(invalid_row)
    return invalid_rows


def classify_invalid_pinyin(marked: str, numeric: str, reason: str) -> str:
    if reason == "invalid_numeric_shape":
        return "multi_syllable_or_compound"
    if not any(char in TONE_MARK_CHARS for char in marked):
        return (
            "plain_untoned"
            if marked in load_valid_plain_untoned_pinyin()
            else "nonstandard"
        )
    return "toned_but_outside_codebook"


def create_views():
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    console_print("\n── 创建 staging 视图 ──")

    cur.execute("DROP VIEW IF EXISTS view_staging_with_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_staging_without_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_staging_with_multireadings")
    cur.execute("DROP VIEW IF EXISTS view_staging_single_reading_not_toned")
    cur.execute("DROP VIEW IF EXISTS view_staging_inspection")
    cur.execute("DROP VIEW IF EXISTS view_staging_invalid_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_staging_invalid_pinyin_summary")
    cur.execute("DROP VIEW IF EXISTS view_staging_invalid_pinyin_multisyllable")
    cur.execute("DROP VIEW IF EXISTS view_staging_invalid_pinyin_plain_untoned")
    cur.execute("DROP VIEW IF EXISTS view_staging_invalid_pinyin_nonstandard")
    cur.execute("DROP VIEW IF EXISTS view_staging_invalid_pinyin_toned_outside")
    cur.execute("DROP TABLE IF EXISTS staging_invalid_pinyin")

    cur.execute("""
        CREATE VIEW view_staging_with_pinyin AS
        SELECT codepoint, hanzi, common_reading, readings
        FROM pinyin_source_staging
        WHERE COALESCE(common_reading, '') <> ''
    """)

    cur.execute("""
        CREATE VIEW view_staging_without_pinyin AS
        SELECT codepoint, hanzi, common_reading, readings
        FROM pinyin_source_staging
        WHERE common_reading IS NULL OR common_reading = ''
    """)

    cur.execute("""
        CREATE VIEW view_staging_with_multireadings AS
        SELECT codepoint, hanzi, common_reading, readings
        FROM pinyin_source_staging
        WHERE COALESCE(common_reading, '') <> ''
          AND readings LIKE '%,%'
    """)

    cur.execute("""
        CREATE VIEW view_staging_single_reading_not_toned AS
        SELECT codepoint, hanzi, common_reading, readings
        FROM pinyin_source_staging
        WHERE COALESCE(common_reading, '') <> ''
          AND readings NOT LIKE '%,%'
          AND common_reading NOT GLOB '*[āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜńňǹḿ]*'
    """)

    cur.execute("""
        CREATE VIEW view_staging_inspection AS
        SELECT
            s.codepoint,
            s.hanzi,
            h.block,
            hf.frequency,
            s.common_reading AS pinyin,
            s.readings AS pinyin_candidates,
            CASE
                WHEN s.readings IS NULL OR s.readings = '' THEN 0
                ELSE LENGTH(s.readings) - LENGTH(REPLACE(s.readings, ',', '')) + 1
            END AS candidate_count,
            CASE
                WHEN TRIM(COALESCE(s.common_reading, '')) = '' THEN 0
                ELSE 1
            END AS has_pinyin,
            CASE
                WHEN s.readings IS NOT NULL
                     AND s.readings <> ''
                     AND LENGTH(s.readings) - LENGTH(REPLACE(s.readings, ',', '')) + 1 > 1 THEN 1
                ELSE 0
            END AS is_polyphonic,
            CASE
                WHEN s.readings IS NULL OR s.readings = '' THEN NULL
                WHEN INSTR(s.readings, ',') = 0 THEN s.readings
                ELSE SUBSTR(s.readings, 1, INSTR(s.readings, ',') - 1)
            END AS candidate_1,
            CASE
                WHEN s.readings IS NULL OR s.readings = '' THEN NULL
                WHEN LENGTH(s.readings) - LENGTH(REPLACE(s.readings, ',', '')) < 1 THEN NULL
                ELSE SUBSTR(
                    SUBSTR(s.readings, INSTR(s.readings, ',') + 1),
                    1,
                    CASE
                        WHEN INSTR(SUBSTR(s.readings, INSTR(s.readings, ',') + 1), ',') = 0
                        THEN LENGTH(SUBSTR(s.readings, INSTR(s.readings, ',') + 1))
                        ELSE INSTR(SUBSTR(s.readings, INSTR(s.readings, ',') + 1), ',') - 1
                    END
                )
            END AS candidate_2,
            CASE
                WHEN s.readings IS NULL OR s.readings = '' THEN NULL
                WHEN LENGTH(s.readings) - LENGTH(REPLACE(s.readings, ',', '')) < 2 THEN NULL
                ELSE SUBSTR(
                    SUBSTR(SUBSTR(s.readings, INSTR(s.readings, ',') + 1), INSTR(SUBSTR(s.readings, INSTR(s.readings, ',') + 1), ',') + 1),
                    1,
                    CASE
                        WHEN INSTR(SUBSTR(SUBSTR(s.readings, INSTR(s.readings, ',') + 1), INSTR(SUBSTR(s.readings, INSTR(s.readings, ',') + 1), ',') + 1), ',') = 0
                        THEN LENGTH(SUBSTR(SUBSTR(s.readings, INSTR(s.readings, ',') + 1), INSTR(SUBSTR(s.readings, INSTR(s.readings, ',') + 1), ',') + 1))
                        ELSE INSTR(SUBSTR(SUBSTR(s.readings, INSTR(s.readings, ',') + 1), INSTR(SUBSTR(s.readings, INSTR(s.readings, ',') + 1), ',') + 1), ',') - 1
                    END
                )
            END AS candidate_3,
            CASE
                WHEN hf.frequency >= 1000000 THEN 'very_high'
                WHEN hf.frequency >= 100000 THEN 'high'
                WHEN hf.frequency >= 10000 THEN 'medium'
                WHEN hf.frequency >= 1 THEN 'low'
                ELSE 'zero'
            END AS frequency_band
        FROM pinyin_source_staging s
        JOIN hanzi h ON s.codepoint = h.codepoint
        LEFT JOIN hanzi_frequency hf ON s.codepoint = hf.codepoint
    """)

    cur.execute("""
        CREATE TABLE staging_invalid_pinyin (
            codepoint TEXT NOT NULL REFERENCES hanzi(codepoint) ON DELETE CASCADE,
            candidate_rank INTEGER,
            invalid_marked_pinyin TEXT NOT NULL,
            invalid_numeric_pinyin TEXT NOT NULL,
            invalid_reason TEXT NOT NULL,
            invalid_group TEXT NOT NULL,
            PRIMARY KEY (codepoint, invalid_marked_pinyin)
        )
    """)

    invalid_rows_to_insert: list[tuple[str, int, str, str, str, str]] = []
    for codepoint, hanzi, pinyin, pinyin_candidates, frequency, block in cur.execute(
        "SELECT s.codepoint, s.hanzi, s.common_reading, s.readings, hf.frequency, h.block "
        "FROM pinyin_source_staging s "
        "JOIN hanzi h ON s.codepoint = h.codepoint "
        "LEFT JOIN hanzi_frequency hf ON s.codepoint = hf.codepoint"
    ):
        raw_candidates: list[str] = [c.strip() for c in pinyin_candidates.split(',') if c.strip()] if pinyin_candidates else []

        candidate_rank_by_marked: dict[str, int] = {}
        for index, marked in enumerate(raw_candidates, start=1):
            if marked and marked not in candidate_rank_by_marked:
                candidate_rank_by_marked[marked] = index

        for invalid_marked, invalid_numeric, invalid_reason in build_invalid_pinyin_rows(pinyin_candidates):
            invalid_group = classify_invalid_pinyin(invalid_marked, invalid_numeric, invalid_reason)
            invalid_rows_to_insert.append(
                (
                    codepoint,
                    candidate_rank_by_marked.get(invalid_marked, 0),
                    invalid_marked,
                    invalid_numeric,
                    invalid_reason,
                    invalid_group,
                )
            )

    if invalid_rows_to_insert:
        cur.executemany(
            """
            INSERT INTO staging_invalid_pinyin (
                codepoint,
                candidate_rank,
                invalid_marked_pinyin,
                invalid_numeric_pinyin,
                invalid_reason,
                invalid_group
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            invalid_rows_to_insert,
        )

    cur.execute("""
        CREATE VIEW view_staging_invalid_pinyin AS
        SELECT
            c.codepoint,
            h.hanzi,
            h.block,
            hf.frequency,
            s.common_reading AS primary_pinyin,
            c.candidate_rank,
            c.invalid_marked_pinyin,
            c.invalid_numeric_pinyin,
            c.invalid_reason,
            c.invalid_group
        FROM staging_invalid_pinyin c
        JOIN hanzi h ON c.codepoint = h.codepoint
        LEFT JOIN pinyin_source_staging s ON c.codepoint = s.codepoint
        LEFT JOIN hanzi_frequency hf ON c.codepoint = hf.codepoint
    """)

    cur.execute("""
        CREATE VIEW view_staging_invalid_pinyin_summary AS
        SELECT
            invalid_group,
            invalid_reason,
            COUNT(*) AS row_count,
            COUNT(DISTINCT codepoint) AS hanzi_count,
            MAX(frequency) AS max_frequency,
            SUM(CASE WHEN frequency > 0 THEN 1 ELSE 0 END) AS nonzero_frequency_rows
        FROM view_staging_invalid_pinyin
        GROUP BY invalid_group, invalid_reason
        ORDER BY row_count DESC, invalid_group ASC
    """)

    for name, group in [
        ("view_staging_invalid_pinyin_multisyllable", "multi_syllable_or_compound"),
        ("view_staging_invalid_pinyin_plain_untoned", "plain_untoned"),
        ("view_staging_invalid_pinyin_nonstandard", "nonstandard"),
        ("view_staging_invalid_pinyin_toned_outside", "toned_but_outside_codebook"),
    ]:
        cur.execute(f"""
            CREATE VIEW {name} AS
            SELECT * FROM view_staging_invalid_pinyin
            WHERE invalid_group = '{group}'
            ORDER BY frequency DESC, codepoint ASC, candidate_rank ASC
        """)

    conn.commit()

    cur.execute(
        "SELECT hanzi, pinyin, candidate_count, is_polyphonic, frequency_band "
        "FROM view_staging_inspection ORDER BY frequency DESC, codepoint ASC LIMIT 5"
    )
    console_print(f"view_staging_inspection 前5个: {cur.fetchall()}")

    cur.execute(
        "SELECT hanzi, primary_pinyin, invalid_marked_pinyin, invalid_reason "
        "FROM view_staging_invalid_pinyin ORDER BY frequency DESC, codepoint ASC LIMIT 5"
    )
    console_print(f"view_staging_invalid_pinyin 前5个: {cur.fetchall()}")

    cur.execute("SELECT invalid_group, invalid_reason, row_count FROM view_staging_invalid_pinyin_summary")
    console_print(f"view_staging_invalid_pinyin_summary: {cur.fetchall()}")

    conn.close()


if __name__ == "__main__":
    DEFAULT_PINYIN = str(Path(__file__).resolve().parents[2] / "external_data" / "pinyin.txt")
    DEFAULT_ZDIC = str(Path(__file__).resolve().parents[2] / "external_data" / "zdic.txt")

    print("选择导入源:")
    print(f"  1) 导入 pinyin.txt [默认]")
    print(f"  2) 导入 zdic.txt")
    print(f"  3) 输入自定义文件路径")
    choice = input("请选择 [1]: ").strip()

    if choice == "" or choice == "1":
        source_path = DEFAULT_PINYIN
    elif choice == "2":
        source_path = DEFAULT_ZDIC
    elif choice == "3":
        source_path = input("请输入文件路径: ").strip()
        if not source_path:
            print("未输入路径，退出")
            raise SystemExit(1)
    else:
        print("无效选择，退出")
        raise SystemExit(1)

    import_to_staging(source_path)
    create_views()
