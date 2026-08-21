"""Persistence model for the research-only three-segment erhua review UI."""

from __future__ import annotations

import json
import os
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping


SEGMENT_NAMES = ("呼音", "主音", "末音")
FEATURE_NAMES = ("rhotic", "nasalized")
DECISIONS = {"reviewed", "deferred", "not_applicable"}
DEFERRED_INTERNAL_FINALS = {"ue", "uong", "v", "ve", "van", "vn"}
_PITCH_MARKS = str.maketrans("", "", "˥˦˧˨˩")
_SEGMENT_FORM_ALIASES: dict[str, str] = {}
_DISCUSSION_IPA_ALIASES = str.maketrans(
    {"ᴀ": "ä", "ᴇ": "e̞", "ᴜ": "ʊ", "𐞑": "ɘ̠", "ᵊ": "ə"}
)
_RHOTIC_VOWEL_BASES = {"ɚ": "ə", "ɝ": "ɜ"}
_BASE_TO_RHOTIC_VOWEL = {base: symbol for symbol, base in _RHOTIC_VOWEL_BASES.items()}
_RHOTIC_MODIFIER = "˞"
_YIME_RHOTIC_COMBINING = "\u1dca"
_LEGACY_YIME_RHOTIC_COMBINING = "\u036c"
_NASALIZATION_MARK = "\u0303"
SPLIT_REVIEW_VARIANTS = {
    "_i_front": {
        "canonical_final": "_i",
        "variant_id": "apical_front",
        "display_final": "i[ɿ]",
        "base_ipa": "ɿ",
        "base_quality": "ɿ",
        "source_base_final": "i(前)",
    },
    "_i_back": {
        "canonical_final": "_i",
        "variant_id": "apical_back",
        "display_final": "i[ʅ]",
        "base_ipa": "ʅ",
        "base_quality": "ʅ",
        "source_base_final": "i(后)",
    },
}


def review_variant_source_annotations(
    annotations: object, config: Mapping[str, Any]
) -> tuple[Mapping[str, Any], ...]:
    """Select a virtual review variant by PSC transcription content, not row number."""

    if not isinstance(annotations, list):
        return ()
    expected = str(config.get("source_base_final") or "").strip()
    return tuple(
        row
        for row in annotations
        if isinstance(row, Mapping)
        and str(row.get("source_base_final") or "").strip() == expected
    )


def psc_result_group(annotation: Mapping[str, Any]) -> dict[str, Any] | None:
    """Return the immutable PSC-result grouping for one source annotation."""

    result = str(annotation.get("source_erhua_final") or "").strip()
    if not result:
        return None
    nasalized = bool(annotation.get("nasalized"))
    project_final = str((annotation.get("alignment") or {}).get("project_final") or "")
    display_result = "er[ɤr]" if result == "er" and project_final == "e" else result
    if nasalized and display_result.endswith("r"):
        display_result = display_result[:-1] + _NASALIZATION_MARK + "r"
    return {
        "key": f"{display_result}|{'nasalized' if nasalized else 'oral'}",
        "label": display_result,
        "source_erhua_final": result,
        "display_erhua_final": display_result,
        "nasalized": nasalized,
    }


def build_psc_result_group_index(payload: Mapping[str, Any]) -> list[dict[str, Any]]:
    """Build a query index without rewriting any PSC transcription."""

    grouped: dict[str, dict[str, Any]] = {}
    for _category, final, entry in ErhuaFinalDraftStore._entries(payload):
        for annotation in entry.get("erhua_final") or []:
            group = psc_result_group(annotation)
            if group is None:
                continue
            row = grouped.setdefault(
                group["key"],
                {
                    **group,
                    "source_indices": [],
                    "project_finals": [],
                },
            )
            source_index = annotation.get("source_index")
            if source_index is not None and source_index not in row["source_indices"]:
                row["source_indices"].append(source_index)
            if final not in row["project_finals"]:
                row["project_finals"].append(final)
    rows = list(grouped.values())
    for row in rows:
        row["source_indices"].sort()
    rows.sort(key=lambda row: (row["source_indices"] or [10_000])[0])
    return rows


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _strip_pitch(value: object) -> str:
    return str(value or "").translate(_PITCH_MARKS).translate(
        _DISCUSSION_IPA_ALIASES
    )


def _normalize_features(value: object) -> dict[str, bool]:
    if value is None:
        source: Mapping[str, object] = {}
    elif isinstance(value, Mapping):
        source = value
    else:
        raise ValueError("音段 features 必须是对象。")
    unknown = set(source) - set(FEATURE_NAMES)
    if unknown:
        raise ValueError(f"未知的音段特征：{sorted(unknown)}")
    return {name: bool(source.get(name, False)) for name in FEATURE_NAMES}


def normalize_surface_segment(value: object) -> dict[str, object]:
    """Validate one structured surface segment without parsing display IPA."""

    if not isinstance(value, Mapping):
        raise ValueError("每个表层音段必须是包含 quality 和 features 的对象。")
    quality = str(value.get("quality") or "").strip()
    if any(
        symbol in quality
        for symbol in (
            *_RHOTIC_VOWEL_BASES,
            _RHOTIC_MODIFIER,
            _YIME_RHOTIC_COMBINING,
            _LEGACY_YIME_RHOTIC_COMBINING,
            _NASALIZATION_MARK,
        )
    ):
        raise ValueError(
            "quality 只能填写基础音质；ɚ/ɝ/˞/᷊/ͬ/鼻化符必须改用 features。"
        )
    return {"quality": quality, "features": _normalize_features(value.get("features"))}


def _migrate_legacy_surface_segment(
    value: object,
    *,
    rhotic: bool,
    nasalized: bool,
) -> dict[str, object]:
    """Split legacy display IPA into quality plus parallel features."""

    if isinstance(value, Mapping):
        return normalize_surface_segment(value)
    quality = str(value or "").strip()
    for symbol, base in _RHOTIC_VOWEL_BASES.items():
        if symbol in quality:
            quality = quality.replace(symbol, base)
            rhotic = True
    if _RHOTIC_MODIFIER in quality:
        quality = quality.replace(_RHOTIC_MODIFIER, "")
        rhotic = True
    if _YIME_RHOTIC_COMBINING in quality:
        quality = quality.replace(_YIME_RHOTIC_COMBINING, "")
        rhotic = True
    if _LEGACY_YIME_RHOTIC_COMBINING in quality:
        quality = quality.replace(_LEGACY_YIME_RHOTIC_COMBINING, "")
        rhotic = True
    if _NASALIZATION_MARK in quality:
        quality = quality.replace(_NASALIZATION_MARK, "")
        nasalized = True
    return {
        "quality": quality,
        "features": {"rhotic": bool(rhotic), "nasalized": bool(nasalized)},
    }


def render_surface_segment(value: object, *, notation: str = "ipa") -> str:
    """Render one structured segment as display IPA without changing its identity."""

    segment = normalize_surface_segment(value)
    quality = str(segment["quality"])
    if not quality:
        return ""
    features = segment["features"]
    if notation == "yime_combining_r":
        rendered = quality
        if features["rhotic"]:
            rendered += _YIME_RHOTIC_COMBINING
        if features["nasalized"]:
            rendered += _NASALIZATION_MARK
        return rendered
    if notation != "ipa":
        raise ValueError(f"未知的儿化显示体例：{notation}")
    if features["rhotic"] and not features["nasalized"] and quality in _BASE_TO_RHOTIC_VOWEL:
        return _BASE_TO_RHOTIC_VOWEL[quality]
    rendered = quality
    if features["nasalized"]:
        rendered += _NASALIZATION_MARK
    if features["rhotic"]:
        rendered += _RHOTIC_MODIFIER
    return rendered


def render_surface_segments(
    segments: Mapping[str, object],
    *,
    notation: str = "ipa",
) -> str:
    if set(segments) != set(SEGMENT_NAMES):
        raise ValueError("表层音质必须且只能包含呼音、主音、末音三个位置。")
    return "".join(
        render_surface_segment(segments[name], notation=notation)
        for name in SEGMENT_NAMES
    )


@dataclass(frozen=True)
class ErhuaReviewItem:
    """One final plus its source evidence and latest three-segment decision."""

    category: str
    final: str
    canonical_final: str
    display_final: str
    variant_id: str
    base_ipa: str
    base_segments: Mapping[str, str]
    base_segment_form: str
    base_segment_ganyin: str
    source_annotations: tuple[Mapping[str, Any], ...]
    source_review_status: str
    source_note: str
    review: Mapping[str, Any]

    @property
    def decision(self) -> str:
        return str(self.review.get("decision") or "pending")

    @property
    def source_rules(self) -> str:
        rules = [str(row.get("source_rule") or "") for row in self.source_annotations]
        return " / ".join(rule for rule in rules if rule)

    @property
    def psc_result_groups(self) -> tuple[dict[str, Any], ...]:
        groups: dict[str, dict[str, Any]] = {}
        for annotation in self.source_annotations:
            group = psc_result_group(annotation)
            if group is not None:
                groups.setdefault(str(group["key"]), group)
        return tuple(groups.values())

    @property
    def psc_result_group_keys(self) -> tuple[str, ...]:
        return tuple(str(group["key"]) for group in self.psc_result_groups)

    @property
    def psc_result_group_text(self) -> str:
        return " / ".join(str(group["label"]) for group in self.psc_result_groups) or "—"

    @property
    def base_segment_text(self) -> str:
        return "｜".join(str(self.base_segments[name]) for name in SEGMENT_NAMES)


class ErhuaFinalDraftStore:
    """Load and atomically update a research-only erhua final draft."""

    def __init__(self, draft_path: Path, decomposition_path: Path) -> None:
        self.draft_path = Path(draft_path)
        self.decomposition_path = Path(decomposition_path)
        self._segment_map = self._load_segment_map()

    def _load_segment_map(self) -> dict[str, tuple[str, dict[str, str]]]:
        payload = _read_json(self.decomposition_path)
        choices: dict[str, list[tuple[int, str, dict[str, str]]]] = {}
        for group in payload.values():
            if not isinstance(group, dict):
                continue
            for ganyin, segments in group.items():
                if not isinstance(ganyin, str) or not ganyin[-1:].isdigit():
                    continue
                final = ganyin[:-1]
                normalized = {
                    name: _strip_pitch(segments.get(name, ""))
                    for name in SEGMENT_NAMES
                }
                choices.setdefault(final, []).append(
                    (int(ganyin[-1]), ganyin, normalized)
                )
        return {
            final: (
                min(options, key=lambda option: option[0])[1],
                min(options, key=lambda option: option[0])[2],
            )
            for final, options in choices.items()
        }

    @property
    def segment_map(self) -> Mapping[str, tuple[str, Mapping[str, str]]]:
        """Current generated base segments; callers must treat the map as read-only."""

        return self._segment_map

    def _payload(self) -> dict[str, Any]:
        payload = _read_json(self.draft_path)
        if payload.get("runtime_enabled") is not False:
            raise ValueError("儿化草稿必须保持 runtime_enabled=false。")
        if not isinstance(payload.get("finals"), dict):
            raise ValueError("儿化草稿缺少 finals 对象。")
        return payload

    @staticmethod
    def _entries(payload: Mapping[str, Any]):
        for category, group in payload["finals"].items():
            for final, entry in group.items():
                yield str(category), str(final), entry

    def load_items(self) -> list[ErhuaReviewItem]:
        payload = self._payload()
        items: list[ErhuaReviewItem] = []
        for category, final, entry in self._entries(payload):
            segment_form = _SEGMENT_FORM_ALIASES.get(final, final)
            segment_record = self._segment_map.get(segment_form)
            if not segment_record:
                raise ValueError(f"三段分解产物中找不到韵母：{final}")
            base_segment_ganyin, base_segments = segment_record
            annotations = entry.get("erhua_final") or []
            if not isinstance(annotations, list):
                raise ValueError(f"{final}.erhua_final 必须是数组。")
            if final == "_i":
                variants = entry.get("three_segment_review_variants") or {}
                for record_id, config in SPLIT_REVIEW_VARIANTS.items():
                    review = variants.get(config["variant_id"]) or entry.get(
                        "three_segment_review"
                    ) or {}
                    if review and int(review.get("schema_version") or 0) != 2:
                        raise ValueError(
                            f"{record_id}.three_segment_review 仍是旧结构；请先运行草稿迁移工具。"
                        )
                    if review:
                        self._normalize_segments(review.get("surface_segments") or {})
                    variant_annotations = review_variant_source_annotations(
                        annotations, config
                    )
                    variant_segments = {
                        name: str(config["base_quality"]) for name in SEGMENT_NAMES
                    }
                    items.append(
                        ErhuaReviewItem(
                            category=category,
                            final=record_id,
                            canonical_final=final,
                            display_final=str(config["display_final"]),
                            variant_id=str(config["variant_id"]),
                            base_ipa=str(config["base_ipa"]),
                            base_segments=variant_segments,
                            base_segment_form=segment_form,
                            base_segment_ganyin=base_segment_ganyin,
                            source_annotations=variant_annotations,
                            source_review_status=str(entry.get("erhua_review_status") or ""),
                            source_note=str(entry.get("erhua_note") or ""),
                            review=dict(review),
                        )
                    )
                continue
            review = entry.get("three_segment_review") or {}
            if review and int(review.get("schema_version") or 0) != 2:
                raise ValueError(
                    f"{final}.three_segment_review 仍是旧结构；请先运行草稿迁移工具。"
                )
            if review:
                self._normalize_segments(review.get("surface_segments") or {})
            items.append(
                ErhuaReviewItem(
                    category=category,
                    final=final,
                    canonical_final=final,
                    display_final=final,
                    variant_id="",
                    base_ipa=str(entry.get("ipa") or ""),
                    base_segments=dict(base_segments),
                    base_segment_form=segment_form,
                    base_segment_ganyin=base_segment_ganyin,
                    source_annotations=tuple(annotations),
                    source_review_status=str(entry.get("erhua_review_status") or ""),
                    source_note=str(entry.get("erhua_note") or ""),
                    review=dict(review),
                )
            )
        return items

    def _find_entry(self, payload: Mapping[str, Any], final: str) -> dict[str, Any]:
        matches = [entry for _category, name, entry in self._entries(payload) if name == final]
        if len(matches) != 1:
            raise KeyError(f"儿化草稿中的韵母键不唯一或不存在：{final}")
        return matches[0]

    @staticmethod
    def _normalize_segments(segments: Mapping[str, object]) -> dict[str, dict[str, object]]:
        if set(segments) != set(SEGMENT_NAMES):
            raise ValueError("表层音质必须且只能包含呼音、主音、末音三个位置。")
        return {name: normalize_surface_segment(segments[name]) for name in SEGMENT_NAMES}

    def save_review(
        self,
        final: str,
        *,
        surface_segments: Mapping[str, object],
        decision: str = "reviewed",
        note: str = "",
        now: datetime | None = None,
    ) -> ErhuaReviewItem:
        if decision not in DECISIONS:
            raise ValueError(f"不支持的复核决定：{decision}")
        normalized = self._normalize_segments(surface_segments)
        if decision == "reviewed" and any(
            not str(normalized[name]["quality"]) for name in SEGMENT_NAMES
        ):
            raise ValueError("标为‘已标注’时，儿化后的呼音、主音、末音都必须填写。")
        if decision == "not_applicable" and not note.strip():
            raise ValueError("标为‘不适用’时必须填写理由。")

        payload = self._payload()
        variant = SPLIT_REVIEW_VARIANTS.get(final)
        canonical_final = str(variant["canonical_final"]) if variant else final
        entry = self._find_entry(payload, canonical_final)
        if variant:
            reviews = entry.setdefault("three_segment_review_variants", {})
            previous = reviews.get(variant["variant_id"]) or {}
        else:
            previous = entry.get("three_segment_review") or {}
        timestamp = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
        segment_form = _SEGMENT_FORM_ALIASES.get(canonical_final, canonical_final)
        base_segment_ganyin, generated_base_segments = self._segment_map[segment_form]
        base_segments = (
            {name: str(variant["base_quality"]) for name in SEGMENT_NAMES}
            if variant
            else generated_base_segments
        )
        previous_generation = previous.get("surface_generation") or {}
        generation: dict[str, Any] = {}
        if previous_generation.get("method") == "rule_generated":
            if previous.get("surface_segments") == normalized:
                generation = dict(previous_generation)
            else:
                generation = {
                    "method": "manual_override",
                    "overrides_class_id": str(previous_generation.get("class_id") or ""),
                    "reason": "UI 中显式修改规则生成结果",
                    "runtime_enabled": False,
                }
        elif previous_generation:
            generation = dict(previous_generation)
        saved_review = {
            "schema_version": 2,
            "surface_segment_schema": "quality_features_v1",
            "decision": decision,
            "base_segments_source": "internal_data/yinyuan_derived/ganyin_to_pianyin_sequence.json",
            "base_segments_final": segment_form,
            "base_segments_ganyin": base_segment_ganyin,
            "base_segments": dict(base_segments),
            "surface_segments": normalized,
            "surface_ipa": render_surface_segments(normalized),
            "note": note.strip(),
            "revision": int(previous.get("revision") or 0) + 1,
            "updated_utc": timestamp.isoformat().replace("+00:00", "Z"),
            "runtime_enabled": False,
        }
        if variant:
            variant_annotations = review_variant_source_annotations(
                entry.get("erhua_final") or [], variant
            )
            if len(variant_annotations) != 1:
                raise ValueError(
                    f"{final} 需要且只能匹配一条 PSC {variant['source_base_final']} 记录。"
                )
            saved_review["review_variant"] = {
                "variant_id": variant["variant_id"],
                "record_id": final,
                "display_final": variant["display_final"],
                "source_index": variant_annotations[0].get("source_index"),
                "source_base_final": variant["source_base_final"],
                "derivation": "按 PSC source_base_final 把规范韵母 _i 的舌尖前、舌尖后记录分列",
            }
        if generation:
            saved_review["surface_generation"] = generation
        for metadata_field in ("surface_class", "surface_class_rule_version"):
            if metadata_field in previous:
                saved_review[metadata_field] = previous[metadata_field]
        if variant:
            entry["three_segment_review_variants"][variant["variant_id"]] = saved_review
        else:
            entry["three_segment_review"] = saved_review
        foundation_sync = payload.get("draft_foundation_sync") or {}
        required = list(foundation_sync.get("surface_review_required") or [])
        if canonical_final in required:
            foundation_sync["surface_review_required"] = [
                name for name in required if name != canonical_final
            ]
            payload["draft_foundation_sync"] = foundation_sync
        self._update_progress(payload, timestamp)
        self._write(payload)
        return next(item for item in self.load_items() if item.final == final)

    def migrate_surface_segment_schema(self) -> dict[str, int]:
        """Atomically migrate every saved review away from display-character parsing."""

        payload = self._payload()
        migrated = 0
        already_current = 0
        removed_legacy_fields = 0
        for _category, _final, entry in self._entries(payload):
            review = entry.get("three_segment_review") or {}
            if not review:
                continue
            old_segments = review.get("surface_segments") or {}
            if set(old_segments) != set(SEGMENT_NAMES):
                raise ValueError("旧草稿的表层音质未保持固定三段。")
            legacy_rhotic = set(review.get("rhotic_positions") or [])
            legacy_nasalized = set(review.get("nasalized_positions") or [])
            current = int(review.get("schema_version") or 0) == 2
            normalized = {
                name: _migrate_legacy_surface_segment(
                    old_segments[name],
                    rhotic=name in legacy_rhotic,
                    nasalized=name in legacy_nasalized,
                )
                for name in SEGMENT_NAMES
            }
            review["schema_version"] = 2
            review["surface_segment_schema"] = "quality_features_v1"
            review["surface_segments"] = normalized
            review["surface_ipa"] = render_surface_segments(normalized)
            for legacy_field in ("rhotic_positions", "nasalized_positions"):
                if legacy_field in review:
                    review.pop(legacy_field)
                    removed_legacy_fields += 1
            if current:
                already_current += 1
            else:
                migrated += 1

        now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        payload["schema_version"] = max(3, int(payload.get("schema_version") or 0))
        payload["surface_segment_model"] = {
            "schema_version": 1,
            "name": "fixed_three_positions_with_parallel_features",
            "positions": list(SEGMENT_NAMES),
            "segment_record": {
                "quality": "基础音质字符串，不含卷舌或鼻化显示符号",
                "features": {"rhotic": "boolean", "nasalized": "boolean"},
            },
            "rendering_policy": "显示 IPA 由 quality 与 features 派生；修饰字母或附标不增加片音位置。",
            "display_notations": {
                "ipa": "标准 IPA 显示采用 U+02DE ˞ 或预组合 ɚ/ɝ。",
                "yime_combining_r": "项目显示采用 U+1DCA ᷊（COMBINING LATIN SMALL LETTER R BELOW）；仅表示前一固定片音的 rhotic 特征，不是 IPA 来源转录，并为其上方继续附加音高符号保留位置。",
            },
            "runtime_enabled": False,
        }
        refresh = payload.setdefault("draft_refresh", {})
        refresh.update(
            {
                "updated_utc": now,
                "surface_segment_schema_migrated": True,
                "review_decisions_changed": False,
                "formal_final_styles_changed": False,
                "runtime_artifacts_changed": False,
            }
        )
        self._write(payload)
        return {
            "migrated_reviews": migrated,
            "already_current_reviews": already_current,
            "removed_legacy_fields": removed_legacy_fields,
        }

    def prune_deferred_internal_finals(self) -> list[str]:
        """Remove forms that are not part of the current internal-final inventory."""

        payload = self._payload()
        removed: list[str] = []
        for group in payload["finals"].values():
            if not isinstance(group, dict):
                continue
            for final in sorted(DEFERRED_INTERNAL_FINALS & set(group)):
                group.pop(final)
                removed.append(final)
        if removed:
            now = datetime.now(timezone.utc)
            self._update_progress(payload, now)
            refresh = payload.setdefault("draft_refresh", {})
            refresh.update(
                {
                    "updated_utc": now.isoformat().replace("+00:00", "Z"),
                    "deferred_internal_finals_removed": removed,
                    "formal_final_styles_changed": False,
                    "runtime_artifacts_changed": False,
                }
            )
            self._write(payload)
        return removed

    def clear_review(self, final: str) -> ErhuaReviewItem:
        payload = self._payload()
        variant = SPLIT_REVIEW_VARIANTS.get(final)
        canonical_final = str(variant["canonical_final"]) if variant else final
        entry = self._find_entry(payload, canonical_final)
        if variant:
            reviews = entry.get("three_segment_review_variants") or {}
            reviews.pop(variant["variant_id"], None)
            entry["three_segment_review_variants"] = reviews
        else:
            entry.pop("three_segment_review", None)
        now = datetime.now(timezone.utc)
        self._update_progress(payload, now)
        self._write(payload)
        return next(item for item in self.load_items() if item.final == final)

    def _update_progress(self, payload: dict[str, Any], now: datetime) -> None:
        counts: Counter[str] = Counter()
        total = 0
        for _category, final, entry in self._entries(payload):
            if final == "_i":
                variants = entry.get("three_segment_review_variants") or {}
                for config in SPLIT_REVIEW_VARIANTS.values():
                    total += 1
                    review = variants.get(config["variant_id"]) or {}
                    counts[str(review.get("decision") or "pending")] += 1
                continue
            total += 1
            review = entry.get("three_segment_review") or {}
            counts[str(review.get("decision") or "pending")] += 1
        payload["three_segment_review_progress"] = {
            "schema_version": 1,
            "total": total,
            "pending": counts["pending"],
            "reviewed": counts["reviewed"],
            "deferred": counts["deferred"],
            "not_applicable": counts["not_applicable"],
            "runtime_aliases_generated": 0,
            "updated_utc": now.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        }
        payload["psc_result_group_index"] = {
            "schema_version": 1,
            "derivation": "由 PSC source_erhua_final、nasalized 与既有韵母对齐结果派生；外部表仅作事后核对，不参与生成",
            "groups": build_psc_result_group_index(payload),
            "runtime_enabled": False,
        }

    def _write(self, payload: Mapping[str, Any]) -> None:
        rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
        temporary = self.draft_path.with_name(
            f".{self.draft_path.name}.{os.getpid()}.tmp"
        )
        temporary.write_text(rendered, encoding="utf-8", newline="\n")
        os.replace(temporary, self.draft_path)


__all__ = [
    "DECISIONS",
    "FEATURE_NAMES",
    "SEGMENT_NAMES",
    "SPLIT_REVIEW_VARIANTS",
    "ErhuaFinalDraftStore",
    "ErhuaReviewItem",
    "build_psc_result_group_index",
    "review_variant_source_annotations",
    "normalize_surface_segment",
    "psc_result_group",
    "render_surface_segment",
    "render_surface_segments",
]
