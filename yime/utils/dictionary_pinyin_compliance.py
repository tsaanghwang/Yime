"""First-round source compliance checks for dictionary Pinyin.

This module validates and canonicalizes source spellings before syllable
decomposition.  Passing this check means that a source entry is structurally
usable and its exceptional treatment is explicit; it is not a declaration
that every attested reading belongs to a closed Standard Mandarin inventory.
"""

from __future__ import annotations

import json
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from .marked_pinyin import marked_syllable_to_numeric

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_POLICY_PATH = (
    REPO_ROOT
    / "internal_data"
    / "pinyin_source_db"
    / "dictionary_pinyin_compliance_policy.json"
)

MARKED_SHAPE_RE = re.compile(r"^[a-züêāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜńňǹḿếề\u0300\u0301\u0304\u030c]+$")
NUMERIC_SHAPE_RE = re.compile(r"^[a-züê]+[1-5]$")
TONE_MARKS = frozenset("āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜńňǹḿếề\u0300\u0301\u0304\u030c")
BREVE_TO_CARON = str.maketrans({"ă": "ǎ", "ĕ": "ě", "ĭ": "ǐ", "ŏ": "ǒ", "ŭ": "ǔ"})


@dataclass(frozen=True)
class SyllableReview:
    source_marked: str
    canonical_marked: str
    source_numeric: str
    canonical_numeric: str
    status: str
    rule_id: str
    reason: str

    @property
    def accepted(self) -> bool:
        return self.status != "rejected" and not self.status.startswith("excluded_")

    @property
    def known_exclusion(self) -> bool:
        return self.status.startswith("excluded_")

    @property
    def changed(self) -> bool:
        return self.source_marked != self.canonical_marked


def load_policy(path: Path = DEFAULT_POLICY_PATH) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != "dictionary-pinyin-compliance-v1":
        raise ValueError(f"不支持的拼音合规策略版本: {path}")
    return payload


def normalize_marked_syllable(value: str) -> str:
    return unicodedata.normalize("NFC", value.strip().translate(BREVE_TO_CARON))


def review_syllable(
    value: str,
    policy: dict[str, Any] | None = None,
    *,
    codepoint: str | None = None,
) -> SyllableReview:
    policy = policy or load_policy()
    marked = normalize_marked_syllable(value)
    if not marked:
        return SyllableReview(value, marked, "", "", "rejected", "SRC-EMPTY", "空拼音音节")
    if "v" in marked or "u:" in marked:
        numeric = marked_syllable_to_numeric(marked)
        return SyllableReview(
            value, marked, numeric, numeric, "rejected", "SRC-TECHNICAL-PINYIN",
            "字典来源不得使用 v 或 u: 代替 ü；技术拼音兼容不属于来源合规层。",
        )
    if not MARKED_SHAPE_RE.fullmatch(marked):
        numeric = marked_syllable_to_numeric(marked)
        return SyllableReview(
            value, marked, numeric, numeric, "rejected", "SRC-INVALID-CHARACTER",
            "音节含有数字、标点、大写字母或第一轮策略未登记的字符。",
        )
    tone_count = sum(char in TONE_MARKS for char in unicodedata.normalize("NFD", marked))
    if tone_count > 1:
        numeric = marked_syllable_to_numeric(marked)
        return SyllableReview(
            value, marked, numeric, numeric, "rejected", "SRC-MULTIPLE-TONES",
            "一个拼音音节只能带一个声调标记。",
        )

    numeric = marked_syllable_to_numeric(marked)
    if not NUMERIC_SHAPE_RE.fullmatch(numeric):
        return SyllableReview(
            value, marked, numeric, numeric, "rejected", "SRC-INVALID-NUMERIC-SHAPE",
            "标调拼音不能稳定转换成“拼式+1~5声”的内部审查形式。",
        )

    alias = policy.get("aliases", {}).get(numeric)
    if alias:
        return SyllableReview(
            value,
            str(alias["canonical_marked"]),
            numeric,
            str(alias["canonical_numeric"]),
            "canonical_alias",
            str(alias["rule_id"]),
            str(alias["reason"]),
        )

    source_record_key = f"{codepoint.upper()}|{numeric}" if codepoint else ""
    correction = policy.get("source_corrections", {}).get(source_record_key)
    if correction:
        return SyllableReview(
            value,
            str(correction["canonical_marked"]),
            numeric,
            str(correction["canonical_numeric"]),
            "source_correction",
            str(correction["rule_id"]),
            str(correction["reason"]),
        )

    exclusion = policy.get("source_exclusions", {}).get(source_record_key)
    if exclusion:
        return SyllableReview(
            value, marked, numeric, numeric, str(exclusion["status"]),
            str(exclusion["rule_id"]), str(exclusion["reason"]),
        )

    base = numeric[:-1]
    syllabic_specials = {str(item) for item in policy.get("admitted_syllabic_specials", [])}
    admitted = base in syllabic_specials
    if not admitted:
        finals_by_initial = policy.get("admitted_finals_by_initial", {})
        initials = sorted(
            (str(item) for item in finals_by_initial if item != "'"),
            key=len,
            reverse=True,
        )
        initial = next((item for item in initials if base.startswith(item)), "'")
        final = base[len(initial):] if initial != "'" else base
        admitted_finals = set(str(finals_by_initial.get(initial, "")).split())
        admitted = final in admitted_finals
    if not admitted:
        return SyllableReview(
            value, marked, numeric, numeric, "rejected", "SRC-UNADMITTED-ORTHOGRAPHY",
            "拼式不在第一轮已准入的声母—韵母结构中；须先补充来源证据和审查策略，不能直接进入解码。",
        )

    source_alias = (
        policy.get("source_aliases", {}).get(codepoint.upper())
        if codepoint
        else None
    )
    if source_alias:
        return SyllableReview(
            value,
            marked,
            numeric,
            numeric,
            "source_alias",
            str(source_alias["rule_id"]),
            str(source_alias["reason"]),
        )

    return SyllableReview(
        value, marked, numeric, numeric, "dictionary_attested", "SRC-DICTIONARY-ATTESTED",
        "来源中实际出现且通过第一轮字符、声调和形态检查；未据此宣称属于封闭的核心规范音节表。",
    )


def review_reading(
    value: str,
    policy: dict[str, Any] | None = None,
    *,
    codepoint: str | None = None,
) -> list[SyllableReview]:
    return [
        review_syllable(part, policy, codepoint=codepoint)
        for part in value.split()
        if part.strip()
    ]


def canonicalize_reading(
    value: str,
    policy: dict[str, Any] | None = None,
    *,
    codepoint: str | None = None,
) -> tuple[str, list[SyllableReview]]:
    reviews = review_reading(value, policy, codepoint=codepoint)
    rejected = [item for item in reviews if not item.accepted]
    if rejected:
        details = "; ".join(f"{item.source_marked}: {item.reason}" for item in rejected)
        raise ValueError(f"拼音来源未通过第一轮合规审查: {details}")
    return " ".join(item.canonical_marked for item in reviews), reviews


def summarize_reviews(reviews: Iterable[SyllableReview]) -> dict[str, int]:
    summary: dict[str, int] = {}
    for item in reviews:
        summary[item.status] = summary.get(item.status, 0) + 1
    return dict(sorted(summary.items()))
