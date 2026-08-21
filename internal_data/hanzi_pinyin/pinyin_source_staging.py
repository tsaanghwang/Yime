import sqlite3
import sys
from dataclasses import replace
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from yime.utils.dictionary_pinyin_compliance import load_policy, review_syllable

from hanzi_pinyin_source_io import (
    DEFAULT_SOURCE_FILE,
    STAGING_DDL,
    parse_hanzi_pinyin_txt,
)

DB_FILE = str(Path(__file__).parent / "hanzi_pinyin.db")


def import_to_staging(source_path: str | Path) -> None:
    path = Path(source_path)
    parsed_rows = parse_hanzi_pinyin_txt(path)
    policy = load_policy()

    conn = sqlite3.connect(DB_FILE)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    cur.execute("DROP TABLE IF EXISTS pinyin_source_staging")
    cur.execute(STAGING_DDL)

    inserted = 0
    skipped = 0
    excluded = 0
    retained_without_reading = 0
    for row in parsed_rows:
        canonical_candidates: list[str] = []
        seen: set[str] = set()
        for candidate in (part.strip() for part in row.readings.split(",")):
            if not candidate:
                continue
            review = review_syllable(candidate, policy, codepoint=row.codepoint)
            if review.known_exclusion:
                excluded += 1
                continue
            if not review.accepted:
                raise ValueError(
                    f"{row.codepoint} {row.hanzi} {candidate}: {review.reason}"
                )
            canonical = review.canonical_marked
            if canonical not in seen:
                seen.add(canonical)
                canonical_candidates.append(canonical)
        canonical_common = ""
        if canonical_candidates:
            if row.common_reading:
                common_review = review_syllable(
                    row.common_reading,
                    policy,
                    codepoint=row.codepoint,
                )
                if common_review.accepted:
                    canonical_common = common_review.canonical_marked
            if not canonical_common or canonical_common not in canonical_candidates:
                canonical_common = canonical_candidates[0]
        else:
            # The character remains part of the character/source inventory even
            # when every recorded reading is deliberately barred from decoding.
            # Empty normalized readings prevent it from entering the syllable
            # pipeline without erasing the codepoint or its source provenance.
            retained_without_reading += 1
        row = replace(
            row,
            common_reading=canonical_common,
            readings=",".join(canonical_candidates),
            is_single=1 if len(canonical_candidates) == 1 else 0,
        )
        known = cur.execute(
            "SELECT hanzi FROM hanzi WHERE codepoint = ?",
            (row.codepoint,),
        ).fetchone()
        if not known:
            skipped += 1
            continue
        hanzi = known[0]
        cur.execute(
            "INSERT INTO pinyin_source_staging "
            "(codepoint, hanzi, common_reading, readings, common_reading_source, is_single) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                row.codepoint,
                hanzi,
                row.common_reading,
                row.readings,
                row.common_reading_source or None,
                row.is_single,
            ),
        )
        inserted += 1

    conn.commit()
    conn.close()

    print(f"staging 导入完成: {inserted:,} 条 (来源: {path})")
    if skipped:
        print(f"跳过: {skipped:,} 条（码点不在 hanzi 主表）")
    if excluded:
        print(f"已知且有意排除的来源读音: {excluded:,} 条")
    if retained_without_reading:
        print(f"保留字形但不送入音节分解: {retained_without_reading:,} 条")


def console_print(message: str) -> None:
    try:
        print(message)
    except UnicodeEncodeError:
        sys.stdout.buffer.write((message + "\n").encode(sys.stdout.encoding or "utf-8", errors="backslashreplace"))


def build_invalid_pinyin_rows(pinyin_candidates_str: str) -> list[tuple[str, str, str]]:
    raw_candidates: list[str] = [c.strip() for c in pinyin_candidates_str.split(',') if c.strip()] if pinyin_candidates_str else []

    invalid_rows: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str, str]] = set()
    for marked in raw_candidates:
        if not marked:
            continue
        review = review_syllable(marked)
        if review.accepted:
            continue
        invalid_row = (marked, review.canonical_numeric, review.rule_id)
        if invalid_row not in seen:
            seen.add(invalid_row)
            invalid_rows.append(invalid_row)
    return invalid_rows


def classify_invalid_pinyin(marked: str, numeric: str, reason: str) -> str:
    del marked, numeric
    return "source_compliance_rejected" if reason else "unknown"


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
        SELECT codepoint, hanzi, common_reading, readings, common_reading_source, is_single
        FROM pinyin_source_staging
        WHERE COALESCE(common_reading, '') <> ''
    """)

    cur.execute("""
        CREATE VIEW view_staging_without_pinyin AS
        SELECT codepoint, hanzi, common_reading, readings, common_reading_source, is_single
        FROM pinyin_source_staging
        WHERE common_reading IS NULL OR common_reading = ''
    """)

    cur.execute("""
        CREATE VIEW view_staging_with_multireadings AS
        SELECT codepoint, hanzi, common_reading, readings, common_reading_source, is_single
        FROM pinyin_source_staging
        WHERE COALESCE(common_reading, '') <> ''
          AND is_single = 0
    """)

    cur.execute("""
        CREATE VIEW view_staging_single_reading_not_toned AS
        SELECT codepoint, hanzi, common_reading, readings, common_reading_source, is_single
        FROM pinyin_source_staging
        WHERE COALESCE(common_reading, '') <> ''
          AND is_single = 1
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
            s.common_reading_source,
            s.is_single,
            CASE
                WHEN s.readings IS NULL OR s.readings = '' THEN 0
                ELSE LENGTH(s.readings) - LENGTH(REPLACE(s.readings, ',', '')) + 1
            END AS candidate_count,
            CASE
                WHEN TRIM(COALESCE(s.common_reading, '')) = '' THEN 0
                ELSE 1
            END AS has_pinyin,
            CASE
                WHEN s.is_single = 1 THEN 0
                WHEN s.readings IS NOT NULL AND s.readings <> '' THEN 1
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
    import argparse

    parser = argparse.ArgumentParser(
        description="Import external_data/hanzi_pinyin.txt into pinyin_source_staging.",
    )
    parser.add_argument(
        "--source",
        default=str(DEFAULT_SOURCE_FILE),
        help=f"TSV source path (default: {DEFAULT_SOURCE_FILE})",
    )
    args = parser.parse_args()

    import_to_staging(args.source)
    create_views()
