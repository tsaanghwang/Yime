from __future__ import annotations

import sqlite3
from typing import Dict, List, SupportsFloat, Tuple, cast

from .char_code_index import CharCodeCandidate
from .sqlite_runtime_source import SQLiteRuntimeSource


def _as_float_value(value: object) -> float:
    try:
        if isinstance(value, (str, bytes, bytearray)):
            return float(value)
        if hasattr(value, "__float__"):
            return float(cast(SupportsFloat, value))
        if hasattr(value, "__index__"):
            return float(cast(int, value))
        return 0.0
    except (TypeError, ValueError):
        return 0.0


def _as_bool_value(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return False


class SQLiteCharCandidateStore:
    """Character-candidate DAO with local caches for SQLite runtime decoders."""

    def __init__(self, runtime_source: SQLiteRuntimeSource, runtime_table_name: str) -> None:
        self.runtime_source = runtime_source
        self.runtime_table_name = runtime_table_name
        self._char_candidate_cache: Dict[str, List[CharCodeCandidate]] = {}
        self._char_prefix_cache: Dict[tuple[str, int], List[Tuple[str, List[CharCodeCandidate]]]] = {}

    def clear_caches(self) -> None:
        self._char_candidate_cache.clear()
        self._char_prefix_cache.clear()

    def load_char_sort_weight_index(self) -> Dict[str, float]:
        with self.runtime_source.connect() as conn:
            rows = conn.execute(
                f"""
                SELECT text, MAX(sort_weight) AS weight
                FROM {self.runtime_table_name}
                WHERE entry_type = 'char'
                GROUP BY text
                """
            ).fetchall()
        return {
            str(row["text"] or "").strip(): _as_float_value(row["weight"])
            for row in rows
            if len(str(row["text"] or "").strip()) == 1
        }

    def get_char_candidates(self, code: str) -> List[CharCodeCandidate]:
        normalized_code = str(code or "").strip()
        if not normalized_code:
            return []
        cached = self._char_candidate_cache.get(normalized_code)
        if cached is not None:
            return list(cached)

        with self.runtime_source.connect() as conn:
            rows = conn.execute(
                f"""
                SELECT entry_type, entry_id, text, yime_code, pinyin_tone, sort_weight, is_common
                FROM {self.runtime_table_name}
                WHERE entry_type = 'char' AND yime_code = ?
                ORDER BY sort_weight DESC, text
                """,
                (normalized_code,),
            ).fetchall()

        candidates = [self._row_to_char_candidate(row) for row in rows]
        self._char_candidate_cache[normalized_code] = list(candidates)
        return candidates

    def get_char_candidates_by_prefix(
        self,
        prefix: str,
        limit: int = 0,
    ) -> List[Tuple[str, List[CharCodeCandidate]]]:
        normalized_prefix = str(prefix or "").strip()
        normalized_limit = max(int(limit or 0), 0)
        cache_key = (normalized_prefix, normalized_limit)
        cached = self._char_prefix_cache.get(cache_key)
        if cached is not None:
            return [(code, list(candidates)) for code, candidates in cached]

        with self.runtime_source.connect() as conn:
            if self.runtime_table_name == "runtime_candidates_materialized":
                if normalized_prefix:
                    query = (
                        """
                        SELECT DISTINCT yime_code
                        FROM runtime_candidates_materialized
                        WHERE entry_type = 'char' AND yime_code >= ? AND yime_code < ?
                        ORDER BY yime_code
                        """
                    )
                    params: tuple[object, ...] = (
                        normalized_prefix,
                        normalized_prefix + "\U0010ffff",
                    )
                else:
                    query = (
                        """
                        SELECT DISTINCT yime_code
                        FROM runtime_candidates_materialized
                        WHERE entry_type = 'char' AND yime_code IS NOT NULL AND yime_code <> ''
                        ORDER BY yime_code
                        """
                    )
                    params = ()
            else:
                if normalized_prefix:
                    query = (
                        """
                        SELECT DISTINCT yime_code
                        FROM runtime_candidates
                        WHERE entry_type = 'char' AND yime_code LIKE ?
                        ORDER BY yime_code
                        """
                    )
                    params = (f"{normalized_prefix}%",)
                else:
                    query = (
                        """
                        SELECT DISTINCT yime_code
                        FROM runtime_candidates
                        WHERE entry_type = 'char' AND yime_code IS NOT NULL AND yime_code <> ''
                        ORDER BY yime_code
                        """
                    )
                    params = ()
            if normalized_limit:
                query += " LIMIT ?"
                params = (*params, normalized_limit)
            rows = conn.execute(query, params).fetchall()

        matches: List[Tuple[str, List[CharCodeCandidate]]] = []
        for row in rows:
            code = str(row[0] or "").strip()
            if not code:
                continue
            candidates = self.get_char_candidates(code)
            if not candidates:
                continue
            matches.append((code, candidates))

        self._char_prefix_cache[cache_key] = [
            (code, list(candidates)) for code, candidates in matches
        ]
        return matches

    def _row_to_char_candidate(self, row: sqlite3.Row) -> CharCodeCandidate:
        return CharCodeCandidate(
            text=str(row["text"] or "").strip(),
            code=str(row["yime_code"] or "").strip(),
            entry_id=str(row["entry_id"] or "").strip(),
            pinyin_tone=str(row["pinyin_tone"] or "").strip(),
            sort_weight=_as_float_value(row["sort_weight"]),
            is_common=_as_bool_value(row["is_common"]),
        )
