"""Audit frequency columns in pinyin_hanzi.db."""
from __future__ import annotations

import sqlite3
from pathlib import Path

from yime.utils.char_frequency_policy import BCC_SOURCE, PHRASE_LEXICON_DEFAULT_FREQUENCY

DB = Path("yime/pinyin_hanzi.db")


def main() -> int:
    conn = sqlite3.connect(DB)
    try:
        print("=== schema ===")
        for table in ("char_inventory", "phrase_inventory"):
            rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
            for r in rows:
                if "freq" in r[1].lower() or r[1] == "frequency_source":
                    print(f"{table}.{r[1]}: declared={r[2]}")

        print("\n=== char_inventory frequency stats ===")
        row = conn.execute(
            """
            SELECT
              COUNT(*) AS total,
              SUM(CASE WHEN char_frequency_abs IS NOT NULL THEN 1 ELSE 0 END) AS abs_set,
              SUM(CASE WHEN frequency_source = ? THEN 1 ELSE 0 END) AS bcc_src,
              SUM(
                CASE
                  WHEN frequency_source IS NOT NULL AND frequency_source <> ? THEN 1
                  ELSE 0
                END
              ) AS synthetic_src
            FROM char_inventory
            """,
            (BCC_SOURCE, BCC_SOURCE),
        ).fetchone()
        print(row)

        print("\n=== phrase_inventory frequency stats ===")
        row = conn.execute(
            """
            SELECT
              COUNT(*) AS total,
              SUM(CASE WHEN LENGTH(phrase) > 1 THEN 1 ELSE 0 END) AS multi_char,
              SUM(CASE WHEN phrase_frequency IS NULL THEN 1 ELSE 0 END) AS null_freq,
              SUM(CASE WHEN phrase_frequency = ? THEN 1 ELSE 0 END) AS lexicon_default,
              SUM(CASE WHEN phrase_frequency > ? THEN 1 ELSE 0 END) AS bcc_rows
            FROM phrase_inventory
            """,
            (PHRASE_LEXICON_DEFAULT_FREQUENCY, PHRASE_LEXICON_DEFAULT_FREQUENCY),
        ).fetchone()
        print(row)

        print("\n=== samples ===")
        print(
            "char 的:",
            conn.execute(
                "SELECT char_frequency_abs, frequency_source FROM char_inventory WHERE hanzi='的'"
            ).fetchone(),
        )
        print(
            "phrase 中国:",
            conn.execute(
                "SELECT phrase_frequency FROM phrase_inventory WHERE phrase='中国'"
            ).fetchone(),
        )

        print("\n=== metadata (freq-related) ===")
        for item in conn.execute(
            """
            SELECT key, value FROM prototype_metadata
            WHERE key LIKE '%freq%' OR key LIKE '%8105%'
            ORDER BY key
            """
        ):
            print(item)
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
