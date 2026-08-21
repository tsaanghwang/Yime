"""Build the decision overlay and seed a high-frequency review queue."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .classifier import PolicyClassifier
from .store import InputModelStore


@dataclass(frozen=True)
class BuildResult:
    database: Path
    universe_count: int
    review_queue_count: int
    decision_overlays: int
    overlay_status_counts: dict[str, int]


def build_input_model(
    *,
    source_database: Path,
    output_database: Path,
    policy_path: Path,
) -> BuildResult:
    PolicyClassifier(policy_path)  # Validate taxonomy and source-category hints before syncing.
    with InputModelStore(output_database) as store:
        store.initialize(source_database=source_database, policy_path=policy_path)
        universe_count = store.sync_candidate_universe(
            source_database=source_database,
            policy_path=policy_path,
        )
        counts = store.count_by_status()
        review_queue_count = store.review_queue_count()
        decision_overlays = sum(counts.values())
    return BuildResult(
        database=output_database.resolve(),
        universe_count=universe_count,
        review_queue_count=review_queue_count,
        decision_overlays=decision_overlays,
        overlay_status_counts=counts,
    )
