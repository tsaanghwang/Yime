from __future__ import annotations

import csv
import sqlite3
from pathlib import Path

from tools.build_two_level_precomposition_lexicon import build


def _dictionary(path: Path, rows: list[tuple[str, str, int]]) -> Path:
    body = "\n".join(
        f"{text}\t{code}\t{weight}" for text, code, weight in rows
    )
    path.write_text(
        "---\nname: test\nsort: by_weight\n...\n" + body + "\n",
        encoding="utf-8",
    )
    return path


def _source(path: Path) -> Path:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE character_tiers (
                hanzi TEXT PRIMARY KEY,
                tier_number INTEGER NOT NULL,
                encoded_reading_count INTEGER NOT NULL
            );
            CREATE TABLE canonical_readings (
                text TEXT NOT NULL,
                bcc_frequency INTEGER NOT NULL,
                wanxiang_weight INTEGER NOT NULL
            );
            INSERT INTO character_tiers VALUES
                ('甲', 1, 1), ('乙', 1, 1), ('词', 1, 1);
            INSERT INTO canonical_readings VALUES
                ('甲词', 6, 999999),
                ('乙词', 0, 10);
            """
        )
    return path


def test_final_two_level_selection_reweights_without_adding_sources(
    tmp_path: Path,
) -> None:
    source = _source(tmp_path / "source.sqlite3")
    base = _dictionary(
        tmp_path / "base.dict.yaml",
        [("甲词", "aaaa", 1000000), ("乙词", "bbbb", 1000000)],
    )
    production = _dictionary(
        tmp_path / "production.dict.yaml",
        [("甲词", "aaaa", 6), ("乙词", "bbbb", 0)],
    )
    selection = tmp_path / "selection.tsv"
    manifest = build(
        base,
        production,
        tmp_path / "output.dict.yaml",
        tmp_path / "manifest.json",
        source,
        capacity=0,
        maximum_tier=5,
        minimum_length=5,
        retained_long_dictionary=None,
        selection_path=selection,
    )
    with selection.open(encoding="utf-8", newline="") as stream:
        rows = {
            row["text"]: row
            for row in csv.DictReader(stream, delimiter="\t")
        }
    assert int(rows["甲词"]["weight"]) > int(rows["乙词"]["weight"])
    assert rows["甲词"]["ranking_evidence_source"] == "direct_bcc"
    assert (
        rows["乙词"]["ranking_evidence_source"]
        == "provisional_rime_lmdg"
    )
    assert "normalized_structural_percentile" in rows["乙词"]
    assert rows["甲词"]["bcc_frequency"] == "6"
    assert rows["乙词"]["bcc_frequency"] == "0"
    assert manifest["ranking_evidence"][
        "raw_bcc_and_lmdg_values_added"
    ] is False
