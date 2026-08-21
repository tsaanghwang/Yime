"""Shared value types for the input candidate model."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any


class CandidateClass(StrEnum):
    SINGLE_CHARACTER = "single_character"
    LEXICAL_CANDIDATE = "lexical_candidate"
    FIXED_EXPRESSION = "fixed_expression"
    PERSON_NAME = "person_name"
    PLACE_NAME = "place_name"
    ORGANIZATION_NAME = "organization_name"
    DOMAIN_TERM = "domain_term"
    SEMI_FIXED_CONSTRUCTION = "semi_fixed_construction"
    PRODUCTIVE_PHRASE = "productive_phrase"
    SYNTACTIC_FRAGMENT = "syntactic_fragment"
    NOISE = "noise"
    CONTEXT_DEPENDENT = "context_dependent"
    UNKNOWN = "unknown"


class IntegrationPolicy(StrEnum):
    STATIC_KEEP = "static_keep"
    DYNAMIC_COMPONENT = "dynamic_component"
    DYNAMIC_RECOVERABLE = "dynamic_recoverable"
    MODEL_ONLY = "model_only"
    REJECT = "reject"
    NEEDS_REVIEW = "needs_review"


class DecisionStatus(StrEnum):
    PROPOSED = "proposed"
    APPROVED = "approved"
    REJECTED = "rejected"
    DEFERRED = "deferred"


@dataclass(frozen=True)
class SourceReading:
    reading_id: int
    text: str
    marked: str
    numeric: str
    is_primary: bool
    bcc_frequency: int
    sources: tuple[str, ...]
    source_categories: tuple[str, ...]
    pronunciation_scope: str = "standalone"
    neutral_tone_positions: tuple[int, ...] = ()
    neutral_tone_status: str = "none"


@dataclass(frozen=True)
class SourceCandidate:
    text: str
    bcc_frequency: int
    readings: tuple[SourceReading, ...] = ()
    source_categories: tuple[str, ...] = ()
    rejection_reasons: tuple[str, ...] = ()

    @property
    def has_gated_reading(self) -> bool:
        return bool(self.readings)


@dataclass(frozen=True)
class CandidateAssessment:
    text: str
    candidate_class: CandidateClass
    integration_policy: IntegrationPolicy
    status: DecisionStatus
    rationale: str
    assessor: str
    confidence: float | None = None
    evidence: dict[str, Any] = field(default_factory=dict)
    allowed_reading_ids: tuple[int, ...] = ()


@dataclass(frozen=True)
class ContextEvidence:
    text: str
    left_context: str
    matched_text: str
    right_context: str
    source: str
    source_reference: str


@dataclass(frozen=True)
class CompositionCandidate:
    text: str
    parts: tuple[str, ...]
    marked_pinyin: str
    numeric_pinyin: str
    reading_ids: tuple[int, ...]
    score: float
    ambiguous: bool
