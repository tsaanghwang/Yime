"""Compatibility shim for asset path helpers."""

from yime.utils.asset_paths import (
    generated_lexicon_source_db_path,
    generated_runtime_candidates_json_path,
    resolve_lexicon_source_db_path,
    resolve_runtime_candidates_json_path,
    resolve_source_pinyin_db_path,
)

__all__ = [
    "generated_lexicon_source_db_path",
    "generated_runtime_candidates_json_path",
    "resolve_lexicon_source_db_path",
    "resolve_runtime_candidates_json_path",
    "resolve_source_pinyin_db_path",
]
