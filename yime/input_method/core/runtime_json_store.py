from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from .char_code_index import CharCodeCandidate, CharCodeIndex
from .runtime_ranking import (
    annotate_candidate_source,
    annotate_phrase_prefix_candidate,
    build_char_sort_weight_index,
    build_phrase_prefix_index,
)


class JSONRuntimeCandidateStore:
    """JSON-backed runtime candidate source with derived prefix and char indexes."""

    def __init__(
        self,
        runtime_path: Path,
        pinyin_to_canonical: Dict[str, str],
        resolve_canonical_code_from_pinyin_tone,
    ) -> None:
        self.runtime_path = runtime_path
        self.pinyin_to_canonical = pinyin_to_canonical
        self._resolve_canonical_code_from_pinyin_tone = resolve_canonical_code_from_pinyin_tone
        self.by_code: Dict[str, List[Dict[str, object]]] = {}
        self.char_sort_weight_by_text: Dict[str, float] = {}
        self.phrase_prefix_index: Dict[str, List[Dict[str, object]]] = {}
        self.char_code_index = CharCodeIndex.from_runtime_candidates({})

    def _load_json(self, path: Path) -> dict:
        raw_text = path.read_text(encoding="utf-8")
        stripped = raw_text.lstrip()
        if stripped.startswith("version https://git-lfs.github.com/spec/v1"):
            raise ValueError(f"运行时候选文件是 Git LFS 指针，未拉取实际内容: {path}")
        return json.loads(raw_text)

    def load_runtime_candidates(
        self,
        path: Optional[Path] = None,
    ) -> Dict[str, List[Dict[str, object]]]:
        target_path = path or self.runtime_path
        if not target_path.exists():
            raise FileNotFoundError(f"未找到运行时候选文件: {target_path}")
        payload = self._load_json(target_path)
        by_code = payload.get("by_code")
        if not isinstance(by_code, dict):
            raise ValueError(f"运行时候选文件格式无效: {target_path}")

        regrouped: Dict[str, List[Dict[str, object]]] = {}
        for raw_candidates in by_code.values():
            if not isinstance(raw_candidates, list):
                continue
            for candidate in raw_candidates:
                if not isinstance(candidate, dict):
                    continue
                canonical_code = str(candidate.get("yime_code", "") or "").strip()
                if not canonical_code:
                    pinyin_tone = str(candidate.get("pinyin_tone", "") or "").strip()
                    canonical_code = self._resolve_canonical_code_from_pinyin_tone(
                        pinyin_tone,
                        self.pinyin_to_canonical,
                    )
                if not canonical_code:
                    continue
                regrouped.setdefault(canonical_code, []).append(
                    annotate_candidate_source(candidate, "exact")
                )
        return regrouped

    def refresh(self, overlay_by_code: Dict[str, List[Dict[str, object]]]) -> None:
        by_code = self.load_runtime_candidates()
        for code, candidates in overlay_by_code.items():
            by_code.setdefault(code, []).extend(
                annotate_candidate_source(candidate, "overlay")
                for candidate in candidates
                if isinstance(candidate, dict)
            )
        self.set_runtime_candidates(by_code)

    def set_runtime_candidates(self, by_code: Dict[str, List[Dict[str, object]]]) -> None:
        self.by_code = by_code
        self.char_sort_weight_by_text = build_char_sort_weight_index(by_code)
        self.phrase_prefix_index = build_phrase_prefix_index(by_code)
        self.char_code_index = CharCodeIndex.from_runtime_candidates(by_code)

    def load_phrase_prefix_candidates(
        self,
        lookup_code: str,
        *,
        limit: int = 0,
    ) -> List[Dict[str, object]]:
        normalized_code = str(lookup_code or "").strip()
        if not normalized_code:
            return []
        candidates = [
            annotate_phrase_prefix_candidate(candidate, len(normalized_code))
            for candidate in self.phrase_prefix_index.get(normalized_code, [])
        ]
        normalized_limit = max(int(limit or 0), 0)
        if normalized_limit > 0:
            return candidates[:normalized_limit]
        return candidates

    def get_char_candidates(self, code: str) -> List[CharCodeCandidate]:
        return self.char_code_index.get_exact(code)

    def get_char_candidates_by_prefix(
        self,
        prefix: str,
        limit: int = 0,
    ) -> List[Tuple[str, List[CharCodeCandidate]]]:
        return self.char_code_index.get_with_prefix(prefix, limit=limit)
