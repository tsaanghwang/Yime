"""Build a bounded second-level precomposition cache for replay.

The first level is an existing strict component dictionary.  The second level
adds:

* already selected long bridge/atom entries, when supplied; and
* the highest-weight formally encoded long candidates from the production
  dictionary.

This is a cache of reusable first-pass results, not a claim that every cached
string is a lexical atom or has a newly inferred source reading.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import heapq
import json
import sqlite3
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from yime.input_model.ranking_evidence import (
    DEFAULT_POLICY_PATH as DEFAULT_RANKING_POLICY_PATH,
    build_ranking_calibration,
    calibration_summary,
    resolve_text_ranking_evidence,
)


@dataclass(frozen=True)
class DictionaryEntry:
    text: str
    code: str
    weight: int


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_dictionary(
    path: Path,
) -> tuple[list[str], Iterable[DictionaryEntry]]:
    header: list[str] = []

    def visit() -> Iterable[DictionaryEntry]:
        in_data = False
        with path.open("r", encoding="utf-8-sig") as stream:
            for raw_line in stream:
                line = raw_line.rstrip("\r\n")
                if not in_data:
                    header.append(line)
                    if line.strip() == "...":
                        in_data = True
                    continue
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                fields = line.split("\t")
                if len(fields) < 2:
                    continue
                text = fields[0].strip()
                code = fields[1].replace(" ", "").strip()
                if not text or not code:
                    continue
                try:
                    weight = (
                        int(fields[2].strip())
                        if len(fields) >= 3
                        else 0
                    )
                except ValueError:
                    weight = 0
                yield DictionaryEntry(text, code, weight)

    entries = visit()
    # Advance through the generator only when the caller iterates; the header
    # is therefore populated by the companion helper below before writing.
    return header, entries


def _entries(path: Path) -> Iterable[DictionaryEntry]:
    _header, entries = _read_dictionary(path)
    return entries


def _header(path: Path) -> list[str]:
    result: list[str] = []
    with path.open("r", encoding="utf-8-sig") as stream:
        for raw_line in stream:
            line = raw_line.rstrip("\r\n")
            if line.startswith("name:"):
                result.append("name: yime_two_level_precomposition_trial")
            else:
                result.append(line)
            if line.strip() == "...":
                break
    return result


def _character_tiers(
    database: Path,
    maximum_tier: int,
) -> dict[str, int]:
    connection = sqlite3.connect(database)
    try:
        return {
            str(row[0]): int(row[1])
            for row in connection.execute(
                """
                SELECT hanzi, tier_number
                FROM character_tiers
                WHERE tier_number <= ?
                  AND encoded_reading_count > 0
                """,
                (maximum_tier,),
            )
        }
    finally:
        connection.close()


def _scan_production(
    source: Path,
    allowed: set[str],
    *,
    requested_keys: set[tuple[str, str]],
    capacity: int,
    minimum_length: int,
) -> tuple[set[tuple[str, str]], list[DictionaryEntry]]:
    matched_requested: set[tuple[str, str]] = set()
    heap: list[tuple[int, str, str]] = []
    for entry in _entries(source):
        key = (entry.text, entry.code)
        if key in requested_keys:
            matched_requested.add(key)
        if (
            capacity <= 0
            or len(entry.text) < minimum_length
            or any(char not in allowed for char in entry.text)
        ):
            continue
        key = (entry.weight, entry.text, entry.code)
        if len(heap) < capacity:
            heapq.heappush(heap, key)
        elif key > heap[0]:
            heapq.heapreplace(heap, key)
    best_long = sorted(
        (
            DictionaryEntry(text=item[1], code=item[2], weight=item[0])
            for item in heap
        ),
        key=lambda entry: (-entry.weight, entry.text, entry.code),
    )
    return matched_requested, best_long


def build(
    base: Path,
    production: Path,
    output: Path,
    manifest_path: Path,
    database: Path,
    *,
    capacity: int,
    maximum_tier: int,
    minimum_length: int,
    retained_long_dictionary: Path | None,
    selection_path: Path | None = None,
    ranking_policy_path: Path = DEFAULT_RANKING_POLICY_PATH,
    ranking_capacity_database: Path | None = None,
    core_maximum_tier: int | None = None,
    core_weight_offset: int = 0,
    peripheral_weight_offset: int = 0,
    require_core_above_peripheral: bool = False,
) -> dict[str, object]:
    character_tiers = _character_tiers(database, maximum_tier)
    allowed = set(character_tiers)
    if core_maximum_tier is None:
        core_maximum_tier = maximum_tier
    if core_maximum_tier > maximum_tier:
        raise ValueError(
            "Core character tier cannot exceed the runtime character tier"
        )
    selected: dict[tuple[str, str], DictionaryEntry] = {}
    source_counts = {
        "base": 0,
        "retained_long": 0,
        "frequency_cache": 0,
    }
    for entry in _entries(base):
        if any(char not in allowed for char in entry.text):
            continue
        selected[(entry.text, entry.code)] = entry
        source_counts["base"] += 1
    requested_base_keys = set(selected)
    if retained_long_dictionary is not None:
        for entry in _entries(retained_long_dictionary):
            if (
                len(entry.text) < minimum_length
                or any(char not in allowed for char in entry.text)
            ):
                continue
            key = (entry.text, entry.code)
            previous = selected.get(key)
            if previous is None or entry.weight > previous.weight:
                selected[key] = entry
            source_counts["retained_long"] += 1
    requested_retained_keys = set(selected) - requested_base_keys
    matched_requested, best_long_entries = _scan_production(
        production,
        allowed,
        requested_keys=set(selected),
        capacity=capacity,
        minimum_length=minimum_length,
    )
    # Single-character entries came directly from the unified source bundle
    # and formal encoder.  They are the atomic input foundation, so an older
    # production runtime export must not veto a newly admitted reading.
    formally_encoded_single_keys = {
        key for key in requested_base_keys if len(key[0]) == 1
    }
    retained_requested = (
        matched_requested | formally_encoded_single_keys
    )
    selected = {
        key: entry
        for key, entry in selected.items()
        if key in retained_requested
    }
    base_keys = requested_base_keys & retained_requested
    retained_added_keys = (
        requested_retained_keys & matched_requested
    )
    for entry in best_long_entries:
        key = (entry.text, entry.code)
        previous = selected.get(key)
        if previous is None or entry.weight > previous.weight:
            selected[key] = entry
        source_counts["frequency_cache"] += 1
    frequency_added_keys = (
        set(selected) - base_keys - retained_added_keys
    )
    ranking_calibration = build_ranking_calibration(
        source_database=database,
        capacity_database=ranking_capacity_database,
        policy_path=ranking_policy_path,
    )
    ranking_by_text = resolve_text_ranking_evidence(
        source_database=database,
        texts={text for text, _code in selected},
        calibration=ranking_calibration,
        capacity_database=ranking_capacity_database,
    )
    missing_ranking_texts = sorted(
        {text for text, _code in selected} - set(ranking_by_text)
    )
    if missing_ranking_texts:
        raise ValueError(
            "Selected texts are missing canonical ranking evidence: "
            + ", ".join(missing_ranking_texts[:10])
        )
    base_ranking_weights = {
        text: ranking.effective_weight
        for text, ranking in ranking_by_text.items()
    }
    character_segments: dict[str, str] = {}
    character_offsets: dict[str, int] = {}
    for text in ranking_by_text:
        if len(text) != 1:
            continue
        tier = character_tiers[text]
        if tier <= core_maximum_tier:
            character_segments[text] = "core"
            character_offsets[text] = core_weight_offset
        else:
            character_segments[text] = "peripheral"
            character_offsets[text] = peripheral_weight_offset
    selected = {
        key: DictionaryEntry(
            text=entry.text,
            code=entry.code,
            weight=(
                base_ranking_weights[entry.text]
                + character_offsets.get(entry.text, 0)
            ),
        )
        for key, entry in selected.items()
    }

    entries = sorted(
        selected.values(),
        key=lambda entry: (
            len(entry.text),
            entry.text,
            entry.code,
            -entry.weight,
        ),
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="\n") as stream:
        for line in _header(base):
            stream.write(line + "\n")
        for entry in entries:
            stream.write(
                f"{entry.text}\t{entry.code}\t{entry.weight}\n"
            )

    if selection_path is not None:
        selection_path.parent.mkdir(parents=True, exist_ok=True)
        with selection_path.open(
            "w",
            encoding="utf-8",
            newline="",
        ) as stream:
            writer = csv.writer(
                stream,
                delimiter="\t",
                lineterminator="\n",
            )
            writer.writerow(
                (
                    "text",
                    "full_layout_code",
                    "weight",
                    "ranking_weight_before_character_segment",
                    "character_tier",
                    "single_character_segment",
                    "character_segment_weight_offset",
                    "bcc_frequency",
                    "wanxiang_weight",
                    "ranking_evidence_source",
                    "ranking_evidence_status",
                    "normalized_fallback_percentile",
                    "normalized_structural_percentile",
                    "ranking_evidence_provisional",
                    "requires_independent_corpus",
                    "selection_level",
                    "selection_reason",
                )
            )
            for entry in entries:
                ranking = ranking_by_text[entry.text]
                key = (entry.text, entry.code)
                if key in base_keys:
                    level = "first_level"
                    reason = "source_gated_1_to_4_component"
                elif key in retained_added_keys:
                    level = "second_level"
                    reason = "retained_selected_long_bridge"
                else:
                    level = "second_level"
                    reason = "bounded_high_weight_long_cache"
                writer.writerow(
                    (
                        entry.text,
                        entry.code,
                        entry.weight,
                        base_ranking_weights[entry.text],
                        character_tiers.get(entry.text, ""),
                        character_segments.get(entry.text, ""),
                        character_offsets.get(entry.text, 0),
                        ranking.bcc_frequency,
                        ranking.wanxiang_weight,
                        ranking.evidence_source,
                        ranking.evidence_status,
                        (
                            f"{ranking.normalized_fallback_percentile:.9f}"
                        ),
                        (
                            f"{ranking.normalized_structural_percentile:.9f}"
                        ),
                        int(ranking.provisional),
                        int(ranking.requires_independent_corpus),
                        level,
                        reason,
                    )
                )

    texts_by_length: dict[int, set[str]] = {}
    readings_by_length: dict[int, int] = {}
    for entry in entries:
        length = len(entry.text)
        texts_by_length.setdefault(length, set()).add(entry.text)
        readings_by_length[length] = (
            readings_by_length.get(length, 0) + 1
        )
    character_segment_texts: dict[str, set[str]] = {
        "core": set(),
        "peripheral": set(),
    }
    character_segment_readings: Counter[str] = Counter()
    character_segment_weights: dict[str, list[int]] = {
        "core": [],
        "peripheral": [],
    }
    for entry in entries:
        segment = character_segments.get(entry.text)
        if segment is None:
            continue
        character_segment_texts[segment].add(entry.text)
        character_segment_readings[segment] += 1
        character_segment_weights[segment].append(entry.weight)
    minimum_core_weight = min(
        character_segment_weights["core"],
        default=0,
    )
    maximum_peripheral_weight = max(
        character_segment_weights["peripheral"],
        default=0,
    )
    core_above_peripheral = (
        not character_segment_weights["core"]
        or not character_segment_weights["peripheral"]
        or minimum_core_weight > maximum_peripheral_weight
    )
    if require_core_above_peripheral and not core_above_peripheral:
        raise ValueError(
            "Core single-character weight range overlaps the peripheral "
            f"range: core minimum {minimum_core_weight}, peripheral "
            f"maximum {maximum_peripheral_weight}"
        )
    payload = {
        "schema_version": "yime-two-level-precomposition-lexicon-v1",
        "semantics": {
            "first_level": "source-gated encoded 1-4 character components",
            "retained_long": (
                "previously selected bridge/atom entries; no new reading "
                "is inferred"
            ),
            "frequency_cache": (
                "bounded cache of high-weight existing encoded long "
                "candidates; not a lexical-atom classification"
            ),
        },
        "base_dictionary": str(base.resolve()),
        "base_sha256": _sha256(base),
        "production_dictionary": str(production.resolve()),
        "production_sha256": _sha256(production),
        "retained_long_dictionary": (
            str(retained_long_dictionary.resolve())
            if retained_long_dictionary
            else ""
        ),
        "frequency_cache_capacity": capacity,
        "minimum_long_length": minimum_length,
        "maximum_character_tier": maximum_tier,
        "allowed_encoded_hanzi": len(allowed),
        "single_character_ranking": {
            "core_maximum_tier": core_maximum_tier,
            "core_weight_offset": core_weight_offset,
            "peripheral_weight_offset": peripheral_weight_offset,
            "require_core_above_peripheral": (
                require_core_above_peripheral
            ),
            "core_distinct_characters": len(
                character_segment_texts["core"]
            ),
            "core_reading_entries": character_segment_readings["core"],
            "peripheral_distinct_characters": len(
                character_segment_texts["peripheral"]
            ),
            "peripheral_reading_entries": (
                character_segment_readings["peripheral"]
            ),
            "minimum_core_weight": minimum_core_weight,
            "maximum_peripheral_weight": maximum_peripheral_weight,
            "core_above_peripheral": core_above_peripheral,
        },
        "ranking_evidence": {
            **calibration_summary(ranking_calibration),
            "policy_sha256": _sha256(ranking_policy_path),
            "distinct_texts_by_source": dict(
                sorted(
                    Counter(
                        evidence.evidence_source
                        for evidence in ranking_by_text.values()
                    ).items()
                )
            ),
            "raw_bcc_and_lmdg_values_added": False,
            "missing_selected_source_texts": 0,
        },
        "source_scan_counts": source_counts,
        "production_intersection": {
            "requested_base_readings": len(requested_base_keys),
            "matched_base_readings": len(base_keys),
            "dropped_base_readings": (
                len(requested_base_keys) - len(base_keys)
            ),
            "retained_formal_single_readings_without_production_match": (
                len(formally_encoded_single_keys - matched_requested)
            ),
            "requested_retained_long_readings": len(
                requested_retained_keys
            ),
            "matched_retained_long_readings": len(
                retained_added_keys
            ),
            "dropped_retained_long_readings": (
                len(requested_retained_keys)
                - len(retained_added_keys)
            ),
        },
        "net_added_readings": {
            "retained_long": len(retained_added_keys),
            "frequency_cache": len(frequency_added_keys),
            "total": len(set(selected) - base_keys),
        },
        "net_added_distinct_texts": {
            "retained_long": len(
                {text for text, _code in retained_added_keys}
            ),
            "frequency_cache": len(
                {text for text, _code in frequency_added_keys}
            ),
            "total": len(
                {
                    text
                    for text, _code in set(selected) - base_keys
                }
            ),
        },
        "reading_entries_by_length": {
            str(key): readings_by_length[key]
            for key in sorted(readings_by_length)
        },
        "distinct_texts_by_length": {
            str(key): len(texts_by_length[key])
            for key in sorted(texts_by_length)
        },
        "total_reading_entries": len(entries),
        "total_distinct_texts": len(
            {entry.text for entry in entries}
        ),
        "output_dictionary": str(output.resolve()),
        "output_sha256": _sha256(output),
        "selection_tsv": (
            str(selection_path.resolve())
            if selection_path is not None
            else ""
        ),
        "selection_tsv_sha256": (
            _sha256(selection_path)
            if selection_path is not None
            else ""
        ),
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--production", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--capacity", type=int, required=True)
    parser.add_argument("--maximum-tier", type=int, default=5)
    parser.add_argument("--core-maximum-tier", type=int)
    parser.add_argument("--core-weight-offset", type=int, default=0)
    parser.add_argument("--peripheral-weight-offset", type=int, default=0)
    parser.add_argument(
        "--require-core-above-peripheral",
        action="store_true",
    )
    parser.add_argument("--minimum-length", type=int, default=5)
    parser.add_argument("--retained-long-dictionary", type=Path)
    parser.add_argument(
        "--ranking-policy",
        type=Path,
        default=DEFAULT_RANKING_POLICY_PATH,
    )
    parser.add_argument("--ranking-capacity-database", type=Path)
    parser.add_argument(
        "--selection",
        type=Path,
        help=(
            "Optional auditable TSV containing every retained encoded "
            "reading and its selection level/reason."
        ),
    )
    args = parser.parse_args()
    payload = build(
        args.base,
        args.production,
        args.output,
        args.manifest,
        args.database,
        capacity=args.capacity,
        maximum_tier=args.maximum_tier,
        minimum_length=args.minimum_length,
        retained_long_dictionary=args.retained_long_dictionary,
        selection_path=args.selection,
        ranking_policy_path=args.ranking_policy,
        ranking_capacity_database=args.ranking_capacity_database,
        core_maximum_tier=args.core_maximum_tier,
        core_weight_offset=args.core_weight_offset,
        peripheral_weight_offset=args.peripheral_weight_offset,
        require_core_above_peripheral=(
            args.require_core_above_peripheral
        ),
    )
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
