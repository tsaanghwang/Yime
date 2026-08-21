"""Resolve the approved lexicon and canonical layout for evaluation."""

from __future__ import annotations

import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
LEXICON_TOOL_ROOT = REPO_ROOT / "tools" / "lexicon"
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(LEXICON_TOOL_ROOT) not in sys.path:
    sys.path.insert(0, str(LEXICON_TOOL_ROOT))

from verify_target_lock import DEFAULT_LOCK, verify

from yime.utils.yinyuan_id_chain import layout_projection_digest


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


@dataclass(frozen=True)
class EvaluationContext:
    lock_id: str
    entry_count: int
    distinct_texts: int
    source_dictionary_sha256: str
    source_selection_sha256: str
    layout_projection_sha256: str
    canonical_layout_path: Path
    canonical_layout_file_sha256: str
    artifacts: dict[str, Path]

    def identity(self) -> dict[str, object]:
        return {
            "lock_id": self.lock_id,
            "entry_count": self.entry_count,
            "distinct_texts": self.distinct_texts,
            "source_dictionary_sha256": self.source_dictionary_sha256,
            "source_selection_sha256": self.source_selection_sha256,
            "layout_projection_sha256": self.layout_projection_sha256,
            "canonical_layout": self.canonical_layout_path.relative_to(
                REPO_ROOT
            ).as_posix(),
            "canonical_layout_file_sha256": self.canonical_layout_file_sha256,
        }


def load_evaluation_context(
    *,
    repo_root: Path = REPO_ROOT,
    lock_path: Path = DEFAULT_LOCK,
) -> EvaluationContext:
    report = verify(lock_path.resolve(), repo_root.resolve())
    target = report["target"]
    artifacts = {
        str(item["role"]): repo_root / str(item["path"])
        for item in report["verified_artifacts"]
    }
    canonical_layout = repo_root / "internal_data" / "manual_key_layout.json"
    payload = json.loads(canonical_layout.read_text(encoding="utf-8"))
    if "yinyuan_id_to_key" in payload:
        raise ValueError("canonical layout must not contain a compact second key map")
    semantic_digest = layout_projection_digest(repo_root)
    if semantic_digest != str(target["layout_projection_sha256"]):
        raise ValueError(
            "canonical layout projection does not match the approved target lock"
        )
    return EvaluationContext(
        lock_id=str(report["lock_id"]),
        entry_count=int(target["entry_count"]),
        distinct_texts=int(target["distinct_texts"]),
        source_dictionary_sha256=str(target["source_dictionary_sha256"]),
        source_selection_sha256=str(target["source_selection_sha256"]),
        layout_projection_sha256=semantic_digest,
        canonical_layout_path=canonical_layout,
        canonical_layout_file_sha256=file_sha256(canonical_layout),
        artifacts=artifacts,
    )
