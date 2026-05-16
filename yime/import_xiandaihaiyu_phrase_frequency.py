"""Compatibility shim for the Xiandai Hanyu phrase-frequency importer."""

from yime.utils.xiandaihaiyu_phrase_frequency_import import (
    DB_PATH,
    FREQUENCY_SOURCE,
    SOURCE_PATH,
    WORKSPACE_ROOT,
    main,
    parse_phrase_frequency,
    update_phrase_frequencies,
    write_import_metadata,
)

__all__ = [
    "DB_PATH",
    "FREQUENCY_SOURCE",
    "SOURCE_PATH",
    "WORKSPACE_ROOT",
    "main",
    "parse_phrase_frequency",
    "update_phrase_frequencies",
    "write_import_metadata",
]

if __name__ == "__main__":
    raise SystemExit(main())
