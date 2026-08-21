"""Export reviewed PSC Hanzi--Pinyin pairs missing from runtime candidates.

The exporter consumes the generated PSC comparison database plus its separate
transcription ledger.  It never writes either PSC source material or the
canonical source database.  Its checked-in JSON output is a candidate-only
supplement that a later normal source-bundle rebuild may import.
"""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, Sequence

from .gate import ReadingGate, is_han_text
from .psc_audit import normalize_marked_pinyin
from .psc_transcription_review import (
    TranscriptionReviewItem,
    TranscriptionReviewStore,
)
from .syllable_admission import DEFAULT_ADMISSION_PATH, load_syllable_admissions


SCHEMA_VERSION = "yime-reviewed-psc-candidate-readings-v1"
SOURCE_NAME = "psc_candidate_coverage"
PSC_PRONUNCIATION_PERIPHERAL_CATEGORY = (
    "reviewed_psc_neutral_erhua_peripheral"
)
PSC_PRONUNCIATION_PERIPHERAL_SOURCE_KINDS = frozenset(
    {"psc_neutral_tone", "psc_erhua"}
)
ELIGIBLE_REVIEW_STATES = frozenset({"machine_verified", "confirmed", "corrected"})
_PARENTHETICAL_RE = re.compile(r"^(.*?)\s*[（(]([^()（）]+)[）)]\s*$", re.DOTALL)
_ALTERNATIVE_RE = re.compile(r"[/、]+")
_SYLLABLE_SEPARATOR_RE = re.compile(r"[\s'’·•\-‐‑‒–—―]+")
_PINYIN_CHARACTER_TRANSLATION = str.maketrans(
    {
        "ă": "ǎ",
        "ĕ": "ě",
        "ĭ": "ǐ",
        "ŏ": "ǒ",
        "ŭ": "ǔ",
        "Ă": "Ǎ",
        "Ĕ": "Ě",
        "Ĭ": "Ǐ",
        "Ŏ": "Ǒ",
        "Ŭ": "Ǔ",
        "ã": "ā",
        "ẽ": "ē",
        "ĩ": "ī",
        "õ": "ō",
        "ũ": "ū",
        "Ã": "Ā",
        "Ẽ": "Ē",
        "Ĩ": "Ī",
        "Õ": "Ō",
        "Ũ": "Ū",
        "ɡ": "g",
        "ɢ": "g",
    }
)


@dataclass(frozen=True)
class ExpandedPair:
    text: str
    source_pinyin: str
    derivation: str


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _split_alternatives(value: str) -> tuple[str, ...]:
    result: list[str] = []
    for part in _ALTERNATIVE_RE.split(unicodedata.normalize("NFC", value)):
        normalized = " ".join(part.strip().split())
        if normalized and normalized not in result:
            result.append(normalized)
    return tuple(result)


def expand_transcription_pair(text: str, pinyin: str) -> tuple[ExpandedPair, ...]:
    """Expand slash alternatives and parallel parenthetical source forms."""

    text = unicodedata.normalize("NFC", text.strip())
    pinyin = unicodedata.normalize("NFC", pinyin.strip())
    text_match = _PARENTHETICAL_RE.fullmatch(text)
    pinyin_match = _PARENTHETICAL_RE.fullmatch(pinyin)
    bases: list[tuple[str, str, str]] = []
    if text_match and pinyin_match:
        bases.extend(
            (
                (text_match.group(1).strip(), pinyin_match.group(1).strip(), "parenthetical-main"),
                (text_match.group(2).strip(), pinyin_match.group(2).strip(), "parenthetical-alternate"),
            )
        )
    elif not text_match and pinyin_match:
        bases.extend(
            (
                (text, pinyin_match.group(1).strip(), "pronunciation-main"),
                (text, pinyin_match.group(2).strip(), "pronunciation-alternate"),
            )
        )
    elif text_match:
        return ()
    else:
        bases.append((text, pinyin, "direct"))

    result: list[ExpandedPair] = []
    for candidate_text, candidate_pinyin, derivation in bases:
        for index, variant in enumerate(_split_alternatives(candidate_pinyin), start=1):
            expanded = ExpandedPair(
                candidate_text,
                variant,
                derivation if index == 1 else f"{derivation}-slash-{index}",
            )
            if expanded not in result:
                result.append(expanded)
    return tuple(result)


class InventorySegmenter:
    """Uniquely segment continuous marked Pinyin with an optional 儿化 alias."""

    def __init__(self, inventory_path: Path) -> None:
        payload = json.loads(inventory_path.read_text(encoding="utf-8"))
        tokens = {
            unicodedata.normalize("NFC", str(marked).lower())
            for marked in payload.values()
            if str(marked).strip()
        }
        tokens.update(
            admission.marked.lower()
            for admission in load_syllable_admissions(DEFAULT_ADMISSION_PATH).values()
            if admission.status == "approved"
        )
        self.tokens = tuple(sorted(tokens, key=lambda item: (-len(item), item)))

    @staticmethod
    def _compact(reading: str) -> str:
        return _SYLLABLE_SEPARATOR_RE.sub(
            "",
            unicodedata.normalize(
                "NFC", reading.translate(_PINYIN_CHARACTER_TRANSLATION).strip().lower()
            ),
        )

    def segment(self, reading: str, expected_count: int) -> str | None:
        normalized = _SYLLABLE_SEPARATOR_RE.sub(
            " ",
            unicodedata.normalize(
                "NFC", reading.translate(_PINYIN_CHARACTER_TRANSLATION).strip().lower()
            ),
        )
        parts = tuple(part for part in normalized.split() if part)
        if len(parts) == expected_count and all(part in self.tokens for part in parts):
            return " ".join(parts)
        compact = self._compact(reading)
        if not compact or expected_count <= 0:
            return None
        paths = self._token_paths(compact, expected_count)
        return " ".join(paths[0]) if len(paths) == 1 else None

    def _token_paths(self, compact: str, expected_count: int) -> tuple[tuple[str, ...], ...]:
        memo: dict[tuple[int, int], tuple[tuple[str, ...], ...]] = {}

        def visit(offset: int, remaining: int) -> tuple[tuple[str, ...], ...]:
            key = (offset, remaining)
            if key in memo:
                return memo[key]
            if remaining == 0:
                return ((),) if offset == len(compact) else ()
            paths: list[tuple[str, ...]] = []
            for token in self.tokens:
                if compact.startswith(token, offset):
                    for suffix in visit(offset + len(token), remaining - 1):
                        paths.append((token, *suffix))
                        if len(paths) > 1:
                            memo[key] = tuple(paths)
                            return memo[key]
            memo[key] = tuple(paths)
            return memo[key]

        return visit(0, expected_count)

    def segment_erhua_alias(self, text: str, reading: str) -> str | None:
        """Map written 儿 to an input-only ``er`` slot without changing source Pinyin."""

        if "儿" not in text:
            return None
        compact = self._compact(reading)
        memo: dict[tuple[int, int], tuple[tuple[str, ...], ...]] = {}

        def visit(text_index: int, offset: int) -> tuple[tuple[str, ...], ...]:
            key = (text_index, offset)
            if key in memo:
                return memo[key]
            if text_index == len(text):
                return ((),) if offset == len(compact) else ()
            paths: list[tuple[str, ...]] = []
            if text[text_index] == "儿":
                consumptions = [0]
                if compact.startswith("r", offset):
                    consumptions.insert(0, 1)
                for consumed in dict.fromkeys(consumptions):
                    for suffix in visit(text_index + 1, offset + consumed):
                        paths.append(("er", *suffix))
                        if len(paths) > 1:
                            memo[key] = tuple(paths)
                            return memo[key]
            else:
                for token in self.tokens:
                    if token == "er" or token.startswith("ér"):
                        continue
                    if compact.startswith(token, offset):
                        for suffix in visit(text_index + 1, offset + len(token)):
                            paths.append((token, *suffix))
                            if len(paths) > 1:
                                memo[key] = tuple(paths)
                                return memo[key]
            memo[key] = tuple(paths)
            return memo[key]

        parses = visit(0, 0)
        return " ".join(parses[0]) if len(parses) == 1 else None

    def segment_by_characters(
        self,
        text: str,
        reading: str,
        readings_by_text: dict[str, tuple[str, ...]],
        *,
        erhua_alias: bool = False,
    ) -> str | None:
        """Resolve continuous Pinyin with attested single-character readings."""

        compact = self._compact(reading)
        memo: dict[tuple[int, int], tuple[tuple[str, ...], ...]] = {}

        def visit(text_index: int, offset: int) -> tuple[tuple[str, ...], ...]:
            key = (text_index, offset)
            if key in memo:
                return memo[key]
            if text_index == len(text):
                return ((),) if offset == len(compact) else ()
            paths: list[tuple[str, ...]] = []
            character = text[text_index]
            if character == "儿" and erhua_alias:
                consumptions = [0]
                if compact.startswith("r", offset):
                    consumptions.insert(0, 1)
                for consumed in dict.fromkeys(consumptions):
                    for suffix in visit(text_index + 1, offset + consumed):
                        paths.append(("er", *suffix))
            else:
                tokens = {
                    unicodedata.normalize("NFC", marked.lower())
                    for marked in readings_by_text.get(character, ())
                    if " " not in marked.strip()
                }
                for token in sorted(tokens, key=lambda item: (-len(item), item)):
                    if compact.startswith(token, offset):
                        for suffix in visit(text_index + 1, offset + len(token)):
                            paths.append((token, *suffix))
                            if len(paths) > 1:
                                memo[key] = tuple(paths)
                                return memo[key]
            memo[key] = tuple(paths)
            return memo[key]

        parses = visit(0, 0)
        return " ".join(parses[0]) if len(parses) == 1 else None


def _current_source_readings(
    connection: sqlite3.Connection,
) -> tuple[dict[str, tuple[str, ...]], set[tuple[str, str]]]:
    by_text: dict[str, list[str]] = {}
    candidates: set[tuple[str, str]] = set()
    for row in connection.execute(
        """
        SELECT text, marked_pinyin, numeric_pinyin, text_length,
               pronunciation_scope, is_primary, pinyin_sources
          FROM canonical_readings
         ORDER BY text, reading_rank, marked_pinyin
        """
    ):
        text = str(row["text"])
        marked = str(row["marked_pinyin"])
        sources = {
            item.strip()
            for item in str(row["pinyin_sources"] or "").split(",")
            if item.strip()
        }
        if sources and all(item == SOURCE_NAME for item in sources):
            continue
        by_text.setdefault(text, []).append(marked)
        candidate = (
            int(row["text_length"]) == 1
            and str(row["pronunciation_scope"]) == "standalone"
        ) or (
            int(row["text_length"]) > 1
            and (
                bool(row["is_primary"])
                or any(item.startswith("psc_orthoepy_") for item in sources)
            )
        )
        if candidate:
            candidates.add((text, str(row["numeric_pinyin"])))
    return {key: tuple(value) for key, value in by_text.items()}, candidates


def _matching_source_reading(
    text: str,
    source_pinyin: str,
    readings_by_text: dict[str, tuple[str, ...]],
) -> str | None:
    target = normalize_marked_pinyin(
        source_pinyin.translate(_PINYIN_CHARACTER_TRANSLATION)
    )
    matches = [
        marked
        for marked in readings_by_text.get(text, ())
        if normalize_marked_pinyin(marked) == target
    ]
    return matches[0] if len(set(matches)) == 1 else None


def _looks_attached_erhua(reading: str) -> bool:
    compact = InventorySegmenter._compact(reading)
    decomposed = "".join(
        char for char in unicodedata.normalize("NFD", compact) if "a" <= char <= "z"
    )
    return decomposed.endswith("r") and not decomposed.endswith("er")


def _eligible_items(store: TranscriptionReviewStore) -> Iterator[TranscriptionReviewItem]:
    for item in store.load_items():
        if item.review_state in ELIGIBLE_REVIEW_STATES:
            yield item


def export_psc_candidate_catalog(
    audit_database: Path,
    decision_database: Path,
    source_database: Path,
    decoder_inventory: Path,
    output_path: Path,
) -> dict[str, object]:
    """Write all reviewed PSC pairs absent from current runtime candidates."""

    snapshots = {
        "audit_database": _sha256(audit_database),
        "decision_database": _sha256(decision_database),
        "source_database": _sha256(source_database),
    }
    store = TranscriptionReviewStore(audit_database, decision_database)
    segmenter = InventorySegmenter(decoder_inventory)
    gate = ReadingGate(decoder_inventory)
    source_connection = sqlite3.connect(
        source_database.resolve().as_uri() + "?mode=ro", uri=True
    )
    source_connection.row_factory = sqlite3.Row
    readings_by_text, current_candidates = _current_source_readings(source_connection)
    source_connection.close()

    grouped: dict[tuple[str, str], dict[str, object]] = {}
    pending: list[dict[str, object]] = []
    expanded_count = 0
    eligible_count = 0
    existing_candidate_events = 0
    missing_candidate_events = 0
    try:
        for item in _eligible_items(store):
            eligible_count += 1
            expanded = expand_transcription_pair(item.effective_text, item.effective_pinyin)
            if not expanded:
                pending.append(
                    {
                        "source_kind": item.source_kind,
                        "source_key": item.source_key,
                        "text": item.effective_text,
                        "source_pinyin": item.effective_pinyin,
                        "reason": "unpaired_parenthetical_form",
                    }
                )
                continue
            for pair in expanded:
                expanded_count += 1
                if not is_han_text(pair.text):
                    pending.append(
                        {
                            "source_kind": item.source_kind,
                            "source_key": item.source_key,
                            "text": pair.text,
                            "source_pinyin": pair.source_pinyin,
                            "reason": "text_not_all_han",
                        }
                    )
                    continue
                reading = _matching_source_reading(
                    pair.text, pair.source_pinyin, readings_by_text
                )
                derivation = "existing-source-spacing" if reading else pair.derivation
                if reading is None:
                    use_erhua_alias = item.source_kind == "psc_erhua" or (
                        "儿" in pair.text and _looks_attached_erhua(pair.source_pinyin)
                    )
                    reading = segmenter.segment_by_characters(
                        pair.text,
                        pair.source_pinyin,
                        readings_by_text,
                        erhua_alias=use_erhua_alias,
                    )
                    if reading is not None:
                        derivation = "source-character-aligned-segmentation"
                    elif use_erhua_alias:
                        reading = segmenter.segment_erhua_alias(pair.text, pair.source_pinyin)
                        derivation = "written-er-input-alias"
                    else:
                        reading = segmenter.segment(pair.source_pinyin, len(pair.text))
                        derivation = "unique-inventory-segmentation"
                        if reading is None and "儿" in pair.text:
                            reading = segmenter.segment_erhua_alias(
                                pair.text, pair.source_pinyin
                            )
                            if reading is not None:
                                derivation = "written-er-zero-suffix-input-alias"
                if reading is None:
                    pending.append(
                        {
                            "source_kind": item.source_kind,
                            "source_key": item.source_key,
                            "text": pair.text,
                            "source_pinyin": pair.source_pinyin,
                            "reason": "no_unique_character_aligned_segmentation",
                        }
                    )
                    continue
                result = gate.admit(
                    pair.text,
                    reading,
                    codepoint_context=len(pair.text) == 1,
                    source=SOURCE_NAME,
                )
                if not result.accepted:
                    pending.append(
                        {
                            "source_kind": item.source_kind,
                            "source_key": item.source_key,
                            "text": pair.text,
                            "source_pinyin": pair.source_pinyin,
                            "input_pinyin": reading,
                            "reason": result.reason,
                        }
                    )
                    continue
                key = (pair.text, result.numeric)
                if key in current_candidates:
                    existing_candidate_events += 1
                    continue
                missing_candidate_events += 1
                evidence = {
                    "source_kind": item.source_kind,
                    "source_key": item.source_key,
                    "review_state": item.review_state,
                    "source_text": item.effective_text,
                    "source_pinyin": item.effective_pinyin,
                    "expanded_text": pair.text,
                    "expanded_pinyin": pair.source_pinyin,
                    "input_derivation": derivation,
                    "locator": item.locator,
                    "note": item.note,
                }
                record = grouped.setdefault(
                    key,
                    {
                        "text": pair.text,
                        "marked_pinyin": result.marked,
                        "numeric_pinyin": result.numeric,
                        "source": SOURCE_NAME,
                        "source_category": "reviewed_psc_candidate_coverage",
                        "source_rank": 92,
                        "source_primary": False,
                        "evidence": [],
                    },
                )
                if evidence not in record["evidence"]:
                    record["evidence"].append(evidence)
    finally:
        store.close()

    records = sorted(
        grouped.values(),
        key=lambda record: (str(record["text"]), str(record["numeric_pinyin"])),
    )
    for record in records:
        evidence_source_kinds = {
            str(item.get("source_kind", ""))
            for item in record.get("evidence", [])
            if isinstance(item, dict)
        }
        if evidence_source_kinds & PSC_PRONUNCIATION_PERIPHERAL_SOURCE_KINDS:
            record["source_category"] = PSC_PRONUNCIATION_PERIPHERAL_CATEGORY
            record["candidate_layer"] = "psc_normative_low_frequency_periphery"
    pending.sort(
        key=lambda record: (
            str(record.get("source_kind", "")),
            str(record.get("source_key", "")),
            str(record.get("text", "")),
        )
    )
    payload = {
        "schema_version": SCHEMA_VERSION,
        "policy": {
            "purpose": "Add reviewed PSC pairs absent from current runtime candidates.",
            "ranking": "Candidate coverage only; never rerank an existing reading.",
            "transcription": "Machine-verified, confirmed, and corrected transcription states are eligible.",
            "erhua": "Preserve source Pinyin as evidence and derive a written-儿 input alias with a separate er slot.",
            "neutral_erhua_runtime": (
                "Reviewed psc_neutral_tone and psc_erhua pairs may enter a "
                "separate fixed-low-frequency peripheral candidate layer; "
                "they never become source-primary or rerank the existing core."
            ),
        },
        "input_sha256": snapshots,
        "records": records,
        "pending_records": pending,
        "counts": {
            "reviewed_observations": eligible_count,
            "expanded_pairs": expanded_count,
            "existing_candidate_events": existing_candidate_events,
            "missing_candidate_evidence_events": missing_candidate_events,
            "missing_candidate_pairs": len(records),
            "pending_pairs": len(pending),
            "accounted_expanded_pairs": (
                existing_candidate_events + missing_candidate_events + len(pending)
            ),
        },
    }
    if payload["counts"]["accounted_expanded_pairs"] != expanded_count:
        raise RuntimeError("PSC candidate coverage accounting mismatch")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return payload["counts"]


__all__ = [
    "ELIGIBLE_REVIEW_STATES",
    "ExpandedPair",
    "InventorySegmenter",
    "SCHEMA_VERSION",
    "SOURCE_NAME",
    "PSC_PRONUNCIATION_PERIPHERAL_CATEGORY",
    "PSC_PRONUNCIATION_PERIPHERAL_SOURCE_KINDS",
    "expand_transcription_pair",
    "export_psc_candidate_catalog",
]
