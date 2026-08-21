"""Conservative policy proposals based only on explicit source metadata."""

from __future__ import annotations

import json
from pathlib import Path

from .types import (
    CandidateAssessment,
    CandidateClass,
    DecisionStatus,
    IntegrationPolicy,
    SourceCandidate,
)


class PolicyClassifier:
    """Create review proposals; never approve a candidate automatically."""

    def __init__(self, policy_path: Path):
        self.policy_path = policy_path.resolve()
        policy = json.loads(self.policy_path.read_text(encoding="utf-8"))
        declared_classes = set(policy.get("candidate_classes", ()))
        declared_policies = set(policy.get("integration_policies", ()))
        if declared_classes != {item.value for item in CandidateClass}:
            raise ValueError("candidate class policy does not match the code taxonomy")
        if declared_policies != {item.value for item in IntegrationPolicy}:
            raise ValueError("integration policy does not match the code taxonomy")
        self.hints = dict(policy.get("source_category_hints", {}))

    def classify(self, candidate: SourceCandidate) -> CandidateAssessment:
        evidence = {
            "bcc_frequency": candidate.bcc_frequency,
            "source_categories": candidate.source_categories,
            "reading_ids": tuple(reading.reading_id for reading in candidate.readings),
            "rejection_reasons": candidate.rejection_reasons,
        }
        if len(candidate.text) == 1 and candidate.has_gated_reading:
            return CandidateAssessment(
                text=candidate.text,
                candidate_class=CandidateClass.SINGLE_CHARACTER,
                integration_policy=IntegrationPolicy.STATIC_KEEP,
                status=DecisionStatus.PROPOSED,
                rationale="有合规来源读音的单字；建议保留为基础材料，仍须审查批准。",
                assessor="policy:single_character",
                confidence=1.0,
                evidence=evidence,
            )

        source_categories = set(candidate.source_categories)
        prioritized_hints = sorted(
            self.hints.items(),
            key=lambda item: (int(item[1].get("priority", 1000)), item[0]),
        )
        for category, hint in prioritized_hints:
            if category not in source_categories:
                continue
            return CandidateAssessment(
                text=candidate.text,
                candidate_class=CandidateClass(hint["candidate_class"]),
                integration_policy=IntegrationPolicy(hint["integration_policy"]),
                status=DecisionStatus.PROPOSED,
                rationale=str(hint["reason"]),
                assessor=f"policy:source_category:{category}",
                confidence=1.0,
                evidence=evidence,
            )

        if candidate.has_gated_reading:
            return CandidateAssessment(
                text=candidate.text,
                candidate_class=CandidateClass.LEXICAL_CANDIDATE,
                integration_policy=IntegrationPolicy.NEEDS_REVIEW,
                status=DecisionStatus.PROPOSED,
                rationale="存在合规读音，但来源没有给出足以决定词汇类型和整合方式的显式分类。",
                assessor="policy:gated_reading_unclassified",
                evidence=evidence,
            )

        rationale = "没有合规读音来源；不得逐字猜测读音，等待语境分类和来源补充。"
        if candidate.rejection_reasons:
            rationale = "现有读音记录均被门禁拒绝；保留拒绝证据并等待来源审查。"
        return CandidateAssessment(
            text=candidate.text,
            candidate_class=CandidateClass.UNKNOWN,
            integration_policy=IntegrationPolicy.NEEDS_REVIEW,
            status=DecisionStatus.PROPOSED,
            rationale=rationale,
            assessor="policy:unresolved",
            evidence=evidence,
        )
