import sqlite3
import sys
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from yime.utils.dictionary_pinyin_compliance import canonicalize_reading, load_policy

DB_FILE = str(Path(__file__).parent / "phrase_pinyin.db")


def _split_syllables(pinyin_str: str) -> list[str]:
    return [p.strip() for p in pinyin_str.split() if p.strip()]


def import_to_staging(source_path: str, db_path: str | Path = DB_FILE) -> None:
    path = Path(source_path)
    if not path.exists():
        raise FileNotFoundError(f"词语拼音源文件未找到: {path}")

    policy = load_policy()
    readings_map: dict[str, tuple[int, str, str]] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        phrase_part, pinyin_part = line.split(":", 1)
        if "#" in pinyin_part:
            pinyin_part = pinyin_part.split("#", 1)[0]
        phrase = phrase_part.strip()
        pinyin_str = pinyin_part.strip()
        if not phrase or not pinyin_str:
            continue

        canonical_pinyin, _ = canonicalize_reading(pinyin_str, policy)
        syllables = _split_syllables(canonical_pinyin)
        if not syllables:
            continue
        # A phrase reading is an ordered character-to-syllable sequence. Tone
        # normalization may replace a syllable in place, but must never move a
        # neutral-tone syllable (or any other syllable) to another position.
        reading = " ".join(syllables)

        existing = readings_map.get(phrase)
        if existing:
            existing_readings = existing[2].split("|")
            merged = existing_readings + [reading]
            seen: set[str] = set()
            deduped: list[str] = []
            for r in merged:
                if r not in seen:
                    seen.add(r)
                    deduped.append(r)
            readings_map[phrase] = (len(phrase), deduped[0], "|".join(deduped))
        else:
            readings_map[phrase] = (len(phrase), reading, reading)

    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    cur.execute("DROP TABLE IF EXISTS phrase_source_staging")
    cur.execute("""
        CREATE TABLE phrase_source_staging (
            phrase          TEXT PRIMARY KEY,
            phrase_len      INTEGER NOT NULL,
            common_reading  TEXT,
            readings        TEXT
        )
    """)

    inserted = 0
    for phrase, (phrase_len, common, readings) in readings_map.items():
        cur.execute(
            "INSERT OR IGNORE INTO phrase_source_staging (phrase, phrase_len, common_reading, readings) VALUES (?, ?, ?, ?)",
            (phrase, phrase_len, common, readings),
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


def create_views():
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    console_print("\n── 创建 staging 视图 ──")

    cur.execute("DROP VIEW IF EXISTS view_staging_with_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_staging_without_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_staging_inspection")

    cur.execute("""
        CREATE VIEW view_staging_with_pinyin AS
        SELECT phrase, phrase_len, common_reading, readings
        FROM phrase_source_staging
        WHERE COALESCE(common_reading, '') <> ''
    """)

    cur.execute("""
        CREATE VIEW view_staging_without_pinyin AS
        SELECT phrase, phrase_len, common_reading, readings
        FROM phrase_source_staging
        WHERE common_reading IS NULL OR common_reading = ''
    """)

    cur.execute("""
        CREATE VIEW view_staging_inspection AS
        SELECT
            s.phrase,
            s.phrase_len,
            s.common_reading AS pinyin,
            s.readings AS pinyin_candidates,
            CASE
                WHEN s.readings IS NULL OR s.readings = '' THEN 0
                ELSE LENGTH(s.readings) - LENGTH(REPLACE(s.readings, '|', '')) + 1
            END AS reading_count,
            CASE
                WHEN TRIM(COALESCE(s.common_reading, '')) = '' THEN 0
                ELSE 1
            END AS has_pinyin,
            CASE
                WHEN s.readings IS NOT NULL
                     AND s.readings <> ''
                     AND INSTR(s.readings, '|') > 0 THEN 1
                ELSE 0
            END AS is_polyphonic
        FROM phrase_source_staging s
    """)

    conn.commit()

    cur.execute(
        "SELECT phrase, phrase_len, pinyin, reading_count, is_polyphonic "
        "FROM view_staging_inspection LIMIT 5"
    )
    console_print(f"view_staging_inspection 前5个: {cur.fetchall()}")

    conn.close()


if __name__ == "__main__":
    import argparse

    default_source = str(Path(__file__).resolve().parents[2] / "external_data" / "phrase_pinyin.txt")

    parser = argparse.ArgumentParser(
        description="Import external_data/phrase_pinyin.txt into phrase_source_staging.",
    )
    parser.add_argument(
        "--source",
        default=default_source,
        help=f"Colon-format source path (default: external_data/phrase_pinyin.txt)",
    )
    args = parser.parse_args()

    import_to_staging(args.source)
    create_views()
