from __future__ import annotations

import json
from pathlib import Path

from yime.lexicon_bundle.parsers import iter_reviewed_psc_candidate_readings
from yime.lexicon_bundle.psc_candidate_coverage import (
    InventorySegmenter,
    PSC_PRONUNCIATION_PERIPHERAL_CATEGORY,
    expand_transcription_pair,
)


ROOT = Path(__file__).resolve().parents[2]
INVENTORY = ROOT / "yime" / "pinyin_normalized.json"
CATALOG = (
    ROOT / "internal_data" / "pinyin_source_db" / "psc_candidate_readings.json"
)


def test_parallel_parenthetical_transcription_expands_to_two_pairs() -> None:
    pairs = expand_transcription_pair("把门儿（把门）", "bǎménr（bǎmén）")
    assert [(item.text, item.source_pinyin) for item in pairs] == [
        ("把门儿", "bǎménr"),
        ("把门", "bǎmén"),
    ]


def test_pronunciation_parenthesis_and_slashes_expand_without_changing_text() -> None:
    pairs = expand_transcription_pair("主意", "zhǔyi (zhúyi/zhùyi)")
    assert [(item.text, item.source_pinyin) for item in pairs] == [
        ("主意", "zhǔyi"),
        ("主意", "zhúyi"),
        ("主意", "zhùyi"),
    ]


def test_erhua_alias_uses_written_er_slot() -> None:
    segmenter = InventorySegmenter(INVENTORY)
    assert segmenter.segment_erhua_alias("馅儿饼", "xiànrbǐng") == "xiàn er bǐng"
    assert segmenter.segment_erhua_alias("旦角儿", "dànjuér") == "dàn jué er"
    assert segmenter.segment_erhua_alias("树叶儿", "shùyè") == "shù yè er"


def test_reviewed_catalog_is_complete_and_duplicate_free() -> None:
    payload = json.loads(CATALOG.read_text(encoding="utf-8"))
    counts = payload["counts"]
    assert counts["reviewed_observations"] == 20311
    assert counts["expanded_pairs"] == counts["accounted_expanded_pairs"]
    assert counts["missing_candidate_pairs"] == len(payload["records"])
    assert counts["pending_pairs"] == len(payload["pending_records"])
    keys = [(item["text"], item["numeric_pinyin"]) for item in payload["records"]]
    assert len(keys) == len(set(keys))
    assert all(item["source"] == "psc_candidate_coverage" for item in payload["records"])
    assert all(not item["source_primary"] for item in payload["records"])
    peripheral = [
        item
        for item in payload["records"]
        if item.get("source_category") == PSC_PRONUNCIATION_PERIPHERAL_CATEGORY
    ]
    assert len(peripheral) == 315
    assert all(
        item.get("candidate_layer") == "psc_normative_low_frequency_periphery"
        for item in peripheral
    )
    assert {
        evidence["source_kind"]
        for item in peripheral
        for evidence in item["evidence"]
    } >= {"psc_neutral_tone", "psc_erhua"}


def test_catalog_parser_keeps_candidate_records_non_primary() -> None:
    rows = list(iter_reviewed_psc_candidate_readings(CATALOG))
    payload = json.loads(CATALOG.read_text(encoding="utf-8"))
    assert len(rows) == payload["counts"]["missing_candidate_pairs"]
    assert all(row.source == "psc_candidate_coverage" for row in rows)
    assert all(not row.source_primary for row in rows)
