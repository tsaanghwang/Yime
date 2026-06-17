"""Compatibility shim for syllable decoder helpers."""

from typing import Any

from yime.utils.syllable_compat import syllable_decoder as _compat_impl

SyllableDecoder = _compat_impl.SyllableDecoder
_normalize_split: Any = getattr(_compat_impl, "_normalize_split")
is_pua_string = _compat_impl.is_pua_string
is_valid_encoded_string = _compat_impl.is_valid_encoded_string
main = _compat_impl.main

__all__ = [
    "SyllableDecoder",
    "_normalize_split",
    "is_pua_string",
    "is_valid_encoded_string",
    "main",
]


if __name__ == "__main__":
    raise SystemExit(main())
