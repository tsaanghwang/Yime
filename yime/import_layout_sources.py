"""Compatibility shim for the layout source import helpers."""

from yime.utils.layout_sources_import import (
    CANONICAL_SYMBOL_PATH,
    DB_PATH,
    DEFAULT_EXTERNAL_REPO,
    EXTERNAL_KLC_PATH,
    EXTERNAL_REPO,
    KLC_ROW_RE,
    LOCAL_KLC_PATH,
    PROJECTION_PATH,
    ROOT,
    RUNTIME_SYMBOL_PATH,
    SCHEMA_PATH,
    SHOUYIN_PATH,
    VK_TO_KEY_CODE,
    YINYUAN_PATH,
    apply_schema,
    build_label_index,
    decode_klc_token,
    format_codepoint,
    import_derived_key_mappings,
    import_klc_rows,
    import_symbols,
    load_json,
    load_symbol_catalog,
    main,
    parse_klc_layout,
    rebuild_default_key_mappings,
    resolve_key_code,
    resolve_klc_path,
    slot_sort_key,
)


if __name__ == "__main__":
    main()
