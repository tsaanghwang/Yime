"""Compile explicit word-final erhua evidence into reversible input routes.

This module deliberately does not infer erhua from a written ``儿`` suffix,
``r`` spelling, or an ``er5`` compatibility syllable. Admission requires a
reviewed dictionary/source record whose evidence explicitly carries the
``psc_erhua`` source kind. The written candidate text is never rewritten.
"""

from __future__ import annotations

import hashlib
import json
import os
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence, cast

from syllable.analysis.syllable_encoding_pipeline import SyllableEncodingPipeline
from yime.utils.canonical_yime_mapping import load_canonical_code_map
from yime.utils.code_modes import CodeModeRecord, build_code_mode_record, load_ganyin_symbol_metadata
from yime.utils.yinyuan_id_chain import (
    load_yinyuan_id_to_layout_key,
    symbol_code_to_yinyuan_ids,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = Path("internal_data/pinyin_source_db/psc_candidate_readings.json")
DEFAULT_FEATURE_RULES = Path("external_data/erhua_yinyuan_feature_rules.json")
DEFAULT_ANNOTATIONS = Path("internal_data/connected_speech/erhua_lexical_annotations.json")
DEFAULT_ALIASES = Path("internal_data/connected_speech/erhua_input_aliases.json")
ERHUA_SOURCE_KIND = "psc_erhua"
ERHUA_SUFFIX_SYLLABLE = "er5"


@dataclass(frozen=True)
class ErhuaCompileContext:
    repo_root: Path
    canonical_code_map: Mapping[str, str]
    layout_key_by_id: Mapping[str, str]
    musical_metadata: Mapping[str, Mapping[str, Any]]
    target_families: Mapping[str, Mapping[str, Any]]
    feature_rule_by_final: Mapping[str, Mapping[str, Any]]


def _read_json(path: Path) -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(path.read_text(encoding="utf-8")))


def _write_json_atomic(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    os.replace(temporary, path)


def _is_han(character: str) -> bool:
    if len(character) != 1:
        return False
    name = unicodedata.name(character, "")
    return name.startswith("CJK UNIFIED IDEOGRAPH-") or name.startswith(
        "CJK COMPATIBILITY IDEOGRAPH-"
    )


def _confirmed_erhua_evidence(record: Mapping[str, Any]) -> list[dict[str, Any]]:
    return [
        cast(dict[str, Any], evidence)
        for evidence in record.get("evidence") or []
        if isinstance(evidence, Mapping)
        and evidence.get("source_kind") == ERHUA_SOURCE_KIND
        and evidence.get("review_state") == "confirmed"
    ]


def is_explicit_word_final_erhua(record: Mapping[str, Any]) -> bool:
    """Check the strict first-stage admission gate; never infer permission."""

    text = str(record.get("text") or "")
    if len(text) < 2 or not text.endswith("儿") or not all(_is_han(char) for char in text):
        return False
    if not _confirmed_erhua_evidence(record):
        return False
    syllables = str(record.get("numeric_pinyin") or "").split()
    return (
        len(syllables) == len(text)
        and len(syllables) >= 2
        and syllables[-1] == ERHUA_SUFFIX_SYLLABLE
    )


def _load_feature_rules(path: Path) -> tuple[dict[str, Mapping[str, Any]], dict[str, Mapping[str, Any]]]:
    payload = _read_json(path)
    if payload.get("schema_version") != 1 or payload.get("runtime_enabled") is not False:
        raise ValueError("儿化音元特征规则必须是离线 schema 1 数据。")
    families = payload.get("target_families")
    rules = payload.get("rules")
    if not isinstance(families, Mapping) or not isinstance(rules, list):
        raise ValueError("儿化音元特征规则缺少目标音元族或规则。")
    by_final: dict[str, Mapping[str, Any]] = {}
    for raw_rule in rules:
        if not isinstance(raw_rule, Mapping) or not raw_rule.get("rule_id"):
            raise ValueError("儿化音元特征规则存在无效记录。")
        rewrites = raw_rule.get("rewrites")
        if not isinstance(rewrites, Mapping) or not rewrites:
            raise ValueError(f"{raw_rule.get('rule_id')} 没有位置改写。")
        for position, family in rewrites.items():
            if str(position) not in {"1", "2", "3"} or str(family) not in families:
                raise ValueError(f"{raw_rule.get('rule_id')} 引用了无效位置或目标音元族。")
        for final in raw_rule.get("finals") or []:
            name = str(final)
            if name in by_final:
                raise ValueError(f"韵母 {name} 重复出现在儿化音元特征规则中。")
            by_final[name] = raw_rule
    return dict(cast(Mapping[str, Mapping[str, Any]], families)), by_final


def _build_context(repo_root: Path, feature_rules_path: Path) -> ErhuaCompileContext:
    target_families, feature_rule_by_final = _load_feature_rules(feature_rules_path)
    context = ErhuaCompileContext(
        repo_root=repo_root,
        canonical_code_map=load_canonical_code_map(repo_root),
        layout_key_by_id=load_yinyuan_id_to_layout_key(repo_root),
        musical_metadata=load_ganyin_symbol_metadata(repo_root),
        target_families=target_families,
        feature_rule_by_final=feature_rule_by_final,
    )
    return context


def _tone_grades(tone: str) -> tuple[str, str, str]:
    try:
        return {
            "1": ("high", "high", "high"),
            "2": ("low", "mid", "high"),
            "3": ("low", "low", "low"),
            "4": ("high", "mid", "low"),
            "5": ("mid", "mid", "mid"),
        }[tone]
    except KeyError as exc:
        raise ValueError(f"Unsupported tone grade for erhua fusion: {tone!r}") from exc


def _mode_payload(record: CodeModeRecord, context: ErhuaCompileContext) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for mode, code in (
        ("full", record.full_code),
        ("variable", record.variable_code),
        ("shorthand", record.shorthand_code),
    ):
        ids = symbol_code_to_yinyuan_ids(code, repo_root=context.repo_root)
        result[mode] = {
            "runtime_symbol_code": code,
            "yinyuan_ids": list(ids),
            "layout_key_code": "".join(context.layout_key_by_id[item] for item in ids),
            "length": len(ids),
        }
    return result


def _encode_syllables(
    syllables: Sequence[str], context: ErhuaCompileContext
) -> tuple[CodeModeRecord, tuple[str, ...]]:
    missing = [syllable for syllable in syllables if syllable not in context.canonical_code_map]
    if missing:
        raise ValueError(f"Canonical syllable code is missing: {missing}")
    full_code = "".join(context.canonical_code_map[syllable] for syllable in syllables)
    mode_record = build_code_mode_record(
        full_code,
        ganyin_symbol_metadata=context.musical_metadata,
    )
    return mode_record, symbol_code_to_yinyuan_ids(full_code, repo_root=context.repo_root)


def _derive_yinyuan_feature_rewrites(
    syllable: str,
    context: ErhuaCompileContext,
) -> tuple[tuple[str, str, str, str] | None, str, str, str, list[dict[str, Any]]]:
    segments = SyllableEncodingPipeline.analyze_syllable_segments(syllable)
    syllable_model = segments.to_syllable()
    final = str(syllable_model.final or "")
    tone = str(syllable_model.tone or "")
    source_code = context.canonical_code_map.get(syllable)
    if not source_code:
        return None, final, "attached_syllable_code_missing", "", []
    source_ids = cast(
        tuple[str, str, str, str],
        symbol_code_to_yinyuan_ids(source_code, repo_root=context.repo_root),
    )
    rule = context.feature_rule_by_final.get(final)
    if rule is None:
        return source_ids, final, "no_erhua_yinyuan_feature_rule", "", []
    grades = _tone_grades(tone)
    rewrites: list[dict[str, Any]] = []
    for position_text, family_name in cast(Mapping[str, Any], rule["rewrites"]).items():
        position = int(position_text)
        family = context.target_families[str(family_name)]
        base_ids = cast(Mapping[str, str], family["base_yinyuan_ids"])
        features = cast(Mapping[str, bool], family["features"])
        rewrites.append({
            "position": position,
            "source_yinyuan_id": source_ids[position],
            "base_yinyuan_id": base_ids[grades[position - 1]],
            "features": {
                "rhotic": bool(features.get("rhotic")),
                "nasalized": bool(features.get("nasalized")),
            },
        })
    rewrites.sort(key=lambda item: int(item["position"]))
    return source_ids, final, "yinyuan_feature_projection_ready", str(rule["rule_id"]), rewrites


def _record_id(text: str, numeric_pinyin: str, evidence: Sequence[Mapping[str, Any]]) -> str:
    source = json.dumps(
        [text, numeric_pinyin, [item.get("source_key") for item in evidence]],
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return "ERHUA-" + hashlib.sha256(source).hexdigest()[:16].upper()


def _preserve_evidence(evidence: Iterable[Mapping[str, Any]]) -> list[dict[str, Any]]:
    fields = (
        "source_kind", "source_key", "review_state", "source_text", "source_pinyin",
        "expanded_text", "expanded_pinyin", "input_derivation", "locator", "note",
    )
    return [{field: item[field] for field in fields if field in item} for item in evidence]


def _compile_one(
    source_record: Mapping[str, Any], context: ErhuaCompileContext
) -> tuple[dict[str, Any], dict[str, Any]]:
    text = str(source_record["text"])
    numeric_pinyin = str(source_record["numeric_pinyin"])
    evidence = _confirmed_erhua_evidence(source_record)
    record_id = _record_id(text, numeric_pinyin, evidence)
    syllables = numeric_pinyin.split()
    attached_syllable = syllables[-2]
    suffix_record, suffix_ids = _encode_syllables(syllables, context)
    source_syllable_ids, final, decision_reason, feature_rule_id, feature_rewrites = _derive_yinyuan_feature_rewrites(
        attached_syllable, context
    )

    annotation = {
        "record_id": record_id,
        "record_type": "explicit_word_final_erhua",
        "text": text,
        "standard_erhua_pinyin": [item.get("source_pinyin") for item in evidence],
        "compatibility_marked_pinyin": str(source_record.get("marked_pinyin") or ""),
        "compatibility_numeric_pinyin": numeric_pinyin,
        "attached_syllable": attached_syllable,
        "attached_final": final,
        "written_er_position": len(text) - 1,
        "authorization": {
            "policy": "confirmed_explicit_erhua_evidence_only",
            "source_kind": ERHUA_SOURCE_KIND,
            "evidence": _preserve_evidence(evidence),
        },
        "candidate_text_mutation": "forbidden",
        "productive_inference": "forbidden",
    }

    routes: dict[str, Any] = {
        "suffix_compatibility": {
            "status": "available",
            "numeric_pinyin": numeric_pinyin,
            "syllable_count": len(syllables),
            "full_yinyuan_ids": list(suffix_ids),
            "codes": _mode_payload(suffix_record, context),
        }
    }
    status = "suffix_only_encoding_pending"
    if source_syllable_ids is not None and feature_rewrites:
        routes["fused_erhua"] = {
            "status": "feature_projection_ready",
            "projection_model": "base_yinyuan_plus_rhotic_nasalized_features",
            "feature_rule_id": feature_rule_id,
            "attached_syllable_source": attached_syllable,
            "attached_syllable_source_yinyuan_ids": list(source_syllable_ids),
            "feature_rewrites": feature_rewrites,
        }
        status = "feature_projection_ready"
    else:
        routes["fused_erhua"] = {
            "status": "encoding_pending",
            "reason": decision_reason,
        }

    alias = {
        "record_id": record_id,
        "text": text,
        "status": status,
        "weight_policy": "preserve_existing_candidate_weight",
        "candidate_text_mutation": "forbidden",
        "routes": routes,
    }
    return annotation, alias


def build_explicit_erhua_bundles(
    *,
    repo_root: Path = REPO_ROOT,
    catalog_path: Path | None = None,
    feature_rules_path: Path | None = None,
    generated_at: datetime | None = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Build formal annotations and derived aliases without touching runtime data."""

    resolved_root = Path(repo_root)
    resolved_catalog = catalog_path or (resolved_root / DEFAULT_CATALOG)
    resolved_feature_rules = feature_rules_path or (resolved_root / DEFAULT_FEATURE_RULES)
    catalog = _read_json(resolved_catalog)
    context = _build_context(resolved_root, resolved_feature_rules)
    rows = [item for item in catalog.get("records") or [] if isinstance(item, Mapping)]
    explicit_rows = [item for item in rows if _confirmed_erhua_evidence(item)]
    admitted_rows = [item for item in explicit_rows if is_explicit_word_final_erhua(item)]
    excluded_explicit = [item for item in explicit_rows if item not in admitted_rows]
    lookalikes = [
        item for item in rows
        if str(item.get("text") or "").endswith("儿") and not _confirmed_erhua_evidence(item)
    ]
    compiled = [_compile_one(item, context) for item in admitted_rows]
    annotations = [item[0] for item in compiled]
    aliases = [item[1] for item in compiled]
    timestamp = (generated_at or datetime.now(timezone.utc)).astimezone(timezone.utc)
    status_counts: dict[str, int] = {}
    for item in aliases:
        status = str(item["status"])
        status_counts[status] = status_counts.get(status, 0) + 1
    common = {
        "schema_version": 2,
        "generated_utc": timestamp.isoformat().replace("+00:00", "Z"),
        "source_catalog": DEFAULT_CATALOG.as_posix(),
        "erhua_yinyuan_feature_source": DEFAULT_FEATURE_RULES.as_posix(),
        "admission_policy": {
            "required_text_shape": "at_least_one_han_plus_word_final_er",
            "required_evidence": "confirmed psc_erhua",
            "required_compatibility_form": "one syllable per written Han character, final er5",
            "suffix_or_r_inference": "forbidden",
            "candidate_text_mutation": "forbidden",
        },
        "runtime_enabled": False,
    }
    annotation_bundle = {
        **common,
        "artifact": "explicit_erhua_lexical_annotations",
        "description": "规范儿化拼音及其来源授权；不是运行时编码表。",
        "counts": {
            "catalog_records": len(rows),
            "explicit_erhua_evidence_records": len(explicit_rows),
            "admitted_word_final_records": len(annotations),
            "excluded_explicit_records": len(excluded_explicit),
            "unannotated_er_suffix_lookalikes": len(lookalikes),
        },
        "excluded_explicit_records": [
            {
                "text": str(item.get("text") or ""),
                "numeric_pinyin": str(item.get("numeric_pinyin") or ""),
                "reason": "not_at_least_one_han_plus_word_final_er",
            }
            for item in excluded_explicit
        ],
        "records": annotations,
    }
    alias_bundle = {
        **common,
        "artifact": "explicit_erhua_input_aliases",
        "description": "儿缀兼容路线与音元特征中间路线；融合码由 Windows 端根据派生音元目录统一生成。",
        "derivation_policy": {
            "suffix_compatibility": "always retain the explicit written-er er5 route",
            "fused_erhua": "canonical Yinyuan tuple plus rhotic/nasalized features, then derived Yinyuan IDs",
            "surface_annotation": "validation only; never an encoding source",
            "unsupported_feature_rule": "mark encoding_pending and keep suffix compatibility only",
            "all_three_modes": ["full", "variable", "shorthand"],
            "weight": "preserve_existing_candidate_weight",
        },
        "counts": {"records": len(aliases), **status_counts},
        "records": aliases,
    }
    return annotation_bundle, alias_bundle


def write_explicit_erhua_bundles(
    *,
    repo_root: Path = REPO_ROOT,
    annotations_path: Path | None = None,
    aliases_path: Path | None = None,
    generated_at: datetime | None = None,
) -> tuple[Path, Path, dict[str, Any]]:
    annotation_bundle, alias_bundle = build_explicit_erhua_bundles(
        repo_root=repo_root, generated_at=generated_at
    )
    resolved_annotations = annotations_path or (Path(repo_root) / DEFAULT_ANNOTATIONS)
    resolved_aliases = aliases_path or (Path(repo_root) / DEFAULT_ALIASES)
    _write_json_atomic(resolved_annotations, annotation_bundle)
    _write_json_atomic(resolved_aliases, alias_bundle)
    return resolved_annotations, resolved_aliases, {
        "annotations": annotation_bundle["counts"],
        "aliases": alias_bundle["counts"],
    }


__all__ = [
    "DEFAULT_ALIASES",
    "DEFAULT_ANNOTATIONS",
    "build_explicit_erhua_bundles",
    "is_explicit_word_final_erhua",
    "write_explicit_erhua_bundles",
]
