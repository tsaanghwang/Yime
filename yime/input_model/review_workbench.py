"""Review workflow for unencoded candidates and productive rule families.

The workbench records lexical decisions and bounded rule-family hypotheses in
``input_model.sqlite3``. Neither lexical approval nor rule registration is an
encoding approval: strings without gated source readings remain ineligible for
the runtime lexicon until the normal source and syllable pipelines can encode
them.
"""

from __future__ import annotations

import base64
import json
import math
import re
import sqlite3
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .recursive_composition import build_composition_tree
from .source import SourceLexicon
from .store import InputModelStore
from .types import (
    CandidateAssessment,
    CandidateClass,
    DecisionStatus,
    IntegrationPolicy,
)


REVIEWABLE_CLASSES = tuple(item.value for item in CandidateClass)
APPROVAL_POLICIES = (
    IntegrationPolicy.STATIC_KEEP.value,
    IntegrationPolicy.MODEL_ONLY.value,
)
REVIEW_STATUSES = ("proposed", "approved", "rejected", "deferred")
REVIEW_STANDARDS = ("standard", "academic", "reviewer")
RULE_FAMILY_STATUSES = ("registered", "deferred", "rejected")
RULE_FAMILY_CLASSES = (
    CandidateClass.SEMI_FIXED_CONSTRUCTION.value,
    CandidateClass.PRODUCTIVE_PHRASE.value,
)
AFFIX_ANALYSIS_CLASSES = (
    *RULE_FAMILY_CLASSES,
    CandidateClass.PERSON_NAME.value,
    CandidateClass.PLACE_NAME.value,
    CandidateClass.ORGANIZATION_NAME.value,
    CandidateClass.DOMAIN_TERM.value,
)
TAIL_SEMANTIC_CLASSES = (
    "person_name",
    "business_name",
    "product_name",
    "currency_measurement",
    "other_proper_name",
    "fixed_lexical_item",
    "noise",
    "uncertain",
)
TAIL_DYNAMIC_CLASSES = {
    "person_name": CandidateClass.PERSON_NAME,
    "business_name": CandidateClass.ORGANIZATION_NAME,
    "product_name": CandidateClass.DOMAIN_TERM,
    "currency_measurement": CandidateClass.PRODUCTIVE_PHRASE,
    "other_proper_name": CandidateClass.DOMAIN_TERM,
}
NUMERIC_AMOUNT_PATTERN = re.compile(
    r"^[0-9０-９零〇一二两兩三四五六七八九十百千万萬亿億兆"
    r"点點半数數多几幾余餘来來\.．,，]+$"
)
RULE_FAMILY_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]{2,63}$")
TEMPLATE_TOKEN_PATTERN = re.compile(
    r"\{([A-Za-z0-9_\u4e00-\u9fff]+)(\?)?\}|\(([^(){}]+)\)"
)


@dataclass(frozen=True)
class ReviewQueueItem:
    text: str
    text_length: int
    text_length_label: str
    bcc_frequency: int
    bcc_categories: tuple[str, ...]
    has_bcc_evidence: bool
    has_source_rejection: bool
    candidate_class: str
    integration_policy: str
    decision_status: str
    rationale: str
    assessor: str
    context_count: int
    updated_at_utc: str | None


@dataclass(frozen=True)
class ReviewQueuePage:
    items: tuple[ReviewQueueItem, ...]
    next_cursor: str | None


def _readonly_uri(path: Path) -> str:
    return f"file:{path.resolve().as_posix()}?mode=ro"


def _encode_cursor(frequency: int, text: str) -> str:
    raw = json.dumps([frequency, text], ensure_ascii=False).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _decode_cursor(cursor: str) -> tuple[int, str]:
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        value = json.loads(base64.urlsafe_b64decode(padded).decode("utf-8"))
        if (
            not isinstance(value, list)
            or len(value) != 2
            or not isinstance(value[0], int)
            or not isinstance(value[1], str)
        ):
            raise ValueError
        return value[0], value[1]
    except (ValueError, TypeError, json.JSONDecodeError) as exc:
        raise ValueError("invalid review queue cursor") from exc


def _text_length_label(text_length: int) -> str:
    return f"{text_length}字"


class UnencodedCandidateReview:
    """Review unencoded strings and discover auditable construction families."""

    def __init__(self, *, input_model_database: Path, source_database: Path):
        self.input_model_database = input_model_database.resolve()
        self.source_database = source_database.resolve()
        if not self.input_model_database.is_file():
            raise FileNotFoundError(
                f"input model database does not exist: {self.input_model_database}"
            )
        if not self.source_database.is_file():
            raise FileNotFoundError(
                f"source lexicon does not exist: {self.source_database}"
            )
        # Apply additive schema migrations before opening query-only connections.
        with InputModelStore(self.input_model_database):
            pass

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(_readonly_uri(self.input_model_database), uri=True)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA query_only = ON")
        return connection

    def _bcc_categories_for(
        self,
        texts: tuple[str, ...],
    ) -> dict[str, tuple[str, ...]]:
        if not texts:
            return {}
        placeholders = ",".join("?" for _ in texts)
        with sqlite3.connect(_readonly_uri(self.source_database), uri=True) as connection:
            table_exists = connection.execute(
                """
                SELECT 1
                FROM sqlite_master
                WHERE type = 'table' AND name = 'bcc_frequency_evidence'
                """
            ).fetchone()
            if table_exists is None:
                return {}
            rows = connection.execute(
                f"""
                SELECT text, source_category, MAX(frequency) AS frequency
                FROM bcc_frequency_evidence
                WHERE text IN ({placeholders})
                GROUP BY text, source_category
                ORDER BY text, frequency DESC, source_category
                """,
                texts,
            ).fetchall()
        categories: dict[str, list[str]] = {}
        for text, category, _frequency in rows:
            categories.setdefault(str(text), []).append(str(category))
        return {text: tuple(values) for text, values in categories.items()}

    def summary(self) -> dict[str, Any]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT
                    CASE
                        WHEN u.baseline_policy = 'reject' THEN 'rejected'
                        ELSE COALESCE(a.decision_status, u.baseline_status)
                    END AS status,
                    COUNT(*) AS count
                FROM candidate_universe AS u
                LEFT JOIN assessments AS a USING (text)
                WHERE u.has_gated_reading = 0
                GROUP BY
                    CASE
                        WHEN u.baseline_policy = 'reject' THEN 'rejected'
                        ELSE COALESCE(a.decision_status, u.baseline_status)
                    END
                """
            ).fetchall()
            counts = {status: 0 for status in REVIEW_STATUSES}
            counts.update({str(row["status"]): int(row["count"]) for row in rows})
            high_frequency = int(
                connection.execute(
                    """
                    SELECT COUNT(*)
                    FROM candidate_universe AS u
                    LEFT JOIN assessments AS a USING (text)
                    WHERE u.has_gated_reading = 0
                      AND CASE
                              WHEN u.baseline_policy = 'reject' THEN 'rejected'
                              ELSE COALESCE(a.decision_status, u.baseline_status)
                          END
                          IN ('proposed', 'deferred')
                      AND u.bcc_frequency >= 1000
                    """
                ).fetchone()[0]
            )
            two_character_dynamic_reachability = int(
                connection.execute(
                    """
                    SELECT COUNT(*)
                    FROM candidate_universe
                    WHERE dynamic_reachable = 1
                      AND dynamic_reachability_rule =
                          'two_character_dynamic_reachability'
                    """
                ).fetchone()[0]
            )
            recursive_composition = dict(
                connection.execute(
                    """
                    SELECT
                        COUNT(*) AS analyzed,
                        SUM(reachability_status = 'reachable') AS reachable,
                        SUM(reachability_status = 'unreachable') AS unreachable,
                        SUM(structural_ambiguous = 1)
                            AS structurally_ambiguous,
                        SUM(reading_ambiguous = 1) AS reading_ambiguous,
                        SUM(
                            reachability_status = 'reachable'
                            AND encoded_multichar_component_count > 0
                        ) AS uses_multichar_component,
                        SUM(
                            reachability_status = 'reachable'
                            AND encoded_multichar_component_count = 0
                        ) AS residual_blocks_only,
                        SUM(single_exception_count > 0)
                            AS single_exception_targets
                    FROM recursive_composition_evidence
                    """
                ).fetchone()
            )
            length_rows = connection.execute(
                """
                SELECT
                    u.text_length,
                    CASE
                        WHEN u.baseline_policy = 'reject' THEN 'rejected'
                        ELSE COALESCE(a.decision_status, u.baseline_status)
                    END AS status,
                    COUNT(*) AS count
                FROM candidate_universe AS u
                LEFT JOIN assessments AS a USING (text)
                WHERE u.has_gated_reading = 0
                GROUP BY
                    u.text_length,
                    CASE
                        WHEN u.baseline_policy = 'reject' THEN 'rejected'
                        ELSE COALESCE(a.decision_status, u.baseline_status)
                    END
                ORDER BY u.text_length
                """
            ).fetchall()
            length_groups: dict[int, dict[str, Any]] = {}
            for row in length_rows:
                text_length = int(row["text_length"])
                group = length_groups.setdefault(
                    text_length,
                    {
                        "text_length": text_length,
                        "label": _text_length_label(text_length),
                        "count": 0,
                        "status_counts": {
                            status: 0 for status in REVIEW_STATUSES
                        },
                    },
                )
                count = int(row["count"])
                group["count"] += count
                group["status_counts"][str(row["status"])] = count
        return {
            "unencoded_total": sum(counts.values()),
            "status_counts": counts,
            "length_groups": list(length_groups.values()),
            "high_frequency_pending": high_frequency,
            "two_character_dynamic_reachability": (
                two_character_dynamic_reachability
            ),
            "recursive_composition": {
                key: int(value or 0)
                for key, value in recursive_composition.items()
            },
            "rule_family_count": self._rule_family_count(),
            "runtime_writes": False,
            "approval_requires_source_reading": True,
        }

    def _rule_family_count(self) -> int:
        with self._connect() as connection:
            return int(
                connection.execute(
                    "SELECT COUNT(*) FROM rule_families WHERE status = 'registered'"
                ).fetchone()[0]
            )

    @staticmethod
    def _validate_affix_model(
        *,
        direction: str,
        root_anchor: str,
        refinements: list[str],
        intended_class: str,
    ) -> tuple[str, tuple[str, ...]]:
        root_anchor = root_anchor.strip()
        if direction not in {"prefix", "suffix"}:
            raise ValueError("direction must be prefix or suffix")
        if not root_anchor or len(root_anchor) > 16:
            raise ValueError("root_anchor must contain 1-16 characters")
        if intended_class not in AFFIX_ANALYSIS_CLASSES:
            raise ValueError("unsupported affix analysis class")
        normalized = tuple(
            dict.fromkeys(
                item.strip()
                for item in refinements
                if isinstance(item, str) and item.strip()
            )
        )
        for anchor in normalized:
            if len(anchor) > 32:
                raise ValueError("refinement anchors cannot exceed 32 characters")
            compatible = (
                anchor.startswith(root_anchor)
                if direction == "prefix"
                else anchor.endswith(root_anchor)
            )
            if not compatible:
                relation = "start with" if direction == "prefix" else "end with"
                raise ValueError(
                    f"refinement anchor {anchor!r} must {relation} root_anchor"
                )
        return root_anchor, tuple(
            sorted(
                (item for item in normalized if item != root_anchor),
                key=lambda item: (-len(item), item),
            )
        )

    @staticmethod
    def _like_literal(value: str) -> str:
        return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")

    def _primary_readings_for(
        self,
        texts: tuple[str, ...],
    ) -> dict[str, dict[str, str]]:
        if not texts:
            return {}
        placeholders = ",".join("?" for _ in texts)
        with sqlite3.connect(_readonly_uri(self.source_database), uri=True) as connection:
            connection.row_factory = sqlite3.Row
            rows = connection.execute(
                f"""
                SELECT text, marked_pinyin, numeric_pinyin
                FROM canonical_readings
                WHERE text IN ({placeholders})
                  AND is_primary = 1
                ORDER BY text, reading_rank, id
                """,
                texts,
            ).fetchall()
        readings: dict[str, dict[str, str]] = {}
        for row in rows:
            readings.setdefault(
                str(row["text"]),
                {
                    "marked": str(row["marked_pinyin"]),
                    "numeric": str(row["numeric_pinyin"]),
                },
            )
        return readings

    def _tail_classifications_for(
        self,
        *,
        direction: str,
        root_anchor: str,
        texts: tuple[str, ...],
    ) -> dict[str, dict[str, str]]:
        if not texts:
            return {}
        placeholders = ",".join("?" for _ in texts)
        with self._connect() as connection:
            rows = connection.execute(
                f"""
                SELECT text, matched_anchor, semantic_class, note, assessor,
                       updated_at_utc
                FROM tail_classifications
                WHERE direction = ?
                  AND root_anchor = ?
                  AND text IN ({placeholders})
                """,
                (direction, root_anchor, *texts),
            ).fetchall()
        return {
            str(row["text"]): {
                "matched_anchor": str(row["matched_anchor"]),
                "semantic_class": str(row["semantic_class"]),
                "note": str(row["note"]),
                "assessor": str(row["assessor"]),
                "updated_at_utc": str(row["updated_at_utc"]),
            }
            for row in rows
        }

    def analyze_affix_family(
        self,
        *,
        direction: str,
        root_anchor: str,
        refinements: list[str],
        intended_class: str = CandidateClass.PRODUCTIVE_PHRASE.value,
        minimum_frequency: int = 0,
        only_unencoded: bool = True,
        limit: int = 200,
    ) -> dict[str, Any]:
        """Discover prefix/suffix families and verify both split components."""
        root_anchor, normalized_refinements = self._validate_affix_model(
            direction=direction,
            root_anchor=root_anchor,
            refinements=refinements,
            intended_class=intended_class,
        )
        if minimum_frequency < 0:
            raise ValueError("minimum_frequency cannot be negative")
        if not 1 <= limit <= 500:
            raise ValueError("limit must be between 1 and 500")

        literal = self._like_literal(root_anchor)
        like_pattern = f"{literal}%" if direction == "prefix" else f"%{literal}"
        clauses = [
            "u.text LIKE ? ESCAPE '\\'",
            "u.text <> ?",
            "u.bcc_frequency >= ?",
        ]
        parameters: list[object] = [like_pattern, root_anchor, minimum_frequency]
        if only_unencoded:
            clauses.append("u.has_gated_reading = 0")
            clauses.append("u.baseline_policy <> 'reject'")
        analysis_anchors = (root_anchor, *normalized_refinements)
        with self._connect() as connection:
            rows = connection.execute(
                f"""
                SELECT u.text, u.text_length, u.bcc_frequency,
                       u.has_gated_reading,
                       CASE
                           WHEN u.baseline_policy = 'reject' THEN 'rejected'
                           ELSE COALESCE(a.decision_status, u.baseline_status)
                       END AS decision_status
                FROM candidate_universe AS u
                LEFT JOIN assessments AS a USING (text)
                WHERE {" AND ".join(clauses)}
                ORDER BY u.bcc_frequency DESC, u.text
                """,
                parameters,
            ).fetchall()
            texts_and_anchors: list[tuple[sqlite3.Row, str]] = []
            all_parts: set[str] = set()
            for row in rows:
                text = str(row["text"])
                matched = next(
                    (
                        anchor
                        for anchor in normalized_refinements
                        if (
                            text.startswith(anchor)
                            if direction == "prefix"
                            else text.endswith(anchor)
                        )
                        and len(text) > len(anchor)
                    ),
                    root_anchor,
                )
                remainder = (
                    text[len(matched) :]
                    if direction == "prefix"
                    else text[: -len(matched)]
                )
                if not remainder:
                    continue
                left_part, right_part = (
                    (matched, remainder)
                    if direction == "prefix"
                    else (remainder, matched)
                )
                texts_and_anchors.append((row, matched))
                all_parts.update((left_part, right_part))
                for anchor in analysis_anchors:
                    matches_anchor = (
                        text.startswith(anchor)
                        if direction == "prefix"
                        else text.endswith(anchor)
                    ) and len(text) > len(anchor)
                    if not matches_anchor:
                        continue
                    anchor_remainder = (
                        text[len(anchor) :]
                        if direction == "prefix"
                        else text[: -len(anchor)]
                    )
                    all_parts.update((anchor, anchor_remainder))
            if all_parts:
                placeholders = ",".join("?" for _ in all_parts)
                part_rows = connection.execute(
                    f"""
                    SELECT text, has_gated_reading
                    FROM candidate_universe
                    WHERE text IN ({placeholders})
                    """,
                    tuple(all_parts),
                ).fetchall()
            else:
                part_rows = []
        gated_by_text = {
            str(row["text"]): bool(row["has_gated_reading"]) for row in part_rows
        }

        anchors = analysis_anchors
        anchor_counts = {
            anchor: {"matched": 0, "both_parts_gated": 0} for anchor in anchors
        }
        result_rows: list[dict[str, Any]] = []
        proper_name_classes = {
            CandidateClass.PERSON_NAME.value,
            CandidateClass.PLACE_NAME.value,
            CandidateClass.ORGANIZATION_NAME.value,
        }
        for row, matched_anchor in texts_and_anchors:
            text = str(row["text"])
            remainder = (
                text[len(matched_anchor) :]
                if direction == "prefix"
                else text[: -len(matched_anchor)]
            )
            left_part, right_part = (
                (matched_anchor, remainder)
                if direction == "prefix"
                else (remainder, matched_anchor)
            )
            left_gated = gated_by_text.get(left_part, False)
            right_gated = gated_by_text.get(right_part, False)
            both_gated = left_gated and right_gated
            for anchor in anchors:
                matches_anchor = (
                    text.startswith(anchor)
                    if direction == "prefix"
                    else text.endswith(anchor)
                ) and len(text) > len(anchor)
                if not matches_anchor:
                    continue
                anchor_counts[anchor]["matched"] += 1
                anchor_remainder = (
                    text[len(anchor) :]
                    if direction == "prefix"
                    else text[: -len(anchor)]
                )
                anchor_left, anchor_right = (
                    (anchor, anchor_remainder)
                    if direction == "prefix"
                    else (anchor_remainder, anchor)
                )
                if gated_by_text.get(anchor_left, False) and gated_by_text.get(
                    anchor_right, False
                ):
                    anchor_counts[anchor]["both_parts_gated"] += 1
            if both_gated:
                if intended_class in proper_name_classes:
                    suggestion = "proper_name_rule_candidate"
                elif intended_class == CandidateClass.DOMAIN_TERM.value:
                    suggestion = "domain_rule_candidate"
                else:
                    suggestion = "dynamic_composition_candidate"
                eventual_policy = IntegrationPolicy.DYNAMIC_RECOVERABLE.value
            else:
                suggestion = "reading_evidence_required"
                eventual_policy = IntegrationPolicy.NEEDS_REVIEW.value
            result_rows.append(
                {
                    "text": text,
                    "bcc_frequency": int(row["bcc_frequency"]),
                    "whole_has_gated_reading": bool(row["has_gated_reading"]),
                    "decision_status": str(row["decision_status"]),
                    "matched_anchor": matched_anchor,
                    "left_part": left_part,
                    "right_part": right_part,
                    "left_has_gated_reading": left_gated,
                    "right_has_gated_reading": right_gated,
                    "both_parts_gated": both_gated,
                    "suggestion": suggestion,
                    "suggested_candidate_class": intended_class,
                    "registration_policy": IntegrationPolicy.MODEL_ONLY.value,
                    "eventual_policy_after_replay": eventual_policy,
                }
            )

        visible = result_rows[:limit]
        saved_classifications = self._tail_classifications_for(
            direction=direction,
            root_anchor=root_anchor,
            texts=tuple(str(item["text"]) for item in visible),
        )
        for item in visible:
            item["tail_classification"] = saved_classifications.get(
                str(item["text"])
            )
        reading_parts: list[str] = []
        for item in visible:
            if item["left_has_gated_reading"]:
                reading_parts.append(str(item["left_part"]))
            if item["right_has_gated_reading"]:
                reading_parts.append(str(item["right_part"]))
        reading_texts = tuple(dict.fromkeys(reading_parts))
        readings = self._primary_readings_for(reading_texts)
        for item in visible:
            item["left_reading"] = readings.get(item["left_part"])
            item["right_reading"] = readings.get(item["right_part"])
        return {
            "direction": direction,
            "root_anchor": root_anchor,
            "refinements": normalized_refinements,
            "intended_class": intended_class,
            "only_unencoded": only_unencoded,
            "minimum_frequency": minimum_frequency,
            "total_matches": len(result_rows),
            "both_parts_gated": sum(
                1 for item in result_rows if item["both_parts_gated"]
            ),
            "anchor_counts": [
                {"anchor": anchor, **anchor_counts[anchor]} for anchor in anchors
            ],
            "items": visible,
            "truncated": len(result_rows) > limit,
            "runtime_writes": False,
        }

    @staticmethod
    def _validate_tail_match(
        *,
        text: str,
        direction: str,
        root_anchor: str,
        matched_anchor: str,
    ) -> None:
        if direction not in {"prefix", "suffix"}:
            raise ValueError("direction must be prefix or suffix")
        if not text or not root_anchor or not matched_anchor:
            raise ValueError("text, root_anchor and matched_anchor are required")
        compatible_anchor = (
            matched_anchor.startswith(root_anchor)
            if direction == "prefix"
            else matched_anchor.endswith(root_anchor)
        )
        matches_text = (
            text.startswith(matched_anchor)
            if direction == "prefix"
            else text.endswith(matched_anchor)
        )
        if not compatible_anchor or not matches_text or len(text) <= len(matched_anchor):
            raise ValueError("classification does not match the requested affix")

    def save_tail_classifications(
        self,
        *,
        direction: str,
        root_anchor: str,
        classifications: list[dict[str, Any]],
        assessor: str,
    ) -> dict[str, Any]:
        """Save semantic labels without directly deciding candidate admission."""
        assessor = assessor.strip()
        root_anchor = root_anchor.strip()
        if not assessor:
            raise ValueError("assessor is required")
        if not root_anchor or len(root_anchor) > 16:
            raise ValueError("root_anchor must contain 1-16 characters")
        if not 1 <= len(classifications) <= 500:
            raise ValueError("classifications must contain 1-500 items")

        normalized: list[dict[str, str]] = []
        seen: set[str] = set()
        for item in classifications:
            if not isinstance(item, dict):
                raise ValueError("each classification must be an object")
            text = str(item.get("text", "")).strip()
            matched_anchor = str(item.get("matched_anchor", "")).strip()
            semantic_class = str(item.get("semantic_class", "")).strip()
            note = str(item.get("note", "")).strip()
            self._validate_tail_match(
                text=text,
                direction=direction,
                root_anchor=root_anchor,
                matched_anchor=matched_anchor,
            )
            if semantic_class not in TAIL_SEMANTIC_CLASSES:
                raise ValueError("unsupported tail semantic class")
            if text in seen:
                raise ValueError(f"duplicate classification text: {text}")
            if len(note) > 1000:
                raise ValueError("classification note cannot exceed 1000 characters")
            seen.add(text)
            normalized.append(
                {
                    "text": text,
                    "matched_anchor": matched_anchor,
                    "semantic_class": semantic_class,
                    "note": note,
                }
            )

        now = datetime.now(timezone.utc).isoformat()
        with InputModelStore(self.input_model_database) as store:
            placeholders = ",".join("?" for _ in normalized)
            existing_texts = {
                str(row[0])
                for row in store.connection.execute(
                    f"""
                    SELECT text
                    FROM candidate_universe
                    WHERE text IN ({placeholders})
                      AND baseline_policy <> 'reject'
                    """,
                    tuple(item["text"] for item in normalized),
                )
            }
            missing = sorted(seen - existing_texts)
            if missing:
                raise ValueError(
                    "classification text is outside the reviewable universe: "
                    + "、".join(missing)
                )
            for item in normalized:
                store.connection.execute(
                    """
                    INSERT INTO tail_classifications(
                        text, direction, root_anchor, matched_anchor,
                        semantic_class, note, assessor,
                        created_at_utc, updated_at_utc
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(text, direction, root_anchor) DO UPDATE SET
                        matched_anchor = excluded.matched_anchor,
                        semantic_class = excluded.semantic_class,
                        note = excluded.note,
                        assessor = excluded.assessor,
                        updated_at_utc = excluded.updated_at_utc
                    """,
                    (
                        item["text"],
                        direction,
                        root_anchor,
                        item["matched_anchor"],
                        item["semantic_class"],
                        item["note"],
                        assessor,
                        now,
                        now,
                    ),
                )
                store.connection.execute(
                    """
                    INSERT INTO audit_events(
                        text, event_type, assessor, payload_json, created_at_utc
                    ) VALUES (?, 'tail_classification_saved', ?, ?, ?)
                    """,
                    (
                        item["text"],
                        assessor,
                        json.dumps(
                            {
                                "direction": direction,
                                "root_anchor": root_anchor,
                                "matched_anchor": item["matched_anchor"],
                                "semantic_class": item["semantic_class"],
                                "note": item["note"],
                            },
                            ensure_ascii=False,
                            sort_keys=True,
                        ),
                        now,
                    ),
                )
            store.connection.commit()
        return {
            "saved_count": len(normalized),
            "direction": direction,
            "root_anchor": root_anchor,
            "runtime_writes": False,
            "decisions_written": False,
        }

    @staticmethod
    def _currency_measurement_is_covered(
        *,
        text: str,
        direction: str,
        root_anchor: str,
        gated_texts: set[str],
    ) -> bool:
        if direction != "suffix" or not text.endswith(root_anchor):
            return False
        amount = text[: -len(root_anchor)]
        if not amount or NUMERIC_AMOUNT_PATTERN.fullmatch(amount) is None:
            return False
        spoken_amount = amount.translate(str.maketrans("", "", ".．,，"))
        if not spoken_amount or not all(character in gated_texts for character in spoken_amount):
            return False
        coverage = UnencodedCandidateReview._recursive_coverage(
            root_anchor, gated_texts
        )
        return str(coverage["status"]) in {"atomic_gated", "composition_covered"}

    def apply_tail_classifications(
        self,
        *,
        direction: str,
        root_anchor: str,
        assessor: str,
        maximum_items: int = 1000,
    ) -> dict[str, Any]:
        """Turn saved labels into deterministic keep, exclude, or review decisions."""
        assessor = assessor.strip()
        root_anchor = root_anchor.strip()
        if direction not in {"prefix", "suffix"}:
            raise ValueError("direction must be prefix or suffix")
        if not root_anchor:
            raise ValueError("root_anchor is required")
        if not assessor:
            raise ValueError("assessor is required")
        if not 1 <= maximum_items <= 5000:
            raise ValueError("maximum_items must be between 1 and 5000")

        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT tc.*, u.bcc_frequency, a.evidence_json
                FROM tail_classifications AS tc
                JOIN candidate_universe AS u USING (text)
                LEFT JOIN assessments AS a USING (text)
                WHERE tc.direction = ?
                  AND tc.root_anchor = ?
                  AND u.baseline_policy <> 'reject'
                ORDER BY u.bcc_frequency DESC, tc.text
                LIMIT ?
                """,
                (direction, root_anchor, maximum_items),
            ).fetchall()
            gated_texts = {
                str(row[0])
                for row in connection.execute(
                    "SELECT text FROM candidate_universe WHERE has_gated_reading = 1"
                )
            }

        outcomes: list[dict[str, Any]] = []
        with InputModelStore(self.input_model_database) as store:
            for row in rows:
                text = str(row["text"])
                matched_anchor = str(row["matched_anchor"])
                semantic_class = str(row["semantic_class"])
                existing_evidence = (
                    json.loads(row["evidence_json"])
                    if row["evidence_json"] is not None
                    else {}
                )
                previous_tail = existing_evidence.get("tail_classification")
                if row["evidence_json"] is not None and not (
                    isinstance(previous_tail, dict)
                    and previous_tail.get("direction") == direction
                    and previous_tail.get("root_anchor") == root_anchor
                ):
                    outcomes.append(
                        {
                            "text": text,
                            "semantic_class": semantic_class,
                            "disposition": "manual_decision_preserved",
                            "applied": False,
                        }
                    )
                    continue

                self._validate_tail_match(
                    text=text,
                    direction=direction,
                    root_anchor=root_anchor,
                    matched_anchor=matched_anchor,
                )
                remainder = (
                    text[len(matched_anchor) :]
                    if direction == "prefix"
                    else text[: -len(matched_anchor)]
                )
                left_part, right_part = (
                    (matched_anchor, remainder)
                    if direction == "prefix"
                    else (remainder, matched_anchor)
                )
                left_coverage = self._recursive_coverage(left_part, gated_texts)
                right_coverage = self._recursive_coverage(right_part, gated_texts)
                component_statuses = {
                    str(left_coverage["status"]),
                    str(right_coverage["status"]),
                }
                components_covered = component_statuses <= {
                    "atomic_gated",
                    "composition_covered",
                }
                if semantic_class == "currency_measurement":
                    components_covered = self._currency_measurement_is_covered(
                        text=text,
                        direction=direction,
                        root_anchor=root_anchor,
                        gated_texts=gated_texts,
                    )

                if semantic_class in TAIL_DYNAMIC_CLASSES and components_covered:
                    candidate_class = TAIL_DYNAMIC_CLASSES[semantic_class]
                    policy = IntegrationPolicy.MODEL_ONLY
                    status = DecisionStatus.APPROVED
                    disposition = "exclude_from_static_encoding"
                    rationale = (
                        "人工语义分类与程序结构门禁同时成立；"
                        "该字串可由已注音组件恢复，不纳入静态待编码系列。"
                    )
                elif semantic_class == "noise":
                    candidate_class = CandidateClass.NOISE
                    policy = IntegrationPolicy.REJECT
                    status = DecisionStatus.REJECTED
                    disposition = "reject"
                    rationale = (
                        "人工确认该材料属于 R0 确定性无效项；"
                        "程序将其移出待编码系列并保留审计证据。"
                    )
                elif semantic_class == "fixed_lexical_item":
                    candidate_class = CandidateClass.LEXICAL_CANDIDATE
                    policy = IntegrationPolicy.STATIC_KEEP
                    status = DecisionStatus.DEFERRED
                    disposition = "keep_for_encoding_review"
                    rationale = "人工分类为固定词项，保留在静态编码审查系列等待读音证据。"
                else:
                    candidate_class = TAIL_DYNAMIC_CLASSES.get(
                        semantic_class, CandidateClass.UNKNOWN
                    )
                    policy = IntegrationPolicy.NEEDS_REVIEW
                    status = DecisionStatus.DEFERRED
                    disposition = (
                        "reading_or_structure_review"
                        if semantic_class in TAIL_DYNAMIC_CLASSES
                        else "manual_review"
                    )
                    rationale = (
                        "已保存语义分类，但组件读音、结构覆盖或类别仍不足以自动决定；"
                        "保留人工审查。"
                    )

                evidence = {
                    "bcc_frequency": int(row["bcc_frequency"]),
                    "has_gated_reading": False,
                    "review_scope": "unencoded_candidate_admission",
                    "runtime_eligible": False,
                    "runtime_blocking_reason": "missing_gated_source_reading",
                    "tail_classification": {
                        "direction": direction,
                        "root_anchor": root_anchor,
                        "matched_anchor": matched_anchor,
                        "semantic_class": semantic_class,
                        "note": str(row["note"]),
                        "classification_assessor": str(row["assessor"]),
                        "left_part": left_part,
                        "right_part": right_part,
                        "left_coverage": left_coverage,
                        "right_coverage": right_coverage,
                        "components_covered": components_covered,
                        "disposition": disposition,
                    },
                }
                store.put(
                    CandidateAssessment(
                        text=text,
                        candidate_class=candidate_class,
                        integration_policy=policy,
                        status=status,
                        rationale=rationale,
                        assessor=assessor,
                        evidence=evidence,
                    )
                )
                outcomes.append(
                    {
                        "text": text,
                        "semantic_class": semantic_class,
                        "disposition": disposition,
                        "applied": True,
                    }
                )
        counts: dict[str, int] = {}
        for item in outcomes:
            disposition = str(item["disposition"])
            counts[disposition] = counts.get(disposition, 0) + 1
        return {
            "processed_count": len(outcomes),
            "applied_count": sum(1 for item in outcomes if item["applied"]),
            "disposition_counts": counts,
            "items": outcomes,
            "runtime_writes": False,
        }

    @staticmethod
    def _parse_construction_template(template: str) -> tuple[dict[str, Any], ...]:
        template = template.strip()
        if not template or len(template) > 128:
            raise ValueError("template must contain 1-128 characters")
        segments: list[dict[str, Any]] = []
        slot_names: set[str] = set()
        offset = 0
        for match in TEMPLATE_TOKEN_PATTERN.finditer(template):
            literal = template[offset : match.start()]
            if literal:
                if any(character in literal for character in "{}()"):
                    raise ValueError("invalid construction template syntax")
                segments.append({"type": "literal", "text": literal})
            if match.group(1) is not None:
                name = str(match.group(1))
                if name in slot_names:
                    raise ValueError(f"duplicate slot name: {name}")
                slot_names.add(name)
                segments.append(
                    {
                        "type": "slot",
                        "name": name,
                        "optional": bool(match.group(2)),
                    }
                )
            else:
                choices = tuple(
                    dict.fromkeys(
                        item.strip()
                        for item in str(match.group(3)).split("|")
                        if item.strip()
                    )
                )
                if len(choices) < 2:
                    raise ValueError("choice segments require at least two alternatives")
                segments.append({"type": "choice", "choices": choices})
            offset = match.end()
        tail = template[offset:]
        if tail:
            if any(character in tail for character in "{}()"):
                raise ValueError("invalid construction template syntax")
            segments.append({"type": "literal", "text": tail})
        if not slot_names:
            raise ValueError("construction template requires at least one slot")
        if all(segment["type"] == "slot" for segment in segments):
            raise ValueError("construction template requires a literal or choice anchor")
        return tuple(segments)

    @staticmethod
    def _match_construction(
        text: str,
        segments: tuple[dict[str, Any], ...],
        *,
        limit: int = 20,
    ) -> tuple[tuple[dict[str, Any], ...], ...]:
        matches: list[tuple[dict[str, Any], ...]] = []

        def visit(
            segment_index: int,
            text_offset: int,
            values: tuple[dict[str, Any], ...],
        ) -> None:
            if len(matches) >= limit:
                return
            if segment_index == len(segments):
                if text_offset == len(text):
                    matches.append(values)
                return
            segment = segments[segment_index]
            segment_type = segment["type"]
            if segment_type == "literal":
                literal = str(segment["text"])
                if text.startswith(literal, text_offset):
                    visit(
                        segment_index + 1,
                        text_offset + len(literal),
                        (*values, {"type": "literal", "text": literal}),
                    )
                return
            if segment_type == "choice":
                for choice in segment["choices"]:
                    if text.startswith(choice, text_offset):
                        visit(
                            segment_index + 1,
                            text_offset + len(choice),
                            (*values, {"type": "choice", "text": choice}),
                        )
                return

            minimum = 0 if bool(segment["optional"]) else 1
            remaining_required = 0
            for later in segments[segment_index + 1 :]:
                if later["type"] == "literal":
                    remaining_required += len(str(later["text"]))
                elif later["type"] == "choice":
                    remaining_required += min(len(item) for item in later["choices"])
                elif not bool(later["optional"]):
                    remaining_required += 1
            maximum_end = len(text) - remaining_required
            for end in range(maximum_end, text_offset + minimum - 1, -1):
                value = text[text_offset:end]
                visit(
                    segment_index + 1,
                    end,
                    (
                        *values,
                        {
                            "type": "slot",
                            "name": str(segment["name"]),
                            "text": value,
                            "optional": bool(segment["optional"]),
                        },
                    ),
                )

        visit(0, 0, ())
        return tuple(matches)

    @staticmethod
    def _recursive_coverage(
        text: str,
        gated_texts: set[str],
        *,
        maximum_alternatives: int = 12,
    ) -> dict[str, Any]:
        if not text:
            return {"status": "empty_optional", "parts": (), "alternatives": 1}
        if text in gated_texts:
            return {"status": "atomic_gated", "parts": (text,), "alternatives": 1}
        if len(text) == 1:
            return {
                "status": "reading_evidence_required",
                "parts": (text,),
                "alternatives": 0,
            }
        if len(text) == 2:
            if all(character in gated_texts for character in text):
                return {
                    "status": "composition_covered",
                    "parts": tuple(text),
                    "alternatives": 1,
                    "rule": "two_character_dynamic_reachability",
                }
            return {
                "status": "short_form_exception",
                "parts": (text,),
                "alternatives": 0,
            }

        memo: dict[int, tuple[tuple[str, ...], ...]] = {}

        def segment(offset: int) -> tuple[tuple[str, ...], ...]:
            if offset == len(text):
                return ((),)
            if offset in memo:
                return memo[offset]
            candidates: list[tuple[str, ...]] = []
            for end in range(len(text), offset, -1):
                part = text[offset:end]
                if part not in gated_texts:
                    continue
                for suffix in segment(end):
                    candidates.append((part, *suffix))
                    if len(candidates) >= maximum_alternatives:
                        break
                if len(candidates) >= maximum_alternatives:
                    break
            memo[offset] = tuple(candidates)
            return memo[offset]

        segmentations = segment(0)
        if not segmentations:
            return {
                "status": "reading_evidence_required",
                "parts": (text,),
                "alternatives": 0,
            }
        minimum_parts = min(len(item) for item in segmentations)
        preferred = tuple(
            item for item in segmentations if len(item) == minimum_parts
        )
        return {
            "status": (
                "ambiguous_split" if len(preferred) > 1 else "composition_covered"
            ),
            "parts": preferred[0],
            "alternatives": len(preferred),
        }

    def analyze_construction_family(
        self,
        *,
        template: str,
        intended_class: str = CandidateClass.PRODUCTIVE_PHRASE.value,
        minimum_frequency: int = 0,
        only_unencoded: bool = True,
        limit: int = 200,
    ) -> dict[str, Any]:
        """Match a frame template and recursively verify every replaceable slot."""
        segments = self._parse_construction_template(template)
        if intended_class not in AFFIX_ANALYSIS_CLASSES:
            raise ValueError("unsupported construction analysis class")
        if minimum_frequency < 0:
            raise ValueError("minimum_frequency cannot be negative")
        if not 1 <= limit <= 500:
            raise ValueError("limit must be between 1 and 500")

        with self._connect() as connection:
            clauses = ["u.bcc_frequency >= ?"]
            parameters: list[object] = [minimum_frequency]
            if only_unencoded:
                clauses.append("u.has_gated_reading = 0")
                clauses.append("u.baseline_policy <> 'reject'")
            candidate_rows = connection.execute(
                f"""
                SELECT u.text, u.bcc_frequency, u.has_gated_reading,
                       CASE
                           WHEN u.baseline_policy = 'reject' THEN 'rejected'
                           ELSE COALESCE(a.decision_status, u.baseline_status)
                       END AS decision_status
                FROM candidate_universe AS u
                LEFT JOIN assessments AS a USING (text)
                WHERE {" AND ".join(clauses)}
                ORDER BY u.bcc_frequency DESC, u.text
                """,
                parameters,
            ).fetchall()
            gated_texts = {
                str(row[0])
                for row in connection.execute(
                    "SELECT text FROM candidate_universe WHERE has_gated_reading = 1"
                )
            }

        result_rows: list[dict[str, Any]] = []
        for row in candidate_rows:
            text = str(row["text"])
            interpretations = self._match_construction(text, segments)
            if not interpretations:
                continue
            analyzed_interpretations: list[dict[str, Any]] = []
            for interpretation in interpretations:
                components: list[dict[str, Any]] = []
                for component in interpretation:
                    value = str(component["text"])
                    coverage = self._recursive_coverage(value, gated_texts)
                    component_result = {
                        **component,
                        "coverage_status": coverage["status"],
                        "parts": coverage["parts"],
                        "alternatives": coverage["alternatives"],
                    }
                    components.append(component_result)
                statuses = {
                    str(item["coverage_status"])
                    for item in components
                    if item["coverage_status"] != "empty_optional"
                }
                if "reading_evidence_required" in statuses:
                    suggestion = "reading_evidence_required"
                    score = 3
                elif "short_form_exception" in statuses:
                    suggestion = "short_form_exception"
                    score = 2
                elif (
                    "ambiguous_split" in statuses
                    or len(interpretations) > 1
                ):
                    suggestion = "ambiguous_split"
                    score = 1
                else:
                    suggestion = (
                        "proper_name_rule_candidate"
                        if intended_class
                        in {
                            CandidateClass.PERSON_NAME.value,
                            CandidateClass.PLACE_NAME.value,
                            CandidateClass.ORGANIZATION_NAME.value,
                        }
                        else (
                            "domain_rule_candidate"
                            if intended_class == CandidateClass.DOMAIN_TERM.value
                            else "frame_composition_candidate"
                        )
                    )
                    score = 0
                analyzed_interpretations.append(
                    {
                        "components": components,
                        "suggestion": suggestion,
                        "score": score,
                    }
                )
            analyzed_interpretations.sort(
                key=lambda item: (
                    int(item["score"]),
                    sum(
                        len(component["parts"])
                        for component in item["components"]
                    ),
                )
            )
            chosen = analyzed_interpretations[0]
            result_rows.append(
                {
                    "text": text,
                    "bcc_frequency": int(row["bcc_frequency"]),
                    "whole_has_gated_reading": bool(row["has_gated_reading"]),
                    "decision_status": str(row["decision_status"]),
                    "components": chosen["components"],
                    "interpretation_count": len(interpretations),
                    "suggestion": chosen["suggestion"],
                    "suggested_candidate_class": intended_class,
                    "registration_policy": IntegrationPolicy.MODEL_ONLY.value,
                    "eventual_policy_after_replay": (
                        IntegrationPolicy.DYNAMIC_RECOVERABLE.value
                        if chosen["score"] == 0
                        else IntegrationPolicy.NEEDS_REVIEW.value
                    ),
                }
            )

        visible = result_rows[:limit]
        reading_parts = [
            str(part)
            for item in visible
            for component in item["components"]
            for part in component["parts"]
        ]
        readings = self._primary_readings_for(
            tuple(dict.fromkeys(reading_parts))
        )
        for item in visible:
            for component in item["components"]:
                component["part_readings"] = [
                    {"text": part, "reading": readings.get(part)}
                    for part in component["parts"]
                ]
        successful_suggestions = {
            "frame_composition_candidate",
            "proper_name_rule_candidate",
            "domain_rule_candidate",
        }
        return {
            "kind": "frame_template",
            "template": template.strip(),
            "segments": segments,
            "intended_class": intended_class,
            "only_unencoded": only_unencoded,
            "minimum_frequency": minimum_frequency,
            "total_matches": len(result_rows),
            "composition_covered": sum(
                1
                for item in result_rows
                if item["suggestion"] in successful_suggestions
            ),
            "short_form_exceptions": sum(
                1
                for item in result_rows
                if item["suggestion"] == "short_form_exception"
            ),
            "ambiguous_matches": sum(
                1
                for item in result_rows
                if item["suggestion"] == "ambiguous_split"
            ),
            "items": visible,
            "truncated": len(result_rows) > limit,
            "runtime_writes": False,
        }

    def _registered_discovery_rules(self) -> tuple[dict[str, Any], ...]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT family_id, title, evidence_json
                FROM rule_families
                WHERE status = 'registered'
                ORDER BY family_id
                """
            ).fetchall()
            negative_rows = connection.execute(
                """
                SELECT family_id, text
                FROM rule_family_examples
                WHERE example_role = 'negative'
                ORDER BY family_id, text
                """
            ).fetchall()
        negatives: dict[str, set[str]] = {}
        for row in negative_rows:
            negatives.setdefault(str(row["family_id"]), set()).add(str(row["text"]))
        rules: list[dict[str, Any]] = []
        for row in rows:
            evidence = json.loads(row["evidence_json"])
            discovery_model = evidence.get("discovery_model")
            if not isinstance(discovery_model, dict):
                continue
            rules.append(
                {
                    "family_id": str(row["family_id"]),
                    "title": str(row["title"]),
                    "candidate_class": str(
                        evidence.get(
                            "candidate_class",
                            CandidateClass.PRODUCTIVE_PHRASE.value,
                        )
                    ),
                    "model": discovery_model,
                    "negative_examples": negatives.get(str(row["family_id"]), set()),
                }
            )
        return tuple(rules)

    def _evaluate_discovery_rule(
        self,
        *,
        text: str,
        rule: dict[str, Any],
        gated_texts: set[str],
    ) -> dict[str, Any] | None:
        if text in rule["negative_examples"]:
            return {
                "status": "negative_example_excluded",
                "specificity": 10_000,
                "details": {},
            }
        model = rule["model"]
        kind = str(model.get("kind", "affix_hierarchy"))
        success_statuses = {"atomic_gated", "composition_covered"}
        if kind == "affix_hierarchy":
            direction = str(model.get("direction", ""))
            root_anchor = str(model.get("root_anchor", ""))
            refinements = tuple(str(item) for item in model.get("refinements", ()))
            if direction not in {"prefix", "suffix"} or not root_anchor:
                return None
            matches_root = (
                text.startswith(root_anchor)
                if direction == "prefix"
                else text.endswith(root_anchor)
            ) and len(text) > len(root_anchor)
            if not matches_root:
                return None
            matched_anchor = next(
                (
                    anchor
                    for anchor in sorted(
                        refinements, key=lambda item: (-len(item), item)
                    )
                    if (
                        text.startswith(anchor)
                        if direction == "prefix"
                        else text.endswith(anchor)
                    )
                    and len(text) > len(anchor)
                ),
                root_anchor,
            )
            remainder = (
                text[len(matched_anchor) :]
                if direction == "prefix"
                else text[: -len(matched_anchor)]
            )
            left_part, right_part = (
                (matched_anchor, remainder)
                if direction == "prefix"
                else (remainder, matched_anchor)
            )
            left = self._recursive_coverage(left_part, gated_texts)
            right = self._recursive_coverage(right_part, gated_texts)
            statuses = {str(left["status"]), str(right["status"])}
            if statuses <= success_statuses:
                status = "auto_covered"
            elif "reading_evidence_required" in statuses:
                status = "reading_evidence_required"
            elif "short_form_exception" in statuses:
                status = "short_form_exception"
            else:
                status = "ambiguous_split"
            return {
                "status": status,
                "specificity": 100 + len(matched_anchor),
                "details": {
                    "kind": kind,
                    "direction": direction,
                    "matched_anchor": matched_anchor,
                    "left_part": left_part,
                    "right_part": right_part,
                    "left_coverage": left,
                    "right_coverage": right,
                },
            }
        if kind != "frame_template":
            return None
        template = str(model.get("template", ""))
        try:
            segments = self._parse_construction_template(template)
        except ValueError:
            return None
        interpretations = self._match_construction(text, segments)
        if not interpretations:
            return None
        covered: list[tuple[dict[str, Any], ...]] = []
        observed_statuses: set[str] = set()
        for interpretation in interpretations:
            components: list[dict[str, Any]] = []
            for component in interpretation:
                coverage = self._recursive_coverage(
                    str(component["text"]), gated_texts
                )
                observed_statuses.add(str(coverage["status"]))
                components.append({**component, "coverage": coverage})
            statuses = {
                str(item["coverage"]["status"])
                for item in components
                if item["coverage"]["status"] != "empty_optional"
            }
            if statuses <= success_statuses:
                covered.append(tuple(components))
        if len(covered) == 1:
            status = "auto_covered"
            chosen = covered[0]
        elif len(covered) > 1:
            status = "ambiguous_split"
            chosen = covered[0]
        elif "reading_evidence_required" in observed_statuses:
            status = "reading_evidence_required"
            chosen = ()
        elif "short_form_exception" in observed_statuses:
            status = "short_form_exception"
            chosen = ()
        else:
            status = "ambiguous_split"
            chosen = ()
        fixed_length = sum(
            (
                len(str(segment["text"]))
                if segment["type"] == "literal"
                else min(len(item) for item in segment["choices"])
                if segment["type"] == "choice"
                else 0
            )
            for segment in segments
        )
        return {
            "status": status,
            "specificity": 200 + fixed_length,
            "details": {
                "kind": kind,
                "template": template,
                "interpretation_count": len(interpretations),
                "components": chosen,
            },
        }

    def _automatic_screening_records(
        self,
        *,
        minimum_frequency: int,
    ) -> tuple[list[dict[str, Any]], tuple[dict[str, Any], ...]]:
        rules = self._registered_discovery_rules()
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT u.text, u.bcc_frequency
                FROM candidate_universe AS u
                LEFT JOIN assessments AS a USING (text)
                WHERE u.has_gated_reading = 0
                  AND u.baseline_policy <> 'reject'
                  AND u.baseline_status IN ('proposed', 'deferred')
                  AND u.baseline_rule <> 'missing_trusted_mandarin_reading'
                  AND u.bcc_frequency >= ?
                  AND a.text IS NULL
                ORDER BY u.bcc_frequency DESC, u.text
                """,
                (minimum_frequency,),
            ).fetchall()
            gated_texts = {
                str(row[0])
                for row in connection.execute(
                    "SELECT text FROM candidate_universe WHERE has_gated_reading = 1"
                )
            }

        records: list[dict[str, Any]] = []
        for row in rows:
            text = str(row["text"])
            evaluations: list[dict[str, Any]] = []
            excluded_by: list[str] = []
            for rule in rules:
                evaluation = self._evaluate_discovery_rule(
                    text=text,
                    rule=rule,
                    gated_texts=gated_texts,
                )
                if evaluation is None:
                    continue
                if evaluation["status"] == "negative_example_excluded":
                    excluded_by.append(str(rule["family_id"]))
                    continue
                evaluations.append({**evaluation, "rule": rule})

            covered = [
                item for item in evaluations if item["status"] == "auto_covered"
            ]
            category: str
            selected: dict[str, Any] | None = None
            if covered:
                classes = {
                    str(item["rule"]["candidate_class"]) for item in covered
                }
                covered.sort(
                    key=lambda item: (
                        -int(item["specificity"]),
                        str(item["rule"]["family_id"]),
                    )
                )
                top_specificity = int(covered[0]["specificity"])
                top = [
                    item
                    for item in covered
                    if int(item["specificity"]) == top_specificity
                ]
                if len(classes) > 1 or len(top) > 1:
                    category = "rule_conflict"
                else:
                    category = "auto_covered"
                    selected = covered[0]
            elif any(
                item["status"] == "short_form_exception" for item in evaluations
            ):
                category = "short_form_exception"
            elif any(item["status"] == "ambiguous_split" for item in evaluations):
                category = "ambiguous_split"
            elif any(
                item["status"] == "reading_evidence_required"
                for item in evaluations
            ):
                category = "reading_evidence_required"
            elif excluded_by:
                category = "negative_example_excluded"
            else:
                generic = self._recursive_coverage(text, gated_texts)
                if generic["status"] == "composition_covered":
                    category = "unclassified_composition"
                elif generic["status"] == "ambiguous_split":
                    category = "ambiguous_split"
                elif generic["status"] == "short_form_exception":
                    category = "short_form_exception"
                else:
                    category = "reading_evidence_required"

            records.append(
                {
                    "text": text,
                    "bcc_frequency": int(row["bcc_frequency"]),
                    "category": category,
                    "selected_family_id": (
                        str(selected["rule"]["family_id"]) if selected else None
                    ),
                    "selected_family_title": (
                        str(selected["rule"]["title"]) if selected else None
                    ),
                    "candidate_class": (
                        str(selected["rule"]["candidate_class"])
                        if selected
                        else None
                    ),
                    "match_details": selected["details"] if selected else None,
                    "matched_families": [
                        {
                            "family_id": str(item["rule"]["family_id"]),
                            "title": str(item["rule"]["title"]),
                            "candidate_class": str(
                                item["rule"]["candidate_class"]
                            ),
                            "status": str(item["status"]),
                            "specificity": int(item["specificity"]),
                        }
                        for item in evaluations
                    ],
                    "excluded_by_negative_examples": excluded_by,
                }
            )
        return records, rules

    @staticmethod
    def _residual_clusters(
        records: list[dict[str, Any]],
        *,
        limit: int = 20,
    ) -> list[dict[str, Any]]:
        clusters: dict[tuple[str, str], dict[str, Any]] = {}
        residual_categories = {
            "unclassified_composition",
            "reading_evidence_required",
            "short_form_exception",
            "ambiguous_split",
        }
        for record in records:
            if record["category"] not in residual_categories:
                continue
            text = str(record["text"])
            if len(text) < 2:
                continue
            for direction, anchor in (("prefix", text[0]), ("suffix", text[-1])):
                key = (direction, anchor)
                cluster = clusters.setdefault(
                    key,
                    {
                        "direction": direction,
                        "anchor": anchor,
                        "count": 0,
                        "total_frequency": 0,
                        "examples": [],
                    },
                )
                cluster["count"] += 1
                cluster["total_frequency"] += int(record["bcc_frequency"])
                if len(cluster["examples"]) < 5:
                    cluster["examples"].append(text)
        return sorted(
            (item for item in clusters.values() if int(item["count"]) >= 2),
            key=lambda item: (
                -int(item["count"]),
                -int(item["total_frequency"]),
                str(item["direction"]),
                str(item["anchor"]),
            ),
        )[:limit]

    def automatic_screening(
        self,
        *,
        minimum_frequency: int = 0,
        limit: int = 200,
    ) -> dict[str, Any]:
        """Preview deterministic rule screening without writing decisions."""
        if minimum_frequency < 0:
            raise ValueError("minimum_frequency cannot be negative")
        if not 1 <= limit <= 500:
            raise ValueError("limit must be between 1 and 500")
        records, rules = self._automatic_screening_records(
            minimum_frequency=minimum_frequency
        )
        categories = (
            "auto_covered",
            "rule_conflict",
            "negative_example_excluded",
            "short_form_exception",
            "ambiguous_split",
            "unclassified_composition",
            "reading_evidence_required",
        )
        counts = {
            category: sum(1 for item in records if item["category"] == category)
            for category in categories
        }
        return {
            "pending_total": len(records),
            "registered_rule_count": len(rules),
            "category_counts": counts,
            "automatic_coverage_rate": (
                counts["auto_covered"] / len(records) if records else 0.0
            ),
            "items": records[:limit],
            "truncated": len(records) > limit,
            "residual_clusters": self._residual_clusters(records),
            "runtime_writes": False,
        }

    def apply_automatic_screening(
        self,
        *,
        assessor: str,
        minimum_frequency: int = 0,
        maximum_items: int = 1000,
    ) -> dict[str, Any]:
        """Write only unique, conflict-free rule matches to the model-only layer."""
        assessor = assessor.strip()
        if not assessor:
            raise ValueError("assessor is required")
        if minimum_frequency < 0:
            raise ValueError("minimum_frequency cannot be negative")
        if not 1 <= maximum_items <= 5000:
            raise ValueError("maximum_items must be between 1 and 5000")
        records, _rules = self._automatic_screening_records(
            minimum_frequency=minimum_frequency
        )
        all_covered = [
            item for item in records if item["category"] == "auto_covered"
        ]
        covered = all_covered[:maximum_items]
        applied: list[str] = []
        with InputModelStore(self.input_model_database) as store:
            for item in covered:
                evidence = {
                    "bcc_frequency": int(item["bcc_frequency"]),
                    "has_gated_reading": False,
                    "review_scope": "unencoded_candidate_admission",
                    "admission_stage": "rule_auto_screened_unvalidated",
                    "runtime_eligible": False,
                    "runtime_blocking_reason": "missing_gated_source_reading",
                    "automation_blocking_reason": (
                        "requires_replay_and_attested_component_readings"
                    ),
                    "automatic_screening": {
                        "family_id": item["selected_family_id"],
                        "family_title": item["selected_family_title"],
                        "match_details": item["match_details"],
                        "registered_rule_only": True,
                    },
                    "rule_family_id": item["selected_family_id"],
                }
                assessment = CandidateAssessment(
                    text=str(item["text"]),
                    candidate_class=CandidateClass(str(item["candidate_class"])),
                    integration_policy=IntegrationPolicy.MODEL_ONLY,
                    status=DecisionStatus.APPROVED,
                    rationale=(
                        f"已登记规则族 {item['selected_family_id']} "
                        "的无冲突自动筛查命中；"
                        "仅进入模型评测层，仍需回放验证。"
                    ),
                    assessor=assessor,
                    evidence=evidence,
                )
                store.put(assessment)
                applied.append(str(item["text"]))
        return {
            "applied_count": len(applied),
            "applied_texts": applied,
            "remaining_safe_matches": max(
                0, len(all_covered) - len(applied)
            ),
            "runtime_writes": False,
            "integration_policy": IntegrationPolicy.MODEL_ONLY.value,
        }

    def rule_families(self) -> tuple[dict[str, Any], ...]:
        """Return registered review hypotheses, not runtime composition rules."""
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT f.*,
                       SUM(CASE WHEN e.example_role = 'representative' THEN 1 ELSE 0 END)
                           AS representative_count,
                       SUM(CASE WHEN e.example_role = 'positive' THEN 1 ELSE 0 END)
                           AS positive_count,
                       SUM(CASE WHEN e.example_role = 'negative' THEN 1 ELSE 0 END)
                           AS negative_count
                FROM rule_families AS f
                LEFT JOIN rule_family_examples AS e USING (family_id)
                GROUP BY f.family_id
                ORDER BY f.updated_at_utc DESC, f.family_id
                """
            ).fetchall()
        return tuple(
            {
                "family_id": str(row["family_id"]),
                "title": str(row["title"]),
                "pattern_description": str(row["pattern_description"]),
                "applicability_notes": str(row["applicability_notes"]),
                "status": str(row["status"]),
                "rationale": str(row["rationale"]),
                "assessor": str(row["assessor"]),
                "review_standard": str(row["review_standard"]),
                "representative_count": int(row["representative_count"] or 0),
                "positive_count": int(row["positive_count"] or 0),
                "negative_count": int(row["negative_count"] or 0),
                "updated_at_utc": str(row["updated_at_utc"]),
                "runtime_eligible": False,
                "validation_state": "unvalidated",
            }
            for row in rows
        )

    def rule_family_detail(self, family_id: str) -> dict[str, Any]:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM rule_families WHERE family_id = ?",
                (family_id,),
            ).fetchone()
            if row is None:
                raise KeyError(family_id)
            examples = connection.execute(
                """
                SELECT text, example_role, note
                FROM rule_family_examples
                WHERE family_id = ?
                ORDER BY CASE example_role
                    WHEN 'representative' THEN 0
                    WHEN 'positive' THEN 1
                    ELSE 2 END, text
                """,
                (family_id,),
            ).fetchall()
            audit_rows = connection.execute(
                """
                SELECT event_type, assessor, payload_json, created_at_utc
                FROM rule_family_audit_events
                WHERE family_id = ?
                ORDER BY id DESC
                LIMIT 20
                """,
                (family_id,),
            ).fetchall()
        return {
            "family_id": str(row["family_id"]),
            "title": str(row["title"]),
            "pattern_description": str(row["pattern_description"]),
            "applicability_notes": str(row["applicability_notes"]),
            "status": str(row["status"]),
            "rationale": str(row["rationale"]),
            "assessor": str(row["assessor"]),
            "review_standard": str(row["review_standard"]),
            "evidence": json.loads(row["evidence_json"]),
            "created_at_utc": str(row["created_at_utc"]),
            "updated_at_utc": str(row["updated_at_utc"]),
            "examples": [dict(item) for item in examples],
            "audit_events": [
                {
                    "event_type": str(item["event_type"]),
                    "assessor": str(item["assessor"]),
                    "payload": json.loads(item["payload_json"]),
                    "created_at_utc": str(item["created_at_utc"]),
                }
                for item in audit_rows
            ],
            "runtime_eligible": False,
            "validation_state": "unvalidated",
            "blocking_reason": "requires_replay_and_attested_component_readings",
        }

    def register_rule_family(
        self,
        *,
        family_id: str,
        title: str,
        pattern_description: str,
        applicability_notes: str,
        representative: str,
        positive_examples: list[str],
        negative_examples: list[str],
        candidate_class: str,
        rationale: str,
        assessor: str,
        review_standard: str = "standard",
        custom_criteria: dict[str, Any] | None = None,
        discovery_model: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Register a bounded rule hypothesis with examples and counterexamples.

        Registration classifies its positive corpus examples as ``model_only``.
        It never promotes the family to a runtime rule or supplies readings.
        """
        family_id = family_id.strip()
        title = title.strip()
        pattern_description = pattern_description.strip()
        applicability_notes = applicability_notes.strip()
        representative = representative.strip()
        rationale = rationale.strip()
        assessor = assessor.strip()
        if not RULE_FAMILY_ID_PATTERN.fullmatch(family_id):
            raise ValueError(
                "family_id must be 3-64 lowercase ASCII letters, digits, '.', '_' or '-'"
            )
        required = {
            "title": title,
            "pattern_description": pattern_description,
            "representative": representative,
            "rationale": rationale,
            "assessor": assessor,
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise ValueError(f"{', '.join(missing)} is required")
        if candidate_class not in AFFIX_ANALYSIS_CLASSES:
            raise ValueError(
                "unsupported rule family class"
            )
        if review_standard not in REVIEW_STANDARDS:
            raise ValueError(f"unsupported review standard: {review_standard}")

        positives = tuple(
            dict.fromkeys(
                item.strip()
                for item in [representative, *positive_examples]
                if isinstance(item, str) and item.strip()
            )
        )
        negatives = tuple(
            dict.fromkeys(
                item.strip()
                for item in negative_examples
                if isinstance(item, str) and item.strip()
            )
        )
        overlap = sorted(set(positives) & set(negatives))
        if overlap:
            raise ValueError(
                "positive and negative examples overlap: " + "、".join(overlap)
            )
        if not negatives:
            raise ValueError("at least one negative example is required")
        all_examples = (*positives, *negatives)
        placeholders = ",".join("?" for _ in all_examples)
        with self._connect() as connection:
            rows = connection.execute(
                f"""
                SELECT text, has_gated_reading
                FROM candidate_universe
                WHERE text IN ({placeholders})
                """,
                all_examples,
            ).fetchall()
        universe = {str(row["text"]): bool(row["has_gated_reading"]) for row in rows}
        outside = [text for text in all_examples if text not in universe]
        if outside:
            raise ValueError(
                "rule family examples must come from the candidate universe: "
                + "、".join(outside)
            )
        encoded = [text for text in positives if universe[text]]
        if encoded:
            raise ValueError(
                "this workbench only registers unencoded positive examples: "
                + "、".join(encoded)
            )

        normalized_custom = self._normalize_custom_criteria(
            review_standard, custom_criteria
        )
        now = datetime.now(timezone.utc).isoformat()
        evidence: dict[str, Any] = {
            "review_scope": "rule_family_registration",
            "runtime_eligible": False,
            "validation_state": "unvalidated",
            "runtime_blocking_reason": (
                "requires_replay_and_attested_component_readings"
            ),
            "candidate_class": candidate_class,
            "review_standard": review_standard,
        }
        if discovery_model is not None:
            if not isinstance(discovery_model, dict):
                raise ValueError("discovery_model must be an object")
            discovery_kind = str(
                discovery_model.get("kind", "affix_hierarchy")
            )
            if discovery_kind == "frame_template":
                discovery_template = str(discovery_model.get("template", ""))
                template_segments = self._parse_construction_template(
                    discovery_template
                )
                with self._connect() as connection:
                    gated_texts = {
                        str(row[0])
                        for row in connection.execute(
                            """
                            SELECT text
                            FROM candidate_universe
                            WHERE has_gated_reading = 1
                            """
                        )
                    }
                incomplete: list[str] = []
                for text in positives:
                    interpretations = self._match_construction(
                        text, template_segments
                    )
                    acceptable_count = 0
                    for interpretation in interpretations:
                        statuses = {
                            self._recursive_coverage(
                                str(component["text"]), gated_texts
                            )["status"]
                            for component in interpretation
                            if str(component["text"])
                        }
                        if statuses <= {
                            "atomic_gated",
                            "composition_covered",
                            "empty_optional",
                        }:
                            acceptable_count += 1
                    if acceptable_count != 1:
                        incomplete.append(text)
                if incomplete:
                    raise ValueError(
                        "frame positive examples must match the template and "
                        "have unambiguous recursive reading coverage: "
                        + "、".join(incomplete)
                    )
                evidence["discovery_model"] = {
                    "kind": "frame_template",
                    "template": discovery_template.strip(),
                    "segments": template_segments,
                }
            elif discovery_kind == "affix_hierarchy":
                discovery_direction = str(discovery_model.get("direction", ""))
                discovery_root = str(discovery_model.get("root_anchor", ""))
                discovery_refinements = discovery_model.get("refinements", [])
                if not isinstance(discovery_refinements, list):
                    raise ValueError("discovery_model refinements must be an array")
                normalized_root, normalized_refinements = self._validate_affix_model(
                    direction=discovery_direction,
                    root_anchor=discovery_root,
                    refinements=discovery_refinements,
                    intended_class=candidate_class,
                )
                discovery_parts: dict[str, tuple[str, str]] = {}
                for text in positives:
                    matches_root = (
                        text.startswith(normalized_root)
                        if discovery_direction == "prefix"
                        else text.endswith(normalized_root)
                    ) and len(text) > len(normalized_root)
                    if not matches_root:
                        raise ValueError(
                            f"positive example {text!r} does not match "
                            "the discovery root"
                        )
                    matched_anchor = next(
                        (
                            anchor
                            for anchor in normalized_refinements
                            if (
                                text.startswith(anchor)
                                if discovery_direction == "prefix"
                                else text.endswith(anchor)
                            )
                            and len(text) > len(anchor)
                        ),
                        normalized_root,
                    )
                    remainder = (
                        text[len(matched_anchor) :]
                        if discovery_direction == "prefix"
                        else text[: -len(matched_anchor)]
                    )
                    discovery_parts[text] = (
                        (matched_anchor, remainder)
                        if discovery_direction == "prefix"
                        else (remainder, matched_anchor)
                    )
                unique_parts = tuple(
                    dict.fromkeys(
                        part for pair in discovery_parts.values() for part in pair
                    )
                )
                placeholders = ",".join("?" for _ in unique_parts)
                with self._connect() as connection:
                    part_rows = connection.execute(
                        f"""
                        SELECT text, has_gated_reading
                        FROM candidate_universe
                        WHERE text IN ({placeholders})
                        """,
                        unique_parts,
                    ).fetchall()
                gated_parts = {
                    str(row["text"])
                    for row in part_rows
                    if bool(row["has_gated_reading"])
                }
                incomplete = [
                    text
                    for text, parts in discovery_parts.items()
                    if any(part not in gated_parts for part in parts)
                ]
                if incomplete:
                    raise ValueError(
                        "discovery-model positive examples require gated readings "
                        "on both split parts: "
                        + "、".join(incomplete)
                    )
                evidence["discovery_model"] = {
                    "kind": "affix_hierarchy",
                    "direction": discovery_direction,
                    "root_anchor": normalized_root,
                    "refinements": normalized_refinements,
                }
            else:
                raise ValueError("unsupported discovery model kind")
        if normalized_custom is not None:
            evidence["custom_criteria"] = normalized_custom
        payload = {
            "family_id": family_id,
            "title": title,
            "pattern_description": pattern_description,
            "applicability_notes": applicability_notes,
            "status": "registered",
            "rationale": rationale,
            "evidence": evidence,
            "examples": {
                "representative": representative,
                "positive": positives,
                "negative": negatives,
            },
        }
        with sqlite3.connect(self.input_model_database) as connection:
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA foreign_keys = ON")
            existing = connection.execute(
                "SELECT created_at_utc FROM rule_families WHERE family_id = ?",
                (family_id,),
            ).fetchone()
            previous_positive_rows = connection.execute(
                """
                SELECT text
                FROM rule_family_examples
                WHERE family_id = ?
                  AND example_role IN ('representative', 'positive')
                """,
                (family_id,),
            ).fetchall()
            previous_positives = {
                str(item["text"]) for item in previous_positive_rows
            }
            created = str(existing["created_at_utc"]) if existing else now
            connection.execute(
                """
                INSERT INTO rule_families(
                    family_id, title, pattern_description, applicability_notes,
                    status, rationale, assessor, review_standard, evidence_json,
                    created_at_utc, updated_at_utc
                ) VALUES (?, ?, ?, ?, 'registered', ?, ?, ?, ?, ?, ?)
                ON CONFLICT(family_id) DO UPDATE SET
                    title = excluded.title,
                    pattern_description = excluded.pattern_description,
                    applicability_notes = excluded.applicability_notes,
                    status = excluded.status,
                    rationale = excluded.rationale,
                    assessor = excluded.assessor,
                    review_standard = excluded.review_standard,
                    evidence_json = excluded.evidence_json,
                    updated_at_utc = excluded.updated_at_utc
                """,
                (
                    family_id,
                    title,
                    pattern_description,
                    applicability_notes,
                    rationale,
                    assessor,
                    review_standard,
                    json.dumps(evidence, ensure_ascii=False, sort_keys=True),
                    created,
                    now,
                ),
            )
            connection.execute(
                "DELETE FROM rule_family_examples WHERE family_id = ?",
                (family_id,),
            )
            example_rows = [(representative, "representative")]
            example_rows.extend(
                (text, "positive") for text in positives if text != representative
            )
            example_rows.extend((text, "negative") for text in negatives)
            connection.executemany(
                """
                INSERT INTO rule_family_examples(
                    family_id, text, example_role, note, created_at_utc
                ) VALUES (?, ?, ?, '', ?)
                """,
                (
                    (family_id, text, role, now)
                    for text, role in example_rows
                ),
            )
            connection.execute(
                """
                INSERT INTO rule_family_audit_events(
                    family_id, event_type, assessor, payload_json, created_at_utc
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    family_id,
                    "rule_family_created" if existing is None else "rule_family_updated",
                    assessor,
                    json.dumps(payload, ensure_ascii=False, sort_keys=True),
                    now,
                ),
            )
            for removed_text in sorted(previous_positives - set(positives)):
                assessment_row = connection.execute(
                    "SELECT evidence_json FROM assessments WHERE text = ?",
                    (removed_text,),
                ).fetchone()
                if assessment_row is None:
                    continue
                assessment_evidence = json.loads(assessment_row["evidence_json"])
                if assessment_evidence.get("rule_family_id") != family_id:
                    continue
                connection.execute(
                    "DELETE FROM assessments WHERE text = ?",
                    (removed_text,),
                )
                connection.execute(
                    """
                    INSERT INTO audit_events(
                        text, event_type, assessor, payload_json, created_at_utc
                    ) VALUES (?, 'rule_family_membership_removed', ?, ?, ?)
                    """,
                    (
                        removed_text,
                        assessor,
                        json.dumps(
                            {"rule_family_id": family_id},
                            ensure_ascii=False,
                            sort_keys=True,
                        ),
                        now,
                    ),
                )
            connection.commit()

        for text in positives:
            self.decide(
                text=text,
                action="approve",
                candidate_class=candidate_class,
                integration_policy=IntegrationPolicy.MODEL_ONLY.value,
                rationale=f"规则族 {family_id} 的已登记正例：{rationale}",
                assessor=assessor,
                review_standard=review_standard,
                custom_criteria=normalized_custom,
                rule_family_id=family_id,
            )
        return self.rule_family_detail(family_id)

    @staticmethod
    def _normalize_custom_criteria(
        review_standard: str,
        custom_criteria: dict[str, Any] | None,
    ) -> dict[str, str] | None:
        if review_standard != "reviewer":
            return None
        if not isinstance(custom_criteria, dict):
            raise ValueError("reviewer standard requires custom criteria")
        normalized = {
            "name": str(custom_criteria.get("name", "")).strip(),
            "goal": str(custom_criteria.get("goal", "")).strip(),
            "rules": str(custom_criteria.get("rules", "")).strip(),
        }
        if not normalized["name"]:
            raise ValueError("custom criteria name is required")
        if normalized["goal"] not in {"runtime", "evaluation", "discovery"}:
            raise ValueError("unsupported custom criteria goal")
        if not normalized["rules"]:
            raise ValueError("custom criteria rules are required")
        return normalized

    def queue(
        self,
        *,
        status: str = "proposed",
        query: str = "",
        minimum_frequency: int = 0,
        text_length: int | None = None,
        limit: int = 50,
        cursor: str | None = None,
    ) -> ReviewQueuePage:
        if status not in REVIEW_STATUSES:
            raise ValueError(f"unsupported decision status: {status}")
        if minimum_frequency < 0:
            raise ValueError("minimum_frequency cannot be negative")
        if text_length is not None and text_length < 1:
            raise ValueError("text_length must be a positive integer")
        if not 1 <= limit <= 100:
            raise ValueError("limit must be between 1 and 100")

        clauses = [
            "u.has_gated_reading = 0",
            """
            CASE
                WHEN u.baseline_policy = 'reject' THEN 'rejected'
                ELSE COALESCE(a.decision_status, u.baseline_status)
            END = ?
            """,
            "u.bcc_frequency >= ?",
        ]
        parameters: list[object] = [status, minimum_frequency]
        normalized_query = query.strip()
        if normalized_query:
            clauses.append("u.text LIKE ?")
            parameters.append(f"%{normalized_query}%")
        if text_length is not None:
            clauses.append("u.text_length = ?")
            parameters.append(text_length)
        if cursor:
            cursor_frequency, cursor_text = _decode_cursor(cursor)
            clauses.append(
                "(u.bcc_frequency < ? OR "
                "(u.bcc_frequency = ? AND u.text > ?))"
            )
            parameters.extend((cursor_frequency, cursor_frequency, cursor_text))
        parameters.append(limit + 1)

        with self._connect() as connection:
            rows = connection.execute(
                f"""
                SELECT
                    u.text,
                    u.text_length,
                    u.bcc_frequency,
                    u.has_bcc_evidence,
                    u.has_source_rejection,
                    COALESCE(a.candidate_class, u.baseline_class) AS candidate_class,
                    COALESCE(a.integration_policy, u.baseline_policy)
                        AS integration_policy,
                    CASE
                        WHEN u.baseline_policy = 'reject' THEN 'rejected'
                        ELSE COALESCE(a.decision_status, u.baseline_status)
                    END AS decision_status,
                    COALESCE(a.rationale, u.baseline_rule) AS rationale,
                    COALESCE(a.assessor, 'baseline:' || u.baseline_rule) AS assessor,
                    (
                        SELECT COUNT(*)
                        FROM context_evidence AS e
                        WHERE e.text = u.text
                    ) AS context_count,
                    a.updated_at_utc
                FROM candidate_universe AS u
                LEFT JOIN assessments AS a USING (text)
                WHERE {" AND ".join(clauses)}
                ORDER BY u.bcc_frequency DESC, u.text
                LIMIT ?
                """,
                parameters,
            ).fetchall()

        has_more = len(rows) > limit
        visible = rows[:limit]
        categories_by_text = self._bcc_categories_for(
            tuple(str(row["text"]) for row in visible)
        )
        items = tuple(
            ReviewQueueItem(
                text=str(row["text"]),
                text_length=int(row["text_length"]),
                text_length_label=_text_length_label(int(row["text_length"])),
                bcc_frequency=int(row["bcc_frequency"]),
                bcc_categories=categories_by_text.get(str(row["text"]), ()),
                has_bcc_evidence=bool(row["has_bcc_evidence"]),
                has_source_rejection=bool(row["has_source_rejection"]),
                candidate_class=str(row["candidate_class"]),
                integration_policy=str(row["integration_policy"]),
                decision_status=str(row["decision_status"]),
                rationale=str(row["rationale"]),
                assessor=str(row["assessor"]),
                context_count=int(row["context_count"]),
                updated_at_utc=(
                    str(row["updated_at_utc"])
                    if row["updated_at_utc"] is not None
                    else None
                ),
            )
            for row in visible
        )
        next_cursor = None
        if has_more and items:
            last = items[-1]
            next_cursor = _encode_cursor(last.bcc_frequency, last.text)
        return ReviewQueuePage(items=items, next_cursor=next_cursor)

    def detail(self, text: str) -> dict[str, Any]:
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT u.*,
                       CASE
                           WHEN u.baseline_policy = 'reject' THEN u.baseline_class
                           ELSE COALESCE(a.candidate_class, u.baseline_class)
                       END AS effective_class,
                       CASE
                           WHEN u.baseline_policy = 'reject' THEN u.baseline_policy
                           ELSE COALESCE(a.integration_policy, u.baseline_policy)
                       END AS effective_policy,
                       CASE
                           WHEN u.baseline_policy = 'reject' THEN 'rejected'
                           ELSE COALESCE(a.decision_status, u.baseline_status)
                       END AS effective_status,
                       COALESCE(a.rationale, u.baseline_rule) AS effective_rationale,
                       COALESCE(a.assessor, 'baseline:' || u.baseline_rule)
                           AS effective_assessor,
                       a.confidence,
                       a.evidence_json,
                       a.updated_at_utc
                FROM candidate_universe AS u
                LEFT JOIN assessments AS a USING (text)
                WHERE u.text = ? AND u.has_gated_reading = 0
                """,
                (text,),
            ).fetchone()
            if row is None:
                raise KeyError(text)
            audit_rows = connection.execute(
                """
                SELECT event_type, assessor, payload_json, created_at_utc
                FROM audit_events
                WHERE text = ?
                ORDER BY id DESC
                LIMIT 20
                """,
                (text,),
            ).fetchall()
            context_rows = connection.execute(
                """
                SELECT left_context, matched_text, right_context,
                       source, source_reference
                FROM context_evidence
                WHERE text = ?
                ORDER BY id
                LIMIT 20
                """,
                (text,),
            ).fetchall()
            recursive_row = connection.execute(
                """
                SELECT *
                FROM recursive_composition_evidence
                WHERE text = ?
                """,
                (text,),
            ).fetchone()
            maximum_parts_row = connection.execute(
                """
                SELECT value FROM metadata
                WHERE key = 'recursive_composition_maximum_parts_per_step'
                """
            ).fetchone()
            maximum_parts_per_step = (
                int(maximum_parts_row[0]) if maximum_parts_row else 6
            )

        with SourceLexicon(self.source_database) as source:
            source_candidate = source.candidate(text)
            recursive_components: list[dict[str, Any]] = []
            if recursive_row is not None:
                segments = json.loads(
                    recursive_row["preferred_segments_json"]
                )
                for segment in segments:
                    part = str(segment["text"])
                    if segment["kind"] == "encoded_multichar":
                        part_readings = source.readings(part)
                        if not part_readings:
                            continue
                        recursive_components.append(
                            {
                                **segment,
                                "text_length": len(part),
                                "reading_count": len(part_readings),
                                "primary": asdict(part_readings[0]),
                                "readings": [
                                    asdict(reading)
                                    for reading in part_readings[:4]
                                ],
                                "readings_truncated": (
                                    len(part_readings) > 4
                                ),
                            }
                        )
                        continue
                    internal_parts = [
                        str(value)
                        for value in segment.get("internal_parts", [])
                    ]
                    groups = [
                        source.readings(value) for value in internal_parts
                    ]
                    if not groups or any(not group for group in groups):
                        continue
                    primary = [asdict(group[0]) for group in groups]
                    recursive_components.append(
                        {
                            **segment,
                            "text_length": len(part),
                            "reading_count": math.prod(
                                len(group) for group in groups
                            ),
                            "primary": {
                                "reading_id": [
                                    item["reading_id"] for item in primary
                                ],
                                "marked": " ".join(
                                    str(item["marked"]) for item in primary
                                ),
                                "numeric": " ".join(
                                    str(item["numeric"]) for item in primary
                                ),
                                "is_primary": all(
                                    bool(item["is_primary"])
                                    for item in primary
                                ),
                            },
                            "readings": [],
                            "readings_truncated": any(
                                len(group) > 1 for group in groups
                            ),
                            "single_reading_groups": [
                                [asdict(reading) for reading in group[:4]]
                                for group in groups
                            ],
                        }
                    )

        evidence = (
            json.loads(row["evidence_json"])
            if row["evidence_json"] is not None
            else {}
        )
        if bool(row["dynamic_reachable"]):
            evidence = {
                **evidence,
                "reachability_scope": "builtin_candidate_evidence",
                "dynamic_reachable": True,
                "dynamic_reachability_rule": str(
                    row["dynamic_reachability_rule"]
                ),
                "components": tuple(str(row["text"])),
                "component_gate": "both_single_characters_have_gated_readings",
                "changes_candidate_disposition": False,
                "runtime_eligible": False,
            }
        recursive_composition = None
        if recursive_row is not None:
            composition_tree: dict[str, Any] = {}
            if recursive_components:
                composition_tree, _depth = build_composition_tree(
                    recursive_components,
                    maximum_parts_per_step=maximum_parts_per_step,
                )
            recursive_composition = {
                "reachability_status": str(
                    recursive_row["reachability_status"]
                ),
                "preferred_parts": json.loads(
                    recursive_row["preferred_parts_json"]
                ),
                "preferred_segments": json.loads(
                    recursive_row["preferred_segments_json"]
                ),
                "alternative_parts": json.loads(
                    recursive_row["alternative_parts_json"]
                ),
                "minimum_leaf_parts": recursive_row["minimum_leaf_parts"],
                "minimum_segmentation_count": str(
                    recursive_row["minimum_segmentation_count"]
                ),
                "alternatives_truncated": bool(
                    recursive_row["alternatives_truncated"]
                ),
                "structural_ambiguous": bool(
                    recursive_row["structural_ambiguous"]
                ),
                "reading_combination_count": str(
                    recursive_row["reading_combination_count"]
                ),
                "reading_ambiguous": bool(
                    recursive_row["reading_ambiguous"]
                ),
                "primary_marked_input": str(
                    recursive_row["primary_marked_input"]
                ),
                "primary_numeric_input": str(
                    recursive_row["primary_numeric_input"]
                ),
                "component_readings": recursive_components,
                "composition_tree": composition_tree,
                "recursive_depth": int(recursive_row["recursive_depth"]),
                "encoded_multichar_coverage": int(
                    recursive_row["encoded_multichar_coverage"]
                ),
                "encoded_multichar_component_count": int(
                    recursive_row["encoded_multichar_component_count"]
                ),
                "dynamic_residual_blocks": json.loads(
                    recursive_row["dynamic_residual_blocks_json"]
                ),
                "dynamic_residual_character_count": int(
                    recursive_row["dynamic_residual_character_count"]
                ),
                "single_exception_count": int(
                    recursive_row["single_exception_count"]
                ),
                "blocker": json.loads(recursive_row["blocker_json"]),
                "evidence_rule": str(recursive_row["evidence_rule"]),
                "changes_candidate_disposition": False,
                "creates_whole_string_reading": False,
            }
            evidence = {
                **evidence,
                "recursive_composition": recursive_composition,
            }
        return {
            "text": str(row["text"]),
            "text_length": int(row["text_length"]),
            "text_length_label": _text_length_label(int(row["text_length"])),
            "bcc_frequency": int(row["bcc_frequency"]),
            "has_bcc_evidence": bool(row["has_bcc_evidence"]),
            "has_gated_reading": False,
            "has_source_rejection": bool(row["has_source_rejection"]),
            "dynamic_reachable": bool(row["dynamic_reachable"]),
            "dynamic_reachability_rule": str(
                row["dynamic_reachability_rule"]
            ),
            "recursive_composition": recursive_composition,
            "candidate_class": str(row["effective_class"]),
            "integration_policy": str(row["effective_policy"]),
            "decision_status": str(row["effective_status"]),
            "rationale": str(row["effective_rationale"]),
            "assessor": str(row["effective_assessor"]),
            "confidence": row["confidence"],
            "evidence": evidence,
            "updated_at_utc": (
                str(row["updated_at_utc"])
                if row["updated_at_utc"] is not None
                else None
            ),
            "source": {
                "categories": source_candidate.source_categories,
                "rejection_reasons": source_candidate.rejection_reasons,
                "readings": [asdict(reading) for reading in source_candidate.readings],
            },
            "contexts": [dict(item) for item in context_rows],
            "audit_events": [
                {
                    "event_type": str(item["event_type"]),
                    "assessor": str(item["assessor"]),
                    "payload": json.loads(item["payload_json"]),
                    "created_at_utc": str(item["created_at_utc"]),
                }
                for item in audit_rows
            ],
            "runtime_eligible": False,
            "blocking_reason": (
                "missing_trusted_mandarin_reading"
                if str(row["baseline_rule"])
                == "missing_trusted_mandarin_reading"
                else "missing_gated_source_reading"
            ),
        }

    def decide(
        self,
        *,
        text: str,
        action: str,
        candidate_class: str,
        integration_policy: str | None,
        rationale: str,
        assessor: str,
        review_standard: str = "standard",
        custom_criteria: dict[str, Any] | None = None,
        rule_family_id: str | None = None,
    ) -> dict[str, Any]:
        rationale = rationale.strip()
        assessor = assessor.strip()
        if not rationale:
            raise ValueError("rationale is required")
        if not assessor:
            raise ValueError("assessor is required")
        if review_standard not in REVIEW_STANDARDS:
            raise ValueError(f"unsupported review standard: {review_standard}")
        normalized_custom_criteria = self._normalize_custom_criteria(
            review_standard, custom_criteria
        )
        if rule_family_id is not None:
            rule_family_id = rule_family_id.strip()
            if not RULE_FAMILY_ID_PATTERN.fullmatch(rule_family_id):
                raise ValueError("invalid rule family id")
        try:
            selected_class = CandidateClass(candidate_class)
        except ValueError as exc:
            raise ValueError(f"unsupported candidate class: {candidate_class}") from exc

        with sqlite3.connect(self.input_model_database) as connection:
            connection.row_factory = sqlite3.Row
            universe = connection.execute(
                "SELECT * FROM candidate_universe WHERE text = ?",
                (text,),
            ).fetchone()
        if universe is None:
            raise KeyError(text)
        if bool(universe["has_gated_reading"]):
            raise ValueError("the review workbench only accepts unencoded strings")
        if (
            str(universe["baseline_policy"]) == IntegrationPolicy.REJECT.value
            and action != "reject"
        ):
            raise ValueError(
                "source policy permanently rejects this string; "
                "it cannot be approved or deferred"
            )

        if action == "approve":
            policy_value = integration_policy or IntegrationPolicy.STATIC_KEEP.value
            if policy_value not in APPROVAL_POLICIES:
                raise ValueError(
                    "unencoded admission may only target static_keep or model_only"
                )
            status = DecisionStatus.APPROVED
            policy = IntegrationPolicy(policy_value)
            admission_stage = "lexical_approved_pending_source_reading"
        elif action == "reject":
            status = DecisionStatus.REJECTED
            policy = IntegrationPolicy.REJECT
            admission_stage = "lexical_rejected"
        elif action == "defer":
            status = DecisionStatus.DEFERRED
            policy = IntegrationPolicy.NEEDS_REVIEW
            admission_stage = "evidence_deferred"
        else:
            raise ValueError(f"unsupported decision action: {action}")

        evidence = {
            "bcc_frequency": int(universe["bcc_frequency"]),
            "has_bcc_evidence": bool(universe["has_bcc_evidence"]),
            "has_gated_reading": False,
            "has_source_rejection": bool(universe["has_source_rejection"]),
            "review_scope": "unencoded_candidate_admission",
            "admission_stage": admission_stage,
            "runtime_eligible": False,
            "runtime_blocking_reason": "missing_gated_source_reading",
            "review_standard": review_standard,
        }
        if normalized_custom_criteria is not None:
            evidence["custom_criteria"] = normalized_custom_criteria
        if rule_family_id is not None:
            evidence["rule_family_id"] = rule_family_id
            evidence["admission_stage"] = "rule_family_example_unvalidated"
        assessment = CandidateAssessment(
            text=text,
            candidate_class=selected_class,
            integration_policy=policy,
            status=status,
            rationale=rationale,
            assessor=assessor,
            evidence=evidence,
        )
        with InputModelStore(self.input_model_database) as store:
            store.put(assessment)
        return self.detail(text)
