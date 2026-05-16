"""Compatibility shim for the phrase prototype importer."""

from yime.utils.prototype_phrase_import import (
    DB_PATH,
    PREFERRED_PHRASE_READINGS,
    SCHEMA_PATH,
    SOURCE_DB_PATH,
    WORKSPACE_ROOT,
    apply_schema,
    build_phrase_yime_code,
    import_phrases_and_mappings,
    load_source_phrase_rows,
    main,
    parse_numeric_pinyin_parts,
    parse_phrase_frequency,
    sync_source_phrase_table,
    write_import_metadata,
)


if __name__ == "__main__":
    main()
