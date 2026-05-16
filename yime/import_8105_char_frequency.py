"""Compatibility shim for the 8105 char-frequency importer."""

from yime.utils.char_frequency_8105_import import (
    DB_PATH,
    FREQUENCY_SOURCE,
    SOURCE_PATH,
    WORKSPACE_ROOT,
    import_frequency_rows,
    main,
    parse_frequency_rows,
    write_import_metadata,
)


if __name__ == "__main__":
    main()
