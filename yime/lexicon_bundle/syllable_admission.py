"""Reviewed bootstrap admissions for source-attested syllables.

The registry breaks the circular dependency where a structurally valid source
reading cannot enter the materialized inventory because it is not in that
inventory yet.  It contains review facts only; encoding remains the job of the
formal syllable pipeline.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from yime.utils.dictionary_pinyin_compliance import load_policy, review_syllable


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ADMISSION_PATH = (
    REPO_ROOT
    / "internal_data"
    / "pinyin_source_db"
    / "syllable_admission_reviews.json"
)


@dataclass(frozen=True)
class SyllableAdmission:
    numeric: str
    marked: str
    status: str
    scope: str
    rule_id: str
    decision_basis: str
    evidence: tuple[dict[str, Any], ...]

    def admits(self, text: str) -> bool:
        return self.status == "approved" and (
            self.scope in {"all_source_records", "word_context_only"}
            or (self.scope == "multi_character_only" and len(text) > 1)
        )


def load_syllable_admissions(
    path: Path = DEFAULT_ADMISSION_PATH,
) -> dict[str, SyllableAdmission]:
    if not path.is_file():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != "source-syllable-admission-review-v1":
        raise ValueError(f"unsupported syllable admission review schema: {path}")

    policy = load_policy()
    admissions: dict[str, SyllableAdmission] = {}
    for numeric, raw in payload.get("reviews", {}).items():
        status = str(raw.get("status", ""))
        scope = str(raw.get("scope", ""))
        marked = str(raw.get("canonical_marked", ""))
        evidence = tuple(raw.get("evidence", ()))
        if status not in {"approved", "deferred", "rejected"}:
            raise ValueError(f"invalid review status for {numeric}: {status}")
        if scope not in {
            "all_source_records",
            "multi_character_only",
            "word_context_only",
        }:
            raise ValueError(f"invalid admission scope for {numeric}: {scope}")
        reviewed = review_syllable(marked, policy)
        if not reviewed.accepted or reviewed.canonical_numeric != numeric:
            raise ValueError(
                f"reviewed marked form does not canonicalize to {numeric}: {marked}"
            )
        if status == "approved" and not evidence:
            raise ValueError(f"approved syllable has no source evidence: {numeric}")
        admissions[numeric] = SyllableAdmission(
            numeric=numeric,
            marked=reviewed.canonical_marked,
            status=status,
            scope=scope,
            rule_id=str(raw.get("rule_id", "SRC-REVIEWED-SYLLABLE-ADMISSION")),
            decision_basis=str(raw.get("decision_basis", "")),
            evidence=evidence,
        )
    return admissions
