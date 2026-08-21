"""Explain every canonical syllable encoding through sources and stable rules.

This module audits the real encoder.  The rule catalog contains no Pinyin-to-code
mapping and therefore cannot become a parallel semantic or keyboard source.
"""

from __future__ import annotations

import csv
import json
import sqlite3
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable, cast

from syllable.codec.neutral_tone_encoding import (
    NeutralToneEncodingPolicy,
    NeutralToneException,
)
from syllable.codec.yinjie_encoder import YinjieEncoder
from yime.utils.yinyuan_id_chain import REPO_ROOT, load_symbol_to_yinyuan_id
from yime.asset_paths import resolve_lexicon_source_db_path


DEFAULT_RULE_CATALOG_PATH = REPO_ROOT / "internal_data" / "syllable_encoding_rule_catalog.json"
DEFAULT_PROVENANCE_OUTPUT_PATH = REPO_ROOT / "internal_data" / "yime_syllable_encoding_provenance.tsv"
DEFAULT_CHAR_SOURCE_PATH = REPO_ROOT / "internal_data" / "hanzi_pinyin" / "pinyin.txt"
DEFAULT_PHRASE_SOURCE_PATH = REPO_ROOT / "internal_data" / "phrase_pinyin" / "phrase_pinyin.txt"
DEFAULT_PATCH_PATH = REPO_ROOT / "internal_data" / "pinyin_source_db" / "pinyin_normalized_patch.json"


@dataclass(frozen=True)
class SourceAttestation:
    char_occurrences: int = 0
    phrase_occurrences: int = 0
    reviewed_patch: bool = False


@dataclass(frozen=True)
class SyllableEncodingProvenanceRow:
    pinyin_tone: str
    marked_pinyin: str
    source_rule_ids: str
    char_occurrences: int
    phrase_occurrences: int
    reviewed_patch: bool
    orthography_rule_ids: str
    encoder_alias_rule_ids: str
    normalized_pinyin: str
    shouyin_label: str
    analyzed_ganyin_label: str
    encoder_ganyin_label: str
    yinyuan_ids: str
    rule_basis: str
    status: str


def load_rule_catalog(path: Path = DEFAULT_RULE_CATALOG_PATH) -> dict[str, dict[str, str]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        raise ValueError(f"Unsupported syllable rule catalog: {path}")
    rules = payload.get("rules")
    if not isinstance(rules, dict) or not rules:
        raise ValueError(f"Syllable rule catalog has no rules: {path}")
    prohibited = {str(item) for item in cast(list[object], payload.get("prohibited_fields", []))}
    validated: dict[str, dict[str, str]] = {}
    for rule_id, raw_entry in rules.items():
        if not isinstance(raw_entry, dict):
            raise ValueError(f"Invalid rule entry: {rule_id}")
        occupied = prohibited & set(raw_entry)
        if occupied:
            raise ValueError(f"Rule {rule_id} contains forbidden mapping fields: {sorted(occupied)}")
        entry = {str(key): str(value) for key, value in raw_entry.items()}
        missing = {"layer", "title", "basis", "policy"} - set(entry)
        if missing:
            raise ValueError(f"Rule {rule_id} is incomplete: {sorted(missing)}")
        validated[str(rule_id)] = entry
    return validated


def _add_count(mapping: dict[str, int], key: str) -> None:
    mapping[key] = mapping.get(key, 0) + 1


def load_source_attestations(
    *,
    char_source_path: Path = DEFAULT_CHAR_SOURCE_PATH,
    phrase_source_path: Path = DEFAULT_PHRASE_SOURCE_PATH,
    patch_path: Path = DEFAULT_PATCH_PATH,
) -> dict[str, SourceAttestation]:
    """Count accepted source evidence from the unified canonical source DB."""
    # The path arguments remain for API compatibility with older callers. They
    # must not redirect the audit around the canonical source database.
    _ = (char_source_path, phrase_source_path)

    char_counts: dict[str, int] = {}
    phrase_counts: dict[str, int] = {}
    source_db = resolve_lexicon_source_db_path(REPO_ROOT)
    with sqlite3.connect(source_db) as conn:
        for text, numeric in conn.execute(
            "SELECT text, numeric FROM accepted_readings"
        ):
            target = char_counts if len(str(text)) == 1 else phrase_counts
            for syllable in str(numeric).split():
                _add_count(target, syllable)

    patch_payload = json.loads(patch_path.read_text(encoding="utf-8"))
    patch_keys = {str(key) for key in patch_payload}
    all_keys = set(char_counts) | set(phrase_counts) | patch_keys
    return {
        key: SourceAttestation(
            char_occurrences=char_counts.get(key, 0),
            phrase_occurrences=phrase_counts.get(key, 0),
            reviewed_patch=key in patch_keys,
        )
        for key in all_keys
    }


def source_rule_ids(attestation: SourceAttestation) -> tuple[str, ...]:
    rules: list[str] = []
    if attestation.char_occurrences:
        rules.append("SRC-UNIHAN")
    if attestation.phrase_occurrences:
        rules.append("SRC-PHRASE-PINYIN")
    if attestation.reviewed_patch:
        rules.append("SRC-REVIEWED-PATCH")
    return tuple(rules)


def _base_orthography_rule_ids(pinyin_tone: str) -> tuple[str, ...]:
    base = pinyin_tone[:-1].lower() if pinyin_tone[-1:].isdigit() else pinyin_tone.lower()
    if "v" in base:
        return ("TECH-V-ALIAS",)
    if base in {"ê", "m", "n", "ng"} or base.startswith(("hm", "hn", "hng")):
        return ("ORTH-SYLLABIC-SPECIAL",)
    if base.startswith(("a", "o", "e", "ê")):
        return ("ORTH-ZERO-INITIAL",)
    if base in {"zhi", "chi", "shi", "ri", "zi", "ci", "si"}:
        return ("ORTH-APICAL-I",)
    if base.startswith("yong"):
        return ("ORTH-YONG-TO-IONG",)
    if base == "yo":
        return ("ORTH-YO-TO-IO",)
    if base.startswith(("yu", "yü")):
        return ("ORTH-Y-UMLAUT",)
    if base.startswith("y"):
        return ("ORTH-Y-FAMILY",)
    if base.startswith("w"):
        return ("ORTH-W-FAMILY",)

    initial_length = 2 if base.startswith(("zh", "ch", "sh")) else 1
    initial = base[:initial_length]
    final = base[initial_length:]
    if initial in {"j", "q", "x"} and final.startswith(("u", "ü")):
        return ("ORTH-JQX-UMLAUT",)
    if final == "iu":
        return ("ORTH-IU-TO-IOU",)
    if final == "ui":
        return ("ORTH-UI-TO-UEI",)
    if final == "un":
        return ("ORTH-UN-TO-UEN",)
    return ("ORTH-REGULAR",)


def orthography_rule_ids(pinyin_tone: str) -> tuple[str, ...]:
    base_rules = _base_orthography_rule_ids(pinyin_tone)
    if pinyin_tone.endswith("5"):
        return ("ORTH-SOURCE-ATTESTED-NEUTRAL", *base_rules)
    return base_rules


def neutral_tone_encoding_rule_ids(
    pinyin_tone: str,
    inventory: Iterable[str],
    *,
    exceptions: dict[str, NeutralToneException] | None = None,
) -> tuple[str, ...]:
    if not pinyin_tone.endswith("5"):
        return ()
    resolution = NeutralToneEncodingPolicy(inventory, exceptions).require_admitted(
        pinyin_tone
    )
    return (resolution.rule_id,)


def encoder_alias_rule_ids(analyzed_ganyin: str, encoder_ganyin: str) -> tuple[str, ...]:
    if analyzed_ganyin == encoder_ganyin:
        return ()
    if analyzed_ganyin.startswith(("hm", "hn", "hng")):
        return ("ENC-H-NASAL-ALIAS",)
    raise ValueError(
        "Uncatalogued encoder alias: "
        f"analyzed={analyzed_ganyin!r}, encoder={encoder_ganyin!r}"
    )


def _join_rule_titles(rule_ids: Iterable[str], catalog: dict[str, dict[str, str]]) -> str:
    return "；".join(f"{rule_id} {catalog[rule_id]['title']}" for rule_id in rule_ids)


def build_syllable_encoding_provenance_rows(
    inventory: dict[str, str],
    *,
    attestations: dict[str, SourceAttestation] | None = None,
    catalog: dict[str, dict[str, str]] | None = None,
    encoder: YinjieEncoder | None = None,
    repo_root: Path = REPO_ROOT,
) -> list[SyllableEncodingProvenanceRow]:
    resolved_attestations = attestations if attestations is not None else load_source_attestations()
    resolved_catalog = catalog if catalog is not None else load_rule_catalog()
    resolved_encoder = encoder or YinjieEncoder()
    symbol_to_id = load_symbol_to_yinyuan_id(repo_root)
    rows: list[SyllableEncodingProvenanceRow] = []

    for pinyin_tone, marked_pinyin in sorted(inventory.items()):
        attestation = resolved_attestations.get(pinyin_tone, SourceAttestation())
        source_ids = source_rule_ids(attestation)
        if not source_ids:
            raise ValueError(f"Canonical syllable has no registered source basis: {pinyin_tone}")
        orthography_ids = orthography_rule_ids(pinyin_tone)
        result = resolved_encoder.encode_yinjie_structured(pinyin_tone)
        encoder_ganyin_label = resolved_encoder.ganyin_encoder.normalize_ganyin_name(
            result.segments.ganyin_label
        )
        encoder_ids = encoder_alias_rule_ids(
            result.segments.ganyin_label,
            encoder_ganyin_label,
        )
        encoder_ids = (
            *neutral_tone_encoding_rule_ids(pinyin_tone, inventory),
            *encoder_ids,
        )
        all_rule_ids = (*source_ids, *orthography_ids, *encoder_ids)
        unknown = set(all_rule_ids) - set(resolved_catalog)
        if unknown:
            raise ValueError(f"Unregistered rule IDs for {pinyin_tone}: {sorted(unknown)}")
        symbols = (
            result.shouyin_yinyuan,
            result.ganyin_slots.huyin,
            result.ganyin_slots.zhuyin,
            result.ganyin_slots.moyin,
        )
        ids = tuple(symbol_to_id[symbol] for symbol in symbols)
        rows.append(
            SyllableEncodingProvenanceRow(
                pinyin_tone=pinyin_tone,
                marked_pinyin=str(marked_pinyin),
                source_rule_ids=" ".join(source_ids),
                char_occurrences=attestation.char_occurrences,
                phrase_occurrences=attestation.phrase_occurrences,
                reviewed_patch=attestation.reviewed_patch,
                orthography_rule_ids=" ".join(orthography_ids),
                encoder_alias_rule_ids=" ".join(encoder_ids),
                normalized_pinyin=result.segments.normalized,
                shouyin_label=result.segments.shouyin_label,
                analyzed_ganyin_label=result.segments.ganyin_label,
                encoder_ganyin_label=encoder_ganyin_label,
                yinyuan_ids=" ".join(ids),
                rule_basis=_join_rule_titles(all_rule_ids, resolved_catalog),
                status="encoded-with-registered-basis",
            )
        )
    return rows


def export_syllable_encoding_provenance_tsv(
    inventory_path: Path,
    output_path: Path = DEFAULT_PROVENANCE_OUTPUT_PATH,
    *,
    char_source_path: Path = DEFAULT_CHAR_SOURCE_PATH,
    phrase_source_path: Path = DEFAULT_PHRASE_SOURCE_PATH,
    patch_path: Path = DEFAULT_PATCH_PATH,
) -> list[SyllableEncodingProvenanceRow]:
    inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    if not isinstance(inventory, dict) or not inventory:
        raise ValueError(f"Pinyin inventory is empty or invalid: {inventory_path}")
    attestations = load_source_attestations(
        char_source_path=char_source_path,
        phrase_source_path=phrase_source_path,
        patch_path=patch_path,
    )
    rows = build_syllable_encoding_provenance_rows(
        cast(dict[str, str], inventory),
        attestations=attestations,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(SyllableEncodingProvenanceRow.__dataclass_fields__)
    with output_path.open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(asdict(row) for row in rows)
    return rows
