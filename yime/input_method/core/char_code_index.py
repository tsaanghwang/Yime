"""Single-character candidate index keyed by Yime code."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Mapping

from .prefix_tree import PrefixTree


@dataclass(frozen=True)
class CharCodeCandidate:
    """A single-character candidate tied to one Yime code."""

    text: str
    code: str
    entry_id: str = ""
    pinyin_tone: str = ""
    sort_weight: float = 0.0
    is_common: bool = False


class CharCodeIndex:
    """Index single-character runtime candidates by exact code and code prefix."""

    def __init__(self) -> None:
        self._tree: PrefixTree[CharCodeCandidate] = PrefixTree()

    @classmethod
    def from_runtime_candidates(
        cls,
        by_code: Mapping[str, Iterable[Mapping[str, object]]],
    ) -> "CharCodeIndex":
        index = cls()
        for code, candidates in by_code.items():
            code_text = str(code).strip()
            if not code_text:
                continue
            for candidate in candidates:
                if str(candidate.get("entry_type", "")).strip() != "char":
                    continue
                text = str(candidate.get("text", "")).strip()
                if not text:
                    continue
                index.insert(
                    code_text,
                    CharCodeCandidate(
                        text=text,
                        code=code_text,
                        entry_id=str(candidate.get("entry_id", "")).strip(),
                        pinyin_tone=str(candidate.get("pinyin_tone", "")).strip(),
                        sort_weight=_as_float(candidate.get("sort_weight", 0.0)),
                        is_common=_as_bool(candidate.get("is_common", False)),
                    ),
                )
        return index

    @property
    def code_count(self) -> int:
        return self._tree.key_count

    @property
    def candidate_count(self) -> int:
        return self._tree.value_count

    def insert(self, code: str, candidate: CharCodeCandidate) -> None:
        self._tree.insert(code, candidate)

    def get_exact(self, code: str) -> list[CharCodeCandidate]:
        return self._tree.get_exact(code)

    def get_with_prefix(
        self,
        prefix: str,
        limit: int = 0,
    ) -> list[tuple[str, list[CharCodeCandidate]]]:
        return self._tree.get_with_prefix(prefix, limit=limit)

    def has_prefix(self, prefix: str) -> bool:
        return self._tree.has_prefix(prefix)


def _as_float(value: object) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _as_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return False
