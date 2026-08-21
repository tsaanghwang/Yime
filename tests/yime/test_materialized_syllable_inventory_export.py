from __future__ import annotations

import sqlite3
from pathlib import Path

from tools.export_materialized_syllable_inventory import export_inventory


def test_export_inventory_uses_only_materialized_source_syllables(
    tmp_path: Path,
) -> None:
    source_database = tmp_path / "source_lexicon.sqlite3"
    output_path = tmp_path / "inventory.tsv"
    with sqlite3.connect(source_database) as connection:
        connection.execute(
            "CREATE TABLE m_distinct_syllable_inventory "
            "(numeric_syllable TEXT PRIMARY KEY)"
        )
        connection.executemany(
            "INSERT INTO m_distinct_syllable_inventory VALUES (?)",
            (("kuai3",), ("kuai2",)),
        )

    count = export_inventory(source_database, output_path)

    assert count == 2
    assert output_path.read_text(encoding="utf-8") == (
        "pinyin_tone\nkuai2\nkuai3\n"
    )
