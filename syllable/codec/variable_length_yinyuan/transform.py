"""Convert canonical four-yinyuan syllables to variable-length codes.

The first position is always retained as a real or virtual shouyin. The three
following positions compose the ganyin: huyin, zhuyin, and moyin. Variable
length mode merges adjacent identical yinyuan that compose this ganyin; it
does not merge the ganyin as a whole. Thus ABC stays ABC, AAC becomes AC,
ABB becomes AB, and AAA becomes A. The shouyin is an explicit syllable
boundary for continuous input and never participates in this merging.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Sequence

from syllable.codec.model_full_code import Yinjie


FOUR_YINYUAN_CODE_LENGTH = 4


@dataclass(frozen=True)
class VariableLengthYinyuanResult:
    """Result of converting one canonical four-yinyuan syllable."""

    full_code: str
    merged_code: str
    variable_code: str
    virtual_initial: str | None
    omitted_virtual_initial: bool
    merged_adjacent_count: int


def merge_adjacent_equal_yinyuan(symbols: Iterable[str]) -> tuple[list[str], int]:
    """Merge adjacent, exactly equal yinyuan."""
    merged: list[str] = []
    merged_adjacent_count = 0
    for symbol in symbols:
        if not merged or merged[-1] != symbol:
            merged.append(symbol)
            continue
        merged_adjacent_count += 1
    return merged, merged_adjacent_count


def _normalize_full_code(full_code: str | Sequence[str]) -> str:
    if isinstance(full_code, str):
        normalized = full_code
    else:
        normalized = "".join(str(symbol) for symbol in full_code)

    if len(normalized) != FOUR_YINYUAN_CODE_LENGTH:
        raise ValueError(
            f"full_code must be a four-yinyuan code, got length {len(normalized)}: {normalized!r}"
        )
    return normalized


def transform_full_code(
    full_code: str | Sequence[str],
    *,
    virtual_initial: str | None = None,
) -> VariableLengthYinyuanResult:
    """Merge adjacent identical yinyuan composing ganyin; preserve shouyin."""
    normalized_code = _normalize_full_code(full_code)
    initial = normalized_code[0]
    merged_ganyin, merged_adjacent_count = merge_adjacent_equal_yinyuan(normalized_code[1:])
    merged_code = "".join([initial, *merged_ganyin])

    return VariableLengthYinyuanResult(
        full_code=normalized_code,
        merged_code=merged_code,
        variable_code=merged_code,
        virtual_initial=virtual_initial,
        omitted_virtual_initial=False,
        merged_adjacent_count=merged_adjacent_count,
    )


def transform_yinjie(
    yinjie: Yinjie,
    *,
    virtual_initial: str | None = None,
) -> VariableLengthYinyuanResult:
    """Convert a ``Yinjie`` full-code object to variable length."""
    return transform_full_code(yinjie.to_code(), virtual_initial=virtual_initial)


def to_variable_length_yinyuan_code(
    full_code: str | Sequence[str],
    *,
    virtual_initial: str | None = None,
) -> str:
    """Return the variable code while preserving its initial boundary."""
    return transform_full_code(full_code, virtual_initial=virtual_initial).variable_code


__all__ = [
    "FOUR_YINYUAN_CODE_LENGTH",
    "VariableLengthYinyuanResult",
    "merge_adjacent_equal_yinyuan",
    "to_variable_length_yinyuan_code",
    "transform_full_code",
    "transform_yinjie",
]
