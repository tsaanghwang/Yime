"""BCC-primary, RIME-LMDG-fallback candidate ranking evidence."""

from __future__ import annotations

import bisect
import csv
import json
import sqlite3
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping
from urllib.parse import quote


DEFAULT_POLICY_PATH = (
    Path(__file__).resolve().parents[2]
    / "internal_data"
    / "candidate_ranking_evidence_policy.json"
)

DIRECT_BCC = "direct_bcc"
PROVISIONAL_LMDG = "provisional_rime_lmdg"
PROVISIONAL_STRUCTURAL = "provisional_structural_floor"
AWAITING_CORPUS = "awaiting_corpus"


@dataclass(frozen=True)
class RankingEvidence:
    bcc_frequency: int
    wanxiang_weight: int
    evidence_source: str
    evidence_status: str
    text_length_bucket: str
    normalized_fallback_percentile: float
    normalized_structural_percentile: float
    effective_weight: int
    provisional: bool
    requires_independent_corpus: bool


@dataclass(frozen=True)
class RankingCalibration:
    policy_id: str
    policy_path: Path
    fallback_weights_by_bucket: Mapping[str, tuple[int, ...]]
    structural_scores_by_bucket: Mapping[str, tuple[float, ...]]
    direct_bcc_offset: int
    fallback_minimum: int
    fallback_maximum: int
    structural_minimum: int
    structural_maximum: int
    primary_reading_bonus: int
    awaiting_corpus_base: int
    length_buckets: tuple[tuple[str, int, int | None], ...]

    def bucket_for_length(self, text_length: int) -> str:
        for bucket_id, minimum, maximum in self.length_buckets:
            if text_length >= minimum and (
                maximum is None or text_length <= maximum
            ):
                return bucket_id
        raise ValueError(f"no ranking bucket for text length {text_length}")


@dataclass(frozen=True)
class RankingEvidenceAudit:
    policy_id: str
    full_inventory_counts: dict[str, int]
    selected_texts: int
    classified_selected_texts: int
    missing_selected_source_texts: int
    selected_counts: dict[str, dict[str, int]]
    selected_counts_by_length: dict[str, dict[str, int]]
    selection_evidence_columns_present: bool
    minimum_direct_bcc_effective_weight: int
    maximum_provisional_lmdg_effective_weight: int
    maximum_provisional_structural_effective_weight: int
    raw_bcc_and_lmdg_values_added: bool
    source_priority_separation_passed: bool
    completion_passed: bool


def _readonly_uri(path: Path) -> str:
    return f"file:{quote(path.resolve().as_posix(), safe='/:')}?mode=ro"


def _load_policy(path: Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError("unsupported ranking evidence policy schema")
    safeguards = payload.get("safeguards", {})
    required_safeguards = (
        "bcc_presence_always_selects_direct_bcc",
        "bcc_and_lmdg_raw_values_are_never_added",
        "fallback_score_is_strictly_below_direct_bcc_score",
        "wanxiang_weight_is_never_written_as_bcc_frequency",
        "fallback_is_marked_provisional",
        "missing_lmdg_does_not_block_build",
        "raw_evidence_and_policy_version_are_exported",
        "structural_floor_is_not_frequency",
    )
    if not isinstance(safeguards, dict) or any(
        safeguards.get(key) is not True for key in required_safeguards
    ):
        raise ValueError("ranking evidence policy is missing a safeguard")
    weights = payload.get("effective_weight", {})
    if not isinstance(weights, dict):
        raise ValueError("ranking evidence policy has no weight settings")
    direct_offset = int(weights["direct_bcc_offset"])
    fallback_minimum = int(weights["fallback_minimum"])
    fallback_maximum = int(weights["fallback_maximum"])
    structural_minimum = int(weights["structural_minimum"])
    structural_maximum = int(weights["structural_maximum"])
    primary_bonus = int(weights["primary_reading_bonus"])
    if fallback_minimum < 1 or fallback_maximum < fallback_minimum:
        raise ValueError("invalid fallback weight range")
    if not 1 <= structural_minimum <= structural_maximum < fallback_minimum:
        raise ValueError("structural range must be below LMDG fallback")
    if direct_offset < fallback_maximum + primary_bonus:
        raise ValueError(
            "direct BCC offset must keep fallback below direct evidence"
        )
    return payload


def build_ranking_calibration(
    *,
    source_database: Path,
    capacity_database: Path | None = None,
    policy_path: Path = DEFAULT_POLICY_PATH,
) -> RankingCalibration:
    """Build read-only percentile calibrations for separated evidence tiers."""

    policy = _load_policy(policy_path)
    buckets = tuple(
        (
            str(item["id"]),
            int(item["minimum"]),
            (
                int(item["maximum"])
                if item.get("maximum") is not None
                else None
            ),
        )
        for item in policy["text_length_buckets"]
    )
    by_bucket: dict[str, list[int]] = {
        bucket_id: [] for bucket_id, _minimum, _maximum in buckets
    }
    structural_by_bucket: dict[str, list[float]] = {
        bucket_id: [] for bucket_id, _minimum, _maximum in buckets
    }

    def bucket_for_length(text_length: int) -> str:
        for bucket_id, minimum, maximum in buckets:
            if text_length >= minimum and (
                maximum is None or text_length <= maximum
            ):
                return bucket_id
        raise ValueError(f"no ranking bucket for text length {text_length}")

    connection = sqlite3.connect(_readonly_uri(source_database), uri=True)
    try:
        columns = {
            str(row[1])
            for row in connection.execute(
                "PRAGMA table_info(canonical_readings)"
            )
        }
        has_wanxiang = "wanxiang_weight" in columns
        if has_wanxiang:
            rows = connection.execute(
                """
                SELECT text, LENGTH(text) AS text_length,
                       MAX(bcc_frequency) AS bcc_frequency,
                       MAX(wanxiang_weight) AS wanxiang_weight
                FROM canonical_readings
                GROUP BY text
                HAVING MAX(bcc_frequency) = 0
                   AND MAX(wanxiang_weight) > 0
                """
            )
            for _text, text_length, _bcc, wanxiang_weight in rows:
                by_bucket[bucket_for_length(int(text_length))].append(
                    int(wanxiang_weight)
                )
        if capacity_database is not None:
            connection.execute(
                "ATTACH DATABASE ? AS capacity",
                (_readonly_uri(capacity_database),),
            )
            wanxiang_expression = (
                "MAX(wanxiang_weight)" if has_wanxiang else "0"
            )
            rows = connection.execute(
                f"""
                WITH source_texts AS (
                    SELECT text, MAX(bcc_frequency) AS bcc_frequency,
                           {wanxiang_expression} AS wanxiang_weight
                    FROM canonical_readings
                    GROUP BY text
                )
                SELECT LENGTH(i.text), i.utility_score
                FROM capacity.static_capacity_items AS i
                JOIN source_texts AS s USING(text)
                WHERE s.bcc_frequency = 0
                  AND s.wanxiang_weight <= 0
                  AND i.utility_score > 0
                """
            )
            for text_length, utility_score in rows:
                structural_by_bucket[
                    bucket_for_length(int(text_length))
                ].append(float(utility_score))
    finally:
        connection.close()

    settings = policy["effective_weight"]
    return RankingCalibration(
        policy_id=str(policy["policy_id"]),
        policy_path=policy_path.resolve(),
        fallback_weights_by_bucket={
            bucket: tuple(sorted(weights))
            for bucket, weights in by_bucket.items()
        },
        structural_scores_by_bucket={
            bucket: tuple(sorted(scores))
            for bucket, scores in structural_by_bucket.items()
        },
        direct_bcc_offset=int(settings["direct_bcc_offset"]),
        fallback_minimum=int(settings["fallback_minimum"]),
        fallback_maximum=int(settings["fallback_maximum"]),
        structural_minimum=int(settings["structural_minimum"]),
        structural_maximum=int(settings["structural_maximum"]),
        primary_reading_bonus=int(settings["primary_reading_bonus"]),
        awaiting_corpus_base=int(settings["awaiting_corpus_base"]),
        length_buckets=buckets,
    )


def resolve_ranking_evidence(
    row: Mapping[str, object],
    calibration: RankingCalibration,
) -> RankingEvidence:
    """Resolve one reading without mixing raw BCC and LMDG values."""

    def value(key: str, default: object = 0) -> object:
        try:
            return row[key]
        except (KeyError, IndexError):
            return default

    bcc = max(int(value("bcc_frequency") or 0), 0)
    wanxiang = max(int(value("wanxiang_weight") or 0), 0)
    utility_score = max(float(value("utility_score") or 0), 0.0)
    text = str(value("text", ""))
    text_length = int(value("text_length") or len(text))
    is_primary = bool(int(value("is_primary") or 0))
    primary_bonus = calibration.primary_reading_bonus if is_primary else 0
    bucket = calibration.bucket_for_length(text_length)

    if bcc > 0:
        return RankingEvidence(
            bcc_frequency=bcc,
            wanxiang_weight=wanxiang,
            evidence_source=DIRECT_BCC,
            evidence_status="verified_corpus",
            text_length_bucket=bucket,
            normalized_fallback_percentile=0.0,
            normalized_structural_percentile=0.0,
            effective_weight=(
                calibration.direct_bcc_offset + bcc + primary_bonus
            ),
            provisional=False,
            requires_independent_corpus=False,
        )

    distribution = calibration.fallback_weights_by_bucket.get(bucket, ())
    if wanxiang > 0 and distribution:
        percentile = bisect.bisect_right(distribution, wanxiang) / len(
            distribution
        )
        span = (
            calibration.fallback_maximum
            - calibration.fallback_minimum
        )
        fallback = calibration.fallback_minimum + round(percentile * span)
        fallback = min(
            calibration.fallback_maximum,
            max(calibration.fallback_minimum, fallback),
        )
        return RankingEvidence(
            bcc_frequency=0,
            wanxiang_weight=wanxiang,
            evidence_source=PROVISIONAL_LMDG,
            evidence_status="provisional_external_ranking",
            text_length_bucket=bucket,
            normalized_fallback_percentile=percentile,
            normalized_structural_percentile=0.0,
            effective_weight=fallback + primary_bonus,
            provisional=True,
            requires_independent_corpus=True,
        )

    structural_distribution = (
        calibration.structural_scores_by_bucket.get(bucket, ())
    )
    if utility_score > 0 and structural_distribution:
        structural_percentile = (
            bisect.bisect_right(
                structural_distribution,
                utility_score,
            )
            / len(structural_distribution)
        )
        span = (
            calibration.structural_maximum
            - calibration.structural_minimum
        )
        structural_weight = (
            calibration.structural_minimum
            + round(structural_percentile * span)
        )
        structural_weight = min(
            calibration.structural_maximum,
            max(calibration.structural_minimum, structural_weight),
        )
        return RankingEvidence(
            bcc_frequency=0,
            wanxiang_weight=wanxiang,
            evidence_source=PROVISIONAL_STRUCTURAL,
            evidence_status="provisional_non_frequency_tiebreak",
            text_length_bucket=bucket,
            normalized_fallback_percentile=0.0,
            normalized_structural_percentile=structural_percentile,
            effective_weight=structural_weight + primary_bonus,
            provisional=True,
            requires_independent_corpus=True,
        )

    return RankingEvidence(
        bcc_frequency=0,
        wanxiang_weight=wanxiang,
        evidence_source=AWAITING_CORPUS,
        evidence_status="no_quantified_ranking_evidence",
        text_length_bucket=bucket,
        normalized_fallback_percentile=0.0,
        normalized_structural_percentile=0.0,
        effective_weight=calibration.awaiting_corpus_base + primary_bonus,
        provisional=False,
        requires_independent_corpus=True,
    )


def calibration_summary(
    calibration: RankingCalibration,
) -> dict[str, object]:
    return {
        "policy_id": calibration.policy_id,
        "policy_path": str(calibration.policy_path),
        "effective_weight": {
            "direct_bcc_offset": calibration.direct_bcc_offset,
            "fallback_minimum": calibration.fallback_minimum,
            "fallback_maximum": calibration.fallback_maximum,
            "structural_minimum": calibration.structural_minimum,
            "structural_maximum": calibration.structural_maximum,
            "primary_reading_bonus": calibration.primary_reading_bonus,
            "awaiting_corpus_base": calibration.awaiting_corpus_base,
        },
        "fallback_population_by_bucket": {
            bucket: len(weights)
            for bucket, weights in calibration.fallback_weights_by_bucket.items()
        },
        "structural_population_by_bucket": {
            bucket: len(scores)
            for bucket, scores in (
                calibration.structural_scores_by_bucket.items()
            )
        },
    }


def resolve_text_ranking_evidence(
    *,
    source_database: Path,
    texts: set[str],
    calibration: RankingCalibration,
    capacity_database: Path | None = None,
) -> dict[str, RankingEvidence]:
    """Resolve one source-separated ranking record per distinct text."""

    if not texts:
        return {}
    connection = sqlite3.connect(_readonly_uri(source_database), uri=True)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute(
            "CREATE TEMP TABLE requested_texts (text TEXT PRIMARY KEY)"
        )
        connection.executemany(
            "INSERT INTO requested_texts VALUES (?)",
            ((text,) for text in sorted(texts)),
        )
        if capacity_database is not None:
            connection.execute(
                "ATTACH DATABASE ? AS capacity",
                (_readonly_uri(capacity_database),),
            )
            utility_join = (
                "LEFT JOIN capacity.static_capacity_items AS i USING(text)"
            )
            utility_expression = "COALESCE(MAX(i.utility_score), 0)"
        else:
            utility_join = ""
            utility_expression = "0"
        rows = connection.execute(
            f"""
            SELECT r.text, LENGTH(r.text) AS text_length,
                   MAX(r.bcc_frequency) AS bcc_frequency,
                   MAX(r.wanxiang_weight) AS wanxiang_weight,
                   {utility_expression} AS utility_score
            FROM canonical_readings AS r
            JOIN requested_texts AS q USING(text)
            {utility_join}
            GROUP BY r.text
            """
        )
        return {
            str(row["text"]): resolve_ranking_evidence(
                {
                    "text": row["text"],
                    "text_length": row["text_length"],
                    "bcc_frequency": row["bcc_frequency"],
                    "wanxiang_weight": row["wanxiang_weight"],
                    "utility_score": row["utility_score"],
                    "is_primary": 0,
                },
                calibration,
            )
            for row in rows
        }
    finally:
        connection.close()


def audit_runtime_ranking_evidence(
    *,
    source_database: Path,
    selection_path: Path,
    capacity_database: Path | None = None,
    policy_path: Path = DEFAULT_POLICY_PATH,
) -> RankingEvidenceAudit:
    """Classify every selected runtime text and enforce source separation."""

    calibration = build_ranking_calibration(
        source_database=source_database,
        capacity_database=capacity_database,
        policy_path=policy_path,
    )
    selected: set[tuple[str, str]] = set()
    with selection_path.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        required_columns = {
            "bcc_frequency",
            "wanxiang_weight",
            "ranking_evidence_source",
            "ranking_evidence_status",
            "normalized_fallback_percentile",
            "normalized_structural_percentile",
            "ranking_evidence_provisional",
            "requires_independent_corpus",
        }
        selection_evidence_columns_present = required_columns.issubset(
            set(reader.fieldnames or ())
        )
        for row in reader:
            text = str(row.get("text", "")).strip()
            level = str(row.get("selection_level", "")).strip()
            if text and level:
                selected.add((text, level))

    connection = sqlite3.connect(_readonly_uri(source_database), uri=True)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute(
            """
            CREATE TEMP TABLE selected_runtime_texts (
                text TEXT NOT NULL,
                selection_level TEXT NOT NULL,
                PRIMARY KEY(text, selection_level)
            )
            """
        )
        connection.executemany(
            "INSERT INTO selected_runtime_texts VALUES (?, ?)",
            sorted(selected),
        )
        if capacity_database is not None:
            connection.execute(
                "ATTACH DATABASE ? AS capacity",
                (_readonly_uri(capacity_database),),
            )
            utility_join = (
                "LEFT JOIN capacity.static_capacity_items AS i USING(text)"
            )
            utility_expression = "COALESCE(MAX(i.utility_score), 0)"
        else:
            utility_join = ""
            utility_expression = "0"
        grouped_cte = f"""
            WITH source_texts AS (
                SELECT r.text, LENGTH(r.text) AS text_length,
                       MAX(r.bcc_frequency) AS bcc_frequency,
                       MAX(r.wanxiang_weight) AS wanxiang_weight,
                       {utility_expression} AS utility_score
                FROM canonical_readings AS r
                {utility_join}
                GROUP BY r.text
            )
        """
        full_rows = connection.execute(
            grouped_cte
            + """
            SELECT text, text_length, bcc_frequency,
                   wanxiang_weight, utility_score
            FROM source_texts
            """
        )
        full_counts_counter: Counter[str] = Counter()
        for row in full_rows:
            full_counts_counter[
                resolve_ranking_evidence(row, calibration).evidence_source
            ] += 1
        full_counts = dict(sorted(full_counts_counter.items()))
        rows = connection.execute(
            grouped_cte
            + """
            SELECT s.selection_level, t.text, t.text_length,
                   t.bcc_frequency, t.wanxiang_weight, t.utility_score
            FROM selected_runtime_texts AS s
            JOIN source_texts AS t USING(text)
            ORDER BY s.selection_level, t.text
            """
        )
        selected_counts: dict[str, Counter[str]] = {}
        selected_lengths: dict[str, Counter[str]] = {}
        classified = 0
        minimum_direct = 0
        maximum_fallback = 0
        maximum_structural = 0
        for row in rows:
            evidence = resolve_ranking_evidence(
                {
                    "text": row["text"],
                    "text_length": row["text_length"],
                    "bcc_frequency": row["bcc_frequency"],
                    "wanxiang_weight": row["wanxiang_weight"],
                    "utility_score": row["utility_score"],
                    "is_primary": 1,
                },
                calibration,
            )
            level = str(row["selection_level"])
            selected_counts.setdefault(level, Counter())[
                evidence.evidence_source
            ] += 1
            selected_lengths.setdefault(
                str(row["text_length"]),
                Counter(),
            )[evidence.evidence_source] += 1
            classified += 1
            if evidence.evidence_source == DIRECT_BCC:
                minimum_direct = (
                    evidence.effective_weight
                    if minimum_direct == 0
                    else min(minimum_direct, evidence.effective_weight)
                )
            elif evidence.evidence_source == PROVISIONAL_LMDG:
                maximum_fallback = max(
                    maximum_fallback,
                    evidence.effective_weight,
                )
            elif evidence.evidence_source == PROVISIONAL_STRUCTURAL:
                maximum_structural = max(
                    maximum_structural,
                    evidence.effective_weight,
                )
    finally:
        connection.close()

    selected_texts = len(selected)
    missing = selected_texts - classified
    separation = (
        (minimum_direct == 0 or maximum_fallback < minimum_direct)
        and (
            maximum_fallback == 0
            or maximum_structural < maximum_fallback
        )
    )
    completion = (
        selected_texts > 0
        and missing == 0
        and separation
        and selection_evidence_columns_present
    )
    return RankingEvidenceAudit(
        policy_id=calibration.policy_id,
        full_inventory_counts=full_counts,
        selected_texts=selected_texts,
        classified_selected_texts=classified,
        missing_selected_source_texts=missing,
        selected_counts={
            level: dict(sorted(counts.items()))
            for level, counts in sorted(selected_counts.items())
        },
        selected_counts_by_length={
            length: dict(sorted(counts.items()))
            for length, counts in sorted(
                selected_lengths.items(),
                key=lambda item: int(item[0]),
            )
        },
        selection_evidence_columns_present=(
            selection_evidence_columns_present
        ),
        minimum_direct_bcc_effective_weight=minimum_direct,
        maximum_provisional_lmdg_effective_weight=maximum_fallback,
        maximum_provisional_structural_effective_weight=(
            maximum_structural
        ),
        raw_bcc_and_lmdg_values_added=False,
        source_priority_separation_passed=separation,
        completion_passed=completion,
    )
