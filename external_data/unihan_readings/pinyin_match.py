"""Pinyin normalization helpers for matching Unihan reading fields."""

from __future__ import annotations

import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from yime.utils.marked_pinyin import marked_syllable_to_numeric  # noqa: E402


def syllable_to_numeric(syllable: str) -> str:
    value = syllable.strip().lower().replace("u:", "ü")
    if not value:
        return value
    if value[-1].isdigit() and any(ch.isalpha() for ch in value[:-1]):
        return value
    return marked_syllable_to_numeric(syllable)


def parse_hanyu_pinlu_raw(value: str) -> list[tuple[str, int]]:
    readings: list[tuple[str, int]] = []
    for part in value.split():
        part = part.strip()
        if not part or "(" not in part:
            continue
        pinyin, freq_part = part.rsplit("(", 1)
        pinyin = pinyin.strip()
        if not pinyin:
            continue
        try:
            freq = int(freq_part.rstrip(")").strip())
        except ValueError:
            continue
        readings.append((pinyin, freq))
    return readings


MANDARIN_SOURCE_COLUMNS = [
    "kTGHZ2013",
    "kHanyuPinlu",
    "kXHC1983",
    "kHanyuPinyin",
    "kMandarin",
]


def split_clean_readings(value: str | None) -> list[str]:
    if not value or not value.strip():
        return []
    return [part.strip() for part in value.split(",") if part.strip()]


def _first_source_for_reading(
    numeric: str,
    merged: dict[str, dict[str, object]],
    source_columns: list[str],
) -> str:
    sources = merged[numeric]["sources"]  # type: ignore[index]
    for col in source_columns:
        if col in sources:
            return col
    return ""


def merge_mandarin_readings(
    source_values: dict[str, str | None],
    raw_pinlu: str | None,
    *,
    source_columns: list[str] | None = None,
) -> tuple[str, str, str, bool]:
    """Merge Mandarin reading columns into readings + common_reading."""
    columns = source_columns or MANDARIN_SOURCE_COLUMNS
    merged: dict[str, dict[str, object]] = {}
    order_counter = 0

    for col in columns:
        for reading in split_clean_readings(source_values.get(col)):
            numeric = syllable_to_numeric(reading)
            if not numeric:
                continue
            if numeric not in merged:
                merged[numeric] = {
                    "display": reading,
                    "sources": {col},
                    "order": order_counter,
                }
                order_counter += 1
            else:
                merged[numeric]["sources"].add(col)  # type: ignore[union-attr]

    if not merged:
        return "", "", "", False

    candidates = sorted(merged.values(), key=lambda item: item["order"])  # type: ignore[arg-type, return-value]
    readings = ",".join(str(item["display"]) for item in candidates)
    is_single = len(candidates) == 1

    if is_single:
        numeric = syllable_to_numeric(str(candidates[0]["display"]))
        return (
            readings,
            str(candidates[0]["display"]),
            _first_source_for_reading(numeric, merged, columns),
            True,
        )

    numeric_to_display = {
        syllable_to_numeric(str(item["display"])): str(item["display"])
        for item in candidates
    }

    if raw_pinlu:
        best_freq = -1
        best_display: str | None = None
        for pinyin, freq in parse_hanyu_pinlu_raw(raw_pinlu):
            numeric = syllable_to_numeric(pinyin)
            display = numeric_to_display.get(numeric)
            if display is not None and freq > best_freq:
                best_freq = freq
                best_display = display
        if best_display is not None:
            return readings, best_display, "kHanyuPinlu", False

    for col in columns:
        for reading in split_clean_readings(source_values.get(col)):
            numeric = syllable_to_numeric(reading)
            if numeric not in merged:
                continue
            display = str(merged[numeric]["display"])
            return readings, display, col, False

    first_numeric = syllable_to_numeric(str(candidates[0]["display"]))
    return (
        readings,
        str(candidates[0]["display"]),
        _first_source_for_reading(first_numeric, merged, columns),
        False,
    )
