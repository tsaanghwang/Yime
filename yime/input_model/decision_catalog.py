"""Version-controlled review decisions for the candidate overlay."""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import quote

from .store import InputModelStore
from .types import (
    CandidateAssessment,
    CandidateClass,
    DecisionStatus,
    IntegrationPolicy,
)


CATALOG_SCHEMA_VERSION = 1


@dataclass(frozen=True)
class CatalogDecision:
    assessment: CandidateAssessment
    expected_bcc_frequency: int | None
    batch_id: str


@dataclass(frozen=True)
class CatalogPlan:
    created: int
    updated: int
    unchanged: int
    frequency_drift: tuple[str, ...]


def _readonly_uri(path: Path) -> str:
    return f"file:{quote(path.resolve().as_posix(), safe='/:')}?mode=ro"


def _required_string(payload: dict[str, Any], key: str, *, context: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{context}.{key} must be a non-empty string")
    return value


def load_decision_catalog(path: Path) -> tuple[CatalogDecision, ...]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != CATALOG_SCHEMA_VERSION:
        raise ValueError(
            f"unsupported decision catalog schema: {payload.get('schema_version')!r}"
        )
    safeguards = payload.get("safeguards")
    if not isinstance(safeguards, dict):
        raise ValueError("safeguards must be an object")
    if safeguards.get("source_lexicon_is_read_only") is not True:
        raise ValueError("catalog must keep source_lexicon_is_read_only enabled")
    if safeguards.get("frequency_orders_review_only") is not True:
        raise ValueError("catalog must declare frequency_orders_review_only")

    batches = payload.get("batches")
    if not isinstance(batches, list) or not batches:
        raise ValueError("batches must be a non-empty array")

    decisions: list[CatalogDecision] = []
    seen: set[str] = set()
    for batch_index, batch in enumerate(batches):
        if not isinstance(batch, dict):
            raise ValueError(f"batches[{batch_index}] must be an object")
        batch_id = _required_string(
            batch, "batch_id", context=f"batches[{batch_index}]"
        )
        rows = batch.get("decisions")
        if not isinstance(rows, list) or not rows:
            raise ValueError(f"batch {batch_id!r} must contain decisions")
        for row_index, row in enumerate(rows):
            context = f"{batch_id}.decisions[{row_index}]"
            if not isinstance(row, dict):
                raise ValueError(f"{context} must be an object")
            text = _required_string(row, "text", context=context)
            if text in seen:
                raise ValueError(f"duplicate decision text: {text}")
            seen.add(text)
            try:
                candidate_class = CandidateClass(
                    _required_string(row, "candidate_class", context=context)
                )
                integration_policy = IntegrationPolicy(
                    _required_string(row, "integration_policy", context=context)
                )
                status = DecisionStatus(
                    _required_string(row, "decision_status", context=context)
                )
            except ValueError as exc:
                raise ValueError(f"{context} has an invalid enum value: {exc}") from exc
            if status is DecisionStatus.PROPOSED:
                raise ValueError(f"{context} must record a reviewed decision")
            if status is DecisionStatus.REJECTED and (
                candidate_class is not CandidateClass.NOISE
                or integration_policy is not IntegrationPolicy.REJECT
            ):
                raise ValueError(
                    f"{context} rejected decisions must use noise + reject"
                )
            if status is DecisionStatus.APPROVED and (
                candidate_class is CandidateClass.NOISE
                or integration_policy
                in {IntegrationPolicy.REJECT, IntegrationPolicy.NEEDS_REVIEW}
            ):
                raise ValueError(
                    f"{context} approved decision has a non-publishable disposition"
                )
            if status is DecisionStatus.DEFERRED and (
                integration_policy is not IntegrationPolicy.NEEDS_REVIEW
            ):
                raise ValueError(
                    f"{context} deferred decisions must use needs_review"
                )
            confidence = row.get("confidence")
            if confidence is not None and (
                not isinstance(confidence, (int, float))
                or not 0.0 <= float(confidence) <= 1.0
            ):
                raise ValueError(f"{context}.confidence must be between 0 and 1")
            expected_bcc_frequency = row.get("bcc_frequency_at_review")
            if expected_bcc_frequency is not None and (
                not isinstance(expected_bcc_frequency, int)
                or expected_bcc_frequency < 0
            ):
                raise ValueError(
                    f"{context}.bcc_frequency_at_review must be a non-negative integer"
                )
            evidence = row.get("evidence", {})
            if not isinstance(evidence, dict):
                raise ValueError(f"{context}.evidence must be an object")
            evidence = {
                **evidence,
                "review_batch": batch_id,
                "frequency_used_for_ordering_only": True,
            }
            if expected_bcc_frequency is not None:
                evidence["bcc_frequency"] = expected_bcc_frequency
                evidence["bcc_frequency_at_review"] = expected_bcc_frequency
            allowed_reading_ids = row.get("allowed_reading_ids", [])
            if (
                not isinstance(allowed_reading_ids, list)
                or any(
                    not isinstance(reading_id, int) or reading_id <= 0
                    for reading_id in allowed_reading_ids
                )
            ):
                raise ValueError(
                    f"{context}.allowed_reading_ids must contain positive integers"
                )
            decisions.append(
                CatalogDecision(
                    assessment=CandidateAssessment(
                        text=text,
                        candidate_class=candidate_class,
                        integration_policy=integration_policy,
                        status=status,
                        rationale=_required_string(
                            row, "rationale", context=context
                        ),
                        assessor=_required_string(row, "assessor", context=context),
                        confidence=(
                            float(confidence) if confidence is not None else None
                        ),
                        evidence=evidence,
                        allowed_reading_ids=tuple(allowed_reading_ids),
                    ),
                    expected_bcc_frequency=expected_bcc_frequency,
                    batch_id=batch_id,
                )
            )
    return tuple(decisions)


def _assessment_payload(assessment: CandidateAssessment) -> tuple[object, ...]:
    return (
        assessment.candidate_class.value,
        assessment.integration_policy.value,
        assessment.status.value,
        assessment.confidence,
        assessment.rationale,
        assessment.assessor,
        json.dumps(assessment.evidence, ensure_ascii=False, sort_keys=True),
        json.dumps(assessment.allowed_reading_ids),
    )


def plan_decision_catalog(
    database: Path,
    decisions: tuple[CatalogDecision, ...],
) -> CatalogPlan:
    if not database.is_file():
        raise FileNotFoundError(f"input model database does not exist: {database}")
    created = updated = unchanged = 0
    frequency_drift: list[str] = []
    with sqlite3.connect(_readonly_uri(database), uri=True) as connection:
        connection.row_factory = sqlite3.Row
        for decision in decisions:
            universe = connection.execute(
                """
                SELECT bcc_frequency, has_gated_reading
                FROM candidate_universe
                WHERE text = ?
                """,
                (decision.assessment.text,),
            ).fetchone()
            if universe is None:
                raise ValueError(
                    "decision text is outside the candidate universe: "
                    f"{decision.assessment.text}"
                )
            if (
                decision.assessment.status is DecisionStatus.APPROVED
                and not bool(universe["has_gated_reading"])
            ):
                raise ValueError(
                    "approved catalog decision has no gated source reading: "
                    f"{decision.assessment.text}"
                )
            if (
                decision.expected_bcc_frequency is not None
                and int(universe["bcc_frequency"])
                != decision.expected_bcc_frequency
            ):
                frequency_drift.append(decision.assessment.text)
            current = connection.execute(
                """
                SELECT candidate_class, integration_policy, decision_status,
                       confidence, rationale, assessor, evidence_json,
                       allowed_reading_ids_json
                FROM assessments
                WHERE text = ?
                """,
                (decision.assessment.text,),
            ).fetchone()
            if current is None:
                created += 1
            elif tuple(current) == _assessment_payload(decision.assessment):
                unchanged += 1
            else:
                updated += 1
    return CatalogPlan(
        created=created,
        updated=updated,
        unchanged=unchanged,
        frequency_drift=tuple(frequency_drift),
    )


def apply_decision_catalog(
    database: Path,
    decisions: tuple[CatalogDecision, ...],
    *,
    overwrite: bool = False,
) -> CatalogPlan:
    plan = plan_decision_catalog(database, decisions)
    if plan.updated and not overwrite:
        raise ValueError(
            f"{plan.updated} existing assessment(s) differ from the catalog; "
            "refusing to overwrite without explicit approval"
        )
    with InputModelStore(database) as store:
        for decision in decisions:
            current = store.get(decision.assessment.text)
            if (
                current is not None
                and _assessment_payload(current)
                == _assessment_payload(decision.assessment)
            ):
                continue
            store.put(decision.assessment)
    return plan
