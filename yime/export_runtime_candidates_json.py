"""Compatibility shim for the runtime-candidate JSON exporter."""

from yime.utils.runtime_candidates_export import (
    DB_PATH,
    DEFAULT_OUTPUT_PATH,
    DEFAULT_PLACEHOLDER_OUTPUT_PATH,
    DEFAULT_TRUE_OUTPUT_PATH,
    RUNTIME_SQL_PRIORITY_ORDER,
    build_candidate_record,
    build_payload,
    group_rows,
    main,
    parse_args,
)

__all__ = [
    "DB_PATH",
    "DEFAULT_OUTPUT_PATH",
    "DEFAULT_PLACEHOLDER_OUTPUT_PATH",
    "DEFAULT_TRUE_OUTPUT_PATH",
    "RUNTIME_SQL_PRIORITY_ORDER",
    "build_candidate_record",
    "build_payload",
    "group_rows",
    "main",
    "parse_args",
]


if __name__ == "__main__":
    raise SystemExit(main())
