"""Offline experiment coverage accounting; never changes source admission."""
from pathlib import Path
from typing import Mapping
import sqlite3
from yime.canonical_yime_mapping import load_canonical_code_map
from tools.ascii_keyboard.layout_chain import load_disabled_yinyuan_ids, load_symbol_to_yinyuan_id, load_yinyuan_id_to_layout_key
ROOT = Path(__file__).resolve().parents[2]

def _assert_character_boundary(
    manifest: Mapping[str, object],
    character_policy: Mapping[str, object],
    *,
    label: str,
    expected_readings_field: str,
    active_boundary: Mapping[str, int] | None = None,
) -> dict[str, int]:
    expected_characters = int(
        character_policy["expected_distinct_characters"]
    )
    expected_readings = int(
        character_policy[expected_readings_field]
    )
    if active_boundary is not None:
        expected_characters = active_boundary["active_distinct_characters"]
        expected_readings = active_boundary[
            "active_source_reading_entries" if expected_readings_field == "expected_source_reading_entries"
            else "active_runtime_mapping_entries"]
    distinct_by_length = manifest.get("distinct_texts_by_length")
    readings_by_length = manifest.get("reading_entries_by_length")
    if not isinstance(distinct_by_length, Mapping) or not isinstance(
        readings_by_length, Mapping
    ):
        raise ValueError(
            f"{label} manifest has no per-length completeness counts"
        )
    actual_characters = int(distinct_by_length.get("1", 0))
    actual_readings = int(readings_by_length.get("1", 0))
    if actual_characters != expected_characters:
        raise ValueError(
            f"{label} single-character coverage mismatch: expected "
            f"{expected_characters}, got {actual_characters}"
        )
    if actual_readings != expected_readings:
        raise ValueError(
            f"{label} single-character reading coverage mismatch: expected "
            f"{expected_readings}, got {actual_readings}"
        )
    allowed_characters = manifest.get("allowed_encoded_hanzi")
    if allowed_characters is not None and (
        int(allowed_characters) != int(character_policy["expected_distinct_characters"])
    ):
        raise ValueError(
            f"{label} allowed-character inventory mismatch: expected "
            f"{expected_characters}, got {allowed_characters}"
        )
    return {
        "distinct_characters": actual_characters,
        "reading_entries": actual_readings,
    }

def active_character_boundary(source_database: Path, character_policy: Mapping[str, object]) -> dict[str, int]:
    """Account for layout-disabled readings without changing source admission.

    First prove the original source inventory against the fixed policy. Then
    derive the effective completeness target from complete semantic tuples;
    never patch historical counts to make a new projection appear complete.
    """
    disabled = load_disabled_yinyuan_ids(ROOT)
    symbols = load_symbol_to_yinyuan_id(ROOT)
    codes = load_canonical_code_map(ROOT)
    mapping = load_yinyuan_id_to_layout_key(ROOT)
    all_texts: set[str] = set()
    active_texts: set[str] = set()
    active_mappings: set[tuple[str, str]] = set()
    all_readings = active_readings = 0
    with sqlite3.connect(source_database.as_uri() + "?mode=ro", uri=True) as connection:
        rows = connection.execute("""
            SELECT r.text, r.numeric_pinyin
            FROM canonical_readings r JOIN character_tiers t ON t.hanzi = r.text
            WHERE t.tier_number <= ? AND t.encoded_reading_count > 0
              AND r.pronunciation_scope = 'standalone'
        """, (int(character_policy["maximum_tier"]),))
        for text, pinyin in rows:
            full = codes.get(pinyin)
            if not full:
                raise ValueError(f"Source character reading cannot be formally encoded: {text} / {pinyin}")
            ids = tuple(symbols[symbol] for symbol in full)
            all_texts.add(text)
            all_readings += 1
            if set(ids) & disabled:
                continue
            active_texts.add(text)
            active_readings += 1
            active_mappings.add((text, "".join(mapping[item] for item in ids)))
    if len(all_texts) != int(character_policy["expected_distinct_characters"]) or all_readings != int(character_policy["expected_source_reading_entries"]):
        raise ValueError(f"Canonical character source changed: {len(all_texts)} texts / {all_readings} readings")
    return {
        "source_distinct_characters": len(all_texts), "source_reading_entries": all_readings,
        "active_distinct_characters": len(active_texts), "active_source_reading_entries": active_readings,
        "active_runtime_mapping_entries": len(active_mappings),
        "excluded_disabled_readings": all_readings - active_readings,
        "excluded_disabled_only_characters": len(all_texts - active_texts),
    }
