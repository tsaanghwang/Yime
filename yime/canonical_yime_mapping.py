"""Compatibility shim for canonical mapping helpers."""

from yime.utils.canonical_yime_mapping import (
    WORKSPACE_ROOT,
    build_bmp_to_canonical_map,
    build_canonical_mapping_rows,
    build_canonical_pinyin_rows,
    canonicalize_code,
    convert_legacy_code_to_primary,
    load_canonical_code_map,
    load_code_mode_map,
    load_primary_code_map,
    load_virtual_initial_symbol,
    load_json,
    sync_canonical_mapping_table,
)

__all__ = [
    "WORKSPACE_ROOT",
    "build_bmp_to_canonical_map",
    "build_canonical_mapping_rows",
    "build_canonical_pinyin_rows",
    "canonicalize_code",
    "convert_legacy_code_to_primary",
    "load_canonical_code_map",
    "load_code_mode_map",
    "load_primary_code_map",
    "load_virtual_initial_symbol",
    "load_json",
    "sync_canonical_mapping_table",
]
