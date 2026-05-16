"""Compatibility shim for the single-char prototype importer."""

from yime.utils.prototype_single_char_import import (
    DB_PATH,
    NUMERIC_PATCH_PATH,
    SCHEMA_PATH,
    SOURCE_DB_PATH,
    WORKSPACE_ROOT,
    apply_schema,
    codepoint_to_int,
    import_hanzi_and_mappings,
    load_numeric_pinyin_patch_rows,
    load_source_single_char_rows,
    main,
    parse_numeric_pinyin_parts,
    sync_source_single_char_table,
    validate_char_inventory_coverage,
    write_import_metadata,
)


if __name__ == "__main__":
    main()
