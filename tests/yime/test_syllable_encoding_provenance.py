import csv
import json
from pathlib import Path

import pytest

from yime.utils.syllable_encoding_provenance import (
    SourceAttestation,
    build_syllable_encoding_provenance_rows,
    encoder_alias_rule_ids,
    load_rule_catalog,
    neutral_tone_encoding_rule_ids,
    orthography_rule_ids,
)


def test_rule_catalog_cannot_contain_parallel_code_or_layout_fields() -> None:
    catalog = load_rule_catalog()
    assert catalog
    assert all("basis" in entry and "policy" in entry for entry in catalog.values())


@pytest.mark.parametrize(
    ("pinyin", "expected_rule"),
    [
        ("yo1", "ORTH-YO-TO-IO"),
        ("jiu2", "ORTH-IU-TO-IOU"),
        ("dui4", "ORTH-UI-TO-UEI"),
        ("sun1", "ORTH-UN-TO-UEN"),
        ("xue2", "ORTH-JQX-UMLAUT"),
        ("yue4", "ORTH-Y-UMLAUT"),
        ("lv4", "TECH-V-ALIAS"),
        ("ng2", "ORTH-SYLLABIC-SPECIAL"),
    ],
)
def test_orthography_rules_name_historical_and_standard_form_families(
    pinyin: str,
    expected_rule: str,
) -> None:
    assert expected_rule in orthography_rule_ids(pinyin)


def test_encoder_aliases_are_explicit_and_uncatalogued_aliases_fail() -> None:
    assert encoder_alias_rule_ids("iou2", "iou2") == ()
    assert encoder_alias_rule_ids("ueng1", "ueng1") == ()
    with pytest.raises(ValueError, match="Uncatalogued encoder alias"):
        encoder_alias_rule_ids("made1", "up1")


def test_neutral_encoding_provenance_distinguishes_regular_and_special_routes() -> None:
    inventory = {"lai2": "lái", "lai5": "lai", "lo5": "lo"}

    assert neutral_tone_encoding_rule_ids("lai5", inventory) == (
        "ENC-NEUTRAL-REGULAR-DERIVATION",
    )
    assert neutral_tone_encoding_rule_ids("lo5", inventory) == (
        "ENC-NEUTRAL-SPECIAL-EXCEPTION",
    )
    assert orthography_rule_ids("lai5")[0] == "ORTH-SOURCE-ATTESTED-NEUTRAL"


def test_canonical_encoding_without_source_basis_is_rejected() -> None:
    with pytest.raises(ValueError, match="no registered source basis"):
        build_syllable_encoding_provenance_rows(
            {"a1": "ā"},
            attestations={},
        )


def test_small_provenance_sample_explains_source_rules_and_ids() -> None:
    rows = build_syllable_encoding_provenance_rows(
        {"yo1": "yō", "jiu2": "jiú"},
        attestations={
            "yo1": SourceAttestation(char_occurrences=1),
            "jiu2": SourceAttestation(phrase_occurrences=2),
        },
    )
    by_pinyin = {row.pinyin_tone: row for row in rows}
    assert by_pinyin["yo1"].source_rule_ids == "SRC-UNIHAN"
    assert by_pinyin["yo1"].orthography_rule_ids == "ORTH-YO-TO-IO"
    assert by_pinyin["jiu2"].orthography_rule_ids == "ORTH-IU-TO-IOU"
    assert by_pinyin["jiu2"].encoder_alias_rule_ids == ""
    assert len(by_pinyin["jiu2"].yinyuan_ids.split()) == 4


def test_checked_in_provenance_covers_every_canonical_encoding() -> None:
    inventory = json.loads(
        Path("internal_data/pinyin_source_db/lexicon_exports/pinyin_normalized.json").read_text(
            encoding="utf-8"
        )
    )
    with Path("internal_data/yime_syllable_encoding_provenance.tsv").open(
        encoding="utf-8", newline=""
    ) as file:
        actual = list(csv.DictReader(file, delimiter="\t"))

    assert len(actual) == len(inventory) == 1737
    assert {row["pinyin_tone"] for row in actual} == set(inventory)
    assert all(row["status"] == "encoded-with-registered-basis" for row in actual)
    assert all(row["source_rule_ids"] for row in actual)
    assert all(row["orthography_rule_ids"] for row in actual)
    assert all(len(row["yinyuan_ids"].split()) == 4 for row in actual)
    chuo5 = next(row for row in actual if row["pinyin_tone"] == "chuo5")
    assert "ORTH-SOURCE-ATTESTED-NEUTRAL" in chuo5["orthography_rule_ids"]
    assert "ENC-NEUTRAL-REGULAR-DERIVATION" in chuo5["encoder_alias_rule_ids"]


def test_excluded_reading_does_not_erase_its_character() -> None:
    with Path("internal_data/hanzi_pinyin/pinyin.txt").open(
        encoding="utf-8", newline=""
    ) as file:
        rows = {
            row["codepoint"]: row
            for row in csv.DictReader(
                (line for line in file if not line.startswith("#")),
                delimiter="\t",
            )
        }

    retained = rows["U+31FC5"]
    assert retained["hanzi"] == "𱿅"
    assert retained["common_reading"] == ""
    assert retained["readings"] == ""

    blue = rows["U+85CD"]
    assert blue["hanzi"] == "藍"
    assert blue["common_reading"] == "lán"
    assert blue["readings"] == "lán"

    inventory = json.loads(
        Path("internal_data/pinyin_source_db/lexicon_exports/pinyin_normalized.json").read_text(
            encoding="utf-8"
        )
    )
    assert "bong4" not in inventory
    assert "wong4" not in inventory
