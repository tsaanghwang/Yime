"""Export a read-only review queue for BCC frequencies 1000 through 9999."""

from __future__ import annotations

import csv
import hashlib
import json
import sqlite3
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROPER_NAME_MARKERS = frozenset(
    {
        "diming",
        "mingren",
        "renming",
        "yiren",
        "person_name",
        "place_name",
        "organization_name",
        "other_proper_name",
    }
)

QUEUE_FIELDS = (
    "text",
    "text_length",
    "bcc_frequency",
    "review_priority",
    "review_lane",
    "suggestion",
    "evidence_flags",
    "numeric_readings",
    "marked_readings",
    "pronunciation_scopes",
    "neutral_tone_statuses",
    "reading_source_categories",
    "wanxiang_categories",
    "has_source_rejection",
    "model_candidate_class",
    "model_integration_policy",
    "model_decision_status",
)


@dataclass(frozen=True)
class SecondBatchReviewResult:
    output_directory: Path
    queue_path: Path
    conflicts_path: Path
    summary_path: Path
    manifest_path: Path
    total_count: int
    conflict_count: int
    lane_counts: dict[str, int]


def _readonly_uri(path: Path) -> str:
    return path.resolve().as_uri() + "?mode=ro"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _tokens(value: object) -> tuple[str, ...]:
    return tuple(token.strip() for token in str(value or "").split(",") if token.strip())


def _is_proper_name_token(token: str) -> bool:
    lowered = token.lower()
    return any(
        lowered == marker
        or lowered.endswith(f":{marker}")
        or lowered.endswith(f"/{marker}")
        for marker in PROPER_NAME_MARKERS
    )


def _load_model_rows(path: Path | None) -> dict[str, dict[str, str]]:
    if path is None or not path.is_file():
        return {}
    with sqlite3.connect(_readonly_uri(path), uri=True) as connection:
        connection.row_factory = sqlite3.Row
        tables = {
            str(row[0])
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        if not {"candidate_universe", "assessments"}.issubset(tables):
            return {}
        rows = connection.execute(
            """
            SELECT u.text, u.has_gated_reading,
                   u.dynamic_reachable, u.dynamic_reachability_rule,
                   COALESCE(a.candidate_class, u.baseline_class) AS candidate_class,
                   COALESCE(a.integration_policy, u.baseline_policy) AS integration_policy,
                   CASE
                       WHEN u.baseline_policy = 'reject' THEN 'rejected'
                       ELSE COALESCE(a.decision_status, u.baseline_status)
                   END AS decision_status
            FROM candidate_universe AS u
            LEFT JOIN assessments AS a USING (text)
            """
        ).fetchall()
    return {
        str(row["text"]): {
            "has_gated_reading": str(row["has_gated_reading"]),
            "dynamic_reachable": str(row["dynamic_reachable"]),
            "dynamic_reachability_rule": str(row["dynamic_reachability_rule"]),
            "candidate_class": str(row["candidate_class"]),
            "integration_policy": str(row["integration_policy"]),
            "decision_status": str(row["decision_status"]),
        }
        for row in rows
    }


def _write_tsv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=QUEUE_FIELDS,
            delimiter="\t",
            lineterminator="\n",
            extrasaction="ignore",
        )
        writer.writeheader()
        writer.writerows(rows)


def _review_lane(
    *,
    reading_count: int,
    has_neutral: bool,
    is_proper_name: bool,
    has_rejection: bool,
) -> tuple[str, str, str]:
    if reading_count == 0:
        return (
            "P0",
            "source_reading_required",
            "Verify a trusted Mandarin reading source; never guess pinyin or codes.",
        )
    if is_proper_name and reading_count > 1:
        return (
            "P1",
            "proper_name_reading_conflict",
            "Verify proper-name scope and the default reading; keep ambiguity explicit.",
        )
    if has_neutral and reading_count > 1:
        return (
            "P1",
            "neutral_tone_reading_conflict",
            "Separate lexical neutral tone from scoped and full-tone readings.",
        )
    if reading_count > 1:
        return (
            "P1",
            "multiple_gated_readings",
            "Verify the default reading and scope; defer when evidence is insufficient.",
        )
    if has_rejection:
        return (
            "P2",
            "accepted_rejected_source_conflict",
            "Review the accepted reading against rejected source evidence.",
        )
    if is_proper_name:
        return (
            "P2",
            "proper_name_scope_review",
            "Verify proper-name classification, retention rationale, and scope.",
        )
    if has_neutral:
        return (
            "P2",
            "neutral_tone_scope_review",
            "Verify neutral-tone positions and pronunciation scope.",
        )
    return (
        "P3",
        "ranking_review",
        "Reading is gated; review only candidate role and ranking evidence.",
    )


def export_second_batch_review(
    *,
    source_database: Path,
    input_model_database: Path | None,
    output_directory: Path,
    minimum_frequency: int = 1000,
    maximum_frequency: int = 9999,
    summary_limit: int = 20,
) -> SecondBatchReviewResult:
    """Export evidence and suggestions without writing source or assessments."""
    if minimum_frequency < 1 or maximum_frequency < minimum_frequency:
        raise ValueError("invalid BCC frequency range")
    if summary_limit < 1:
        raise ValueError("summary_limit must be positive")
    if not source_database.is_file():
        raise FileNotFoundError(source_database)

    model_rows = _load_model_rows(input_model_database)
    readings_by_text: dict[str, list[sqlite3.Row]] = defaultdict(list)
    rejection_counts: Counter[str] = Counter()

    with sqlite3.connect(_readonly_uri(source_database), uri=True) as connection:
        connection.row_factory = sqlite3.Row
        frequency_rows = connection.execute(
            """
            SELECT text, frequency
            FROM bcc_frequency
            WHERE frequency BETWEEN ? AND ?
            ORDER BY frequency DESC, text
            """,
            (minimum_frequency, maximum_frequency),
        ).fetchall()
        for row in connection.execute(
            """
            SELECT c.text, c.marked_pinyin, c.numeric_pinyin,
                   c.reading_rank, c.is_primary,
                   c.pinyin_sources, c.reading_source_categories,
                   c.wanxiang_categories, c.pronunciation_scope,
                   c.neutral_tone_positions, c.neutral_tone_status
            FROM canonical_readings AS c
            JOIN bcc_frequency AS f USING (text)
            WHERE f.frequency BETWEEN ? AND ?
            ORDER BY c.text, c.reading_rank, c.numeric_pinyin
            """,
            (minimum_frequency, maximum_frequency),
        ):
            readings_by_text[str(row["text"])].append(row)
        for row in connection.execute(
            """
            SELECT r.text, COUNT(*) AS rejection_count
            FROM rejections AS r
            JOIN bcc_frequency AS f USING (text)
            WHERE f.frequency BETWEEN ? AND ?
            GROUP BY r.text
            """,
            (minimum_frequency, maximum_frequency),
        ):
            rejection_counts[str(row["text"])] = int(row["rejection_count"])

    queue_rows: list[dict[str, object]] = []
    for frequency_row in frequency_rows:
        text = str(frequency_row["text"])
        readings = readings_by_text.get(text, [])
        model = model_rows.get(text, {})
        source_categories = sorted(
            {
                token
                for reading in readings
                for token in _tokens(reading["reading_source_categories"])
            }
        )
        wanxiang_categories = sorted(
            {
                token
                for reading in readings
                for token in _tokens(reading["wanxiang_categories"])
            }
        )
        model_class = model.get("candidate_class", "")
        is_proper_name = any(
            _is_proper_name_token(token)
            for token in (*source_categories, *wanxiang_categories, model_class)
        )
        has_neutral = any(
            str(reading["neutral_tone_status"]) == "attested_neutral"
            or bool(str(reading["neutral_tone_positions"]).strip())
            for reading in readings
        )
        has_rejection = rejection_counts[text] > 0
        priority, lane, suggestion = _review_lane(
            reading_count=len(readings),
            has_neutral=has_neutral,
            is_proper_name=is_proper_name,
            has_rejection=has_rejection,
        )
        flags: list[str] = []
        if len(readings) > 1:
            flags.append("multiple_gated_readings")
        if has_neutral:
            flags.append("attested_neutral_or_scoped_reading")
        if is_proper_name:
            flags.append("proper_name_evidence")
        if has_rejection:
            flags.append("source_rejection_present")
        if not readings:
            flags.append("missing_gated_reading")
        if len(source_categories) > 1 and len(readings) > 1:
            flags.append("multiple_source_categories")
        queue_rows.append(
            {
                "text": text,
                "text_length": len(text),
                "bcc_frequency": int(frequency_row["frequency"]),
                "review_priority": priority,
                "review_lane": lane,
                "suggestion": suggestion,
                "evidence_flags": ",".join(flags),
                "numeric_readings": ";".join(
                    str(reading["numeric_pinyin"]) for reading in readings
                ),
                "marked_readings": ";".join(
                    str(reading["marked_pinyin"]) for reading in readings
                ),
                "pronunciation_scopes": ";".join(
                    sorted({str(reading["pronunciation_scope"]) for reading in readings})
                ),
                "neutral_tone_statuses": ";".join(
                    sorted({str(reading["neutral_tone_status"]) for reading in readings})
                ),
                "reading_source_categories": ",".join(source_categories),
                "wanxiang_categories": ",".join(wanxiang_categories),
                "has_source_rejection": int(has_rejection),
                "model_candidate_class": model_class,
                "model_integration_policy": model.get("integration_policy", ""),
                "model_decision_status": model.get("decision_status", ""),
            }
        )

    all_review_rows = queue_rows
    if model_rows:
        queue_rows = [
            row
            for row in all_review_rows
            if model_rows.get(str(row["text"]), {}).get("has_gated_reading") == "0"
        ]
    for row in queue_rows:
        model = model_rows.get(str(row["text"]), {})
        if model.get("dynamic_reachable") == "1":
            row["review_priority"] = "P1"
            row["review_lane"] = "dynamic_composition_review"
            row["suggestion"] = (
                "Review the existing dynamic composition evidence; do not add a whole-string reading."
            )
            flags = [flag for flag in str(row["evidence_flags"]).split(",") if flag]
            flags.append("dynamic_composition_reachable")
            row["evidence_flags"] = ",".join(flags)
    conflict_rows = [
        row
        for row in all_review_rows
        if row["numeric_readings"]
        and any(
            flag in str(row["evidence_flags"]).split(",")
            for flag in (
                "multiple_gated_readings",
                "attested_neutral_or_scoped_reading",
                "proper_name_evidence",
                "source_rejection_present",
            )
        )
    ]
    lane_counts = Counter(str(row["review_lane"]) for row in queue_rows)
    flag_counts = Counter(
        flag
        for row in queue_rows
        for flag in str(row["evidence_flags"]).split(",")
        if flag
    )
    output_directory.mkdir(parents=True, exist_ok=True)
    queue_path = output_directory / "second_batch_queue.tsv"
    conflicts_path = output_directory / "second_batch_conflicts.tsv"
    summary_path = output_directory / "summary.md"
    manifest_path = output_directory / "manifest.json"
    _write_tsv(queue_path, queue_rows)
    _write_tsv(conflicts_path, conflict_rows)

    lines = [
        "# Second-batch BCC review queue",
        "",
        f"- BCC frequency range: `{minimum_frequency}-{maximum_frequency}`",
        f"- Total candidates: `{len(queue_rows)}`",
        f"- Conflict or scoped-review candidates: `{len(conflict_rows)}`",
        "- This report writes suggestions only; it never writes pinyin, codes, or assessments.",
        "",
        "## Review lanes",
        "",
        "| Lane | Count |",
        "| --- | ---: |",
    ]
    lines.extend(f"| {lane} | {count} |" for lane, count in sorted(lane_counts.items()))
    for lane in sorted(lane_counts):
        examples = [row for row in queue_rows if row["review_lane"] == lane][
            :summary_limit
        ]
        lines.extend(
            [
                "",
                f"## {lane} (first {summary_limit})",
                "",
                "| Text | BCC | Readings | Evidence | Suggestion |",
                "| --- | ---: | --- | --- | --- |",
            ]
        )
        for row in examples:
            safe = {
                key: str(value).replace("|", "\\|") for key, value in row.items()
            }
            lines.append(
                "| {text} | {bcc_frequency} | {numeric_readings} | "
                "{evidence_flags} | {suggestion} |".format(**safe)
            )
    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    manifest: dict[str, Any] = {
        "schema_version": 1,
        "policy_id": "bcc-second-batch-explainable-review-v1",
        "frequency_range": {"minimum": minimum_frequency, "maximum": maximum_frequency},
        "inputs": {
            "source_database_sha256": _sha256(source_database),
            "input_model_database_sha256": (
                _sha256(input_model_database)
                if input_model_database is not None and input_model_database.is_file()
                else None
            ),
        },
        "counts": {
            "total": len(queue_rows),
            "conflict_or_scoped_review": len(conflict_rows),
            "by_lane": dict(sorted(lane_counts.items())),
            "by_evidence_flag": dict(sorted(flag_counts.items())),
        },
        "outputs": {
            "queue_sha256": _sha256(queue_path),
            "conflicts_sha256": _sha256(conflicts_path),
            "summary_sha256": _sha256(summary_path),
        },
        "safeguards": {
            "source_database_read_only": True,
            "input_model_read_only": True,
            "writes_assessments": False,
            "writes_pronunciation": False,
            "writes_yinyuan_or_layout": False,
            "suggestions_require_human_review": True,
        },
        "decision": "complete",
    }
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return SecondBatchReviewResult(
        output_directory=output_directory.resolve(),
        queue_path=queue_path.resolve(),
        conflicts_path=conflicts_path.resolve(),
        summary_path=summary_path.resolve(),
        manifest_path=manifest_path.resolve(),
        total_count=len(queue_rows),
        conflict_count=len(conflict_rows),
        lane_counts=dict(sorted(lane_counts.items())),
    )