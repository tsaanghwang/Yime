from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from yime.input_model.core_trial_export import (
    default_core_trial_capacities,
    export_core_trial_lexicons,
)
from yime.input_model.static_capacity import (
    StaticCapacityConfig,
    build_static_capacity_model,
)


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
                wanxiang_weight INTEGER NOT NULL,
                pinyin_sources TEXT NOT NULL,
                pronunciation_scope TEXT NOT NULL,
                neutral_tone_status TEXT NOT NULL
            );
            """
        )
        connection.executemany(
            """
            INSERT INTO canonical_readings VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, 'test', 'standalone', 'none'
            )
            """,
            [
                (1, "中", "zhōng", "zhong1", 1, 1, 10_000, 10),
                (2, "国", "guó", "guo2", 1, 1, 9_000, 9),
                (3, "行", "xíng", "xing2", 1, 1, 8_000, 8),
                (4, "行", "háng", "hang2", 2, 0, 8_000, 8),
                (
                    5,
                    "中国",
                    "zhōng guó",
                    "zhong1 guo2",
                    1,
                    1,
                    7_000,
                    7,
                ),
                (
                    6,
                    "中国行",
                    "zhōng guó xíng",
                    "zhong1 guo2 xing2",
                    1,
                    1,
                    1,
                    1,
                ),
            ],
        )
        connection.execute(
            """
            INSERT INTO canonical_readings VALUES (
                7, '中', 'zhong', 'zhong5', 2, 0, 100, 1,
                'test', 'word_context_only', 'confirmed_neutral'
            )
            """
        )
        connection.execute(
            "ALTER TABLE canonical_readings ADD COLUMN "
            "wanxiang_categories TEXT NOT NULL DEFAULT ''"
        )
        connection.execute(
            "UPDATE canonical_readings "
            "SET pinyin_sources = 'pypinyin,wanxiang', "
            "wanxiang_categories = 'jichu' "
            "WHERE text = '中国行'"
        )
    return path


def test_export_preserves_all_readings_of_selected_texts(
    tmp_path: Path,
) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    source = _source_database(tmp_path / "source.sqlite3")
    capacity_result = build_static_capacity_model(
        source_database=source,
        output_dir=tmp_path / "capacity",
        config=StaticCapacityConfig(target_capacity=4),
    )

    result = export_core_trial_lexicons(
        source_database=source,
        capacity_database=capacity_result.database,
        output_dir=tmp_path / "core",
        capacities=(4,),
        repo_root=repo_root,
    )

    tier = result.tiers[0]
    assert tier.selected_texts == 4
    assert tier.reading_entries == 5
    dictionary = tier.dictionary_path.read_text(encoding="utf-8")
    assert "\n中\t" in dictionary
    assert dictionary.count("\n中\t") == 1
    assert dictionary.count("\n行\t") == 2
    assert "\n中国\t" in dictionary
    assert all(
        len(line.split("\t")[1]) == 4 * len(line.split("\t")[0])
        for line in dictionary.splitlines()
        if "\t" in line
    )

    manifest = json.loads(tier.manifest_path.read_text(encoding="utf-8"))
    assert manifest["capacity_unit"] == "distinct_text"
    assert manifest["selected_texts"] == 4
    assert manifest["reading_entries"] == 5
    assert manifest["trial_only"] is True
    assert manifest["runtime_replay_required"] is True
    assert (
        manifest["ranking_evidence"]["policy_id"]
        == "bcc-primary-lmdg-fallback-structural-floor-v1"
    )
    assert manifest["ranking_evidence"][
        "raw_bcc_and_lmdg_values_added"
    ] is False
    selection_header = tier.selection_path.read_text(
        encoding="utf-8"
    ).splitlines()[0]
    assert "bcc_frequency" in selection_header
    assert "wanxiang_weight" in selection_header
    assert "ranking_evidence_source" in selection_header
    assert "normalized_structural_percentile" in selection_header
    assert len(manifest["outputs"]["dictionary_sha256"]) == 64
    assert len(manifest["outputs"]["selection_sha256"]) == 64


def test_default_tiers_include_replay_discrimination_band() -> None:
    assert default_core_trial_capacities(
        mandatory_capacity=52_290,
        recommended_capacity=111_294,
        total_texts=2_441_908,
    ) == (
        52_290,
        62_290,
        102_290,
        111_294,
        152_290,
        202_290,
    )


def test_export_can_union_full_gated_pinyin_source(
    tmp_path: Path,
) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    source = _source_database(tmp_path / "source.sqlite3")
    capacity_result = build_static_capacity_model(
        source_database=source,
        output_dir=tmp_path / "capacity",
        config=StaticCapacityConfig(target_capacity=4),
    )

    result = export_core_trial_lexicons(
        source_database=source,
        capacity_database=capacity_result.database,
        output_dir=tmp_path / "core",
        capacities=(4,),
        include_pinyin_sources=("pypinyin",),
        repo_root=repo_root,
    )

    tier = result.tiers[0]
    assert tier.selected_texts == 5
    dictionary = tier.dictionary_path.read_text(encoding="utf-8")
    assert "\n中国行\t" in dictionary
    assert tier.dictionary_path.parent.name == "capacity_0000004_plus_pypinyin"
    manifest = json.loads(tier.manifest_path.read_text(encoding="utf-8"))
    assert manifest["base_capacity"] == 4
    assert manifest["included_pinyin_sources"] == ["pypinyin"]
    selection = tier.selection_path.read_text(encoding="utf-8")
    assert "source:pypinyin" in selection


def test_export_can_filter_source_union_by_text_length(
    tmp_path: Path,
) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    source = _source_database(tmp_path / "source.sqlite3")
    capacity_result = build_static_capacity_model(
        source_database=source,
        output_dir=tmp_path / "capacity",
        config=StaticCapacityConfig(target_capacity=4),
    )

    result = export_core_trial_lexicons(
        source_database=source,
        capacity_database=capacity_result.database,
        output_dir=tmp_path / "core",
        capacities=(4,),
        include_source_lengths={"pypinyin": (2,)},
        trial_label="length-filter",
        repo_root=repo_root,
    )

    tier = result.tiers[0]
    assert tier.selected_texts == 4
    assert "\n中国行\t" not in tier.dictionary_path.read_text(encoding="utf-8")
    assert tier.dictionary_path.parent.name == (
        "capacity_0000004_plus_length_filter"
    )
    manifest = json.loads(tier.manifest_path.read_text(encoding="utf-8"))
    assert manifest["included_source_lengths"] == {"pypinyin": [2]}
    assert manifest["trial_label"] == "length-filter"


def test_export_can_filter_wanxiang_category_by_text_length(
    tmp_path: Path,
) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    source = _source_database(tmp_path / "source.sqlite3")
    capacity_result = build_static_capacity_model(
        source_database=source,
        output_dir=tmp_path / "capacity",
        config=StaticCapacityConfig(target_capacity=4),
    )

    result = export_core_trial_lexicons(
        source_database=source,
        capacity_database=capacity_result.database,
        output_dir=tmp_path / "core",
        capacities=(4,),
        include_wanxiang_category_lengths={"jichu": (3,)},
        trial_label="category-filter",
        repo_root=repo_root,
    )

    tier = result.tiers[0]
    assert tier.selected_texts == 5
    assert "\n中国行\t" in tier.dictionary_path.read_text(encoding="utf-8")
    manifest = json.loads(tier.manifest_path.read_text(encoding="utf-8"))
    assert manifest["included_wanxiang_category_lengths"] == {
        "jichu": [3]
    }
    selection = tier.selection_path.read_text(encoding="utf-8")
    assert "wanxiang_category:jichu:length:3" in selection
