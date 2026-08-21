"""Apply an auditable encoded-reading selection to runtime materialization.

The complete character/phrase inventories remain intact.  This module only
populates ``runtime_lexicon_selection`` and rebuilds the materialized table,
so disabling the overlay restores the complete runtime on the next refresh.
"""

from __future__ import annotations

import csv
import hashlib
import json
import sqlite3
from collections import Counter
from pathlib import Path
from typing import Iterable

from yime.canonical_yime_mapping import load_code_mode_map
from yime.utils.rime_export import (
    convert_runtime_code_to_layout_keys,
    load_runtime_symbol_to_layout_key,
)
from yime.utils.runtime_codes_refresh import (
    rebuild_materialized_runtime_candidates,
)


SELECTION_SCHEMA = """
CREATE TABLE IF NOT EXISTS runtime_lexicon_selection (
    entry_type TEXT NOT NULL CHECK (entry_type IN ('char', 'phrase')),
    text TEXT NOT NULL,
    pinyin_tone TEXT NOT NULL,
    selection_level TEXT NOT NULL,
    selection_reason TEXT NOT NULL,
    source_full_layout_code TEXT NOT NULL,
    source_weight INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (entry_type, text, pinyin_tone)
);
CREATE INDEX IF NOT EXISTS idx_runtime_lexicon_selection_text
ON runtime_lexicon_selection(entry_type, text, pinyin_tone);
"""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _selection_rows(
    path: Path,
) -> Iterable[tuple[str, str, int, str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        required = {
            "text",
            "full_layout_code",
            "weight",
            "selection_level",
            "selection_reason",
        }
        missing = required - set(reader.fieldnames or ())
        if missing:
            raise ValueError(
                "Selection TSV is missing columns: "
                + ", ".join(sorted(missing))
            )
        for row in reader:
            text = str(row["text"] or "").strip()
            code = str(row["full_layout_code"] or "").strip()
            if not text or not code:
                continue
            yield (
                text,
                code,
                int(row["weight"] or 0),
                str(row["selection_level"] or "").strip(),
                str(row["selection_reason"] or "").strip(),
            )


def clone_database(source: Path, output: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(source)
    if output.exists():
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(source) as source_connection:
        with sqlite3.connect(output) as output_connection:
            source_connection.backup(output_connection)


def apply_runtime_selection(
    database: Path,
    selection_tsv: Path,
    *,
    manifest_path: Path | None = None,
    strict_unmatched: bool = True,
) -> dict[str, object]:
    selected: dict[tuple[str, str], tuple[int, str, str]] = {}
    source_counts: Counter[str] = Counter()
    for text, code, weight, level, reason in _selection_rows(selection_tsv):
        selected[(text, code)] = (weight, level, reason)
        source_counts[level] += 1

    symbol_to_key = load_runtime_symbol_to_layout_key()
    mode_map = load_code_mode_map()
    matched_keys: set[tuple[str, str]] = set()
    matched_rows: list[tuple[object, ...]] = []
    matched_counts: Counter[str] = Counter()

    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    try:
        connection.executescript(SELECTION_SCHEMA)
        cursor = connection.execute(
            """
            SELECT
                entry_type,
                text,
                pinyin_tone,
                yime_code
            FROM runtime_candidates
            WHERE yime_code IS NOT NULL
              AND TRIM(yime_code) <> ''
            """
        )
        while batch := cursor.fetchmany(20_000):
            for row in batch:
                text = str(row["text"])
                pinyin_tone = str(row["pinyin_tone"]).strip()
                syllable_codes = [
                    mode_map[syllable].full_code
                    for syllable in pinyin_tone.split()
                    if syllable in mode_map
                ]
                formal_full_code = (
                    "".join(syllable_codes)
                    if len(syllable_codes)
                    == len(pinyin_tone.split())
                    else str(row["yime_code"])
                )
                full_layout_code = convert_runtime_code_to_layout_keys(
                    formal_full_code,
                    symbol_to_key,
                )
                key = (text, full_layout_code)
                evidence = selected.get(key)
                if evidence is None:
                    continue
                weight, level, reason = evidence
                entry_type = str(row["entry_type"])
                matched_rows.append(
                    (
                        entry_type,
                        text,
                        pinyin_tone,
                        level,
                        reason,
                        full_layout_code,
                        weight,
                    )
                )
                matched_keys.add(key)
                matched_counts[entry_type] += 1

        unmatched = sorted(set(selected) - matched_keys)
        if strict_unmatched and unmatched:
            examples = ", ".join(
                f"{text}/{code}" for text, code in unmatched[:10]
            )
            raise ValueError(
                f"{len(unmatched)} selected encoded readings are absent "
                f"from the runtime inventory: {examples}"
            )

        connection.execute("DELETE FROM runtime_lexicon_selection")
        connection.executemany(
            """
            INSERT INTO runtime_lexicon_selection (
                entry_type,
                text,
                pinyin_tone,
                selection_level,
                selection_reason,
                source_full_layout_code,
                source_weight,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            """,
            matched_rows,
        )
        metadata_rows = [
            (
                "runtime_lexicon_selection_active",
                "1",
                "Enable runtime_lexicon_selection during materialization.",
            ),
            (
                "runtime_lexicon_selection_source",
                str(selection_tsv.resolve()),
                "Auditable two-level encoded-reading selection TSV.",
            ),
            (
                "runtime_lexicon_selection_sha256",
                _sha256(selection_tsv),
                "Selection TSV content identity.",
            ),
            (
                "runtime_lexicon_selection_rows",
                str(len(matched_rows)),
                "Matched runtime reading rows.",
            ),
        ]
        connection.executemany(
            """
            INSERT OR REPLACE INTO prototype_metadata (
                key, value, note, updated_at
            ) VALUES (?, ?, ?, CURRENT_TIMESTAMP)
            """,
            metadata_rows,
        )
        materialized_rows = rebuild_materialized_runtime_candidates(
            connection
        )
        complete_inventory_rows = int(
            connection.execute(
                "SELECT COUNT(*) FROM runtime_candidates"
            ).fetchone()[0]
        )
        phrase_inventory_exists = connection.execute(
            """
            SELECT 1
            FROM sqlite_master
            WHERE type = 'table' AND name = 'phrase_inventory'
            """
        ).fetchone()
        complete_phrase_rows = (
            int(
                connection.execute(
                    "SELECT COUNT(*) FROM phrase_inventory"
                ).fetchone()[0]
            )
            if phrase_inventory_exists is not None
            else 0
        )
        materialized_distinct_texts = int(
            connection.execute(
                """
                SELECT COUNT(DISTINCT text)
                FROM runtime_candidates_materialized
                """
            ).fetchone()[0]
        )
        connection.commit()
    finally:
        connection.close()

    payload: dict[str, object] = {
        "schema_version": "yime-runtime-lexicon-selection-v1",
        "database": str(database.resolve()),
        "selection_tsv": str(selection_tsv.resolve()),
        "selection_tsv_sha256": _sha256(selection_tsv),
        "selected_layout_readings": len(selected),
        "matched_layout_readings": len(matched_keys),
        "matched_runtime_rows": len(matched_rows),
        "matched_by_entry_type": dict(sorted(matched_counts.items())),
        "selected_by_level": dict(sorted(source_counts.items())),
        "unmatched_layout_readings": len(set(selected) - matched_keys),
        "complete_inventory_rows_preserved": complete_inventory_rows,
        "complete_phrase_rows_preserved": complete_phrase_rows,
        "materialized_runtime_rows": materialized_rows,
        "materialized_distinct_texts": (
            materialized_distinct_texts
        ),
    }
    if manifest_path is not None:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    return payload


def disable_runtime_selection(database: Path) -> int:
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute(
            """
            INSERT OR REPLACE INTO prototype_metadata (
                key, value, note, updated_at
            ) VALUES (
                'runtime_lexicon_selection_active',
                '0',
                'Disable runtime selection overlay.',
                CURRENT_TIMESTAMP
            )
            """
        )
        rows = rebuild_materialized_runtime_candidates(connection)
        connection.commit()
        return rows
    finally:
        connection.close()
