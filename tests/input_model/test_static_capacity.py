from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from yime.input_model import StaticCapacityConfig, build_static_capacity_model


def _source_database(path: Path) -> Path:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE canonical_readings (
                id INTEGER PRIMARY KEY,
                text TEXT NOT NULL,
                marked_pinyin TEXT NOT NULL,
                numeric_pinyin TEXT NOT NULL,
                reading_rank INTEGER NOT NULL,
                is_primary INTEGER NOT NULL,
                bcc_frequency INTEGER NOT NULL,
                pinyin_sources TEXT NOT NULL,
                pronunciation_scope TEXT NOT NULL,
                neutral_tone_status TEXT NOT NULL
            );
            """
        )
        connection.executemany(
            """
            INSERT INTO canonical_readings VALUES (
                ?, ?, ?, ?, 1, 1, ?, 'test', 'standalone', 'none'
            )
            """,
            [
                (1, "中", "zhōng", "zhong1", 10_000),
                (2, "国", "guó", "guo2", 9_000),
                (3, "人", "rén", "ren2", 8_000),
                (4, "银", "yín", "yin2", 7_000),
                (5, "行", "xíng", "xing2", 6_000),
                (6, "中国", "zhōng guó", "zhong1 guo2", 5_000),
                (
                    7,
                    "中国人",
                    "zhōng guó rén",
                    "zhong1 guo2 ren2",
                    4_000,
                ),
                (8, "银行", "yín háng", "yin2 hang2", 3_000),
            ],
        )
    return path


def test_static_capacity_separates_foundation_from_reachability(
    tmp_path: Path,
) -> None:
    result = build_static_capacity_model(
        source_database=_source_database(tmp_path / "source.sqlite3"),
        output_dir=tmp_path / "capacity",
        config=StaticCapacityConfig(target_capacity=7),
    )

    assert result.encoded_texts == 8
    assert result.mandatory_static_texts == 6
    assert result.dynamically_recoverable_texts == 2
    assert result.recommended_static_capacity == 7

    with sqlite3.connect(result.database) as connection:
        connection.row_factory = sqlite3.Row
        china = connection.execute(
            """
            SELECT recoverability_status, best_decomposition_json
            FROM reading_analysis
            WHERE text = '中国'
            """
        ).fetchone()
        chinese = connection.execute(
            """
            SELECT recoverability_status, best_decomposition_json
            FROM reading_analysis
            WHERE text = '中国人'
            """
        ).fetchone()
        bank = connection.execute(
            """
            SELECT recoverability_status, mandatory_reason
            FROM reading_analysis
            WHERE text = '银行'
            """
        ).fetchone()
        dispositions = dict(
            connection.execute(
                """
                SELECT text, recommended_disposition
                FROM static_capacity_items
                """
            )
        )

    assert china["recoverability_status"] == "dynamically_recoverable"
    assert json.loads(china["best_decomposition_json"])[0] == ["中", "国"]
    assert chinese["recoverability_status"] == "dynamically_recoverable"
    assert json.loads(chinese["best_decomposition_json"])[0] == ["中国", "人"]
    assert bank["recoverability_status"] == "mandatory_static"
    assert bank["mandatory_reason"] == (
        "no_shorter_attested_reading_decomposition"
    )
    assert dispositions["中国"] == "selected_static"
    assert dispositions["中国人"] == "dynamic_migration_candidate"
    assert dispositions["银行"] == "mandatory_static"

    manifest = json.loads(result.manifest.read_text(encoding="utf-8"))
    assert manifest["recommendation"]["proxy_only"] is True
    assert manifest["recommendation"]["runtime_replay_required"] is True
    assert result.items_tsv.is_file()
    assert result.frontier_tsv.is_file()
    assert result.summary_markdown.is_file()
