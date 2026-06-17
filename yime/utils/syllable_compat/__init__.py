"""Compatibility helpers for syllable structure and decoding."""

from .syllable_decoder import (
    SyllableDecoder,
    is_pua_string,
    is_valid_encoded_string,
    main,
)
from .syllable_structure import SyllableStructure

__all__ = [
    "SyllableDecoder",
    "SyllableStructure",
    "is_pua_string",
    "is_valid_encoded_string",
    "main",
]
