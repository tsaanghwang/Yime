from __future__ import annotations

import json
from dataclasses import dataclass
from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Any, Mapping, cast

from syllable.codec.input_shorthand import omit_middle_tone_if_same_quality_run
from syllable.codec.variable_length_yinyuan import transform_full_code


WORKSPACE_ROOT = Path(__file__).resolve().parents[2]


class YimeCodeMode(StrEnum):
    """运行时可切换的三种音元输入模式。"""

    FULL = "full"
    VARIABLE = "variable"
    SHORTHAND = "shorthand"


CODE_MODE_LABELS: dict[YimeCodeMode, str] = {
    YimeCodeMode.FULL: "等长模式",
    YimeCodeMode.VARIABLE: "变长模式",
    YimeCodeMode.SHORTHAND: "省键模式",
}


LOOKUP_CODE_COLUMNS: dict[YimeCodeMode, str] = {
    YimeCodeMode.FULL: "full_yime_code",
    YimeCodeMode.VARIABLE: "variable_yinyuan_code",
    YimeCodeMode.SHORTHAND: "input_shorthand_code",
}


LEGACY_LOOKUP_CODE_COLUMNS: dict[YimeCodeMode, str] = {
    YimeCodeMode.FULL: "yime_code",
    YimeCodeMode.VARIABLE: "primary_yime_code",
    YimeCodeMode.SHORTHAND: "input_shorthand_code",
}


@dataclass(frozen=True)
class CodeModeRecord:
    full_code: str
    variable_code: str
    shorthand_code: str

    def lookup_code(self, mode: YimeCodeMode | str | object) -> str:
        normalized_mode = normalize_code_mode(mode)
        if normalized_mode == YimeCodeMode.FULL:
            return self.full_code
        if normalized_mode == YimeCodeMode.SHORTHAND:
            return self.shorthand_code
        return self.variable_code


def normalize_code_mode(value: YimeCodeMode | str | object) -> YimeCodeMode:
    normalized = str(value or "").strip().lower()
    if normalized in {"full", "fixed", "fixed_length", "等长", "等长模式"}:
        return YimeCodeMode.FULL
    if normalized in {"shorthand", "input_shorthand", "省键", "省键模式"}:
        return YimeCodeMode.SHORTHAND
    return YimeCodeMode.VARIABLE


def code_mode_label(mode: YimeCodeMode | str | object) -> str:
    return CODE_MODE_LABELS[normalize_code_mode(mode)]


def lookup_code_column(mode: YimeCodeMode | str | object, *, legacy: bool = False) -> str:
    normalized_mode = normalize_code_mode(mode)
    if legacy:
        return LEGACY_LOOKUP_CODE_COLUMNS[normalized_mode]
    return LOOKUP_CODE_COLUMNS[normalized_mode]


def _load_json(path: Path) -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(path.read_text(encoding="utf-8")))


@lru_cache(maxsize=None)
def _load_ganyin_symbol_metadata_cached(repo_root_key: str) -> dict[str, dict[str, int | str]]:
    repo_root = Path(repo_root_key)
    mapping = _load_json(repo_root / "internal_data" / "yinjie_runtime_key_symbol_mapping.json")
    key_to_symbol = _load_json(repo_root / "internal_data" / "key_to_symbol.json")

    metadata: dict[str, dict[str, int | str]] = {}
    for entry in mapping.get("entries", []):
        if not isinstance(entry, dict) or entry.get("source_type") != "ganyin":
            continue
        key = str(entry.get("key") or "")
        if not key.startswith("M"):
            continue
        try:
            ordinal = int(key[1:]) - 1
        except ValueError:
            continue
        symbol = str(key_to_symbol.get(key) or entry.get("symbol") or "")
        if not symbol:
            continue
        metadata[symbol] = {
            "quality_group": ordinal // 3,
            "tone_level": ("high", "mid", "low")[ordinal % 3],
        }
    return metadata


def load_ganyin_symbol_metadata(repo_root: Path | None = None) -> dict[str, dict[str, int | str]]:
    resolved_root = repo_root or WORKSPACE_ROOT
    return _load_ganyin_symbol_metadata_cached(str(resolved_root.resolve()))


def _to_shorthand_syllable_code(
    variable_code: str,
    *,
    ganyin_symbol_metadata: Mapping[str, Mapping[str, Any]],
) -> str:
    symbols = list(variable_code)
    shouyin = symbols[:1]
    ganyin = symbols[1:]

    compressed_ganyin, _ = omit_middle_tone_if_same_quality_run(
        ganyin,
        ganyin_symbol_metadata,
    )
    return "".join([*shouyin, *compressed_ganyin])


def build_code_mode_record(
    full_code: str,
    *,
    virtual_initial: str | None = None,
    ganyin_symbol_metadata: Mapping[str, Mapping[str, Any]] | None = None,
) -> CodeModeRecord:
    normalized_code = str(full_code or "").strip()
    if not normalized_code:
        return CodeModeRecord("", "", "")

    metadata = ganyin_symbol_metadata or {}
    _ = virtual_initial  # Compatibility argument; initials are always preserved.
    if len(normalized_code) % 4 != 0:
        raise ValueError(
            f"full_code length must be divisible by 4, got {len(normalized_code)}: "
            f"{normalized_code!r}"
        )
    complete_codes = [
        normalized_code[index:index + 4]
        for index in range(0, len(normalized_code), 4)
    ]
    variable_parts: list[str] = []
    shorthand_parts: list[str] = []

    for syllable_code in complete_codes:
        variable_code = transform_full_code(syllable_code).variable_code
        variable_parts.append(variable_code)
        shorthand_parts.append(
            _to_shorthand_syllable_code(
                variable_code,
                ganyin_symbol_metadata=metadata,
            )
        )

    variable_code = "".join(variable_parts)
    shorthand_code = "".join(shorthand_parts)
    return CodeModeRecord(
        full_code=normalized_code,
        variable_code=variable_code,
        shorthand_code=shorthand_code or variable_code,
    )


def build_code_mode_map(
    full_code_map: Mapping[str, str],
    *,
    virtual_initial: str | None = None,
    ganyin_symbol_metadata: Mapping[str, Mapping[str, Any]] | None = None,
) -> dict[str, CodeModeRecord]:
    return {
        key: build_code_mode_record(
            code,
            virtual_initial=virtual_initial,
            ganyin_symbol_metadata=ganyin_symbol_metadata,
        )
        for key, code in full_code_map.items()
        if str(key or "").strip() and str(code or "").strip()
    }
