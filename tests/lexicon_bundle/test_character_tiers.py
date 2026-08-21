from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from yime.lexicon_bundle.character_tiers import (
    CharacterTierPolicy,
    CharacterTierSources,
    export_character_tiers,
    rebuild_character_tiers,
)


def _cp(character: str) -> str:
    return f"U+{ord(character):04X}"


def test_rebuild_character_tiers_is_mutually_exclusive_and_auditable(
    tmp_path: Path,
) -> None:
    tgh_chars = "一丁七万"
    xhc_extra = "丈"
    hanyu_selected = "三"
    hanyu_tail = "上"
    mandarin_selected = "下"
    mandarin_tail = "不"
    project_extra = "与"
    unencoded_extra = "丏"
    structural = "⼀"

    other_mappings = tmp_path / "Unihan_OtherMappings.txt"
    other_mappings.write_text(
        "".join(
            f"{_cp(character)}\tkTGH\t2013:{index}\n"
            for index, character in enumerate(tgh_chars, start=1)
        ),
        encoding="utf-8",
    )
    readings = tmp_path / "Unihan_Readings.txt"
    readings.write_text(
        "".join(
            (
                f"{_cp(tgh_chars[0])}\tkXHC1983\t0001.010:yī\n",
                f"{_cp(xhc_extra)}\tkXHC1983\t0002.010:zhàng\n",
                f"{_cp(hanyu_selected)}\tkHanyuPinyin\t10000.010:sān\n",
                f"{_cp(hanyu_tail)}\tkHanyuPinyin\t10000.020:shàng\n",
                f"{_cp(mandarin_selected)}\tkMandarin\txià\n",
                f"{_cp(mandarin_tail)}\tkMandarin\tbù\n",
            )
        ),
        encoding="utf-8",
    )
    codebook = tmp_path / "yinjie_code.json"
    codebook.write_text(
        json.dumps({"san1": "AAAA", "xia4": "BBBB", "yu3": "CCCC"}),
        encoding="utf-8",
    )

    catalog_db = tmp_path / "hanzi_pinyin.db"
    catalog_chars = (
        tgh_chars
        + xhc_extra
        + hanyu_selected
        + hanyu_tail
        + mandarin_selected
        + mandarin_tail
        + project_extra
        + unencoded_extra
        + structural
    )
    with sqlite3.connect(catalog_db) as catalog:
        catalog.execute(
            """
            CREATE TABLE hanzi (
                codepoint TEXT PRIMARY KEY,
                hanzi TEXT NOT NULL,
                block TEXT,
                block_order INTEGER
            )
            """
        )
        catalog.executemany(
            "INSERT INTO hanzi VALUES (?, ?, ?, ?)",
            (
                (
                    _cp(character),
                    character,
                    "test",
                    index,
                )
                for index, character in enumerate(catalog_chars)
            ),
        )

    source_db = tmp_path / "source_lexicon.sqlite3"
    with sqlite3.connect(source_db) as source:
        source.executescript(
            """
            CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE canonical_readings (
                codepoint TEXT,
                text_length INTEGER NOT NULL,
                numeric_pinyin TEXT NOT NULL,
                pronunciation_scope TEXT NOT NULL
            );
            CREATE TABLE bcc_frequency (
                text TEXT PRIMARY KEY,
                frequency INTEGER NOT NULL
            );
            """
        )
        source.executemany(
            "INSERT INTO canonical_readings VALUES (?, 1, ?, 'standalone')",
            (
                (_cp(hanyu_selected), "san1"),
                (_cp(mandarin_selected), "xia4"),
                (_cp(project_extra), "yu3"),
            ),
        )
        source.executemany(
            "INSERT INTO bcc_frequency VALUES (?, ?)",
            (
                (hanyu_selected, 100),
                (mandarin_selected, 90),
                (project_extra, 80),
            ),
        )

        counts = rebuild_character_tiers(
            source,
            CharacterTierSources(
                other_mappings=other_mappings,
                readings=readings,
                character_catalog_db=catalog_db,
                yinjie_codebook=codebook,
            ),
            policy=CharacterTierPolicy(
                tgh_level_ends=(2, 3, 4),
                modern_dictionary_estimated_cap=7,
            ),
        )

        assert counts == {
            "tgh_level_1": 2,
            "tgh_level_2": 1,
            "tgh_level_3": 1,
            "xhc1983_extension": 1,
            "modern_dictionary_estimated": 2,
            "hanyu_dazidian": 1,
            "mandarin_regional": 1,
            "project_encoded": 1,
            "unencoded_unihan": 1,
        }
        by_char = {
            hanzi: tier
            for hanzi, tier in source.execute(
                "SELECT hanzi, tier_number FROM character_tiers"
            )
        }
        assert by_char[hanyu_selected] == 5
        assert by_char[mandarin_selected] == 5
        assert by_char[hanyu_tail] == 6
        assert by_char[mandarin_tail] == 7
        assert by_char[project_extra] == 8
        assert by_char[unencoded_extra] == 9
        assert structural not in by_char
        assert source.execute(
            """
            SELECT is_classifiable
            FROM unihan_character_inventory
            WHERE codepoint = ?
            """,
            (_cp(structural),),
        ).fetchone()[0] == 0

        output = tmp_path / "character_tiers.tsv"
        assert export_character_tiers(source, output) == 11
        assert output.read_text(encoding="utf-8").startswith(
            "codepoint\thanzi\ttier_number\ttier_name"
        )
