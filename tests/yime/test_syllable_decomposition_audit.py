import csv
import json
from dataclasses import asdict
from pathlib import Path

import pytest

from yime.asset_paths import resolve_lexicon_source_db_path
from yime.utils.syllable_decomposition_audit import (
    build_encoder_failure_rows,
    build_syllable_decomposition_rows,
    export_syllable_decomposition_tsv,
    export_syllable_omissions_tsv,
    rule_ids,
)
from syllable.codec.yinjie_encoder import YinjieEncodingError


def test_structured_audit_exposes_normalization_segments_ids_and_rules() -> None:
    rows = build_syllable_decomposition_rows({"a1": "ā", "ya1": "yā", "yu1": "yū"})
    by_pinyin = {row.pinyin_tone: row for row in rows}

    assert by_pinyin["a1"].normalized == "a1"
    assert by_pinyin["a1"].shouyin_label == "'"
    assert by_pinyin["a1"].shouyin_id == "N12"
    assert by_pinyin["a1"].rule_id == "zero-initial"
    assert by_pinyin["ya1"].rule_id == "virtual-j"
    assert by_pinyin["yu1"].rule_id == "virtual-h-rounded"
    assert len(by_pinyin["yu1"].layout_code) == 4
    assert rule_ids(rows) == {"zero-initial", "virtual-j", "virtual-h-rounded"}


def test_export_is_exhaustive_and_keeps_alias_groups(tmp_path: Path) -> None:
    inventory = tmp_path / "inventory.json"
    inventory.write_text('{"a1": "ā", "a5": "a"}', encoding="utf-8")
    output = tmp_path / "audit.tsv"

    assert export_syllable_decomposition_tsv(output, inventory_path=inventory) == 2
    lines = output.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 3
    assert lines[0].startswith("pinyin_tone\tmarked_pinyin\tnormalized")
    assert all("\tN12\t" in line for line in lines[1:])


def test_checked_in_audit_matches_the_complete_current_encoder_chain() -> None:
    inventory_path = Path("internal_data/pinyin_source_db/lexicon_exports/pinyin_normalized.json")
    inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    expected = [asdict(row) for row in build_syllable_decomposition_rows(inventory)]
    with Path("internal_data/yime_syllable_decomposition.tsv").open(encoding="utf-8", newline="") as file:
        actual = list(csv.DictReader(file, delimiter="\t"))

    assert actual == expected


def test_encoder_failure_points_to_the_failed_semantic_stage() -> None:
    class FailingEncoder:
        def encode_yinjie_structured(self, _candidate: str) -> None:
            raise YinjieEncodingError("missing ganyin", stage="ganyin_encode")

    rows = build_encoder_failure_rows(
        {"bad1": "bad"},
        encoder=FailingEncoder(),  # type: ignore[arg-type]
    )

    assert len(rows) == 1
    assert rows[0].status == "encoder_failed"
    assert rows[0].source_rule.endswith("ganyin_encoder.py")


def test_checked_in_omission_audit_matches_current_sources(tmp_path: Path) -> None:
    if not resolve_lexicon_source_db_path(Path.cwd()).is_file():
        pytest.skip("requires unified source_lexicon.sqlite3")

    output = tmp_path / "yime_syllable_omissions.tsv"
    rows = export_syllable_omissions_tsv(output)
    with output.open(encoding="utf-8", newline="") as file:
        actual = list(csv.DictReader(file, delimiter="\t"))
    with Path("internal_data/yime_syllable_omissions.tsv").open(
        encoding="utf-8", newline=""
    ) as file:
        checked_in = list(csv.DictReader(file, delimiter="\t"))

    assert actual == [asdict(row) | {"occurrences": str(row.occurrences)} for row in rows]
    assert checked_in == actual
    filtered_rows = [row for row in rows if row.status == "filtered_before_inventory"]
    assert all(row.candidate.strip() for row in filtered_rows)
    assert {
        (row.candidate, row.reason.split(":", 1)[0]) for row in filtered_rows
    } <= {("la", "excluded_obsolete_reading")}
    assert not any(row.status == "encoder_failed" for row in rows)
