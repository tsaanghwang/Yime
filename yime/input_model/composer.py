"""Auditable dynamic recovery from approved, attested components."""

from __future__ import annotations

import itertools
import json
import math
from dataclasses import dataclass
from pathlib import Path

from .protocols import CompositionScorer
from .source import SourceLexicon
from .store import InputModelStore
from .types import CompositionCandidate, SourceReading


@dataclass(frozen=True)
class CompositionPolicy:
    minimum_parts: int = 2
    maximum_parts: int = 6
    maximum_reading_combinations: int = 128
    part_count_penalty: float = 1.0

    @classmethod
    def from_path(cls, path: Path) -> "CompositionPolicy":
        values = json.loads(path.read_text(encoding="utf-8"))["dynamic_composition"]
        return cls(
            minimum_parts=int(values["minimum_parts"]),
            maximum_parts=int(values["maximum_parts"]),
            maximum_reading_combinations=int(values["maximum_reading_combinations"]),
            part_count_penalty=float(values["part_count_penalty"]),
        )


@dataclass(frozen=True)
class FrequencyCompositionScorer:
    """Transparent baseline scorer; not a lexicality judgment."""

    part_count_penalty: float = 1.0

    def score(
        self,
        parts: tuple[str, ...],
        readings: tuple[SourceReading, ...],
    ) -> float:
        frequency_score = sum(math.log1p(item.bcc_frequency) for item in readings)
        return frequency_score - self.part_count_penalty * (len(parts) - 1)


class DynamicComposer:
    """Recover a requested text; it does not invent text, readings, or encodings."""

    def __init__(
        self,
        source: SourceLexicon,
        store: InputModelStore,
        policy: CompositionPolicy | None = None,
        scorer: CompositionScorer | None = None,
    ):
        self.source = source
        self.store = store
        self.policy = policy or CompositionPolicy()
        self.scorer = scorer or FrequencyCompositionScorer(
            part_count_penalty=self.policy.part_count_penalty
        )

    def _segmentations(self, text: str) -> list[tuple[str, ...]]:
        results: list[tuple[str, ...]] = []

        def visit(offset: int, parts: tuple[str, ...]) -> None:
            if len(parts) > self.policy.maximum_parts:
                return
            if offset == len(text):
                if len(parts) >= self.policy.minimum_parts:
                    results.append(parts)
                return
            for end in range(offset + 1, len(text) + 1):
                part = text[offset:end]
                if self.store.approved_component(part) is not None:
                    visit(end, (*parts, part))

        visit(0, ())
        return results

    def _allowed_readings(self, text: str) -> tuple[SourceReading, ...]:
        assessment = self.store.approved_component(text)
        if assessment is None:
            return ()
        readings = self.source.readings(text)
        if assessment.allowed_reading_ids:
            allowed = set(assessment.allowed_reading_ids)
            readings = tuple(item for item in readings if item.reading_id in allowed)
        return readings

    def compose(self, text: str) -> tuple[CompositionCandidate, ...]:
        candidates: list[CompositionCandidate] = []
        for parts in self._segmentations(text):
            reading_groups = tuple(self._allowed_readings(part) for part in parts)
            if any(not readings for readings in reading_groups):
                continue
            combination_count = math.prod(len(group) for group in reading_groups)
            if combination_count > self.policy.maximum_reading_combinations:
                continue
            ambiguous = combination_count > 1
            for readings in itertools.product(*reading_groups):
                candidates.append(
                    CompositionCandidate(
                        text=text,
                        parts=parts,
                        marked_pinyin=" ".join(item.marked for item in readings),
                        numeric_pinyin=" ".join(item.numeric for item in readings),
                        reading_ids=tuple(item.reading_id for item in readings),
                        score=self.scorer.score(parts, readings),
                        ambiguous=ambiguous,
                    )
                )
        candidates.sort(
            key=lambda item: (-item.score, len(item.parts), item.parts, item.numeric_pinyin)
        )
        return tuple(candidates)
