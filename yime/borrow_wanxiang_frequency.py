"""Legacy shim for the Wanxiang frequency import entrypoint."""

from yime.utils.wanxiang_frequency_import import (
    ImportStats,
    apply_frequency_updates,
    backup_database,
    iter_rime_rows,
    load_char_frequency_map,
    load_phrase_frequency_map,
    main,
    parse_args,
    refresh_runtime_export,
    resolve_phrase_dicts,
)

__all__ = [
    "ImportStats",
    "apply_frequency_updates",
    "backup_database",
    "iter_rime_rows",
    "load_char_frequency_map",
    "load_phrase_frequency_map",
    "main",
    "parse_args",
    "refresh_runtime_export",
    "resolve_phrase_dicts",
]


if __name__ == "__main__":
    raise SystemExit(main())
