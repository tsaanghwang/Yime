"""SQLite-backed builder for the unified, gated Yime source lexicon bundle."""

from __future__ import annotations

import csv
import hashlib
import json
import sqlite3
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator

from yime.utils.dictionary_pinyin_compliance import (
    DEFAULT_POLICY_PATH as DEFAULT_SOURCE_COMPLIANCE_POLICY_PATH,
    load_policy as load_source_compliance_policy,
)

from .gate import DEFAULT_NEUTRAL_SOURCE_POLICY_PATH, ReadingGate, is_han_text
from .syllable_admission import DEFAULT_ADMISSION_PATH
from .character_tiers import (
    CharacterTierSources,
    create_character_tier_schema,
    export_character_tiers,
    rebuild_character_tiers,
)
from .parsers import (
    FrequencyRecord,
    ReadingRecord,
    iter_bcc_frequencies,
    iter_pypinyin_phrase_readings,
    iter_reviewed_orthoepy_readings,
    iter_reviewed_psc_candidate_readings,
    iter_unihan_readings,
    iter_wanxiang_readings,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ORTHOEPY_COVERAGE_PATH = (
    REPO_ROOT / "internal_data" / "pinyin_source_db" / "orthoepy_coverage_readings.json"
)
DEFAULT_PSC_CANDIDATE_COVERAGE_PATH = (
    REPO_ROOT / "internal_data" / "pinyin_source_db" / "psc_candidate_readings.json"
)
DEFAULT_WANXIANG_FILES = (
    "zi.dict.yaml",
    "jichu.dict.yaml",
    "lianxiang.dict.yaml",
    "duoyin.dict.yaml",
    "diming.dict.yaml",
    "fangyan.dict.yaml",
    "huaxue.dict.yaml",
    "mingren.dict.yaml",
    "renming.dict.yaml",
    "shici.dict.yaml",
    "taifeng.dict.yaml",
    "wuzhong.dict.yaml",
    "yaopin.dict.yaml",
    "yiren.dict.yaml",
    "yixue.dict.yaml",
)

BCC_CATEGORY_FILES = (
    ("modern_chinese", "modern_chinese_{kind}_freq.txt"),
    ("news", "news_total_{kind}_freq.txt"),
    ("dialogue", "dialogue_{kind}_freq.txt"),
    ("literature", "literature_{kind}_freq.txt"),
    ("classical_chinese", "classical_chinese_{kind}_freq.txt"),
    ("multi_domain", "multi_domain_total_{kind}_freq.txt"),
)
BCC_CATEGORY_COLUMNS = tuple(category for category, _ in BCC_CATEGORY_FILES)
GENERATED_BCC_FILENAMES = frozenset(
    {
        "merged_word_freq.txt",
        "merged_char_freq.txt",
        "word_freq_merged_single_char_freq.txt",
    }
)


@dataclass(frozen=True)
class CategorizedPath:
    category: str
    kind: str
    path: Path


@dataclass(frozen=True)
class BundleInputs:
    unihan: Path
    pypinyin_phrases: Path
    bcc_word_files: tuple[CategorizedPath, ...]
    bcc_char_files: tuple[CategorizedPath, ...]
    wanxiang_files: tuple[Path, ...]
    decoder_inventory: Path
    source_compliance_policy: Path = DEFAULT_SOURCE_COMPLIANCE_POLICY_PATH
    character_tier_sources: CharacterTierSources | None = None
    orthoepy_coverage: Path | None = None
    psc_candidate_coverage: Path | None = None


@dataclass(frozen=True)
class BundleResult:
    output_dir: Path
    database: Path
    entries: Path
    rejections: Path
    unencoded_pending_strings: Path
    unresolved_bcc: Path
    conflicts: Path
    character_tiers: Path
    manifest: Path
    accepted_readings: int
    output_entries: int
    unencoded_pending_string_count: int
    unresolved_bcc_count: int


def default_inputs(wanxiang_root: Path | None = None) -> BundleInputs:
    root = wanxiang_root or REPO_ROOT.parent / "RIME-LMDG"
    word_dir = REPO_ROOT / "external_data" / "word_freq"
    char_dir = REPO_ROOT / "external_data" / "char_freq"
    return BundleInputs(
        unihan=REPO_ROOT / "internal_data" / "hanzi_pinyin" / "pinyin.txt",
        pypinyin_phrases=REPO_ROOT / "internal_data" / "phrase_pinyin" / "phrase_pinyin.txt",
        bcc_word_files=tuple(
            CategorizedPath(category, "word", word_dir / pattern.format(kind="word"))
            for category, pattern in BCC_CATEGORY_FILES
        ),
        bcc_char_files=tuple(
            CategorizedPath(category, "char", char_dir / pattern.format(kind="char"))
            for category, pattern in BCC_CATEGORY_FILES
        ),
        wanxiang_files=tuple(root / "dicts" / name for name in DEFAULT_WANXIANG_FILES),
        decoder_inventory=REPO_ROOT / "yime" / "pinyin_normalized.json",
        source_compliance_policy=DEFAULT_SOURCE_COMPLIANCE_POLICY_PATH,
        character_tier_sources=CharacterTierSources(
            other_mappings=(
                REPO_ROOT
                / "external_data"
                / "unihan_readings"
                / "Unihan_OtherMappings.txt"
            ),
            readings=(
                REPO_ROOT
                / "external_data"
                / "unihan_readings"
                / "Unihan_Readings.txt"
            ),
            character_catalog_db=(
                REPO_ROOT
                / "internal_data"
                / "hanzi_pinyin"
                / "hanzi_pinyin.db"
            ),
            yinjie_codebook=REPO_ROOT / "syllable" / "codec" / "yinjie_code.json",
        ),
        orthoepy_coverage=DEFAULT_ORTHOEPY_COVERAGE_PATH,
        psc_candidate_coverage=DEFAULT_PSC_CANDIDATE_COVERAGE_PATH,
    )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        CREATE TABLE accepted_readings (
            text TEXT NOT NULL,
            marked TEXT NOT NULL,
            source_marked TEXT NOT NULL,
            numeric TEXT NOT NULL,
            source TEXT NOT NULL,
            source_category TEXT NOT NULL,
            source_file TEXT NOT NULL,
            source_rank INTEGER NOT NULL,
            source_weight INTEGER,
            source_primary INTEGER NOT NULL,
            rule_ids TEXT NOT NULL,
            pronunciation_scope TEXT NOT NULL,
            neutral_tone_positions TEXT NOT NULL,
            neutral_tone_status TEXT NOT NULL,
            PRIMARY KEY (text, marked, source, source_category, source_file)
        ) WITHOUT ROWID;
        CREATE INDEX accepted_text_idx ON accepted_readings(text);
        CREATE TABLE canonical_readings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            text_length INTEGER NOT NULL,
            codepoint TEXT,
            marked_pinyin TEXT NOT NULL,
            numeric_pinyin TEXT NOT NULL,
            reading_rank INTEGER NOT NULL,
            is_primary INTEGER NOT NULL CHECK (is_primary IN (0, 1)),
            bcc_frequency INTEGER NOT NULL,
            bcc_modern_chinese INTEGER,
            bcc_news INTEGER,
            bcc_dialogue INTEGER,
            bcc_literature INTEGER,
            bcc_classical_chinese INTEGER,
            bcc_multi_domain INTEGER,
            wanxiang_weight INTEGER NOT NULL,
            pinyin_sources TEXT NOT NULL,
            reading_source_categories TEXT NOT NULL,
            wanxiang_categories TEXT NOT NULL,
            rule_ids TEXT NOT NULL,
            pronunciation_scope TEXT NOT NULL,
            neutral_tone_positions TEXT NOT NULL,
            neutral_tone_status TEXT NOT NULL,
            UNIQUE (text, marked_pinyin)
        );
        CREATE INDEX canonical_text_rank_idx
            ON canonical_readings(text, reading_rank);
        CREATE INDEX canonical_numeric_idx
            ON canonical_readings(numeric_pinyin);
        CREATE INDEX canonical_primary_frequency_idx
            ON canonical_readings(is_primary, bcc_frequency DESC, text);
        CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        ) WITHOUT ROWID;
        CREATE TABLE source_files (
            source_kind TEXT PRIMARY KEY CHECK (source_kind IN ('char', 'phrase')),
            source_path TEXT NOT NULL,
            imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) WITHOUT ROWID;
        CREATE TABLE bcc_frequency (
            text TEXT PRIMARY KEY,
            frequency INTEGER NOT NULL,
            modern_chinese INTEGER,
            news INTEGER,
            dialogue INTEGER,
            literature INTEGER,
            classical_chinese INTEGER,
            multi_domain INTEGER
        ) WITHOUT ROWID;
        CREATE TABLE bcc_frequency_evidence (
            text TEXT NOT NULL,
            source_category TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            frequency INTEGER NOT NULL,
            source_file TEXT NOT NULL,
            PRIMARY KEY (text, source_category, source_kind, source_file)
        ) WITHOUT ROWID;
        CREATE INDEX bcc_evidence_category_frequency_idx
            ON bcc_frequency_evidence(source_category, frequency DESC, text);
        CREATE TABLE rejections (
            source TEXT NOT NULL,
            source_file TEXT NOT NULL,
            line_number INTEGER NOT NULL,
            text TEXT NOT NULL,
            reading TEXT NOT NULL,
            rule_ids TEXT NOT NULL,
            reason TEXT NOT NULL
        );
        CREATE TABLE unencoded_pending_strings (
            text TEXT PRIMARY KEY,
            text_length INTEGER NOT NULL,
            matched_codepoints TEXT NOT NULL,
            rule_ids TEXT NOT NULL,
            reason TEXT NOT NULL,
            bcc_frequency INTEGER NOT NULL DEFAULT 0
        ) WITHOUT ROWID;
        CREATE VIEW v_bcc_frequency_by_category AS
        SELECT text, frequency AS aggregate_frequency,
               modern_chinese, news, dialogue, literature,
               classical_chinese, multi_domain
        FROM bcc_frequency;
        CREATE VIEW v_reading_source_conflicts AS
        SELECT text, COUNT(DISTINCT marked) AS reading_count,
               GROUP_CONCAT(DISTINCT marked) AS marked_readings
        FROM accepted_readings
        GROUP BY text
        HAVING COUNT(DISTINCT marked) > 1;
        CREATE VIEW char_readings AS
        SELECT id, codepoint, text AS hanzi,
               marked_pinyin, numeric_pinyin, reading_rank, is_primary
        FROM canonical_readings
        WHERE text_length = 1 AND pronunciation_scope = 'standalone';
        CREATE VIEW phrase_readings AS
        SELECT id, text AS phrase, text_length AS phrase_len,
               marked_pinyin, numeric_pinyin, reading_rank
        FROM canonical_readings
        WHERE text_length > 1 AND is_primary = 1;
        CREATE VIEW phrase_candidate_readings AS
        SELECT candidate.id,
               primary_reading.id AS phrase_id,
               candidate.text AS phrase,
               candidate.text_length AS phrase_len,
               candidate.marked_pinyin,
               candidate.numeric_pinyin,
               candidate.reading_rank,
               candidate.is_primary,
               primary_reading.numeric_pinyin AS primary_numeric_pinyin,
               candidate.bcc_frequency,
               candidate.pinyin_sources,
               candidate.reading_source_categories,
               candidate.wanxiang_categories
        FROM canonical_readings AS candidate
        JOIN canonical_readings AS primary_reading
          ON primary_reading.text = candidate.text
         AND primary_reading.is_primary = 1
        WHERE candidate.text_length > 1
          AND (
              candidate.is_primary = 1
              OR instr(candidate.pinyin_sources, 'psc_orthoepy_') > 0
              OR instr(candidate.pinyin_sources, 'psc_candidate_coverage') > 0
          );
        """
    )
    create_character_tier_schema(conn)


def _load_unencoded_pending_characters(
    policy_path: Path,
) -> dict[str, tuple[str, str, str]]:
    policy = load_source_compliance_policy(policy_path)
    raw_entries = policy.get("unencoded_pending_codepoints", {})
    if not isinstance(raw_entries, dict):
        raise ValueError("unencoded_pending_codepoints must be an object")
    result: dict[str, tuple[str, str, str]] = {}
    for raw_codepoint, raw_record in raw_entries.items():
        codepoint = str(raw_codepoint).upper()
        record = dict(raw_record)
        if not codepoint.startswith("U+"):
            raise ValueError("unencoded pending codepoints must use U+ notation")
        character = str(record.get("character", ""))
        if len(character) != 1 or ord(character) != int(codepoint[2:], 16):
            raise ValueError(
                f"unencoded pending character does not match {codepoint}"
            )
        rule_id = str(record.get("rule_id", "")).strip()
        reason = str(record.get("reason", "")).strip()
        if not rule_id or not reason:
            raise ValueError(
                f"incomplete unencoded pending policy for {codepoint}"
            )
        result[character] = (codepoint, rule_id, reason)
    return result


def _record_unencoded_pending_string(
    conn: sqlite3.Connection,
    text: str,
    pending_characters: dict[str, tuple[str, str, str]],
) -> bool:
    hits = [
        pending_characters[character]
        for character in dict.fromkeys(text)
        if character in pending_characters
    ]
    if not hits:
        return False
    codepoints = ",".join(sorted({item[0] for item in hits}))
    rule_ids = ",".join(sorted({item[1] for item in hits}))
    reasons = "；".join(dict.fromkeys(item[2] for item in hits))
    conn.execute(
        """
        INSERT INTO unencoded_pending_strings (
            text, text_length, matched_codepoints, rule_ids, reason
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(text) DO UPDATE SET
            matched_codepoints = excluded.matched_codepoints,
            rule_ids = excluded.rule_ids,
            reason = excluded.reason
        """,
        (text, len(text), codepoints, rule_ids, reasons),
    )
    return True


def _import_readings(
    conn: sqlite3.Connection,
    gate: ReadingGate,
    records: Iterable[ReadingRecord],
    pending_characters: dict[str, tuple[str, str, str]],
) -> tuple[int, int]:
    accepted = rejected = 0
    for record in records:
        if _record_unencoded_pending_string(
            conn, record.text, pending_characters
        ):
            row = conn.execute(
                """
                SELECT rule_ids, reason
                FROM unencoded_pending_strings
                WHERE text = ?
                """,
                (record.text,),
            ).fetchone()
            conn.execute(
                "INSERT INTO rejections VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    record.source,
                    record.source_file,
                    record.line_number,
                    record.text,
                    record.reading,
                    str(row[0]),
                    "deferred_missing_trusted_mandarin_reading:" + str(row[1]),
                ),
            )
            rejected += 1
            continue
        result = gate.admit(
            record.text,
            record.reading,
            codepoint_context=record.codepoint_context,
            source=record.source,
        )
        if not result.accepted:
            conn.execute(
                "INSERT INTO rejections VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    record.source,
                    record.source_file,
                    record.line_number,
                    record.text,
                    record.reading,
                    ",".join(result.rule_ids),
                    result.reason,
                ),
            )
            rejected += 1
            continue
        conn.execute(
            """
            INSERT INTO accepted_readings VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(text, marked, source, source_category, source_file) DO UPDATE SET
                source_rank = MIN(source_rank, excluded.source_rank),
                source_weight = CASE
                    WHEN source_weight IS NULL THEN excluded.source_weight
                    WHEN excluded.source_weight IS NULL THEN source_weight
                    ELSE MAX(source_weight, excluded.source_weight)
                END,
                source_primary = MAX(source_primary, excluded.source_primary)
            """,
            (
                record.text,
                result.marked,
                record.reading,
                result.numeric,
                record.source,
                record.source_category,
                record.source_file,
                record.source_rank,
                record.source_weight,
                int(record.source_primary),
                ",".join(result.rule_ids),
                result.pronunciation_scope,
                ",".join(str(item) for item in result.neutral_tone_positions),
                result.neutral_tone_status,
            ),
        )
        accepted += 1
    conn.commit()
    return accepted, rejected


def _import_frequencies(
    conn: sqlite3.Connection,
    records: Iterable[FrequencyRecord],
    pending_characters: dict[str, tuple[str, str, str]],
) -> int:
    count = 0
    for record in records:
        if not is_han_text(record.text):
            continue
        if record.source_kind == "word" and len(record.text) < 2:
            continue
        if record.source_kind == "char" and len(record.text) != 1:
            continue
        if record.source_kind not in {"word", "char"}:
            raise ValueError(f"unknown BCC source kind: {record.source_kind}")
        if record.source_category not in BCC_CATEGORY_COLUMNS:
            raise ValueError(f"unknown BCC source category: {record.source_category}")
        conn.execute(
            """
            INSERT INTO bcc_frequency_evidence VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(text, source_category, source_kind, source_file) DO UPDATE SET
                frequency = MAX(frequency, excluded.frequency)
            """,
            (
                record.text,
                record.source_category,
                record.source_kind,
                record.frequency,
                record.source_file,
            ),
        )
        category_column = record.source_category
        conn.execute(
            f"""
            INSERT INTO bcc_frequency (text, frequency, {category_column})
            VALUES (?, ?, ?)
            ON CONFLICT(text) DO UPDATE SET
                frequency = MAX(frequency, excluded.frequency),
                {category_column} = CASE
                    WHEN {category_column} IS NULL THEN excluded.{category_column}
                    ELSE MAX({category_column}, excluded.{category_column})
                END
            """,
            (record.text, record.frequency, record.frequency),
        )
        _record_unencoded_pending_string(
            conn, record.text, pending_characters
        )
        count += 1
    conn.commit()
    return count


def _reading_groups(conn: sqlite3.Connection) -> Iterator[tuple[str, list[sqlite3.Row]]]:
    cursor = conn.execute(
        """
        SELECT a.*, COALESCE(f.frequency, 0) AS bcc_frequency,
               f.modern_chinese, f.news, f.dialogue, f.literature,
               f.classical_chinese, f.multi_domain
        FROM accepted_readings AS a
        LEFT JOIN bcc_frequency AS f USING (text)
        ORDER BY a.text, a.marked, a.source_rank, a.source
        """
    )
    current = ""
    rows: list[sqlite3.Row] = []
    for row in cursor:
        text = str(row["text"])
        if rows and text != current:
            yield current, rows
            rows = []
        current = text
        rows.append(row)
    if rows:
        yield current, rows


def _export_entries(conn: sqlite3.Connection, output_dir: Path) -> tuple[int, int]:
    entries_path = output_dir / "entries.tsv"
    conflicts_path = output_dir / "reading_conflicts.tsv"
    fields = [
        "text", "text_length", "pinyin_marked", "pinyin_numeric", "reading_rank",
        "is_primary", "bcc_frequency", "bcc_categories",
        "bcc_modern_chinese", "bcc_news", "bcc_dialogue", "bcc_literature",
        "bcc_classical_chinese", "bcc_multi_domain", "wanxiang_weight",
        "wanxiang_categories", "pinyin_sources", "reading_source_categories", "rule_ids",
        "pronunciation_scope", "neutral_tone_positions", "neutral_tone_status",
    ]
    output_count = conflict_count = 0
    conn.execute("DELETE FROM canonical_readings")
    canonical_batch: list[tuple[object, ...]] = []
    with entries_path.open("w", encoding="utf-8", newline="") as entries_stream, conflicts_path.open(
        "w", encoding="utf-8", newline=""
    ) as conflicts_stream:
        writer = csv.DictWriter(entries_stream, fieldnames=fields, delimiter="\t")
        conflict_writer = csv.DictWriter(conflicts_stream, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        conflict_writer.writeheader()
        for text, source_rows in _reading_groups(conn):
            readings: dict[str, list[sqlite3.Row]] = defaultdict(list)
            for source_row in source_rows:
                readings[str(source_row["marked"])].append(source_row)
            ranked = sorted(
                readings.items(),
                key=lambda item: (
                    min(int(row["source_rank"]) for row in item[1]),
                    -max(int(row["source_primary"]) for row in item[1]),
                    -max(int(row["source_weight"] or 0) for row in item[1]),
                    item[0],
                ),
            )
            for rank, (marked, rows) in enumerate(ranked, start=1):
                sources = sorted({str(row["source"]) for row in rows})
                source_categories = sorted(
                    {f'{row["source"]}:{row["source_category"]}' for row in rows}
                )
                wanxiang_categories = sorted(
                    {
                        str(row["source_category"])
                        for row in rows
                        if row["source"] == "wanxiang"
                    }
                )
                rules = sorted(
                    {rule for row in rows for rule in str(row["rule_ids"]).split(",") if rule}
                )
                pronunciation_scope = (
                    "standalone"
                    if any(str(row["pronunciation_scope"]) == "standalone" for row in rows)
                    else "word_context_only"
                )
                neutral_positions = sorted(
                    {
                        int(position)
                        for row in rows
                        for position in str(row["neutral_tone_positions"]).split(",")
                        if position
                    }
                )
                neutral_status = (
                    "attested_neutral"
                    if any(str(row["neutral_tone_status"]) == "attested_neutral" for row in rows)
                    else "unmarked_ambiguous"
                    if neutral_positions
                    else "none"
                )
                wanxiang_weight = max(
                    (int(row["source_weight"] or 0) for row in rows if row["source"] == "wanxiang"),
                    default=0,
                )
                bcc_categories = [
                    category
                    for category in BCC_CATEGORY_COLUMNS
                    if rows[0][category] is not None
                ]
                exported = {
                    "text": text,
                    "text_length": len(text),
                    "pinyin_marked": marked,
                    "pinyin_numeric": str(rows[0]["numeric"]),
                    "reading_rank": rank,
                    "is_primary": int(rank == 1),
                    "bcc_frequency": int(rows[0]["bcc_frequency"]),
                    "bcc_categories": ",".join(bcc_categories),
                    "bcc_modern_chinese": rows[0]["modern_chinese"],
                    "bcc_news": rows[0]["news"],
                    "bcc_dialogue": rows[0]["dialogue"],
                    "bcc_literature": rows[0]["literature"],
                    "bcc_classical_chinese": rows[0]["classical_chinese"],
                    "bcc_multi_domain": rows[0]["multi_domain"],
                    "wanxiang_weight": wanxiang_weight,
                    "wanxiang_categories": ",".join(wanxiang_categories),
                    "pinyin_sources": ",".join(sources),
                    "reading_source_categories": ",".join(source_categories),
                    "rule_ids": ",".join(rules),
                    "pronunciation_scope": pronunciation_scope,
                    "neutral_tone_positions": ",".join(str(item) for item in neutral_positions),
                    "neutral_tone_status": neutral_status,
                }
                writer.writerow(exported)
                canonical_batch.append(
                    (
                        text,
                        len(text),
                        f"U+{ord(text):04X}" if len(text) == 1 else None,
                        marked,
                        str(rows[0]["numeric"]),
                        rank,
                        int(rank == 1),
                        int(rows[0]["bcc_frequency"]),
                        rows[0]["modern_chinese"],
                        rows[0]["news"],
                        rows[0]["dialogue"],
                        rows[0]["literature"],
                        rows[0]["classical_chinese"],
                        rows[0]["multi_domain"],
                        wanxiang_weight,
                        ",".join(sources),
                        ",".join(source_categories),
                        ",".join(wanxiang_categories),
                        ",".join(rules),
                        pronunciation_scope,
                        ",".join(str(item) for item in neutral_positions),
                        neutral_status,
                    )
                )
                if len(canonical_batch) >= 10_000:
                    conn.executemany(
                        """
                        INSERT INTO canonical_readings (
                            text, text_length, codepoint, marked_pinyin, numeric_pinyin,
                            reading_rank, is_primary, bcc_frequency,
                            bcc_modern_chinese, bcc_news, bcc_dialogue, bcc_literature,
                            bcc_classical_chinese, bcc_multi_domain, wanxiang_weight,
                            pinyin_sources, reading_source_categories,
                            wanxiang_categories, rule_ids, pronunciation_scope,
                            neutral_tone_positions, neutral_tone_status
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        canonical_batch,
                    )
                    canonical_batch.clear()
                if len(ranked) > 1:
                    conflict_writer.writerow(exported)
                    conflict_count += 1
                output_count += 1
        if canonical_batch:
            conn.executemany(
                """
                INSERT INTO canonical_readings (
                    text, text_length, codepoint, marked_pinyin, numeric_pinyin,
                    reading_rank, is_primary, bcc_frequency,
                    bcc_modern_chinese, bcc_news, bcc_dialogue, bcc_literature,
                    bcc_classical_chinese, bcc_multi_domain, wanxiang_weight,
                    pinyin_sources, reading_source_categories,
                    wanxiang_categories, rule_ids, pronunciation_scope,
                    neutral_tone_positions, neutral_tone_status
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                canonical_batch,
            )
    conn.commit()
    return output_count, conflict_count


def _export_rejections(conn: sqlite3.Connection, output_dir: Path) -> int:
    path = output_dir / "rejected_readings.tsv"
    fields = ["source", "source_file", "line_number", "text", "reading", "rule_ids", "reason"]
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(fields)
        count = 0
        for row in conn.execute(
            "SELECT source, source_file, line_number, text, reading, rule_ids, reason FROM rejections ORDER BY source, source_file, line_number"
        ):
            writer.writerow(tuple(row))
            count += 1
    return count


def _finalize_unencoded_pending_strings(conn: sqlite3.Connection) -> int:
    conn.execute(
        """
        UPDATE unencoded_pending_strings
        SET bcc_frequency = COALESCE(
            (
                SELECT frequency
                FROM bcc_frequency AS f
                WHERE f.text = unencoded_pending_strings.text
            ),
            0
        )
        """
    )
    conn.commit()
    return int(
        conn.execute(
            "SELECT COUNT(*) FROM unencoded_pending_strings"
        ).fetchone()[0]
    )


def _export_unencoded_pending_strings(
    conn: sqlite3.Connection,
    output_dir: Path,
) -> int:
    path = output_dir / "unencoded_pending_strings.tsv"
    fields = (
        "text",
        "text_length",
        "matched_codepoints",
        "bcc_frequency",
        "rule_ids",
        "reason",
    )
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(fields)
        rows = conn.execute(
            """
            SELECT text, text_length, matched_codepoints, bcc_frequency,
                   rule_ids, reason
            FROM unencoded_pending_strings
            ORDER BY bcc_frequency DESC, text
            """
        ).fetchall()
        writer.writerows(rows)
    return len(rows)


def _export_unresolved_bcc(conn: sqlite3.Connection, output_dir: Path) -> int:
    path = output_dir / "unresolved_bcc.tsv"
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("text", "text_length", "bcc_frequency", "reason"))
        count = 0
        for text, frequency in conn.execute(
            """
            SELECT f.text, f.frequency
            FROM bcc_frequency AS f
            WHERE NOT EXISTS (
                SELECT 1 FROM accepted_readings AS a WHERE a.text = f.text
            )
              AND NOT EXISTS (
                SELECT 1
                FROM unencoded_pending_strings AS n
                WHERE n.text = f.text
            )
            ORDER BY f.frequency DESC, f.text
            """
        ):
            writer.writerow((text, len(str(text)), frequency, "no_gated_reading_source"))
            count += 1
    return count


def build_bundle(inputs: BundleInputs, output_dir: Path) -> BundleResult:
    categorized_bcc = (*inputs.bcc_word_files, *inputs.bcc_char_files)
    generated_bcc_inputs = [
        str(item.path)
        for item in categorized_bcc
        if item.path.name in GENERATED_BCC_FILENAMES
    ]
    if generated_bcc_inputs:
        raise ValueError(
            "generated/secondary BCC files cannot be source evidence: "
            + "; ".join(generated_bcc_inputs)
        )
    invalid_bcc_kinds = [
        f"{item.path}:{item.kind}"
        for item in categorized_bcc
        if item.kind not in {"word", "char"}
    ]
    if invalid_bcc_kinds:
        raise ValueError("invalid BCC source kinds: " + "; ".join(invalid_bcc_kinds))
    bcc_files = tuple(item.path for item in categorized_bcc)
    tier_source_paths = (
        inputs.character_tier_sources.paths()
        if inputs.character_tier_sources is not None
        else ()
    )
    optional_reading_sources = (
        (inputs.orthoepy_coverage,) if inputs.orthoepy_coverage is not None else ()
    ) + (
        (inputs.psc_candidate_coverage,)
        if inputs.psc_candidate_coverage is not None
        else ()
    )
    source_paths = (
        inputs.unihan,
        inputs.pypinyin_phrases,
        inputs.source_compliance_policy,
        *optional_reading_sources,
        DEFAULT_ADMISSION_PATH,
        DEFAULT_NEUTRAL_SOURCE_POLICY_PATH,
        *bcc_files,
        inputs.decoder_inventory,
        *inputs.wanxiang_files,
        *tier_source_paths,
    )
    missing = [str(path) for path in source_paths if not path.is_file()]
    if missing:
        raise FileNotFoundError("missing lexicon bundle inputs: " + "; ".join(missing))

    output_dir.mkdir(parents=True, exist_ok=True)
    database = output_dir / "source_lexicon.sqlite3"
    if database.exists():
        database.unlink()
    conn = sqlite3.connect(database)
    conn.row_factory = sqlite3.Row
    _create_schema(conn)
    gate = ReadingGate(
        inputs.decoder_inventory,
        source_compliance_policy_path=inputs.source_compliance_policy,
    )
    pending_characters = _load_unencoded_pending_characters(
        inputs.source_compliance_policy
    )

    source_stats: dict[str, dict[str, int]] = {}
    accepted_total = 0
    reading_sources: list[tuple[str, Iterable[ReadingRecord]]] = [
        ("unihan", iter_unihan_readings(inputs.unihan)),
        ("pypinyin", iter_pypinyin_phrase_readings(inputs.pypinyin_phrases)),
    ]
    if inputs.orthoepy_coverage is not None:
        reading_sources.append(
            (
                "psc_orthoepy",
                iter_reviewed_orthoepy_readings(inputs.orthoepy_coverage),
            )
        )
    if inputs.psc_candidate_coverage is not None:
        reading_sources.append(
            (
                "psc_candidate_coverage",
                iter_reviewed_psc_candidate_readings(
                    inputs.psc_candidate_coverage
                ),
            )
        )
    for name, records in reading_sources:
        accepted, rejected = _import_readings(
            conn, gate, records, pending_characters
        )
        source_stats[name] = {"accepted": accepted, "rejected": rejected}
        accepted_total += accepted

    wanxiang_accepted = wanxiang_rejected = 0
    for path in inputs.wanxiang_files:
        accepted, rejected = _import_readings(
            conn,
            gate,
            iter_wanxiang_readings(path),
            pending_characters,
        )
        wanxiang_accepted += accepted
        wanxiang_rejected += rejected
    source_stats["wanxiang"] = {
        "accepted": wanxiang_accepted,
        "rejected": wanxiang_rejected,
    }
    accepted_total += wanxiang_accepted

    bcc_rows = 0
    for categorized in categorized_bcc:
        bcc_rows += _import_frequencies(
            conn,
            iter_bcc_frequencies(
                categorized.path,
                source_category=categorized.category,
                source_kind=categorized.kind,
            ),
            pending_characters,
        )

    pending_count = _finalize_unencoded_pending_strings(conn)
    output_entries, conflict_rows = _export_entries(conn, output_dir)
    character_tier_counts: dict[str, int] = {}
    character_tier_rows = 0
    character_tiers_path = output_dir / "character_tiers.tsv"
    if inputs.character_tier_sources is not None:
        character_tier_counts = rebuild_character_tiers(
            conn,
            inputs.character_tier_sources,
        )
    character_tier_rows = export_character_tiers(
        conn,
        character_tiers_path,
    )
    rejected_rows = _export_rejections(conn, output_dir)
    exported_pending_count = _export_unencoded_pending_strings(conn, output_dir)
    if exported_pending_count != pending_count:
        raise RuntimeError("unencoded pending string export count mismatch")
    unresolved_count = _export_unresolved_bcc(conn, output_dir)
    unique_bcc = int(conn.execute("SELECT COUNT(*) FROM bcc_frequency").fetchone()[0])
    unique_texts = int(conn.execute("SELECT COUNT(DISTINCT text) FROM accepted_readings").fetchone()[0])
    conn.executemany(
        "INSERT INTO source_files (source_kind, source_path) VALUES (?, ?)",
        (("char", str(database)), ("phrase", str(database))),
    )
    conn.executemany(
        "INSERT INTO metadata (key, value) VALUES (?, ?)",
        (
            ("schema_version", "yime-gated-source-lexicon-v5"),
            ("char_rows", str(conn.execute("SELECT COUNT(*) FROM char_readings").fetchone()[0])),
            ("phrase_rows", str(conn.execute("SELECT COUNT(*) FROM phrase_readings").fetchone()[0])),
            ("canonical_reading_rows", str(output_entries)),
            ("source_role", "canonical_lexicon_and_encoding_source"),
        ),
    )
    conn.commit()
    conn.close()

    manifest_path = output_dir / "manifest.json"
    manifest = {
        "schema_version": "yime-gated-source-lexicon-v5",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "policy": {
            "frequency": "BCC integer counts are preserved; absent BCC evidence remains 0.",
            "bcc_categories": "Domain counts remain separate; aggregate frequency is their maximum.",
            "bcc_source_boundary": (
                "Only original domain downloads are accepted; word channels contribute multi-character terms, "
                "char channels contribute single characters, and generated merged/derived files are rejected."
            ),
            "wanxiang_weight": "Kept separately; never treated as a BCC count.",
            "wanxiang_categories": "Original dictionary categories are preserved from file names.",
            "reading": (
                "Shared first-round source compliance, reviewed non-neutral admissions, "
                "source-specific unmarked-tone interpretation, and current decoder inventory."
            ),
            "orthoepy_coverage": (
                "Reviewed orthoepy records add missing text-reading coverage only; "
                "they are never source-primary and never delete or rerank existing readings."
            ),
            "psc_candidate_coverage": (
                "Reviewed PSC transcription pairs absent from current runtime candidates "
                "are imported as non-primary candidate coverage with source evidence; "
                "pending non-aligned records remain outside the runtime lexicon."
            ),
            "unresolved": "No per-character pronunciation guessing for unmatched BCC terms.",
            "unencoded_pending": (
                "Strings containing a codepoint without a trusted Mandarin "
                "reading source remain unencoded and deferred for expert or "
                "future source review."
            ),
            "excluded_wanxiang_files": ["cuoyin.dict.yaml", "mixed.dict.yaml"],
        },
        "counts": {
            "accepted_source_rows": accepted_total,
            "unique_accepted_texts": unique_texts,
            "output_text_readings": output_entries,
            "reading_conflict_rows": conflict_rows,
            "rejected_source_rows": rejected_rows,
            "unencoded_pending_strings": pending_count,
            "bcc_input_rows": bcc_rows,
            "unique_bcc_texts": unique_bcc,
            "unresolved_bcc_texts": unresolved_count,
            "character_tier_rows": character_tier_rows,
            "character_tiers": character_tier_counts,
        },
        "sources": [
            {"path": str(path), "sha256": _sha256(path), "bytes": path.stat().st_size}
            for path in source_paths
        ],
        "source_gate_counts": source_stats,
        "outputs": {
            "entries": "entries.tsv",
            "rejected_readings": "rejected_readings.tsv",
            "unencoded_pending_strings": "unencoded_pending_strings.tsv",
            "unresolved_bcc": "unresolved_bcc.tsv",
            "reading_conflicts": "reading_conflicts.tsv",
            "character_tiers": "character_tiers.tsv",
            "database": "source_lexicon.sqlite3",
        },
    }
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return BundleResult(
        output_dir=output_dir,
        database=database,
        entries=output_dir / "entries.tsv",
        rejections=output_dir / "rejected_readings.tsv",
        unencoded_pending_strings=output_dir / "unencoded_pending_strings.tsv",
        unresolved_bcc=output_dir / "unresolved_bcc.tsv",
        conflicts=output_dir / "reading_conflicts.tsv",
        character_tiers=character_tiers_path,
        manifest=manifest_path,
        accepted_readings=accepted_total,
        output_entries=output_entries,
        unencoded_pending_string_count=pending_count,
        unresolved_bcc_count=unresolved_count,
    )
