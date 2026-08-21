"""Pure numeric-Pinyin spacing and canonical-code composition helpers."""

from __future__ import annotations

from collections.abc import Mapping

from yime.utils.numeric_pinyin_standardizer import standardize_numeric_pinyin


def split_compact_numeric_pinyin_token(token: str) -> list[str]:
    """Split ``ni3hao3`` without guessing syllable boundaries beyond tones."""
    normalized_token = token.strip()
    if not normalized_token:
        return []

    parts: list[str] = []
    start = 0
    saw_tone_digit = False
    for index, char in enumerate(normalized_token):
        if char not in "12345":
            continue
        saw_tone_digit = True
        if index == start:
            return [normalized_token]
        parts.append(normalized_token[start : index + 1])
        start = index + 1

    if not saw_tone_digit or start != len(normalized_token):
        return [normalized_token]
    return parts


def normalize_numeric_pinyin_syllable_spacing(raw_pinyin: str) -> str:
    """Normalize whitespace and registered numeric-Pinyin spellings."""
    normalized_tokens: list[str] = []
    for token in raw_pinyin.split():
        normalized_tokens.extend(split_compact_numeric_pinyin_token(token))
    return " ".join(
        standardize_numeric_pinyin(token)
        for token in normalized_tokens
        if token
    )


def resolve_canonical_code_from_numeric_pinyin(
    pinyin_to_canonical: Mapping[str, str],
    numeric_pinyin: str,
) -> str:
    """Compose existing per-syllable codes; never infer a missing code."""
    normalized = normalize_numeric_pinyin_syllable_spacing(numeric_pinyin)
    if not normalized:
        return ""

    parts: list[str] = []
    for syllable in normalized.split(" "):
        canonical_code = str(pinyin_to_canonical.get(syllable) or "").strip()
        if not canonical_code:
            return ""
        parts.append(canonical_code)
    return "".join(parts)


__all__ = [
    "normalize_numeric_pinyin_syllable_spacing",
    "resolve_canonical_code_from_numeric_pinyin",
    "split_compact_numeric_pinyin_token",
]
