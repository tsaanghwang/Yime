from __future__ import annotations

import sqlite3
from pathlib import Path

from tools.audit_wanxiang_pinyin_order import audit_wanxiang_order
from yime.lexicon_bundle.parsers import iter_wanxiang_readings


def test_wanxiang_parser_preserves_phrase_syllable_order(tmp_path: Path) -> None:
    source = tmp_path / "jichu.dict.yaml"
    source.write_text(
        "---\nname: test\n...\n"
        "听不见\ttīng bu jiàn\t100\n"
        "一块石头落了地\tyī kuài shí tou luò le dì\t90\n",
        encoding="utf-8",
    )

    records = list(iter_wanxiang_readings(source))

    assert [(record.text, record.reading) for record in records] == [
        ("听不见", "tīng bu jiàn"),
        ("一块石头落了地", "yī kuài shí tou luò le dì"),
    ]


def test_wanxiang_database_audit_detects_only_order_changes(tmp_path: Path) -> None:
    database = tmp_path / "source_lexicon.sqlite3"
    with sqlite3.connect(database) as connection:
        connection.execute(
            """
            CREATE TABLE accepted_readings (
                text TEXT,
                source_marked TEXT,
                numeric TEXT,
                source TEXT,
                source_file TEXT,
                source_category TEXT
            )
            """
        )
        connection.execute("CREATE TABLE rejections (source TEXT, reason TEXT)")
        connection.executemany(
            "INSERT INTO accepted_readings VALUES (?, ?, ?, 'wanxiang', 'test.yaml', 'jichu')",
            (
                ("听不见", "tīng bu jiàn", "ting1 bu5 jian4"),
                ("一个劲地问", "yí gè jìn de wèn", "yi2 ge4 jin4 wen4 de5"),
            ),
        )

    report = audit_wanxiang_order(database)

    assert report["accepted_rows"] == 2
    assert report["rows_with_internal_untoned_syllables"] == 2
    assert report["accepted_syllable_count_mismatches"] == 0
    assert report["numeric_order_mismatches"] == 1
    assert report["permutation_only_mismatches"] == 1
    assert report["passed"] is False
