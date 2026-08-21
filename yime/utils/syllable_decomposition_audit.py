"""Export the canonical Pinyin-to-Yinyuan decomposition as an inspectable table.

The table is a read-only view of the real encoder stages.  It must never grow a
second Pinyin parser or infer Yinyuan IDs from keyboard keys.
"""

from __future__ import annotations

import csv
import json
import sqlite3
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

from syllable.codec.yinjie_encoder import YinjieEncoder, YinjieEncodingError
from yime.utils.yinyuan_id_chain import (
    REPO_ROOT,
    load_semantic_yinyuan_registry,
    load_symbol_to_yinyuan_id,
    load_yinyuan_id_to_layout_key,
)
from yime.asset_paths import resolve_lexicon_source_db_path


DEFAULT_INVENTORY_PATH = (
    REPO_ROOT / "internal_data" / "pinyin_source_db" / "lexicon_exports" / "pinyin_normalized.json"
)
DEFAULT_OUTPUT_PATH = REPO_ROOT / "internal_data" / "yime_syllable_decomposition.tsv"
DEFAULT_OMISSION_OUTPUT_PATH = REPO_ROOT / "internal_data" / "yime_syllable_omissions.tsv"
DEFAULT_CHAR_SOURCE_PATH = REPO_ROOT / "internal_data" / "hanzi_pinyin" / "pinyin.txt"


@dataclass(frozen=True)
class SyllableDecompositionRow:
    pinyin_tone: str
    marked_pinyin: str
    normalized: str
    shouyin_label: str
    ganyin_label: str
    rule_id: str
    shouyin_symbol: str
    huyin_symbol: str
    zhuyin_symbol: str
    moyin_symbol: str
    shouyin_id: str
    huyin_id: str
    zhuyin_id: str
    moyin_id: str
    shouyin_name: str
    huyin_name: str
    zhuyin_name: str
    moyin_name: str
    layout_code: str
    aliases: str
    status: str


@dataclass(frozen=True)
class SyllableOmissionRow:
    """A candidate absent from a later stage, without pretending every gap is a syllable."""

    candidate: str
    candidate_kind: str
    stage: str
    status: str
    classification: str
    rule_ids: str
    occurrences: int
    reason: str
    surface_forms: str
    source_rule: str
    first_change: str
    followup_change: str
    lock_scope: str


def _rule_id(pinyin_tone: str, ids: tuple[str, str, str, str]) -> str:
    initial, first_musical, _, _ = ids
    base = pinyin_tone[:-1].lower() if pinyin_tone[-1:].isdigit() else pinyin_tone.lower()
    if initial == "N12":
        if base in {"ê", "m", "n", "ng"}:
            return f"syllabic-{base}"
        return "zero-initial"
    if initial == "N23":
        if first_musical in {"M01", "M02", "M03"}:
            return "virtual-j"
        if first_musical in {"M07", "M08", "M09"}:
            return "virtual-h-rounded"
        return "virtual-y-other"
    if initial == "N24":
        return "virtual-w"
    if initial == "N25":
        return "virtual-h-rounded"
    return "regular-initial"


def build_syllable_decomposition_rows(
    inventory: dict[str, str],
    *,
    repo_root: Path = REPO_ROOT,
    encoder: YinjieEncoder | None = None,
) -> list[SyllableDecompositionRow]:
    """Run every inventory item through the canonical structured encoder."""
    resolved_encoder = encoder or YinjieEncoder()
    symbol_to_id = load_symbol_to_yinyuan_id(repo_root)
    registry = load_semantic_yinyuan_registry(repo_root)
    layout = load_yinyuan_id_to_layout_key(repo_root)

    staged: list[tuple[str, str, object, tuple[str, str, str, str]]] = []
    aliases_by_ids: dict[tuple[str, str, str, str], list[str]] = {}
    for pinyin_tone, marked_pinyin in inventory.items():
        result = resolved_encoder.encode_yinjie_structured(pinyin_tone)
        symbols = (
            result.shouyin_yinyuan,
            result.ganyin_slots.huyin,
            result.ganyin_slots.zhuyin,
            result.ganyin_slots.moyin,
        )
        try:
            ids = tuple(symbol_to_id[symbol] for symbol in symbols)
        except KeyError as error:
            raise ValueError(f"{pinyin_tone} contains an unknown Yinyuan symbol: {error}") from error
        if len(ids) != 4:
            raise ValueError(f"{pinyin_tone} did not resolve to four Yinyuan IDs: {ids}")
        typed_ids = (ids[0], ids[1], ids[2], ids[3])
        aliases_by_ids.setdefault(typed_ids, []).append(pinyin_tone)
        staged.append((pinyin_tone, str(marked_pinyin), result, typed_ids))

    rows: list[SyllableDecompositionRow] = []
    for pinyin_tone, marked_pinyin, raw_result, ids in staged:
        result = raw_result
        symbols = (
            result.shouyin_yinyuan,
            result.ganyin_slots.huyin,
            result.ganyin_slots.zhuyin,
            result.ganyin_slots.moyin,
        )
        names = tuple(registry[yinyuan_id]["label"] for yinyuan_id in ids)
        rows.append(
            SyllableDecompositionRow(
                pinyin_tone=pinyin_tone,
                marked_pinyin=marked_pinyin,
                normalized=result.segments.normalized,
                shouyin_label=result.segments.shouyin_label,
                ganyin_label=result.segments.ganyin_label,
                rule_id=_rule_id(pinyin_tone, ids),
                shouyin_symbol=symbols[0],
                huyin_symbol=symbols[1],
                zhuyin_symbol=symbols[2],
                moyin_symbol=symbols[3],
                shouyin_id=ids[0],
                huyin_id=ids[1],
                zhuyin_id=ids[2],
                moyin_id=ids[3],
                shouyin_name=names[0],
                huyin_name=names[1],
                zhuyin_name=names[2],
                moyin_name=names[3],
                layout_code="".join(layout[yinyuan_id] for yinyuan_id in ids),
                aliases=" ".join(aliases_by_ids[ids]),
                status="ok",
            )
        )
    return rows


def export_syllable_decomposition_tsv(
    output_path: Path = DEFAULT_OUTPUT_PATH,
    *,
    inventory_path: Path = DEFAULT_INVENTORY_PATH,
    repo_root: Path = REPO_ROOT,
) -> int:
    inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    if not isinstance(inventory, dict) or not inventory:
        raise ValueError(f"Pinyin inventory is empty or invalid: {inventory_path}")
    rows = build_syllable_decomposition_rows(inventory, repo_root=repo_root)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(SyllableDecompositionRow.__dataclass_fields__)
    with output_path.open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(asdict(row) for row in rows)
    return len(rows)


def rule_ids(rows: Iterable[SyllableDecompositionRow]) -> set[str]:
    return {row.rule_id for row in rows}


def build_source_filter_omission_rows(
    char_source_path: Path = DEFAULT_CHAR_SOURCE_PATH,
) -> list[SyllableOmissionRow]:
    """Expose single-character readings rejected by the unified source gate."""
    _ = char_source_path
    counts: dict[tuple[str, str], int] = {}
    source_db = resolve_lexicon_source_db_path(REPO_ROOT)
    with sqlite3.connect(source_db) as conn:
        for candidate, reason, occurrences in conn.execute(
            """
            SELECT reading, reason, COUNT(*)
            FROM rejections
            WHERE length(text) = 1
              AND trim(reading) <> ''
            GROUP BY reading, reason
            """
        ):
            counts[(str(candidate), str(reason))] = int(occurrences)

    return [
        SyllableOmissionRow(
            candidate=candidate,
            candidate_kind="source_marked_syllable",
            stage="source_import",
            status="filtered_before_inventory",
            classification="导入格式规则过滤",
            rule_ids="",
            occurrences=occurrences,
            reason=reason,
            surface_forms="",
            source_rule="yime.lexicon_bundle.gate.ReadingGate",
            first_change="先核实上游读音是否合法；合法时修改导入规范化或允许格式。",
            followup_change="重建 source_lexicon.sqlite3，再刷新物化音节清单和全部编码产物。",
            lock_scope="上游语义输入改动：不得直接补 Yinyuan ID、码元或键位。",
        )
        for (candidate, reason), occurrences in sorted(counts.items())
    ]


def build_encoder_failure_rows(
    inventory: dict[str, str],
    *,
    encoder: YinjieEncoder | None = None,
) -> list[SyllableOmissionRow]:
    """Expose canonical inventory entries that fail the real structured encoder."""
    resolved_encoder = encoder or YinjieEncoder()
    rows: list[SyllableOmissionRow] = []
    for candidate in sorted(inventory):
        try:
            resolved_encoder.encode_yinjie_structured(candidate)
        except YinjieEncodingError as error:
            stage = error.stage
            if stage == "split":
                rule = "syllable/analysis/syllable_encoding_pipeline.py"
            elif stage == "shouyin_encode":
                rule = "syllable/analysis/shouyin_encoder.py"
            elif stage == "ganyin_encode":
                rule = "syllable/analysis/ganyin_encoder.py"
            else:
                rule = "syllable/codec/yinjie_encoder.py"
            rows.append(
                SyllableOmissionRow(
                    candidate=candidate,
                    candidate_kind="canonical_numeric_syllable",
                    stage=f"canonical_encoder:{stage}",
                    status="encoder_failed",
                    classification="规范音节编码失败",
                    rule_ids="",
                    occurrences=1,
                    reason=str(error),
                    surface_forms="",
                    source_rule=rule,
                    first_change="从错误阶段指向的正式规则或语义真源开始修复。",
                    followup_change="重建 yinjie_code.json，并由锁检查完整的拼音到四个 Yinyuan ID 链。",
                    lock_scope="语义改动：单独审查并更新语义锁；不得在布局投影层兜底。",
                )
            )
    return rows


def build_syllable_omission_rows(
    inventory: dict[str, str],
    *,
    char_source_path: Path = DEFAULT_CHAR_SOURCE_PATH,
    encoder: YinjieEncoder | None = None,
) -> list[SyllableOmissionRow]:
    rows = build_source_filter_omission_rows(char_source_path)
    rows.extend(build_encoder_failure_rows(inventory, encoder=encoder))
    return rows


def export_syllable_omissions_tsv(
    output_path: Path = DEFAULT_OMISSION_OUTPUT_PATH,
    *,
    inventory_path: Path = DEFAULT_INVENTORY_PATH,
    char_source_path: Path = DEFAULT_CHAR_SOURCE_PATH,
) -> list[SyllableOmissionRow]:
    inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    if not isinstance(inventory, dict) or not inventory:
        raise ValueError(f"Pinyin inventory is empty or invalid: {inventory_path}")
    rows = build_syllable_omission_rows(
        inventory,
        char_source_path=char_source_path,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(SyllableOmissionRow.__dataclass_fields__)
    with output_path.open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(asdict(row) for row in rows)
    return rows
