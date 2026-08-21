"""Source-backed connected-speech preparation helpers."""

from .erhua_lexicon import (
    build_explicit_erhua_bundles,
    is_explicit_word_final_erhua,
    write_explicit_erhua_bundles,
)

__all__ = [
    "build_explicit_erhua_bundles",
    "is_explicit_word_final_erhua",
    "write_explicit_erhua_bundles",
]
