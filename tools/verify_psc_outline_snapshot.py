#!/usr/bin/env python3
"""Verify the content lock and path portability of the internal PSC snapshot."""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import sys
from pathlib import Path, PurePosixPath
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT_ROOT = REPO_ROOT / "internal_data" / "psc_outline"
MANIFEST_PATH = SNAPSHOT_ROOT / "snapshot_manifest.json"
DATABASE_PATH = SNAPSHOT_ROOT / "psc_outline_ocr.sqlite3"
SCHEMA_VERSION = "yime-internal-psc-outline-snapshot-v1"
WINDOWS_ABSOLUTE_PATH = re.compile(r"(?i)(?:[a-z]:[\\/]|\\\\)")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def portable_relative_path(value: object, *, label: str) -> Path:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{label} must be a non-empty string")
    if "\\" in value or ":" in value:
        raise ValueError(f"{label} is not portable: {value!r}")
    pure = PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts:
        raise ValueError(f"{label} escapes the snapshot: {value!r}")
    return SNAPSHOT_ROOT.joinpath(*pure.parts)


def load_manifest() -> dict[str, Any]:
    payload = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or payload.get("schema_version") != SCHEMA_VERSION:
        raise ValueError("unsupported PSC snapshot manifest schema")
    authorization = payload.get("authorization")
    if not isinstance(authorization, dict):
        raise ValueError("PSC snapshot manifest has no authorization record")
    for field in ("approved_by", "authorization_reference", "reason"):
        if not isinstance(authorization.get(field), str) or not authorization[field].strip():
            raise ValueError(f"PSC snapshot authorization has no {field}")
    return payload


def verify_files(payload: dict[str, Any]) -> tuple[int, int, dict[str, dict[str, Any]]]:
    records = payload.get("files")
    if not isinstance(records, list) or not records:
        raise ValueError("PSC snapshot manifest has no files")
    seen: set[str] = set()
    locked_files: dict[str, dict[str, Any]] = {}
    total_bytes = 0
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("PSC snapshot manifest contains a non-object file record")
        relative = str(record.get("path") or "")
        path = portable_relative_path(relative, label="snapshot file path")
        if relative in seen:
            raise ValueError(f"duplicate PSC snapshot file record: {relative}")
        seen.add(relative)
        locked_files[relative] = record
        if not path.is_file():
            raise ValueError(f"PSC snapshot file is missing: {relative}")
        expected_size = record.get("bytes")
        expected_digest = record.get("sha256")
        if path.stat().st_size != expected_size:
            raise ValueError(f"PSC snapshot size mismatch: {relative}")
        if sha256(path) != expected_digest:
            raise ValueError(f"PSC snapshot SHA-256 mismatch: {relative}")
        total_bytes += path.stat().st_size

    actual = {
        path.relative_to(SNAPSHOT_ROOT).as_posix()
        for path in SNAPSHOT_ROOT.rglob("*")
        if path.is_file() and path.name not in {"README.md", MANIFEST_PATH.name}
    }
    if actual != seen:
        missing = sorted(seen - actual)
        untracked = sorted(actual - seen)
        raise ValueError(
            f"PSC snapshot manifest file set mismatch: missing={missing}, untracked={untracked}"
        )
    return len(seen), total_bytes, locked_files


def verify_database(
    payload: dict[str, Any], locked_files: dict[str, dict[str, Any]]
) -> tuple[int, int, int]:
    database_record = payload.get("database")
    if not isinstance(database_record, dict) or database_record.get("path") != DATABASE_PATH.name:
        raise ValueError("PSC snapshot manifest database record is invalid")
    connection = sqlite3.connect(f"file:{DATABASE_PATH.as_posix()}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok" or database_record.get("integrity_check") != "ok":
            raise ValueError(f"PSC snapshot database integrity failed: {integrity}")
        expected_counts = database_record.get("table_counts")
        if not isinstance(expected_counts, dict):
            raise ValueError("PSC snapshot manifest has no table counts")
        for table, expected in expected_counts.items():
            actual = connection.execute(f"SELECT COUNT(*) FROM [{table}]").fetchone()[0]
            if actual != expected:
                raise ValueError(
                    f"PSC snapshot table count mismatch for {table}: {actual} != {expected}"
                )

        for table, column in (("documents", "source_path"), ("pages", "image_path")):
            for row in connection.execute(
                f"SELECT rowid, [{column}] AS value FROM [{table}] WHERE [{column}] IS NOT NULL"
            ):
                value = str(row["value"])
                if WINDOWS_ABSOLUTE_PATH.search(value):
                    raise ValueError(
                        f"machine-absolute path remains in {table}.{column} row {row['rowid']}"
                    )
                portable_relative_path(value, label=f"{table}.{column}")

        for row in connection.execute(
            "SELECT source_path, source_filename, source_sha256, source_size FROM documents"
        ):
            relative = str(row["source_path"])
            if PurePosixPath(relative).name != str(row["source_filename"]):
                raise ValueError(f"PSC source filename mismatch: {relative}")
            record = locked_files.get(relative)
            if record is None:
                raise ValueError(f"PSC source document is not content-locked: {relative}")
            if str(record.get("sha256", "")).casefold() != str(
                row["source_sha256"]
            ).casefold():
                raise ValueError(f"PSC source document hash disagrees with database: {relative}")
            if record.get("bytes") != row["source_size"]:
                raise ValueError(f"PSC source document size disagrees with database: {relative}")

        for row in connection.execute(
            "SELECT image_path, image_sha256 FROM pages WHERE image_path IS NOT NULL AND image_path != ''"
        ):
            relative = str(row["image_path"])
            record = locked_files.get(relative)
            if record is None:
                raise ValueError(f"PSC OCR page is not content-locked: {relative}")
            if str(record.get("sha256", "")).casefold() != str(
                row["image_sha256"]
            ).casefold():
                raise ValueError(f"PSC OCR page hash disagrees with database: {relative}")

        for table, column in (
            ("pages", "ocr_json"),
            ("orthoepy_source_rows", "evidence_json"),
        ):
            for row in connection.execute(
                f"SELECT rowid, [{column}] AS value FROM [{table}] WHERE [{column}] IS NOT NULL"
            ):
                if WINDOWS_ABSOLUTE_PATH.search(str(row["value"])):
                    raise ValueError(
                        f"machine-absolute path remains in {table}.{column} row {row['rowid']}"
                    )

        document_count = connection.execute("SELECT COUNT(*) FROM documents").fetchone()[0]
        page_count = connection.execute(
            "SELECT COUNT(*) FROM pages WHERE image_path IS NOT NULL AND image_path != ''"
        ).fetchone()[0]
        review_count = connection.execute(
            "SELECT COUNT(*) FROM manual_corrections"
        ).fetchone()[0]
        source_record = payload.get("source")
        if not isinstance(source_record, dict):
            raise ValueError("PSC snapshot manifest has no source record")
        if source_record.get("document_count") != document_count:
            raise ValueError("PSC snapshot source document count disagrees with database")
        if source_record.get("ocr_page_count") != page_count:
            raise ValueError("PSC snapshot source page count disagrees with database")
        return int(document_count), int(page_count), int(review_count)
    finally:
        connection.close()


def main() -> int:
    try:
        payload = load_manifest()
        file_count, total_bytes, locked_files = verify_files(payload)
        document_count, page_count, review_count = verify_database(payload, locked_files)
    except (OSError, ValueError, json.JSONDecodeError, sqlite3.Error) as error:
        print(f"FAIL internal PSC outline snapshot: {error}", file=sys.stderr)
        return 1
    print(
        "PASS internal PSC outline snapshot: "
        f"{file_count} files, {total_bytes} bytes, {document_count} source documents, "
        f"{page_count} OCR pages, {review_count} manual decisions"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
