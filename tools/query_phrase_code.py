from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path
from typing import Iterable, Sequence


ROOT = Path(__file__).resolve().parent.parent
SOURCE_DB_PATH = ROOT / "internal_data" / "pinyin_source_db" / "source_pinyin.db"
RUNTIME_DB_PATH = ROOT / "yime" / "pinyin_hanzi.db"
USER_DB_PATH = ROOT / "yime" / "user_lexicon.db"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="查询字词是否在词库中，以及其标准拼音、数字标调拼音和音元编码。"
    )
    parser.add_argument("term", help="要查询的字词，例如：今日、日本、日")
    parser.add_argument(
        "--like",
        action="store_true",
        help="使用 LIKE 模糊查询，而不是精确匹配。",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="每个分组最多显示多少条结果，默认 20。",
    )
    return parser.parse_args()


def format_codepoints(text: str) -> str:
    if not text:
        return ""
    return " ".join(
        f"U+{ord(char):06X}" if ord(char) > 0xFFFF else f"U+{ord(char):04X}"
        for char in text
    )


def print_section(title: str) -> None:
    print()
    print(title)
    print("-" * len(title))


def print_no_result() -> None:
    print("无结果")


def fetch_rows(
    connection: sqlite3.Connection,
    query: str,
    parameter: str,
    limit: int,
) -> list[sqlite3.Row]:
    return connection.execute(query, (parameter, limit)).fetchall()


def build_match_value(term: str, use_like: bool) -> str:
    return f"%{term}%" if use_like else term


def print_source_phrase_rows(rows: Sequence[sqlite3.Row]) -> None:
    if not rows:
        print_no_result()
        return
    for row in rows:
        print(
            "phrase={phrase} marked={marked_pinyin} numeric={numeric_pinyin} "
            "rank={reading_rank} source={source_name}".format(**dict(row))
        )


def print_source_char_rows(rows: Sequence[sqlite3.Row]) -> None:
    if not rows:
        print_no_result()
        return
    for row in rows:
        print(
            "hanzi={hanzi} marked={marked_pinyin} numeric={numeric_pinyin} "
            "rank={reading_rank} source={source_name}".format(**dict(row))
        )


def print_runtime_phrase_rows(rows: Sequence[sqlite3.Row]) -> None:
    if not rows:
        print_no_result()
        return
    for row in rows:
        payload = dict(row)
        yime_code = str(payload.get("yime_code") or "")
        print(
            "phrase={phrase} pinyin={pinyin_tone} yime={yime_code} codepoints={codepoints} "
            "rank={reading_rank} freq={phrase_frequency}".format(
                codepoints=format_codepoints(yime_code),
                **payload,
            )
        )


def print_runtime_char_rows(rows: Sequence[sqlite3.Row]) -> None:
    if not rows:
        print_no_result()
        return
    for row in rows:
        payload = dict(row)
        yime_code = str(payload.get("yime_code") or "")
        print(
            "hanzi={hanzi} marked={marked_pinyin} numeric={pinyin_tone} yime={yime_code} "
            "codepoints={codepoints} rank={reading_rank}".format(
                codepoints=format_codepoints(yime_code),
                **payload,
            )
        )


def print_user_phrase_rows(rows: Sequence[sqlite3.Row]) -> None:
    if not rows:
        print_no_result()
        return
    for row in rows:
        payload = dict(row)
        yime_code = str(payload.get("yime_code") or "")
        print(
            "phrase={phrase} marked={marked_pinyin} numeric={numeric_pinyin} yime={yime_code} "
            "codepoints={codepoints} note={source_note} freq={freq} last_used={last_used_at} updated={updated_at}".format(
                codepoints=format_codepoints(yime_code),
                **payload,
            )
        )


def query_source_db(term: str, use_like: bool, limit: int) -> None:
    comparator = "LIKE" if use_like else "="
    match_value = build_match_value(term, use_like)
    with sqlite3.connect(SOURCE_DB_PATH) as connection:
        connection.row_factory = sqlite3.Row

        print_section("Source 词语")
        phrase_rows = fetch_rows(
            connection,
            f"""
            SELECT phrase, marked_pinyin, numeric_pinyin, reading_rank, source_name
            FROM phrase_readings
            WHERE phrase {comparator} ?
            ORDER BY phrase, reading_rank, source_name
            LIMIT ?
            """,
            match_value,
            limit,
        )
        print_source_phrase_rows(phrase_rows)

        print_section("Source 单字")
        char_rows = fetch_rows(
            connection,
            f"""
            SELECT hanzi, marked_pinyin, numeric_pinyin, reading_rank, source_name
            FROM single_char_readings
            WHERE hanzi {comparator} ?
            ORDER BY hanzi, reading_rank, source_name
            LIMIT ?
            """,
            match_value,
            limit,
        )
        print_source_char_rows(char_rows)


def query_runtime_db(term: str, use_like: bool, limit: int) -> None:
    comparator = "LIKE" if use_like else "="
    match_value = build_match_value(term, use_like)
    with sqlite3.connect(RUNTIME_DB_PATH) as connection:
        connection.row_factory = sqlite3.Row

        print_section("Runtime 词语编码")
        phrase_rows = fetch_rows(
            connection,
            f"""
            SELECT phrase, pinyin_tone, yime_code, reading_rank, phrase_frequency
            FROM phrase_lexicon_view
            WHERE phrase {comparator} ?
            ORDER BY phrase, reading_rank, phrase_frequency DESC
            LIMIT ?
            """,
            match_value,
            limit,
        )
        print_runtime_phrase_rows(phrase_rows)

        print_section("Runtime 单字编码")
        char_rows = fetch_rows(
            connection,
            f"""
            SELECT hanzi, marked_pinyin, pinyin_tone, yime_code, reading_rank
            FROM char_lexicon
            WHERE hanzi {comparator} ?
            ORDER BY hanzi, reading_rank, reading_weight DESC
            LIMIT ?
            """,
            match_value,
            limit,
        )
        print_runtime_char_rows(char_rows)


def query_user_db(term: str, use_like: bool, limit: int) -> None:
    print_section("User 词语编码")
    if not USER_DB_PATH.exists():
        print_no_result()
        return

    comparator = "LIKE" if use_like else "="
    match_value = build_match_value(term, use_like)
    with sqlite3.connect(USER_DB_PATH) as connection:
        connection.row_factory = sqlite3.Row
        has_frequency_table = connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'user_candidate_frequency'"
        ).fetchone() is not None
        frequency_select = (
            "COALESCE(ucf.freq, 0) AS freq, COALESCE(ucf.last_used_at, '') AS last_used_at"
            if has_frequency_table
            else "0 AS freq, '' AS last_used_at"
        )
        frequency_join = (
            "LEFT JOIN user_candidate_frequency AS ucf ON ucf.text = upe.phrase"
            if has_frequency_table
            else ""
        )
        order_by = (
            "COALESCE(ucf.freq, 0) DESC, upe.updated_at DESC, upe.phrase"
            if has_frequency_table
            else "upe.updated_at DESC, upe.phrase"
        )
        phrase_rows = fetch_rows(
            connection,
            f"""
            SELECT
                upe.phrase,
                upe.marked_pinyin,
                upe.numeric_pinyin,
                upe.yime_code,
                upe.source_note,
                upe.updated_at,
                {frequency_select}
            FROM user_phrase_entries AS upe
            {frequency_join}
            WHERE upe.phrase {comparator} ?
            ORDER BY {order_by}
            LIMIT ?
            """,
            match_value,
            limit,
        )
        print_user_phrase_rows(phrase_rows)


def print_metadata(term: str, use_like: bool, limit: int) -> None:
    print(f"query={term}")
    print(f"mode={'like' if use_like else 'exact'}")
    print(f"source_db={SOURCE_DB_PATH}")
    print(f"runtime_db={RUNTIME_DB_PATH}")
    print(f"user_db={USER_DB_PATH}")
    print(f"limit={limit}")


def main() -> None:
    args = parse_args()
    print_metadata(args.term, args.like, args.limit)
    query_source_db(args.term, args.like, args.limit)
    query_runtime_db(args.term, args.like, args.limit)
    query_user_db(args.term, args.like, args.limit)


if __name__ == "__main__":
    main()
