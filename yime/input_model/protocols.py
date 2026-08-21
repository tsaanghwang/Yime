"""Extension seams for rule, statistical, Gram, small-model, or LLM adapters."""

from __future__ import annotations

from typing import Protocol

from .types import CandidateAssessment, SourceCandidate, SourceReading


class CandidateClassifier(Protocol):
    """Return an auditable proposal for one source candidate."""

    def classify(self, candidate: SourceCandidate) -> CandidateAssessment: ...


class CompositionScorer(Protocol):
    """Rank an attested component sequence without changing its readings."""

    def score(
        self,
        parts: tuple[str, ...],
        readings: tuple[SourceReading, ...],
    ) -> float: ...
