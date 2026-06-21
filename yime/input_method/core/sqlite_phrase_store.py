from __future__ import annotations

from typing import Dict, List, Mapping

from .runtime_ranking import (
    annotate_candidate_source,
    annotate_phrase_prefix_candidate,
    phrase_candidate_payload_sort_key,
)
from .sqlite_runtime_source import SQLiteRuntimeSource


_RUNTIME_SQL_PRIORITY_ORDER = """
CASE
    WHEN entry_type = 'phrase' AND text_length BETWEEN 2 AND 4 THEN 0
    WHEN entry_type = 'char' THEN 1
END,
sort_weight DESC,
text,
pinyin_tone
"""


class SQLitePhraseCandidateStore:
    """SQLite-backed phrase/runtime candidate source with local caches."""

    def __init__(
        self,
        runtime_source: SQLiteRuntimeSource,
        runtime_table_name: str,
    ) -> None:
        self.runtime_source = runtime_source
        self.runtime_table_name = runtime_table_name
        self._runtime_candidate_cache: Dict[str, List[Dict[str, object]]] = {}
        self._phrase_prefix_cache: Dict[str, List[Dict[str, object]]] = {}

    def clear_caches(self) -> None:
        self._runtime_candidate_cache.clear()
        self._phrase_prefix_cache.clear()

    def load_runtime_candidates_for_code(
        self,
        lookup_code: str,
        phrase_candidate_overlays: Mapping[str, List[Dict[str, object]]],
    ) -> List[Dict[str, object]]:
        normalized_code = str(lookup_code or "").strip()
        if not normalized_code:
            return []
        try:
            cached = self._runtime_candidate_cache[normalized_code]
        except KeyError:
            with self.runtime_source.connect() as conn:
                rows = conn.execute(
                    f"""
                    SELECT entry_type, entry_id, text, pinyin_tone, yime_code, sort_weight, is_common, text_length, updated_at
                    FROM {self.runtime_table_name}
                    WHERE yime_code = ?
                    ORDER BY {_RUNTIME_SQL_PRIORITY_ORDER}
                    """,
                    (normalized_code,),
                ).fetchall()

                char_usage_tier_by_key = {
                    (str(row["hanzi"] or "").strip(), str(row["pinyin_tone"] or "").strip()): str(row["usage_tier"] or "").strip()
                    for row in conn.execute(
                        """
                        SELECT hanzi, pinyin_tone, usage_tier
                        FROM char_lexicon
                        WHERE yime_code = ?
                        """,
                        (normalized_code,),
                    ).fetchall()
                }

            cached: List[Dict[str, object]] = []
            for row in rows:
                candidate = dict(row)
                if str(candidate.get("entry_type", "") or "").strip() == "char":
                    candidate["usage_tier"] = char_usage_tier_by_key.get(
                        (
                            str(candidate.get("text", "") or "").strip(),
                            str(candidate.get("pinyin_tone", "") or "").strip(),
                        ),
                        "",
                    )
                cached.append(annotate_candidate_source(candidate, "exact"))
            self._runtime_candidate_cache[normalized_code] = list(cached)

        merged = list(cached)
        merged.extend(
            annotate_candidate_source(candidate, "overlay")
            for candidate in phrase_candidate_overlays.get(normalized_code, [])
        )
        return merged

    def load_phrase_prefix_candidates(
        self,
        lookup_code: str,
        phrase_candidate_overlays: Mapping[str, List[Dict[str, object]]],
        *,
        limit: int = 0,
    ) -> List[Dict[str, object]]:
        normalized_code = str(lookup_code or "").strip()
        if not normalized_code:
            return []
        normalized_limit = max(int(limit or 0), 0)
        cached = self._phrase_prefix_cache.get(normalized_code)
        if cached is not None:
            if normalized_limit > 0:
                return list(cached[:normalized_limit])
            return list(cached)

        with self.runtime_source.connect() as conn:
            rows = conn.execute(
                f"""
                SELECT entry_type, entry_id, text, pinyin_tone, yime_code, sort_weight, is_common, text_length, updated_at
                FROM {self.runtime_table_name}
                WHERE entry_type = 'phrase'
                  AND yime_code >= ?
                  AND yime_code < ?
                  AND LENGTH(yime_code) > ?
                ORDER BY sort_weight DESC, text, pinyin_tone
                LIMIT ?
                """,
                (
                    normalized_code,
                    normalized_code + "\U0010ffff",
                    len(normalized_code),
                    normalized_limit or 64,
                ),
            ).fetchall()

        merged = [
            annotate_phrase_prefix_candidate(
                annotate_candidate_source(dict(row), "exact"),
                len(normalized_code),
            )
            for row in rows
        ]
        for overlay_code, overlay_candidates in phrase_candidate_overlays.items():
            normalized_overlay_code = str(overlay_code or "").strip()
            if normalized_overlay_code.startswith(normalized_code) and normalized_overlay_code != normalized_code:
                merged.extend(
                    annotate_phrase_prefix_candidate(
                        annotate_candidate_source(candidate, "overlay"),
                        len(normalized_code),
                    )
                    for candidate in overlay_candidates
                )

        merged.sort(key=phrase_candidate_payload_sort_key)
        cached = merged[: normalized_limit or 64]
        self._phrase_prefix_cache[normalized_code] = list(cached)
        return list(cached)
