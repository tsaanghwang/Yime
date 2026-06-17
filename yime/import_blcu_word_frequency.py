"""Compatibility shim for the BCC word-frequency importer."""

from yime.utils.blcu_word_frequency_import import (
    BCC_CITATION,
    ImportStats,
    OBSOLETE_FREQUENCY_METADATA_KEYS,
    apply_frequency_updates,
    backup_database,
    load_char_frequency_map,
    load_phrase_frequency_map,
    load_word_frequency_csv,
    main,
    parse_args,
    migrate_phrase_frequency_column_to_integer,
    phrase_frequency_column_type,
    purge_obsolete_frequency_metadata,
    rebuild_materialized_runtime_candidates,
    refresh_prototype_schema_views,
    refresh_runtime_export,
)

__all__ = [
    "BCC_CITATION",
    "ImportStats",
    "OBSOLETE_FREQUENCY_METADATA_KEYS",
    "apply_frequency_updates",
    "backup_database",
    "load_char_frequency_map",
    "load_phrase_frequency_map",
    "load_word_frequency_csv",
    "main",
    "migrate_phrase_frequency_column_to_integer",
    "parse_args",
    "phrase_frequency_column_type",
    "purge_obsolete_frequency_metadata",
    "rebuild_materialized_runtime_candidates",
    "refresh_prototype_schema_views",
    "refresh_runtime_export",
]


if __name__ == "__main__":
    raise SystemExit(main())
