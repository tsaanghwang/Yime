from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Mapping, Optional, cast


def _as_float_value(value: object) -> float:
    try:
        return float(cast("str | int | float", value))
    except (TypeError, ValueError):
        return 0.0


def _as_int_value(value: object) -> int:
    try:
        if isinstance(value, (str, int, float)):
            return int(value)
    except (TypeError, ValueError):
        pass
    return 0


def _as_bool_value(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return False


@dataclass(frozen=True)
class RuntimeCandidateRecord:
    """Normalized runtime candidate used for phrase-aware ranking."""

    lookup_code: str
    text: str
    entry_type: str
    pinyin_tone: str = ""
    sort_weight: float = 0.0
    text_length: int = 0
    is_common: bool = False
    matched_code_length: int = 0
    full_code_length: int = 0
    first_char_sort_weight: float = 0.0
    short_prefix_template_bonus: int = 0
    head_char_cluster_weight: float = 0.0
    candidate_source_tag: str = "exact"
    phrase_priority_tier: int = 2
    local_phrase_priority_boost: float = 0.0
    debug_tag: str = "normal"
    usage_tier: str = ""


_PHRASE_PREFIX_CANDIDATE_LIMIT = 64
_SHORT_PREFIX_TEMPLATE_CHARS = frozenset("的们是在有了和要会就也都不来去没吗吧呢啊")
_STAGE_B_RARE_REPRESENTATIVE_PAGE_LIMIT = 5
_STAGE_B_RARE_REPRESENTATIVE_SECOND_PAGE_SLOT = 2
_STAGE_B_RARE_REPRESENTATIVE_MIN_EXACT_CHAR_COUNT = 64


def load_local_phrase_priority_rules(
    path: Path,
    pinyin_to_canonical: Dict[str, str],
    resolve_canonical_code_from_pinyin_tone: Callable[[str, Dict[str, str]], object],
    *,
    expected_lookup_code_length: Optional[int] = 4,
    min_lookup_code_length: int = 1,
) -> Dict[str, Dict[str, float]]:
    if not path.exists():
        return {}

    payload = json.loads(path.read_text(encoding="utf-8"))
    payload_mapping = cast(Mapping[str, object], payload) if isinstance(payload, dict) else None
    raw_rules = payload_mapping.get("rules") if payload_mapping is not None else None
    if not isinstance(raw_rules, list):
        return {}

    rules_by_lookup_code: Dict[str, Dict[str, float]] = {}
    for raw_rule in cast(List[object], raw_rules):
        if not isinstance(raw_rule, dict):
            continue
        rule = cast(Mapping[str, object], raw_rule)
        lookup_code = str(rule.get("lookup_code", "") or "").strip()
        if not lookup_code:
            lookup_code = str(resolve_canonical_code_from_pinyin_tone(
                str(rule.get("lookup_pinyin_tone", "") or "").strip(),
                pinyin_to_canonical,
            ) or "").strip()
        if expected_lookup_code_length is not None and len(lookup_code) != expected_lookup_code_length:
            continue
        if len(lookup_code) < min_lookup_code_length:
            continue
        raw_targets = rule.get("targets")
        if not isinstance(raw_targets, list):
            continue
        target_boosts: Dict[str, float] = rules_by_lookup_code.setdefault(lookup_code, {})
        for raw_target in cast(List[object], raw_targets):
            if not isinstance(raw_target, dict):
                continue
            target = cast(Mapping[str, object], raw_target)
            text = str(target.get("text", "") or "").strip()
            boost = _as_float_value(target.get("boost", 0.0))
            if not text or boost <= 0.0:
                continue
            target_boosts[text] = max(target_boosts.get(text, 0.0), boost)
    return {
        lookup_code: target_boosts
        for lookup_code, target_boosts in rules_by_lookup_code.items()
        if target_boosts
    }


def merge_phrase_priority_rule_maps(
    *rule_maps: Mapping[str, Mapping[str, float]],
) -> Dict[str, Dict[str, float]]:
    merged: Dict[str, Dict[str, float]] = {}
    for rule_map in rule_maps:
        for lookup_code, target_boosts in rule_map.items():
            merged_targets = merged.setdefault(lookup_code, {})
            for text, boost in target_boosts.items():
                if boost > merged_targets.get(text, 0.0):
                    merged_targets[text] = boost
    return merged


def resolve_stage_phrase_priority_metadata(
    stage: str,
    lookup_code: str,
    candidate: Dict[str, object],
    local_phrase_priority_rules: Mapping[str, Mapping[str, float]],
    continuous_input_priority_rules: Mapping[str, Mapping[str, float]],
) -> tuple[int, float, str]:
    local_boost = resolve_local_phrase_priority_boost(
        lookup_code,
        candidate,
        local_phrase_priority_rules,
    )
    continuous_boost = resolve_local_phrase_priority_boost(
        lookup_code,
        candidate,
        continuous_input_priority_rules,
    )

    if stage == "B":
        if local_boost > 0.0:
            return 0, local_boost, "B-local"
        if continuous_boost > 0.0:
            return 1, continuous_boost, "B-continuous"
        return 2, 0.0, "normal"
    if stage in {"C", "D"}:
        if continuous_boost > 0.0:
            return 0, continuous_boost, f"{stage}-continuous"
        if local_boost > 0.0:
            return 1, local_boost, f"{stage}-local"
        return 2, 0.0, "normal"
    if local_boost > 0.0:
        return 0, local_boost, "local"
    if continuous_boost > 0.0:
        return 1, continuous_boost, "continuous"
    return 2, 0.0, "normal"


def format_runtime_debug_summary(
    candidates: List[RuntimeCandidateRecord],
    *,
    limit: int = 3,
) -> str:
    if limit <= 0:
        return ""

    visible = candidates[:limit]
    if not visible:
        return ""
    return ", ".join(
        f"{candidate.text}[{candidate.candidate_source_tag}/{candidate.debug_tag}]"
        for candidate in visible
    )


def annotate_candidate_source(
    candidate: Dict[str, object],
    source_tag: str,
) -> Dict[str, object]:
    annotated = dict(candidate)
    annotated["_candidate_source"] = source_tag
    return annotated


def resolve_candidate_source_tag(candidate: Dict[str, object]) -> str:
    source_tag = str(candidate.get("_candidate_source", "") or "").strip()
    if source_tag:
        return source_tag
    matched_code_length = _as_int_value(candidate.get("_matched_code_length"))
    return "prefix" if matched_code_length > 0 else "exact"


def resolve_local_phrase_priority_boost(
    lookup_code: str,
    candidate: Dict[str, object],
    rules_by_lookup_code: Mapping[str, Mapping[str, float]],
) -> float:
    entry_type = str(candidate.get("entry_type", "") or "").strip()
    if entry_type != "phrase":
        return 0.0

    text = str(candidate.get("text", "") or "").strip()
    if not text:
        return 0.0

    boost = _as_float_value(rules_by_lookup_code.get(lookup_code, {}).get(text, 0.0))
    if boost <= 0.0:
        return 0.0

    matched_code_length = _as_int_value(candidate.get("_matched_code_length"))
    full_code = str(candidate.get("yime_code", "") or lookup_code).strip()
    full_code_length_value = candidate.get("_full_code_length")
    full_code_length = (
        int(full_code_length_value)
        if isinstance(full_code_length_value, (int, float, str)) and full_code_length_value
        else len(full_code)
    )
    if matched_code_length > 0:
        if matched_code_length != len(lookup_code) or full_code_length <= matched_code_length:
            return 0.0
        return boost

    if len(lookup_code) <= 4:
        return 0.0
    if full_code != lookup_code or full_code_length != len(lookup_code):
        return 0.0

    return boost


def runtime_candidate_priority(candidate: RuntimeCandidateRecord) -> int:
    if candidate.entry_type == "phrase" and 2 <= candidate.text_length <= 4:
        return 0
    if candidate.entry_type == "char":
        return 1
    return 2


def runtime_candidate_sort_key(
    candidate: RuntimeCandidateRecord,
    user_freq: int,
) -> tuple[int, int, int, float, float, int, str, str]:
    is_partial_phrase = (
        candidate.entry_type == "phrase"
        and candidate.matched_code_length > 0
        and candidate.full_code_length > candidate.matched_code_length
    )
    return (
        runtime_candidate_priority(candidate),
        0 if is_partial_phrase else 1,
        candidate.phrase_priority_tier,
        -candidate.local_phrase_priority_boost,
        -candidate.sort_weight,
        -user_freq,
        candidate.text,
        candidate.pinyin_tone,
    )


def phrase_candidate_payload_sort_key(candidate: Dict[str, object]) -> tuple[float, str, str]:
    return (
        -_as_float_value(candidate.get("sort_weight", 0.0)),
        str(candidate.get("text", "") or "").strip(),
        str(candidate.get("pinyin_tone", "") or "").strip(),
    )


def build_char_sort_weight_index(
    by_code: Dict[str, List[Dict[str, object]]],
) -> Dict[str, float]:
    weight_by_char: Dict[str, float] = {}
    for candidates in by_code.values():
        for candidate in candidates:
            if str(candidate.get("entry_type", "") or "").strip() != "char":
                continue
            text = str(candidate.get("text", "") or "").strip()
            if len(text) != 1:
                continue
            sort_weight = _as_float_value(candidate.get("sort_weight", 0.0))
            if sort_weight > weight_by_char.get(text, float("-inf")):
                weight_by_char[text] = sort_weight
    return weight_by_char


def compute_short_prefix_template_bonus(text: str) -> int:
    normalized_text = str(text or "").strip()
    if len(normalized_text) < 2:
        return 0
    bonus = 0
    if len(normalized_text) == 2:
        bonus += 2
    if normalized_text[1] in _SHORT_PREFIX_TEMPLATE_CHARS:
        bonus += 2
    return bonus


def build_head_char_cluster_weight_map(
    raw_candidates: List[Dict[str, object]],
) -> Dict[str, float]:
    cluster_weight_by_char: Dict[str, float] = {}
    for candidate in raw_candidates:
        if str(candidate.get("entry_type", "") or "").strip() != "phrase":
            continue
        matched_code_length_value = candidate.get("_matched_code_length", 0)
        matched_code_length = int(matched_code_length_value) if isinstance(matched_code_length_value, (str, int, float)) else 0
        if matched_code_length != 1:
            continue
        text = str(candidate.get("text", "") or "").strip()
        if not text:
            continue
        cluster_weight_by_char[text[:1]] = cluster_weight_by_char.get(text[:1], 0.0) + _as_float_value(candidate.get("sort_weight", 0.0))
    return cluster_weight_by_char


def annotate_phrase_prefix_candidate(
    candidate: Dict[str, object],
    matched_code_length: int,
) -> Dict[str, object]:
    annotated = dict(candidate)
    full_code = str(candidate.get("yime_code", "") or "").strip()
    annotated["_matched_code_length"] = matched_code_length
    annotated["_full_code_length"] = len(full_code) if full_code else matched_code_length
    current_source = str(candidate.get("_candidate_source", "") or "").strip()
    if current_source == "overlay":
        annotated["_candidate_source"] = "prefix-overlay"
    elif current_source != "prefix-overlay":
        annotated["_candidate_source"] = "prefix"
    return annotated


def build_phrase_prefix_index(
    by_code: Dict[str, List[Dict[str, object]]],
) -> Dict[str, List[Dict[str, object]]]:
    prefix_index: Dict[str, List[Dict[str, object]]] = {}
    for canonical_code, candidates in by_code.items():
        normalized_code = str(canonical_code or "").strip()
        if len(normalized_code) <= 1:
            continue
        for candidate in candidates:
            if str(candidate.get("entry_type", "") or "").strip() != "phrase":
                continue
            text = str(candidate.get("text", "") or "").strip()
            if not text:
                continue
            raw_text_length = candidate.get("text_length")
            text_length = raw_text_length if isinstance(raw_text_length, int) else len(text)
            if not (2 <= text_length <= 4):
                continue
            max_prefix_length = min(len(normalized_code) - 1, 15)
            for prefix_length in range(1, max_prefix_length + 1):
                prefix_index.setdefault(normalized_code[:prefix_length], []).append(candidate)

    for prefix, items in prefix_index.items():
        items.sort(key=phrase_candidate_payload_sort_key)
        prefix_index[prefix] = items[:_PHRASE_PREFIX_CANDIDATE_LIMIT]
    return prefix_index


def build_runtime_candidate_records(
    lookup_code: str,
    raw_candidates: List[Dict[str, object]],
    *,
    stage: str = "",
    priority_lookup_code: str = "",
    char_sort_weight_by_text: Optional[Mapping[str, float]] = None,
    local_phrase_priority_rules: Optional[Mapping[str, Mapping[str, float]]] = None,
    continuous_input_priority_rules: Optional[Mapping[str, Mapping[str, float]]] = None,
) -> List[RuntimeCandidateRecord]:
    records: List[RuntimeCandidateRecord] = []
    head_char_cluster_weight_by_text = build_head_char_cluster_weight_map(raw_candidates)
    boost_lookup_code = str(priority_lookup_code or lookup_code).strip()
    local_rules = local_phrase_priority_rules or {}
    continuous_rules = continuous_input_priority_rules or {}
    first_char_weight_map = dict(char_sort_weight_by_text or {})
    for candidate in raw_candidates:
        text = str(candidate.get("text", "")).strip()
        if not text:
            continue
        text_length = _as_int_value(candidate.get("text_length") or len(text))
        (
            phrase_priority_tier,
            local_phrase_priority_boost,
            debug_tag,
        ) = resolve_stage_phrase_priority_metadata(
            stage,
            boost_lookup_code,
            candidate,
            local_rules,
            continuous_rules,
        )
        records.append(
            RuntimeCandidateRecord(
                lookup_code=lookup_code,
                text=text,
                entry_type=str(candidate.get("entry_type", "")).strip(),
                pinyin_tone=str(candidate.get("pinyin_tone", "")).strip(),
                sort_weight=_as_float_value(candidate.get("sort_weight", 0.0)),
                text_length=text_length,
                is_common=_as_bool_value(candidate.get("is_common", False)),
                matched_code_length=_as_int_value(candidate.get("_matched_code_length") or 0),
                full_code_length=_as_int_value(
                    candidate.get("_full_code_length")
                    or len(str(candidate.get("yime_code", "") or lookup_code).strip())
                ),
                first_char_sort_weight=float(first_char_weight_map.get(text[:1], 0.0)),
                short_prefix_template_bonus=compute_short_prefix_template_bonus(text),
                head_char_cluster_weight=float(head_char_cluster_weight_by_text.get(text[:1], 0.0)),
                candidate_source_tag=resolve_candidate_source_tag(candidate),
                phrase_priority_tier=phrase_priority_tier,
                local_phrase_priority_boost=local_phrase_priority_boost,
                debug_tag=debug_tag,
                usage_tier=str(candidate.get("usage_tier", "") or "").strip(),
            )
        )
    return records


def apply_stage_b_rare_representative_guardrail(
    candidates: List[RuntimeCandidateRecord],
    *,
    page_limit: int = _STAGE_B_RARE_REPRESENTATIVE_PAGE_LIMIT,
    second_page_slot: int = _STAGE_B_RARE_REPRESENTATIVE_SECOND_PAGE_SLOT,
    min_exact_char_count: int = _STAGE_B_RARE_REPRESENTATIVE_MIN_EXACT_CHAR_COUNT,
) -> List[RuntimeCandidateRecord]:
    normalized_page_limit = max(int(page_limit or 0), 0)
    normalized_second_page_slot = max(int(second_page_slot or 0), 1)
    normalized_target_rank = normalized_page_limit + normalized_second_page_slot
    target_index = normalized_target_rank - 1
    if normalized_page_limit <= 0 or len(candidates) <= target_index:
        return list(candidates)

    exact_char_candidates = [candidate for candidate in candidates if candidate.entry_type == "char"]
    if len(exact_char_candidates) < max(int(min_exact_char_count or 0), 0):
        return list(candidates)

    if any(
        candidate.entry_type == "char" and candidate.usage_tier == "rare"
        for candidate in candidates[:normalized_target_rank]
    ):
        return list(candidates)

    representative_index = next(
        (
            index
            for index, candidate in enumerate(candidates)
            if candidate.entry_type == "char" and candidate.usage_tier == "rare"
        ),
        -1,
    )
    if representative_index < normalized_target_rank:
        return list(candidates)
    if representative_index < 0:
        return list(candidates)

    reordered = list(candidates)
    representative = reordered.pop(representative_index)
    reordered.insert(target_index, representative)
    return reordered


def rank_runtime_candidates(
    candidates: List[RuntimeCandidateRecord],
    user_freq_by_candidate: Mapping[tuple[str, str], int],
) -> List[RuntimeCandidateRecord]:
    best_by_text: dict[str, RuntimeCandidateRecord] = {}
    for candidate in candidates:
        if candidate.entry_type == "phrase" and not (2 <= candidate.text_length <= 4):
            continue
        existing = best_by_text.get(candidate.text)
        candidate_freq = user_freq_by_candidate.get((candidate.lookup_code, candidate.text), 0)
        if existing is None:
            best_by_text[candidate.text] = candidate
            continue
        existing_freq = user_freq_by_candidate.get((existing.lookup_code, existing.text), 0)
        if runtime_candidate_sort_key(candidate, candidate_freq) < runtime_candidate_sort_key(existing, existing_freq):
            best_by_text[candidate.text] = candidate

    ranked = list(best_by_text.values())
    ranked.sort(
        key=lambda candidate: runtime_candidate_sort_key(
            candidate,
            user_freq_by_candidate.get((candidate.lookup_code, candidate.text), 0),
        )
    )
    return ranked
