"""Conservative batch suggestions for PSC pronunciation review cases.

Suggestions never modify either source database.  A suggestion is only a
review-decision candidate; the reviewer must preview and explicitly apply it.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from typing import Iterable

from yime.lexicon_bundle.psc_audit import (
    ReviewCase,
    normalize_marked_pinyin,
)


CORE_REVIEW_LANES = frozenset(
    {
        "invalid_psc_evidence_review",
        "canonical_pronunciation_review",
        "canonical_promotion_review",
        "primary_ranking_review",
        "neutral_tone_review",
        "missing_source_text_review",
    }
)

POLICY_AND_REFERENCE_LANES = frozenset(
    {
        "erhua_policy_review",
        "contextual_reference_review",
        "supplemental_reference_review",
    }
)

_NUMERIC_PREFIX = re.compile(
    r"^\s*(\d{1,6})(?:\s+|\s*[,，、:：;；]\s*)(.+?)\s*$",
    re.DOTALL,
)
_TONE_COMBINING_MARKS = frozenset({"\u0304", "\u0301", "\u030c", "\u0300"})


@dataclass(frozen=True)
class ReviewSuggestion:
    rule_id: str
    rule_label: str
    confidence: str
    decision: str
    selected_pinyin: str
    note: str
    reason: str
    batch_safe: bool = True


def _primary_readings(case: ReviewCase) -> Iterable[dict[str, object]]:
    primary = tuple(item for item in case.canonical_readings if item.get("is_primary"))
    return primary or case.canonical_readings[:1]


def _locator_indices(case: ReviewCase) -> tuple[str, ...]:
    result: list[str] = []
    for item in case.evidence_items:
        locator = item.get("locator")
        if not isinstance(locator, dict):
            continue
        source_index = locator.get("source_index")
        if source_index is not None:
            result.append(str(source_index).strip())
    return tuple(result)


def _recognized_normalized_forms(case: ReviewCase) -> set[str]:
    """Return attested forms plus strict 一/不 underlying-tone projections."""

    result: set[str] = set()
    for reading in (*case.canonical_readings, *case.accepted_readings):
        marked = str(reading.get("marked", "")).strip()
        numeric = str(reading.get("numeric", "")).strip()
        normalized = normalize_marked_pinyin(marked)
        if normalized:
            result.add(normalized)
        marked_tokens = marked.split()
        numeric_tokens = numeric.split()
        if (
            not marked_tokens
            or len(marked_tokens) != len(numeric_tokens)
            or len(marked_tokens) != len(case.text)
        ):
            continue
        projected = list(marked_tokens)
        changed = False
        for index, (character, numeric_token) in enumerate(
            zip(case.text, numeric_tokens, strict=True)
        ):
            if character == "一" and numeric_token in {"yi2", "yi4"}:
                projected[index] = "yī"
                changed = True
            elif character == "不" and numeric_token == "bu2":
                projected[index] = "bù"
                changed = True
        if changed:
            result.add(normalize_marked_pinyin(" ".join(projected)))
    return result


def _numeric_prefix_suggestion(case: ReviewCase) -> ReviewSuggestion | None:
    if len(case.pinyin_forms) != 1:
        return None
    match = _NUMERIC_PREFIX.match(case.pinyin_forms[0])
    if match is None:
        return None
    prefix, corrected = match.groups()
    normalized_corrected = normalize_marked_pinyin(corrected)
    if not corrected or not normalized_corrected:
        return None
    indices = _locator_indices(case)
    if not indices or not any(index.endswith(prefix) for index in indices):
        return None
    if normalized_corrected not in _recognized_normalized_forms(case):
        # The prefix is suspicious, but another OCR/pronunciation difference remains.
        # Such rows must stay in the manual tail instead of being partially corrected.
        return None
    matching_reading = next(
        (
            str(reading.get("marked", "")).strip()
            for reading in (*case.canonical_readings, *case.accepted_readings)
            if normalize_marked_pinyin(str(reading.get("marked", "")))
            == normalized_corrected
        ),
        "",
    )
    corrected_display = (
        matching_reading
        if matching_reading and re.search(r"[·•]", corrected)
        else re.sub(r"[·•]+", " ", corrected).strip()
    )
    return ReviewSuggestion(
        rule_id="ocr_source_index_prefix",
        rule_label="序号末位混入拼音",
        confidence="高",
        decision="psc_evidence_error",
        selected_pinyin=corrected_display,
        note=(
            f'OCR 框重叠或字段错位，来源序号末位“{prefix}”被重复识别并误入拼音字段；'
            f"正确拼音为 {corrected_display}。"
        ),
        reason=(
            f"拼音字段以孤立数字 {prefix} 开头，且证据来源序号以该数字结尾；"
            "清理后得到有效拼音。"
        ),
    )


def _numeric_prefix_manual_suggestion(case: ReviewCase) -> ReviewSuggestion | None:
    if len(case.pinyin_forms) != 1:
        return None
    match = _NUMERIC_PREFIX.match(case.pinyin_forms[0])
    if match is None:
        return None
    prefix, corrected = match.groups()
    corrected = corrected.strip()
    if not normalize_marked_pinyin(corrected):
        return None
    return ReviewSuggestion(
        rule_id="ocr_source_index_prefix_manual",
        rule_label="序号混入拼音（仍有其他差异）",
        confidence="需人工",
        decision="psc_evidence_error",
        selected_pinyin=corrected,
        note=(
            f'拼音字段开头的数字“{prefix}”疑似由来源序号或相邻编号混入；'
            "去除数字后仍与原型既有读音证据不完全一致，需继续核对原页中的调号、"
            "音节及词形，不能直接自动更正。"
        ),
        reason=(
            "拼音字段以非法数字前缀开头，但去除数字后仍存在其他差异；"
            "本规则只负责聚类，不参加批量裁决。"
        ),
        batch_safe=False,
    )


def _underlying_tone_suggestion(
    case: ReviewCase,
    *,
    character: str,
    surface_numeric: frozenset[str],
    underlying_marked: str,
    rule_id: str,
    rule_label: str,
) -> ReviewSuggestion | None:
    if not case.pinyin_variants or character not in case.text:
        return None
    for reading in _primary_readings(case):
        marked = str(reading.get("marked", "")).strip()
        numeric = str(reading.get("numeric", "")).strip()
        marked_tokens = marked.split()
        numeric_tokens = numeric.split()
        if not marked_tokens or len(marked_tokens) != len(numeric_tokens):
            continue
        if len(marked_tokens) != len(case.text):
            continue
        replacements: list[int] = []
        underlying_tokens = list(marked_tokens)
        for index, (text_character, numeric_token) in enumerate(
            zip(case.text, numeric_tokens, strict=True)
        ):
            if text_character == character and numeric_token in surface_numeric:
                underlying_tokens[index] = underlying_marked
                replacements.append(index)
        if not replacements:
            continue
        underlying = " ".join(underlying_tokens)
        normalized_underlying = normalize_marked_pinyin(underlying)
        if normalized_underlying not in case.pinyin_variants:
            continue
        selected = next(
            (
                form
                for form in case.pinyin_forms
                if normalize_marked_pinyin(form) == normalized_underlying
            ),
            underlying,
        )
        surface = " ".join(marked_tokens)
        return ReviewSuggestion(
            rule_id=rule_id,
            rule_label=rule_label,
            confidence="高",
            decision="accept_psc",
            selected_pinyin=selected,
            note=(
                f"原型 {surface} 是“{character}”的语流变调；规范读音真源保存 {underlying}。"
                f"{surface} 后续作为语流音变输入别名处理，不作为规范词典并列读音。"
            ),
            reason=(
                f"除“{character}”的表层声调外，PSC 与原型主读音的字符—音节位置逐项一致。"
            ),
        )
    return None


def _tone_profile(value: str) -> tuple[str, dict[int, str]]:
    normalized = unicodedata.normalize(
        "NFC", str(value or "").strip().lower().replace("u:", "ü").replace("v", "ü")
    )
    normalized = re.sub(r"[\s'’·•\-‐‑‒–—―]+", "", normalized)
    base: list[str] = []
    tones: dict[int, str] = {}
    letter_index = -1
    for char in unicodedata.normalize("NFD", normalized):
        if char in _TONE_COMBINING_MARKS:
            tones[letter_index] = char
        elif unicodedata.category(char) == "Mn":
            base.append(char)
        else:
            base.append(char)
            letter_index += 1
    return unicodedata.normalize("NFC", "".join(base)), tones


def _reading_forms_with_underlying_sandhi(
    case: ReviewCase, reading: dict[str, object]
) -> tuple[str, ...]:
    marked = str(reading.get("marked", "")).strip()
    numeric = str(reading.get("numeric", "")).strip()
    forms = [marked] if marked else []
    marked_tokens = marked.split()
    numeric_tokens = numeric.split()
    if (
        marked_tokens
        and len(marked_tokens) == len(numeric_tokens)
        and len(marked_tokens) == len(case.text)
    ):
        projected = list(marked_tokens)
        changed = False
        for index, (character, numeric_token) in enumerate(
            zip(case.text, numeric_tokens, strict=True)
        ):
            if character == "一" and numeric_token in {"yi2", "yi4"}:
                projected[index] = "yī"
                changed = True
            elif character == "不" and numeric_token == "bu2":
                projected[index] = "bù"
                changed = True
        if changed:
            forms.append(" ".join(projected))
    return tuple(dict.fromkeys(forms))


def _missing_tone_mark_suggestion(case: ReviewCase) -> ReviewSuggestion | None:
    if (
        case.review_lane != "canonical_pronunciation_review"
        or "psc_main" not in case.evidence_sources
        or len(case.pinyin_forms) != 1
    ):
        return None
    psc_base, psc_tones = _tone_profile(case.pinyin_forms[0])
    matches: list[str] = []
    for reading in case.canonical_readings:
        for candidate in _reading_forms_with_underlying_sandhi(case, reading):
            candidate_base, candidate_tones = _tone_profile(candidate)
            if candidate_base != psc_base or len(candidate_tones) <= len(psc_tones):
                continue
            if all(
                candidate_tones.get(position) == tone
                for position, tone in psc_tones.items()
            ):
                matches.append(candidate)
    unique = tuple(dict.fromkeys(matches))
    if len(unique) != 1:
        return None
    corrected = unique[0]
    return ReviewSuggestion(
        rule_id="ocr_missing_tone_mark",
        rule_label="调号变成了点",
        confidence="中",
        decision="psc_evidence_error",
        selected_pinyin=corrected,
        note=(
            "PSC 原页中的一个或多个调号在 OCR／解析结果中变成了点，"
            f"候选修正拼音为 {corrected}。"
        ),
        reason=(
            "PSC 已有调号均与唯一候选一致，缺少的调号来自 OCR／解析时调号变点；"
            "该批记录已经人工确认，可按唯一候选统一复核。"
        ),
        batch_safe=False,
    )


def _reading_contains_neutral_tone(reading: dict[str, object]) -> bool:
    numeric = str(reading.get("numeric", ""))
    status = str(reading.get("neutral_tone_status", ""))
    return status not in {"", "none"} or any(
        token.endswith("5") for token in numeric.split()
    )


def _neutral_primary_suggestion(case: ReviewCase) -> ReviewSuggestion | None:
    primary = tuple(item for item in case.canonical_readings if item.get("is_primary"))
    if not primary or not any(_reading_contains_neutral_tone(item) for item in primary):
        return None
    non_neutral_matches = tuple(
        dict.fromkeys(
            str(reading.get("marked", "")).strip()
            for reading in (*case.canonical_readings, *case.accepted_readings)
            if not _reading_contains_neutral_tone(reading)
            and normalize_marked_pinyin(str(reading.get("marked", "")))
            in case.pinyin_variants
        )
    )
    primary_forms = " / ".join(str(item.get("marked", "")) for item in primary)
    if non_neutral_matches:
        selected = next(
            (
                form
                for form in case.pinyin_forms
                if normalize_marked_pinyin(form)
                in {
                    normalize_marked_pinyin(item) for item in non_neutral_matches
                }
            ),
            non_neutral_matches[0],
        )
        if case.review_lane in {
            "contextual_reference_review",
            "supplemental_reference_review",
        }:
            return ReviewSuggestion(
                rule_id="neutral_primary_reference",
                rule_label="轻声主读（仅参考证据）",
                confidence="参考",
                decision="defer",
                selected_pinyin=selected,
                note=(
                    f"原型当前主读 {primary_forms} 含轻声音节，PSC 语境或补充材料命中"
                    "既有非轻声读音；该来源只作参考，不据此自动调整规范主读，留待主词表或"
                    "其他规范证据复核。"
                ),
                reason=(
                    "非轻声读音匹配成立，但证据来自语境或补充材料；"
                    "按来源分层规则不得批量提升为规范主读。"
                ),
                batch_safe=False,
            )
        return ReviewSuggestion(
            rule_id="neutral_primary_semantic_review",
            rule_label="轻声与本调分义（两读并存）",
            confidence="政策确定",
            decision="keep_both",
            selected_pinyin=selected,
            note=(
                f"原型当前主读 {primary_forms} 含轻声音节；PSC 读音与原型既有非轻声"
                "次读或来源读音完全一致。按同形、分义、分读的词位政策保留轻声与本调"
                "两读，不以 PSC 只收其中一读为由删除另一读，也不在本次审计中裁决全局主次。"
            ),
            reason=(
                "原型轻声读音和 PSC 本调读音均已有证据；当前政策将其作为同形、分义、"
                "分读的两个词位保存。现有主读标记只作兼容，读音排序以后改由使用频率决定。"
            ),
            batch_safe=True,
        )
    return ReviewSuggestion(
        rule_id="neutral_primary_complex",
        rule_label="轻声主读复杂冲突",
        confidence="需人工",
        decision="defer",
        selected_pinyin=" / ".join(case.pinyin_forms),
        note=(
            f"原型当前主读 {primary_forms} 含轻声音节，但 PSC 读音未能唯一匹配原型既有"
            "非轻声读音；本条可能同时涉及 OCR、词形、音节次序或真实轻声差异，需人工复核。"
        ),
        reason=(
            "检测到原型轻声主读，但不能把差异唯一归结为主次读音排序；"
            "本规则只负责聚类，不参加批量裁决。"
        ),
        batch_safe=False,
    )


def suggest_review_case(case: ReviewCase) -> ReviewSuggestion | None:
    """Return one conservative suggestion, ordered from data error to sandhi."""

    numeric_prefix = _numeric_prefix_suggestion(case)
    if numeric_prefix is not None:
        return numeric_prefix
    numeric_prefix_manual = _numeric_prefix_manual_suggestion(case)
    if numeric_prefix_manual is not None:
        return numeric_prefix_manual

    yi_sandhi = _underlying_tone_suggestion(
        case,
        character="一",
        surface_numeric=frozenset({"yi2", "yi4"}),
        underlying_marked="yī",
        rule_id="yi_sandhi_underlying",
        rule_label="“一”变调还原本调",
    )
    if yi_sandhi is not None:
        return yi_sandhi

    bu_sandhi = _underlying_tone_suggestion(
        case,
        character="不",
        surface_numeric=frozenset({"bu2"}),
        underlying_marked="bù",
        rule_id="bu_sandhi_underlying",
        rule_label="“不”变调还原本调",
    )
    if bu_sandhi is not None:
        return bu_sandhi
    missing_tone = _missing_tone_mark_suggestion(case)
    if missing_tone is not None:
        return missing_tone
    neutral_primary = _neutral_primary_suggestion(case)
    if neutral_primary is not None:
        return neutral_primary
    return None


def suggestion_map(cases: Iterable[ReviewCase]) -> dict[str, ReviewSuggestion]:
    return {
        case.case_key: suggestion
        for case in cases
        if (suggestion := suggest_review_case(case)) is not None
    }


def case_search_text(case: ReviewCase) -> str:
    readings = [
        str(reading.get("marked", ""))
        for reading in (*case.canonical_readings, *case.accepted_readings)
    ]
    return unicodedata.normalize(
        "NFC",
        " ".join(
            (
                case.case_key,
                case.text,
                *case.pinyin_forms,
                *case.pinyin_variants,
                *readings,
            )
        ),
    ).lower()


__all__ = [
    "CORE_REVIEW_LANES",
    "POLICY_AND_REFERENCE_LANES",
    "ReviewSuggestion",
    "case_search_text",
    "suggest_review_case",
    "suggestion_map",
]
