"""Plan and evaluate bounded construction-component caches."""

from __future__ import annotations

import json
import sqlite3
from dataclasses import asdict, dataclass
from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Any
from urllib.parse import quote


class ConstructionFamily(StrEnum):
    DE = "de_construction"
    SUO = "suo_construction"


@dataclass(frozen=True)
class ConstructionComponentCandidate:
    text: str
    numeric_pinyin: str
    family: ConstructionFamily
    bcc_frequency: int
    dependent_reading_count: int
    dependent_frequency: int
    utility_score: float
    current_disposition: str
    proposed_role: str
    decision_status: str
    decision_rationale: str


@dataclass(frozen=True)
class SegmentationResult:
    reachable: bool
    minimum_parts: int | None
    minimum_alternatives: tuple[tuple[str, ...], ...]


def _readonly_uri(path: Path) -> str:
    return f"file:{quote(path.resolve().as_posix(), safe='/:')}?mode=ro"


def _tokens(numeric_pinyin: str) -> tuple[str, ...]:
    return tuple(token for token in str(numeric_pinyin).split() if token)


def construction_family(
    text: str,
    numeric_pinyin: str,
) -> ConstructionFamily | None:
    normalized = str(text or "").strip()
    readings = _tokens(numeric_pinyin)
    if len(normalized) < 2 or len(readings) != len(normalized):
        return None
    if normalized.endswith("的") and readings[-1] == "de5":
        return ConstructionFamily.DE
    if normalized.startswith("所") and readings[0] == "suo3":
        return ConstructionFamily.SUO
    return None


def _load_policy(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError("unsupported construction component policy schema")
    if payload.get("safeguards", {}).get("source_readings_only") is not True:
        raise ValueError("construction policy must require source readings")
    if (
        payload.get("safeguards", {}).get(
            "fixed_lexical_decisions_override_family_rules"
        )
        is not True
    ):
        raise ValueError("construction policy must preserve lexical overrides")
    return payload


def _decision_map(path: Path | None) -> dict[str, dict[str, Any]]:
    if path is None:
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    result: dict[str, dict[str, Any]] = {}
    for batch in payload.get("batches", []):
        for decision in batch.get("decisions", []):
            text = str(decision.get("text", "")).strip()
            if text:
                result[text] = decision
    return result


def plan_construction_components(
    *,
    capacity_database: Path,
    policy_path: Path,
    decision_catalog: Path | None = None,
    input_model_database: Path | None = None,
) -> tuple[ConstructionComponentCandidate, ...]:
    policy = _load_policy(policy_path)
    maximum_length = int(policy["maximum_component_length"])
    gate = policy["cache_gate"]
    minimum_dependents = int(gate["minimum_dependent_reading_count"])
    decisions = _decision_map(decision_catalog)
    protected_classes = set(
        policy["safeguards"].get("excluded_candidate_classes", [])
    )
    display_exceptions = {
        ConstructionFamily(family): set(config.get("display_and_component_texts", []))
        for family, config in policy["families"].items()
    }
    effective_classes: dict[str, str] = {}
    if input_model_database is not None:
        input_connection = sqlite3.connect(
            _readonly_uri(input_model_database),
            uri=True,
        )
        try:
            effective_classes = {
                str(row[0]): str(row[1])
                for row in input_connection.execute(
                    """
                    SELECT u.text,
                           COALESCE(a.candidate_class, u.baseline_class)
                    FROM candidate_universe AS u
                    LEFT JOIN assessments AS a USING (text)
                    WHERE u.text_length BETWEEN 2 AND ?
                      AND (
                            SUBSTR(u.text, -1, 1) = '的'
                         OR SUBSTR(u.text, 1, 1) = '所'
                      )
                    """,
                    (maximum_length,),
                )
            }
        finally:
            input_connection.close()

    connection = sqlite3.connect(_readonly_uri(capacity_database), uri=True)
    connection.row_factory = sqlite3.Row
    try:
        rows = connection.execute(
            """
            SELECT i.text, r.numeric_pinyin, i.bcc_frequency,
                   i.reading_count, i.recoverable_reading_count,
                   i.mandatory_static, i.dependent_reading_count,
                   i.dependent_frequency, i.utility_score,
                   i.recommended_disposition
            FROM static_capacity_items AS i
            JOIN reading_analysis AS r
              ON r.text = i.text
             AND r.is_primary = 1
            WHERE i.text_length BETWEEN 2 AND ?
              AND (
                    SUBSTR(i.text, -1, 1) = '的'
                 OR SUBSTR(i.text, 1, 1) = '所'
              )
            ORDER BY i.utility_score DESC, i.bcc_frequency DESC, i.text
            """,
            (maximum_length,),
        ).fetchall()
    finally:
        connection.close()

    candidates: list[ConstructionComponentCandidate] = []
    for row in rows:
        family = construction_family(
            str(row["text"]),
            str(row["numeric_pinyin"]),
        )
        if family is None:
            continue
        effective_class = effective_classes.get(str(row["text"]), "")
        if effective_class in protected_classes:
            continue
        decision = decisions.get(str(row["text"]), {})
        status = str(decision.get("decision_status", "proposed"))
        policy_value = str(decision.get("integration_policy", ""))
        candidate_class = str(decision.get("candidate_class", ""))
        rationale = str(decision.get("rationale", ""))
        decision_evidence = decision.get("evidence", {})
        if not isinstance(decision_evidence, dict):
            decision_evidence = {}
        prebuilt_decision = str(
            decision_evidence.get("prebuilt_component_decision", "")
        )
        all_recoverable = int(row["recoverable_reading_count"]) == int(
            row["reading_count"]
        )

        if status == "rejected":
            role = "reject"
        elif str(row["text"]) in display_exceptions.get(family, set()):
            role = "display_and_component"
        elif status == "approved" and policy_value == "static_keep":
            role = "display_and_component"
        elif int(row["mandatory_static"]):
            role = "display_and_component"
        elif prebuilt_decision == "do_not_prebuild_use_runtime_generation":
            role = str(gate["fallback_role"])
        elif (
            all_recoverable
            and int(row["dependent_reading_count"]) >= minimum_dependents
        ):
            role = "component_only_candidate"
        else:
            role = str(gate["fallback_role"])
        if candidate_class == "fixed_expression" and status == "approved":
            role = "display_and_component"

        candidates.append(
            ConstructionComponentCandidate(
                text=str(row["text"]),
                numeric_pinyin=str(row["numeric_pinyin"]),
                family=family,
                bcc_frequency=int(row["bcc_frequency"]),
                dependent_reading_count=int(row["dependent_reading_count"]),
                dependent_frequency=int(row["dependent_frequency"]),
                utility_score=float(row["utility_score"]),
                current_disposition=str(row["recommended_disposition"]),
                proposed_role=role,
                decision_status=status,
                decision_rationale=rationale,
            )
        )
    return tuple(candidates)


class _AttestedLookup:
    def __init__(self, connection: sqlite3.Connection) -> None:
        self.connection = connection

    @lru_cache(maxsize=500_000)
    def has(self, text: str, numeric_pinyin: str) -> bool:
        row = self.connection.execute(
            """
            SELECT 1
            FROM canonical_readings
            WHERE text = ?
              AND numeric_pinyin = ?
              AND (LENGTH(text) > 1 OR pronunciation_scope = 'standalone')
            LIMIT 1
            """,
            (text, numeric_pinyin),
        ).fetchone()
        return row is not None


def _segment(
    *,
    text: str,
    numeric_pinyin: str,
    lookup: _AttestedLookup,
    blocked_components: frozenset[str] = frozenset(),
    maximum_alternatives: int = 32,
) -> SegmentationResult:
    readings = _tokens(numeric_pinyin)
    if len(text) < 2 or len(readings) != len(text):
        return SegmentationResult(False, None, ())
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
            if part in blocked_components:
                continue
            numeric = " ".join(readings[offset:end])
            if not lookup.has(part, numeric):
                continue
            for suffix in visit(end):
                candidates.append((part, *suffix))
        if not candidates:
            memo[offset] = ()
            return ()
        minimum = min(len(item) for item in candidates)
        preferred = sorted(
            {item for item in candidates if len(item) == minimum}
        )[:maximum_alternatives]
        memo[offset] = tuple(preferred)
        return memo[offset]

    alternatives = visit(0)
    return SegmentationResult(
        reachable=bool(alternatives),
        minimum_parts=(len(alternatives[0]) if alternatives else None),
        minimum_alternatives=alternatives,
    )


def evaluate_prebuilt_component(
    *,
    source_database: Path,
    policy_path: Path,
    component_text: str,
    component_numeric_pinyin: str,
) -> dict[str, Any]:
    policy = _load_policy(policy_path)
    gate = policy["cache_gate"]
    family = construction_family(component_text, component_numeric_pinyin)
    if family is None:
        raise ValueError("component does not match a registered construction")

    connection = sqlite3.connect(_readonly_uri(source_database), uri=True)
    connection.row_factory = sqlite3.Row
    lookup = _AttestedLookup(connection)
    try:
        if not lookup.has(component_text, component_numeric_pinyin):
            raise ValueError("component has no exact source-backed reading")
        target_rows = connection.execute(
            """
            SELECT text, numeric_pinyin, bcc_frequency
            FROM canonical_readings
            WHERE text_length > ?
              AND INSTR(text, ?) > 0
            ORDER BY bcc_frequency DESC, text, reading_rank
            """,
            (len(component_text), component_text),
        ).fetchall()

        comparisons: list[dict[str, Any]] = []
        improved = 0
        total_parts_saved = 0
        weighted_parts_saved = 0
        newly_ambiguous = 0
        best_uses_component = 0
        reachable_with = 0
        reachable_without = 0
        for row in target_rows:
            text = str(row["text"])
            numeric = str(row["numeric_pinyin"])
            with_component = _segment(
                text=text,
                numeric_pinyin=numeric,
                lookup=lookup,
            )
            without_component = _segment(
                text=text,
                numeric_pinyin=numeric,
                lookup=lookup,
                blocked_components=frozenset({component_text}),
            )
            reachable_with += int(with_component.reachable)
            reachable_without += int(without_component.reachable)
            uses_component = any(
                component_text in alternative
                for alternative in with_component.minimum_alternatives
            )
            best_uses_component += int(uses_component)
            parts_saved = 0
            if (
                with_component.minimum_parts is not None
                and without_component.minimum_parts is not None
            ):
                parts_saved = max(
                    without_component.minimum_parts
                    - with_component.minimum_parts,
                    0,
                )
            if parts_saved:
                improved += 1
                total_parts_saved += parts_saved
                weighted_parts_saved += parts_saved * int(row["bcc_frequency"])
            added_ambiguity = (
                with_component.minimum_parts == without_component.minimum_parts
                and len(with_component.minimum_alternatives)
                > len(without_component.minimum_alternatives)
            )
            newly_ambiguous += int(added_ambiguity)
            if uses_component or parts_saved or added_ambiguity:
                comparisons.append(
                    {
                        "text": text,
                        "numeric_pinyin": numeric,
                        "bcc_frequency": int(row["bcc_frequency"]),
                        "with_component": asdict(with_component),
                        "without_component": asdict(without_component),
                        "parts_saved": parts_saved,
                        "new_minimum_segmentation_ambiguity": added_ambiguity,
                    }
                )
    finally:
        connection.close()

    minimum_improved = int(gate["minimum_ab_improved_target_readings"])
    improvement_ratio = improved / len(target_rows) if target_rows else 0.0
    structural_competition_ratio = (
        newly_ambiguous / len(target_rows) if target_rows else 0.0
    )
    minimum_improvement_ratio = float(
        gate.get("minimum_ab_improvement_ratio", 0.0)
    )
    maximum_structural_competition_ratio = float(
        gate.get(
            "maximum_structural_competition_ratio",
            0.0,
        )
    )
    keep = (
        improved >= minimum_improved
        and improvement_ratio >= minimum_improvement_ratio
        and structural_competition_ratio
        <= maximum_structural_competition_ratio
    )
    family_config = policy.get("families", {}).get(family.value, {})
    display_and_component = component_text in set(
        family_config.get("display_and_component_texts", [])
    )
    decision = (
        (
            "keep_as_display_and_component"
            if display_and_component
            else "keep_as_component_only"
        )
        if keep
        else "do_not_prebuild_use_runtime_generation"
    )
    return {
        "schema_version": 1,
        "component": {
            "text": component_text,
            "numeric_pinyin": component_numeric_pinyin,
            "family": family.value,
        },
        "target_readings": len(target_rows),
        "metrics": {
            "reachable_with_component": reachable_with,
            "reachable_without_component": reachable_without,
            "minimum_part_count_improved": improved,
            "total_parts_saved": total_parts_saved,
            "bcc_weighted_parts_saved": weighted_parts_saved,
            "minimum_paths_using_component": best_uses_component,
            "new_minimum_segmentation_ambiguities": newly_ambiguous,
            "minimum_part_count_improvement_ratio": improvement_ratio,
            "structural_competition_ratio": structural_competition_ratio,
            "user_visible_output_ambiguities": 0,
        },
        "gate": {
            "minimum_improved_target_readings": minimum_improved,
            "minimum_improvement_ratio": minimum_improvement_ratio,
            "maximum_structural_competition_ratio": (
                maximum_structural_competition_ratio
            ),
        },
        "decision": decision,
        "comparisons": comparisons,
        "safeguards": policy["safeguards"],
    }
