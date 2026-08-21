from __future__ import annotations

import csv
import json
import sqlite3
from pathlib import Path

from yime.input_model.second_batch_review import export_second_batch_review


def _build_source_database(path: Path) -> None:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE bcc_frequency (text TEXT PRIMARY KEY, frequency INTEGER NOT NULL);
            CREATE TABLE canonical_readings (
                text TEXT NOT NULL,
                marked_pinyin TEXT NOT NULL,
                numeric_pinyin TEXT NOT NULL,
                reading_rank INTEGER NOT NULL,
                is_primary INTEGER NOT NULL,
                pinyin_sources TEXT NOT NULL,
                reading_source_categories TEXT NOT NULL,
                wanxiang_categories TEXT NOT NULL,
                pronunciation_scope TEXT NOT NULL,
                neutral_tone_positions TEXT NOT NULL,
                neutral_tone_status TEXT NOT NULL
            );
            CREATE TABLE rejections (text TEXT NOT NULL);
            INSERT INTO bcc_frequency VALUES
                ('proper', 9000), ('neutral', 8000), ('missing', 7000),
                ('plain', 6000), ('rejected', 5000), ('outside', 999);
            INSERT INTO canonical_readings VALUES
                ('proper', 'a', 'a1', 1, 1, 'source', 'diming', '', 'proper_name', '', 'not_neutral'),
                ('proper', 'b', 'b1', 2, 0, 'source', 'diming', '', 'proper_name', '', 'not_neutral'),
                ('neutral', 'a', 'a1', 1, 1, 'source', 'lexicon', '', 'lexical', '', 'not_neutral'),
                ('neutral', 'a', 'a5', 2, 0, 'source', 'lexicon', '', 'lexical', '1', 'attested_neutral'),
                ('plain', 'a', 'a1', 1, 1, 'source', 'lexicon', '', 'lexical', '', 'not_neutral'),
                ('rejected', 'a', 'a1', 1, 1, 'source', 'lexicon', '', 'lexical', '', 'not_neutral');
            INSERT INTO rejections VALUES ('rejected');
            """
        )


def test_export_second_batch_review_is_read_only_and_explainable(tmp_path: Path) -> None:
    source_database = tmp_path / "source.sqlite3"
    output_directory = tmp_path / "report"
    _build_source_database(source_database)

    result = export_second_batch_review(
        source_database=source_database,
        input_model_database=None,
        output_directory=output_directory,
    )

    assert result.total_count == 5
    assert result.conflict_count == 3
    assert result.lane_counts == {
        "accepted_rejected_source_conflict": 1,
        "neutral_tone_reading_conflict": 1,
        "proper_name_reading_conflict": 1,
        "ranking_review": 1,
        "source_reading_required": 1,
    }
    with result.queue_path.open(encoding="utf-8", newline="") as stream:
        rows = {row["text"]: row for row in csv.DictReader(stream, delimiter="\t")}
    assert rows["proper"]["review_lane"] == "proper_name_reading_conflict"
    assert rows["neutral"]["review_lane"] == "neutral_tone_reading_conflict"
    assert rows["missing"]["review_lane"] == "source_reading_required"
    assert rows["rejected"]["review_lane"] == "accepted_rejected_source_conflict"

    manifest = json.loads(result.manifest_path.read_text(encoding="utf-8"))
    assert manifest["decision"] == "complete"
    assert manifest["safeguards"] == {
        "input_model_read_only": True,
        "source_database_read_only": True,
        "suggestions_require_human_review": True,
        "writes_assessments": False,
        "writes_pronunciation": False,
        "writes_yinyuan_or_layout": False,
    }
    with sqlite3.connect(source_database) as connection:
        assert connection.execute("SELECT COUNT(*) FROM bcc_frequency").fetchone() == (6,)

def test_export_filters_primary_queue_to_undecoded_model_rows(tmp_path: Path) -> None:
    source_database = tmp_path / "source.sqlite3"
    model_database = tmp_path / "model.sqlite3"
    _build_source_database(source_database)
    with sqlite3.connect(model_database) as connection:
        connection.executescript(
            """
            CREATE TABLE candidate_universe (
                text TEXT PRIMARY KEY,
                has_gated_reading INTEGER NOT NULL,
                dynamic_reachable INTEGER NOT NULL,
                dynamic_reachability_rule TEXT NOT NULL,
                baseline_class TEXT NOT NULL,
                baseline_policy TEXT NOT NULL,
                baseline_status TEXT NOT NULL
            );
            CREATE TABLE assessments (
                text TEXT PRIMARY KEY,
                candidate_class TEXT,
                integration_policy TEXT,
                decision_status TEXT
            );
            INSERT INTO candidate_universe VALUES
                ('proper', 1, 0, '', 'unknown', 'needs_review', 'proposed'),
                ('neutral', 1, 0, '', 'unknown', 'needs_review', 'proposed'),
                ('missing', 0, 1, 'two_character_dynamic_reachability', 'unknown', 'needs_review', 'proposed'),
                ('plain', 1, 0, '', 'unknown', 'needs_review', 'proposed'),
                ('rejected', 1, 0, '', 'unknown', 'needs_review', 'proposed');
            """
        )

    result = export_second_batch_review(
        source_database=source_database,
        input_model_database=model_database,
        output_directory=tmp_path / "report",
    )

    assert result.total_count == 1
    assert result.conflict_count == 3
    assert result.lane_counts == {"dynamic_composition_review": 1}