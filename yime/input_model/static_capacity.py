"""Plan a compact static lexicon without deleting source evidence.

The planner is deliberately narrower than a general-purpose segmenter.  It asks
whether an attested ``text + numeric pinyin`` reading can be reconstructed from
shorter attested readings, then proposes a static capacity frontier.  Runtime
ranking and real-input replay remain separate promotion gates.
"""

from __future__ import annotations

import csv
import json
import math
import os
import sqlite3
from dataclasses import dataclass
from functools import lru_cache
from itertools import groupby
from pathlib import Path
from typing import Iterable


SCHEMA_VERSION = "yime-static-lexicon-capacity-v1"


@dataclass(frozen=True)
class StaticCapacityConfig:
    maximum_parts: int = 6
    maximum_alternatives: int = 4
    target_direct_frequency_coverage: float = 0.98
    target_capacity: int | None = None

    def validate(self) -> None:
        if self.maximum_parts < 2:
            raise ValueError("maximum_parts must be at least 2")
        if self.maximum_alternatives < 1:
            raise ValueError("maximum_alternatives must be positive")
        if not 0 < self.target_direct_frequency_coverage <= 1:
            raise ValueError(
                "target_direct_frequency_coverage must be in (0, 1]"
            )
        if self.target_capacity is not None and self.target_capacity < 1:
            raise ValueError("target_capacity must be positive")


@dataclass(frozen=True)
class StaticCapacityResult:
    output_dir: Path
    database: Path
    items_tsv: Path
    frontier_tsv: Path
    summary_markdown: Path
    manifest: Path
    encoded_texts: int
    mandatory_static_texts: int
    dynamically_recoverable_texts: int
    recommended_static_capacity: int


SCHEMA = """
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
CREATE TABLE metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;
CREATE TABLE reading_analysis (
    text TEXT NOT NULL,
    numeric_pinyin TEXT NOT NULL,
    is_primary INTEGER NOT NULL CHECK (is_primary IN (0, 1)),
    text_length INTEGER NOT NULL,
    bcc_frequency INTEGER NOT NULL,
    pinyin_sources TEXT NOT NULL,
    pronunciation_scope TEXT NOT NULL,
    neutral_tone_status TEXT NOT NULL,
    recoverability_status TEXT NOT NULL,
    mandatory_reason TEXT NOT NULL,
    best_decomposition_json TEXT NOT NULL,
    alternative_count INTEGER NOT NULL,
    direct_part_count INTEGER NOT NULL,
    PRIMARY KEY (text, numeric_pinyin)
) WITHOUT ROWID;
CREATE INDEX reading_status_idx
    ON reading_analysis(recoverability_status, bcc_frequency DESC, text);
CREATE TABLE component_usage (
    text TEXT PRIMARY KEY,
    dependent_reading_count INTEGER NOT NULL,
    dependent_frequency INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TABLE static_capacity_items (
    text TEXT PRIMARY KEY,
    text_length INTEGER NOT NULL,
    bcc_frequency INTEGER NOT NULL,
    reading_count INTEGER NOT NULL,
    recoverable_reading_count INTEGER NOT NULL,
    mandatory_static INTEGER NOT NULL CHECK (mandatory_static IN (0, 1)),
    mandatory_reasons TEXT NOT NULL,
    representative_decomposition_json TEXT NOT NULL,
    dependent_reading_count INTEGER NOT NULL DEFAULT 0,
    dependent_frequency INTEGER NOT NULL DEFAULT 0,
    utility_score REAL NOT NULL DEFAULT 0,
    recommended_disposition TEXT NOT NULL DEFAULT 'unplanned'
) WITHOUT ROWID;
CREATE INDEX static_capacity_utility_idx
    ON static_capacity_items(
        mandatory_static DESC, utility_score DESC, bcc_frequency DESC, text
    );
CREATE TABLE optional_static_rank (
    selection_rank INTEGER PRIMARY KEY,
    text TEXT NOT NULL UNIQUE,
    bcc_frequency INTEGER NOT NULL,
    cumulative_frequency INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TABLE capacity_frontier (
    static_capacity INTEGER PRIMARY KEY,
    mandatory_static_texts INTEGER NOT NULL,
    selected_optional_texts INTEGER NOT NULL,
    migration_candidate_texts INTEGER NOT NULL,
    direct_bcc_frequency INTEGER NOT NULL,
    total_bcc_frequency INTEGER NOT NULL,
    direct_frequency_coverage REAL NOT NULL,
    proxy_only INTEGER NOT NULL CHECK (proxy_only IN (0, 1))
) WITHOUT ROWID;
"""


def _reading_tokens(numeric: str) -> tuple[str, ...]:
    return tuple(token for token in numeric.split() if token)


class _ReadingLookup:
    def __init__(self, connection: sqlite3.Connection) -> None:
        self.connection = connection

    @lru_cache(maxsize=500_000)
    def has(self, text: str, numeric: str) -> bool:
        row = self.connection.execute(
            """
            SELECT 1
            FROM canonical_readings
            WHERE text = ?
              AND numeric_pinyin = ?
              AND (LENGTH(text) > 1 OR pronunciation_scope = 'standalone')
            LIMIT 1
            """,
            (text, numeric),
        ).fetchone()
        return row is not None


def _best_decompositions(
    *,
    text: str,
    tokens: tuple[str, ...],
    lookup: _ReadingLookup,
    maximum_parts: int,
    maximum_alternatives: int,
) -> tuple[tuple[str, ...], ...]:
    if len(text) < 2 or len(tokens) != len(text):
        return ()

    memo: dict[int, tuple[tuple[str, ...], ...]] = {}

    def visit(offset: int) -> tuple[tuple[str, ...], ...]:
        if offset == len(text):
            return ((),)
        if offset in memo:
            return memo[offset]
        candidates: list[tuple[str, ...]] = []
        for end in range(len(text), offset, -1):
            if offset == 0 and end == len(text):
                continue
            part = text[offset:end]
            numeric = " ".join(tokens[offset:end])
            if not lookup.has(part, numeric):
                continue
            for suffix in visit(end):
                candidate = (part, *suffix)
                if len(candidate) <= maximum_parts:
                    candidates.append(candidate)
        if not candidates:
            memo[offset] = ()
            return ()
        minimum = min(len(candidate) for candidate in candidates)
        best = {
            candidate for candidate in candidates if len(candidate) == minimum
        }
        ordered = sorted(
            best,
            key=lambda parts: (
                tuple(-len(part) for part in parts),
                parts,
            ),
        )[:maximum_alternatives]
        memo[offset] = tuple(ordered)
        return memo[offset]

    return visit(0)


def _source_rows(connection: sqlite3.Connection) -> Iterable[sqlite3.Row]:
    return connection.execute(
        """
        SELECT text, numeric_pinyin, is_primary, LENGTH(text) AS text_length,
               bcc_frequency, pinyin_sources,
               COALESCE(pronunciation_scope, 'standalone') AS pronunciation_scope,
               COALESCE(neutral_tone_status, 'none') AS neutral_tone_status
        FROM canonical_readings
        WHERE LENGTH(text) > 1 OR pronunciation_scope = 'standalone'
        ORDER BY text, reading_rank
        """
    )


def _flush_component_usage(
    connection: sqlite3.Connection,
    usage: dict[str, tuple[int, int]],
) -> None:
    if not usage:
        return
    connection.executemany(
        """
        INSERT INTO component_usage(
            text, dependent_reading_count, dependent_frequency
        ) VALUES (?, ?, ?)
        ON CONFLICT(text) DO UPDATE SET
            dependent_reading_count =
                component_usage.dependent_reading_count
                + excluded.dependent_reading_count,
            dependent_frequency =
                component_usage.dependent_frequency
                + excluded.dependent_frequency
        """,
        (
            (text, values[0], values[1])
            for text, values in usage.items()
        ),
    )
    usage.clear()


def _utility_score(
    *,
    text_length: int,
    bcc_frequency: int,
    dependent_reading_count: int,
    dependent_frequency: int,
) -> float:
    # This is a transparent capacity-ranking proxy, not a lexical truth score.
    return (
        math.log1p(max(0, bcc_frequency))
        + 0.70 * math.log1p(max(0, dependent_frequency))
        + 0.30 * math.log1p(max(0, dependent_reading_count))
        + 1.0 / max(1, text_length)
    )


def _frontier_capacities(
    *,
    mandatory: int,
    total: int,
    recommended: int,
    requested: int | None,
) -> tuple[int, ...]:
    values = {
        mandatory,
        recommended,
        total,
        *(
            min(total, mandatory + increment)
            for increment in (
                10_000,
                25_000,
                50_000,
                100_000,
                200_000,
                500_000,
                1_000_000,
            )
        ),
    }
    if requested is not None:
        values.add(min(total, max(mandatory, requested)))
    return tuple(sorted(value for value in values if mandatory <= value <= total))


def _export_items(connection: sqlite3.Connection, path: Path) -> None:
    fields = (
        "text",
        "text_length",
        "bcc_frequency",
        "reading_count",
        "recoverable_reading_count",
        "mandatory_static",
        "mandatory_reasons",
        "representative_decomposition_json",
        "dependent_reading_count",
        "dependent_frequency",
        "utility_score",
        "recommended_disposition",
    )
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(fields)
        writer.writerows(
            connection.execute(
                f"""
                SELECT {", ".join(fields)}
                FROM static_capacity_items
                ORDER BY
                    mandatory_static DESC,
                    utility_score DESC,
                    bcc_frequency DESC,
                    text
                """
            )
        )


def _export_frontier(connection: sqlite3.Connection, path: Path) -> None:
    fields = (
        "static_capacity",
        "mandatory_static_texts",
        "selected_optional_texts",
        "migration_candidate_texts",
        "direct_bcc_frequency",
        "total_bcc_frequency",
        "direct_frequency_coverage",
        "proxy_only",
    )
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(fields)
        writer.writerows(
            connection.execute(
                f"""
                SELECT {", ".join(fields)}
                FROM capacity_frontier
                ORDER BY static_capacity
                """
            )
        )


def build_static_capacity_model(
    *,
    source_database: Path,
    output_dir: Path,
    config: StaticCapacityConfig = StaticCapacityConfig(),
) -> StaticCapacityResult:
    """Build a read-only-source static lexicon capacity proposal."""

    config.validate()
    source_database = source_database.resolve()
    if not source_database.is_file():
        raise FileNotFoundError(source_database)
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    database = output_dir / "static_capacity.sqlite3"
    temporary_database = output_dir / "static_capacity.sqlite3.next"
    if temporary_database.exists():
        temporary_database.unlink()

    source = sqlite3.connect(
        f"file:{source_database.as_posix()}?mode=ro",
        uri=True,
    )
    source.row_factory = sqlite3.Row
    source.execute("PRAGMA query_only = ON")
    output = sqlite3.connect(temporary_database)
    output.row_factory = sqlite3.Row
    output.executescript(SCHEMA)
    lookup = _ReadingLookup(source)
    usage: dict[str, tuple[int, int]] = {}

    reading_batch: list[tuple[object, ...]] = []
    item_batch: list[tuple[object, ...]] = []
    for text, grouped_rows in groupby(_source_rows(source), key=lambda row: str(row["text"])):
        rows = list(grouped_rows)
        reading_results: list[dict[str, object]] = []
        for row in rows:
            numeric = str(row["numeric_pinyin"])
            tokens = _reading_tokens(numeric)
            alternatives = _best_decompositions(
                text=text,
                tokens=tokens,
                lookup=lookup,
                maximum_parts=config.maximum_parts,
                maximum_alternatives=config.maximum_alternatives,
            )
            if len(text) == 1:
                status = "mandatory_static"
                reason = "single_character_foundation"
            elif len(tokens) != len(text):
                status = "mandatory_static"
                reason = "syllable_alignment_mismatch"
            elif alternatives:
                status = "dynamically_recoverable"
                reason = ""
            else:
                status = "mandatory_static"
                reason = "no_shorter_attested_reading_decomposition"
            best = alternatives[0] if alternatives else ()
            reading_results.append(
                {
                    "status": status,
                    "reason": reason,
                    "best": best,
                    "is_primary": bool(row["is_primary"]),
                }
            )
            reading_batch.append(
                (
                    text,
                    numeric,
                    int(row["is_primary"]),
                    len(text),
                    int(row["bcc_frequency"]),
                    str(row["pinyin_sources"] or ""),
                    str(row["pronunciation_scope"]),
                    str(row["neutral_tone_status"]),
                    status,
                    reason,
                    json.dumps(alternatives, ensure_ascii=False),
                    len(alternatives),
                    len(best),
                )
            )
            if best:
                for part in best:
                    count, frequency = usage.get(part, (0, 0))
                    usage[part] = (
                        count + 1,
                        frequency + int(row["bcc_frequency"]),
                    )
            if len(reading_batch) >= 20_000:
                output.executemany(
                    """
                    INSERT INTO reading_analysis VALUES (
                        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                    )
                    """,
                    reading_batch,
                )
                reading_batch.clear()
            if len(usage) >= 50_000:
                _flush_component_usage(output, usage)

        mandatory_reasons = sorted(
            {
                str(result["reason"])
                for result in reading_results
                if result["status"] == "mandatory_static"
            }
        )
        representative = next(
            (
                result["best"]
                for result in reading_results
                if result["is_primary"] and result["best"]
            ),
            next(
                (
                    result["best"]
                    for result in reading_results
                    if result["best"]
                ),
                (),
            ),
        )
        item_batch.append(
            (
                text,
                len(text),
                max(int(row["bcc_frequency"]) for row in rows),
                len(rows),
                sum(
                    result["status"] == "dynamically_recoverable"
                    for result in reading_results
                ),
                int(bool(mandatory_reasons)),
                ",".join(mandatory_reasons),
                json.dumps(representative, ensure_ascii=False),
            )
        )
        if len(item_batch) >= 20_000:
            output.executemany(
                """
                INSERT INTO static_capacity_items(
                    text, text_length, bcc_frequency, reading_count,
                    recoverable_reading_count, mandatory_static,
                    mandatory_reasons, representative_decomposition_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                item_batch,
            )
            item_batch.clear()

    if reading_batch:
        output.executemany(
            "INSERT INTO reading_analysis VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            reading_batch,
        )
    if item_batch:
        output.executemany(
            """
            INSERT INTO static_capacity_items(
                text, text_length, bcc_frequency, reading_count,
                recoverable_reading_count, mandatory_static,
                mandatory_reasons, representative_decomposition_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            item_batch,
        )
    _flush_component_usage(output, usage)
    output.execute(
        """
        UPDATE static_capacity_items
        SET dependent_reading_count = COALESCE(
                (SELECT dependent_reading_count FROM component_usage AS usage
                 WHERE usage.text = static_capacity_items.text),
                0
            ),
            dependent_frequency = COALESCE(
                (SELECT dependent_frequency FROM component_usage AS usage
                 WHERE usage.text = static_capacity_items.text),
                0
            )
        """
    )

    utility_updates = []
    for row in output.execute(
        """
        SELECT text, text_length, bcc_frequency,
               dependent_reading_count, dependent_frequency
        FROM static_capacity_items
        """
    ):
        utility_updates.append(
            (
                _utility_score(
                    text_length=int(row["text_length"]),
                    bcc_frequency=int(row["bcc_frequency"]),
                    dependent_reading_count=int(row["dependent_reading_count"]),
                    dependent_frequency=int(row["dependent_frequency"]),
                ),
                str(row["text"]),
            )
        )
        if len(utility_updates) >= 50_000:
            output.executemany(
                "UPDATE static_capacity_items SET utility_score = ? WHERE text = ?",
                utility_updates,
            )
            utility_updates.clear()
    if utility_updates:
        output.executemany(
            "UPDATE static_capacity_items SET utility_score = ? WHERE text = ?",
            utility_updates,
        )

    total_texts = int(
        output.execute("SELECT COUNT(*) FROM static_capacity_items").fetchone()[0]
    )
    mandatory = int(
        output.execute(
            "SELECT COUNT(*) FROM static_capacity_items WHERE mandatory_static = 1"
        ).fetchone()[0]
    )
    total_frequency = int(
        output.execute(
            "SELECT COALESCE(SUM(bcc_frequency), 0) FROM static_capacity_items"
        ).fetchone()[0]
    )
    mandatory_frequency = int(
        output.execute(
            """
            SELECT COALESCE(SUM(bcc_frequency), 0)
            FROM static_capacity_items
            WHERE mandatory_static = 1
            """
        ).fetchone()[0]
    )
    output.execute(
        """
        INSERT INTO optional_static_rank(
            selection_rank, text, bcc_frequency, cumulative_frequency
        )
        SELECT
            ROW_NUMBER() OVER (
                ORDER BY utility_score DESC, bcc_frequency DESC, text
            ),
            text,
            bcc_frequency,
            SUM(bcc_frequency) OVER (
                ORDER BY utility_score DESC, bcc_frequency DESC, text
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )
        FROM static_capacity_items
        WHERE mandatory_static = 0
        """
    )
    required_frequency = (
        config.target_direct_frequency_coverage * total_frequency
    )
    if mandatory_frequency >= required_frequency:
        recommended_optional = 0
    else:
        recommendation_row = output.execute(
            """
            SELECT MIN(selection_rank)
            FROM optional_static_rank
            WHERE cumulative_frequency + ? >= ?
            """,
            (mandatory_frequency, required_frequency),
        ).fetchone()
        recommended_optional = int(
            recommendation_row[0]
            if recommendation_row is not None
            and recommendation_row[0] is not None
            else total_texts - mandatory
        )
    recommended = min(total_texts, mandatory + recommended_optional)
    if config.target_capacity is not None:
        recommended = min(
            total_texts,
            max(mandatory, config.target_capacity),
        )

    output.execute(
        """
        UPDATE static_capacity_items
        SET recommended_disposition = CASE
            WHEN mandatory_static = 1 THEN 'mandatory_static'
            ELSE 'dynamic_migration_candidate'
        END
        """
    )
    selected_optional = max(0, recommended - mandatory)
    if selected_optional:
        output.execute(
            """
            UPDATE static_capacity_items
            SET recommended_disposition = 'selected_static'
            WHERE text IN (
                SELECT text
                FROM optional_static_rank
                WHERE selection_rank <= ?
            )
            """,
            (selected_optional,),
        )

    frontier_rows = []
    for capacity in _frontier_capacities(
        mandatory=mandatory,
        total=total_texts,
        recommended=recommended,
        requested=config.target_capacity,
    ):
        optional_count = capacity - mandatory
        optional_frequency = (
            int(
                output.execute(
                    """
                    SELECT cumulative_frequency
                    FROM optional_static_rank
                    WHERE selection_rank = ?
                    """,
                    (optional_count,),
                ).fetchone()[0]
            )
            if optional_count
            else 0
        )
        direct_frequency = mandatory_frequency + optional_frequency
        coverage = (
            direct_frequency / total_frequency if total_frequency else 1.0
        )
        frontier_rows.append(
            (
                capacity,
                mandatory,
                optional_count,
                total_texts - capacity,
                direct_frequency,
                total_frequency,
                coverage,
                1,
            )
        )
    output.executemany(
        "INSERT INTO capacity_frontier VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        frontier_rows,
    )
    metadata = {
        "schema_version": SCHEMA_VERSION,
        "source_database": str(source_database),
        "maximum_parts": str(config.maximum_parts),
        "maximum_alternatives": str(config.maximum_alternatives),
        "target_direct_frequency_coverage": str(
            config.target_direct_frequency_coverage
        ),
        "recommended_static_capacity": str(recommended),
        "proxy_only": "1",
        "runtime_replay_required": "1",
    }
    output.executemany(
        "INSERT INTO metadata(key, value) VALUES (?, ?)",
        metadata.items(),
    )
    output.commit()
    source.close()
    output.close()
    os.replace(temporary_database, database)

    with sqlite3.connect(database) as report:
        report.row_factory = sqlite3.Row
        items_tsv = output_dir / "static_capacity_items.tsv"
        frontier_tsv = output_dir / "capacity_frontier.tsv"
        _export_items(report, items_tsv)
        _export_frontier(report, frontier_tsv)
        recommended_row = report.execute(
            """
            SELECT * FROM capacity_frontier WHERE static_capacity = ?
            """,
            (recommended,),
        ).fetchone()

    recoverable_texts = total_texts - mandatory
    manifest_payload = {
        "schema_version": SCHEMA_VERSION,
        "source_database": str(source_database),
        "configuration": {
            "maximum_parts_per_recursive_step": config.maximum_parts,
            "maximum_equal_best_alternatives": config.maximum_alternatives,
            "target_direct_frequency_coverage": (
                config.target_direct_frequency_coverage
            ),
            "requested_capacity": config.target_capacity,
        },
        "method": {
            "unit": "text_and_numeric_pinyin",
            "mandatory_if_any_reading_is_not_recoverable": True,
            "decomposition_requires_attested_exact_component_readings": True,
            "whole_item_is_not_its_own_decomposition": True,
        },
        "counts": {
            "encoded_texts": total_texts,
            "mandatory_static_texts": mandatory,
            "dynamically_recoverable_texts": recoverable_texts,
            "recommended_static_capacity": recommended,
            "recommended_dynamic_migration_candidates": (
                total_texts - recommended
            ),
        },
        "recommendation": {
            "target_direct_frequency_coverage": (
                config.target_direct_frequency_coverage
            ),
            "actual_direct_frequency_coverage": float(
                recommended_row["direct_frequency_coverage"]
            ),
            "proxy_only": True,
            "runtime_replay_required": True,
            "disclaimer": (
                "Dynamic reachability proves pronunciation reconstruction only; "
                "migration still requires candidate-rank, ambiguity, latency, "
                "and real-input replay."
            ),
        },
        "outputs": {
            "database": database.name,
            "items": items_tsv.name,
            "frontier": frontier_tsv.name,
            "summary": "summary.md",
        },
    }
    manifest = output_dir / "manifest.json"
    manifest.write_text(
        json.dumps(manifest_payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    summary_markdown = output_dir / "summary.md"
    summary_markdown.write_text(
        "\n".join(
            (
                "# 静态词库容量规划",
                "",
                f"- 已编码不同字串：`{total_texts:,}`",
                f"- 强制静态底座：`{mandatory:,}`",
                f"- 读音可动态重建：`{recoverable_texts:,}`",
                f"- 建议静态容量：`{recommended:,}`",
                f"- 建议迁出候选：`{total_texts - recommended:,}`",
                (
                    "- 建议容量下的直接 BCC 频次覆盖："
                    f"`{float(recommended_row['direct_frequency_coverage']):.4%}`"
                ),
                "",
                "该结果是容量代理模型，不是删除清单。所有迁出候选仍须通过"
                "真实输入回放、候选排名、歧义和延迟验证。",
                "",
            )
        ),
        encoding="utf-8",
    )
    return StaticCapacityResult(
        output_dir=output_dir,
        database=database,
        items_tsv=items_tsv,
        frontier_tsv=frontier_tsv,
        summary_markdown=summary_markdown,
        manifest=manifest,
        encoded_texts=total_texts,
        mandatory_static_texts=mandatory,
        dynamically_recoverable_texts=recoverable_texts,
        recommended_static_capacity=recommended,
    )
