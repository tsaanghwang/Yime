from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
import json
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Literal, Mapping


@dataclass(frozen=True)
class UserPhraseEntry:
    phrase: str
    numeric_pinyin: str
    marked_pinyin: str
    yime_code: str
    sort_weight: float


@dataclass(frozen=True)
class UserPhraseEntryDetail:
    phrase: str
    numeric_pinyin: str
    marked_pinyin: str
    yime_code: str
    source_note: str
    sort_weight: float
    created_at: str
    updated_at: str


@dataclass(frozen=True)
class UserCandidateFrequencyEntry:
    lookup_code: str
    text: str
    freq: int
    last_used_at: str
    numeric_pinyin: str
    marked_pinyin: str
    yime_code: str
    source_note: str


@lru_cache(maxsize=None)
def _load_numeric_yime_code_map(mapping_path: str) -> dict[str, str]:
    payload = json.loads(Path(mapping_path).read_text(encoding="utf-8"))
    return {
        str(pinyin_tone).strip(): str(yime_code)
        for pinyin_tone, yime_code in payload.items()
        if str(pinyin_tone).strip() and str(yime_code)
    }


def resolve_yime_code_from_numeric_pinyin(repo_root: Path, numeric_pinyin: str) -> str:
    normalized = " ".join(numeric_pinyin.split())
    if not normalized:
        return ""

    mapping = _load_numeric_yime_code_map(
        str(repo_root / "syllable_codec" / "yinjie_code.json")
    )
    parts: list[str] = []
    for syllable in normalized.split(" "):
        yime_code = mapping.get(syllable)
        if not yime_code:
            return ""
        parts.append(yime_code)
    return "".join(parts)


def resolve_canonical_code_from_numeric_pinyin(
    pinyin_to_canonical: Mapping[str, str],
    numeric_pinyin: str,
) -> str:
    normalized = " ".join(numeric_pinyin.split())
    if not normalized:
        return ""

    parts: list[str] = []
    for syllable in normalized.split(" "):
        canonical_code = str(pinyin_to_canonical.get(syllable) or "").strip()
        if not canonical_code:
            return ""
        parts.append(canonical_code)
    return "".join(parts)


class UserLexiconStore:
    DEFAULT_PHRASE_SORT_WEIGHT = 1_000_000.0

    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.ensure_schema()

    def _connect(self, readonly: bool = False) -> sqlite3.Connection:
        if readonly:
            connection = sqlite3.connect(f"file:{self.db_path}?mode=ro", uri=True)
        else:
            connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection

    def ensure_schema(self) -> None:
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS user_phrase_entries (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    phrase TEXT NOT NULL UNIQUE,
                    numeric_pinyin TEXT NOT NULL,
                    marked_pinyin TEXT NOT NULL DEFAULT '',
                    yime_code TEXT NOT NULL,
                    source_note TEXT NOT NULL DEFAULT '',
                    sort_weight REAL NOT NULL DEFAULT 1000000.0,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE INDEX IF NOT EXISTS idx_user_phrase_entries_numeric
                ON user_phrase_entries(numeric_pinyin);

                CREATE TABLE IF NOT EXISTS user_candidate_frequency (
                    lookup_code TEXT NOT NULL,
                    text TEXT NOT NULL,
                    freq INTEGER NOT NULL DEFAULT 0,
                    last_used_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (lookup_code, text)
                );

                CREATE INDEX IF NOT EXISTS idx_user_candidate_frequency_last_used
                ON user_candidate_frequency(last_used_at);

                CREATE TABLE IF NOT EXISTS user_lexicon_meta (
                    meta_key TEXT PRIMARY KEY,
                    meta_value TEXT NOT NULL DEFAULT ''
                );
                """
            )

    def get_meta(self, key: str) -> str:
        normalized_key = key.strip()
        if not normalized_key:
            raise ValueError("meta key 不能为空")

        with self._connect(readonly=True) as connection:
            row = connection.execute(
                "SELECT meta_value FROM user_lexicon_meta WHERE meta_key = ? LIMIT 1",
                (normalized_key,),
            ).fetchone()
        return str(row["meta_value"] or "") if row is not None else ""

    def set_meta(self, key: str, value: str) -> None:
        normalized_key = key.strip()
        if not normalized_key:
            raise ValueError("meta key 不能为空")

        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO user_lexicon_meta (meta_key, meta_value)
                VALUES (?, ?)
                ON CONFLICT(meta_key) DO UPDATE SET
                    meta_value = excluded.meta_value
                """,
                (normalized_key, value),
            )

    def has_user_data(self) -> bool:
        with self._connect(readonly=True) as connection:
            phrase_row = connection.execute(
                "SELECT 1 FROM user_phrase_entries LIMIT 1"
            ).fetchone()
            if phrase_row is not None:
                return True
            frequency_row = connection.execute(
                "SELECT 1 FROM user_candidate_frequency LIMIT 1"
            ).fetchone()
        return frequency_row is not None

    def list_recent_phrase_entries(self, limit: int = 20) -> list[UserPhraseEntryDetail]:
        return self.list_phrase_entries(limit=limit)

    def upsert_phrase(
        self,
        phrase: str,
        numeric_pinyin: str,
        *,
        marked_pinyin: str = "",
        yime_code: str,
        source_note: str = "",
        sort_weight: float | None = None,
    ) -> Literal["inserted", "updated"]:
        normalized_phrase = phrase.strip()
        normalized_numeric = " ".join(numeric_pinyin.split())
        normalized_marked = " ".join(marked_pinyin.split())
        normalized_code = yime_code.strip()
        if not normalized_phrase:
            raise ValueError("phrase 不能为空")
        if not normalized_numeric:
            raise ValueError("numeric_pinyin 不能为空")
        if not normalized_code:
            raise ValueError("yime_code 不能为空")

        weight = (
            self.DEFAULT_PHRASE_SORT_WEIGHT
            if sort_weight is None
            else float(sort_weight)
        )
        with self._connect() as connection:
            existing = connection.execute(
                "SELECT 1 FROM user_phrase_entries WHERE phrase = ? LIMIT 1",
                (normalized_phrase,),
            ).fetchone()
            connection.execute(
                """
                INSERT INTO user_phrase_entries (
                    phrase,
                    numeric_pinyin,
                    marked_pinyin,
                    yime_code,
                    source_note,
                    sort_weight
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(phrase) DO UPDATE SET
                    numeric_pinyin = excluded.numeric_pinyin,
                    marked_pinyin = excluded.marked_pinyin,
                    yime_code = excluded.yime_code,
                    source_note = excluded.source_note,
                    sort_weight = excluded.sort_weight,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (
                    normalized_phrase,
                    normalized_numeric,
                    normalized_marked,
                    normalized_code,
                    source_note.strip(),
                    weight,
                ),
            )
        return "updated" if existing is not None else "inserted"

    def delete_phrase(self, phrase: str) -> bool:
        normalized_phrase = phrase.strip()
        if not normalized_phrase:
            raise ValueError("phrase 不能为空")

        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT yime_code
                FROM user_phrase_entries
                WHERE phrase = ?
                LIMIT 1
                """,
                (normalized_phrase,),
            ).fetchone()
            if row is None:
                return False

            yime_code = str(row["yime_code"] or "").strip()
            connection.execute(
                "DELETE FROM user_phrase_entries WHERE phrase = ?",
                (normalized_phrase,),
            )
            if yime_code:
                connection.execute(
                    "DELETE FROM user_candidate_frequency WHERE lookup_code = ? AND text = ?",
                    (yime_code, normalized_phrase),
                )
        return True

    def load_candidate_frequency(self) -> dict[tuple[str, str], int]:
        with self._connect(readonly=True) as connection:
            rows = connection.execute(
                """
                SELECT lookup_code, text, freq
                FROM user_candidate_frequency
                WHERE freq > 0
                """
            ).fetchall()
        return {
            (str(row["lookup_code"] or "").strip(), str(row["text"] or "").strip()): int(row["freq"] or 0)
            for row in rows
            if str(row["lookup_code"] or "").strip() and str(row["text"] or "").strip()
        }

    def list_phrase_entries(
        self,
        term: str = "",
        *,
        use_like: bool = False,
        limit: int = 50,
    ) -> list[UserPhraseEntryDetail]:
        comparator = "LIKE" if use_like else "="
        match_value = f"%{term.strip()}%" if use_like else term.strip()
        query = f"""
            SELECT
                phrase,
                numeric_pinyin,
                marked_pinyin,
                yime_code,
                source_note,
                sort_weight,
                created_at,
                updated_at
            FROM user_phrase_entries
            {{where_clause}}
            ORDER BY updated_at DESC, phrase
            LIMIT ?
        """
        params: list[object] = []
        where_clause = ""
        if match_value:
            where_clause = f"WHERE phrase {comparator} ?"
            params.append(match_value)
        params.append(limit)

        with self._connect(readonly=True) as connection:
            rows = connection.execute(query.format(where_clause=where_clause), params).fetchall()

        return [
            UserPhraseEntryDetail(
                phrase=str(row["phrase"] or ""),
                numeric_pinyin=str(row["numeric_pinyin"] or ""),
                marked_pinyin=str(row["marked_pinyin"] or ""),
                yime_code=str(row["yime_code"] or ""),
                source_note=str(row["source_note"] or ""),
                sort_weight=float(row["sort_weight"] or self.DEFAULT_PHRASE_SORT_WEIGHT),
                created_at=str(row["created_at"] or ""),
                updated_at=str(row["updated_at"] or ""),
            )
            for row in rows
        ]

    def list_candidate_frequency_entries(
        self,
        term: str = "",
        *,
        use_like: bool = False,
        limit: int = 50,
    ) -> list[UserCandidateFrequencyEntry]:
        comparator = "LIKE" if use_like else "="
        match_value = f"%{term.strip()}%" if use_like else term.strip()
        query = f"""
            SELECT
                ucf.lookup_code,
                ucf.text,
                ucf.freq,
                ucf.last_used_at,
                COALESCE(upe.numeric_pinyin, '') AS numeric_pinyin,
                COALESCE(upe.marked_pinyin, '') AS marked_pinyin,
                COALESCE(upe.yime_code, '') AS yime_code,
                COALESCE(upe.source_note, '') AS source_note
            FROM user_candidate_frequency AS ucf
            LEFT JOIN user_phrase_entries AS upe
                ON upe.phrase = ucf.text
            {{where_clause}}
            ORDER BY ucf.freq DESC, ucf.last_used_at DESC, ucf.text
            LIMIT ?
        """
        params: list[object] = []
        where_clause = ""
        if match_value:
            where_clause = f"WHERE ucf.text {comparator} ?"
            params.append(match_value)
        params.append(limit)

        with self._connect(readonly=True) as connection:
            rows = connection.execute(query.format(where_clause=where_clause), params).fetchall()

        return [
            UserCandidateFrequencyEntry(
                lookup_code=str(row["lookup_code"] or ""),
                text=str(row["text"] or ""),
                freq=int(row["freq"] or 0),
                last_used_at=str(row["last_used_at"] or ""),
                numeric_pinyin=str(row["numeric_pinyin"] or ""),
                marked_pinyin=str(row["marked_pinyin"] or ""),
                yime_code=str(row["yime_code"] or ""),
                source_note=str(row["source_note"] or ""),
            )
            for row in rows
        ]

    def reset_candidate_frequency(
        self,
        *,
        text: str | None = None,
        lookup_code: str | None = None,
    ) -> int:
        normalized_text = (text or "").strip()
        normalized_lookup_code = (lookup_code or "").strip()
        if not normalized_text and not normalized_lookup_code:
            raise ValueError("text 和 lookup_code 不能同时为空")

        clauses: list[str] = []
        params: list[object] = []
        if normalized_text:
            clauses.append("text = ?")
            params.append(normalized_text)
        if normalized_lookup_code:
            clauses.append("lookup_code = ?")
            params.append(normalized_lookup_code)

        with self._connect() as connection:
            cursor = connection.execute(
                f"DELETE FROM user_candidate_frequency WHERE {' AND '.join(clauses)}",
                params,
            )
        return int(cursor.rowcount or 0)

    def export_payload(self, *, include_frequency: bool = True) -> dict[str, Any]:
        phrase_entries = [
            {
                "phrase": row.phrase,
                "numeric_pinyin": row.numeric_pinyin,
                "marked_pinyin": row.marked_pinyin,
                "yime_code": row.yime_code,
                "source_note": row.source_note,
                "sort_weight": row.sort_weight,
                "created_at": row.created_at,
                "updated_at": row.updated_at,
            }
            for row in self.list_phrase_entries(limit=1_000_000)
        ]
        payload: dict[str, Any] = {
            "schema_version": 1,
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "phrase_entries": phrase_entries,
        }
        if include_frequency:
            payload["candidate_frequency"] = [
                {
                    "lookup_code": row.lookup_code,
                    "text": row.text,
                    "freq": row.freq,
                    "last_used_at": row.last_used_at,
                }
                for row in self.list_candidate_frequency_entries(limit=1_000_000)
            ]
        return payload

    def write_export_file(
        self,
        path: Path,
        *,
        include_frequency: bool = True,
    ) -> Path:
        payload = self.export_payload(include_frequency=include_frequency)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        return path

    def import_payload(
        self,
        payload: Mapping[str, Any],
        *,
        replace_existing: bool = False,
        include_frequency: bool = True,
    ) -> dict[str, int]:
        phrase_entries = payload.get("phrase_entries") or []
        candidate_frequency = payload.get("candidate_frequency") or []

        imported_phrases = 0
        imported_frequency_rows = 0

        with self._connect() as connection:
            if replace_existing:
                connection.execute("DELETE FROM user_candidate_frequency")
                connection.execute("DELETE FROM user_phrase_entries")

            for raw_entry in phrase_entries:
                phrase = str(raw_entry.get("phrase") or "").strip()
                numeric_pinyin = str(raw_entry.get("numeric_pinyin") or "").strip()
                yime_code = str(raw_entry.get("yime_code") or "").strip()
                if not phrase or not numeric_pinyin or not yime_code:
                    continue
                connection.execute(
                    """
                    INSERT INTO user_phrase_entries (
                        phrase,
                        numeric_pinyin,
                        marked_pinyin,
                        yime_code,
                        source_note,
                        sort_weight,
                        created_at,
                        updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), COALESCE(?, CURRENT_TIMESTAMP))
                    ON CONFLICT(phrase) DO UPDATE SET
                        numeric_pinyin = excluded.numeric_pinyin,
                        marked_pinyin = excluded.marked_pinyin,
                        yime_code = excluded.yime_code,
                        source_note = excluded.source_note,
                        sort_weight = excluded.sort_weight,
                        updated_at = excluded.updated_at
                    """,
                    (
                        phrase,
                        numeric_pinyin,
                        str(raw_entry.get("marked_pinyin") or "").strip(),
                        yime_code,
                        str(raw_entry.get("source_note") or "").strip(),
                        float(raw_entry.get("sort_weight") or self.DEFAULT_PHRASE_SORT_WEIGHT),
                        str(raw_entry.get("created_at") or "").strip() or None,
                        str(raw_entry.get("updated_at") or "").strip() or None,
                    ),
                )
                imported_phrases += 1

            if include_frequency:
                for raw_entry in candidate_frequency:
                    lookup_code = str(raw_entry.get("lookup_code") or "").strip()
                    text = str(raw_entry.get("text") or "").strip()
                    if not lookup_code or not text:
                        continue
                    connection.execute(
                        """
                        INSERT INTO user_candidate_frequency (
                            lookup_code,
                            text,
                            freq,
                            last_used_at
                        ) VALUES (?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
                        ON CONFLICT(lookup_code, text) DO UPDATE SET
                            freq = excluded.freq,
                            last_used_at = excluded.last_used_at
                        """,
                        (
                            lookup_code,
                            text,
                            int(raw_entry.get("freq") or 0),
                            str(raw_entry.get("last_used_at") or "").strip() or None,
                        ),
                    )
                    imported_frequency_rows += 1

        return {
            "phrase_entries": imported_phrases,
            "candidate_frequency": imported_frequency_rows,
        }

    def import_file(
        self,
        path: Path,
        *,
        replace_existing: bool = False,
        include_frequency: bool = True,
    ) -> dict[str, int]:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("导入文件格式无效：顶层必须是 JSON object")
        return self.import_payload(
            payload,
            replace_existing=replace_existing,
            include_frequency=include_frequency,
        )

    def check_repairable_issues(self, repo_root: Path) -> dict[str, int]:
        issues = {
            "sqlite_integrity_errors": 0,
            "user_phrase_entries": 0,
            "persisted_reorder_entries": 0,
            "meta_entries": 0,
            "invalid_phrase_rows": 0,
            "normalizable_phrase_rows": 0,
            "duplicate_phrase_rows": 0,
            "invalid_frequency_rows": 0,
            "normalizable_frequency_rows": 0,
            "duplicate_frequency_rows": 0,
            "invalid_meta_rows": 0,
            "normalizable_meta_rows": 0,
        }

        with self._connect(readonly=True) as connection:
            integrity_rows = connection.execute("PRAGMA integrity_check").fetchall()
            integrity_messages = [str(row[0] or "") for row in integrity_rows]
            issues["sqlite_integrity_errors"] = sum(
                1 for message in integrity_messages if message.strip().lower() != "ok"
            )

            phrase_rows = connection.execute(
                """
                SELECT id, phrase, numeric_pinyin, marked_pinyin, yime_code, source_note
                FROM user_phrase_entries
                ORDER BY updated_at DESC, id DESC
                """
            ).fetchall()
            issues["user_phrase_entries"] = len(phrase_rows)

            normalized_phrases: dict[str, int] = {}
            for row in phrase_rows:
                normalized_phrase = str(row["phrase"] or "").strip()
                normalized_numeric = " ".join(str(row["numeric_pinyin"] or "").split())
                normalized_marked = " ".join(str(row["marked_pinyin"] or "").split())
                normalized_yime = str(row["yime_code"] or "").strip()
                normalized_note = str(row["source_note"] or "").strip()

                if not normalized_phrase or not normalized_numeric:
                    issues["invalid_phrase_rows"] += 1
                    continue

                resolved_yime = resolve_yime_code_from_numeric_pinyin(repo_root, normalized_numeric)
                if not resolved_yime:
                    issues["invalid_phrase_rows"] += 1
                    continue

                if (
                    normalized_phrase != str(row["phrase"] or "")
                    or normalized_numeric != str(row["numeric_pinyin"] or "")
                    or normalized_marked != str(row["marked_pinyin"] or "")
                    or normalized_note != str(row["source_note"] or "")
                    or resolved_yime != normalized_yime
                ):
                    issues["normalizable_phrase_rows"] += 1

                normalized_phrases[normalized_phrase] = normalized_phrases.get(normalized_phrase, 0) + 1

            issues["duplicate_phrase_rows"] = sum(
                count - 1 for count in normalized_phrases.values() if count > 1
            )

            frequency_rows = connection.execute(
                """
                SELECT rowid, lookup_code, text, freq, last_used_at
                FROM user_candidate_frequency
                ORDER BY last_used_at DESC, rowid DESC
                """
            ).fetchall()
            issues["persisted_reorder_entries"] = len(frequency_rows)

            normalized_frequency_keys: dict[tuple[str, str], int] = {}
            for row in frequency_rows:
                normalized_lookup = str(row["lookup_code"] or "").strip()
                normalized_text = str(row["text"] or "").strip()
                freq = int(row["freq"] or 0)
                if not normalized_lookup or not normalized_text or freq <= 0:
                    issues["invalid_frequency_rows"] += 1
                    continue

                if (
                    normalized_lookup != str(row["lookup_code"] or "")
                    or normalized_text != str(row["text"] or "")
                ):
                    issues["normalizable_frequency_rows"] += 1

                key = (normalized_lookup, normalized_text)
                normalized_frequency_keys[key] = normalized_frequency_keys.get(key, 0) + 1

            issues["duplicate_frequency_rows"] = sum(
                count - 1 for count in normalized_frequency_keys.values() if count > 1
            )

            meta_rows = connection.execute(
                "SELECT meta_key, meta_value FROM user_lexicon_meta ORDER BY meta_key"
            ).fetchall()
            issues["meta_entries"] = len(meta_rows)

        has_user_data = self.has_user_data()
        for row in meta_rows:
            meta_key = str(row["meta_key"] or "").strip()
            meta_value = str(row["meta_value"] or "")
            normalized_value = meta_value.strip()
            if meta_key != "seed_import_completed":
                if normalized_value != meta_value:
                    issues["normalizable_meta_rows"] += 1
                continue
            if not normalized_value:
                issues["invalid_meta_rows"] += 1
                continue
            if normalized_value == "skipped_existing_user_data" and not has_user_data:
                issues["invalid_meta_rows"] += 1
                continue
            if normalized_value.startswith(("imported:", "empty_seed:")) or normalized_value == "skipped_existing_user_data":
                if normalized_value != meta_value:
                    issues["normalizable_meta_rows"] += 1
                continue
            issues["invalid_meta_rows"] += 1

        return issues

    def repair_phrase_entries(self, repo_root: Path) -> dict[str, int]:
        rows: list[sqlite3.Row]
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT id, phrase, numeric_pinyin, marked_pinyin, yime_code, source_note, sort_weight, created_at, updated_at
                FROM user_phrase_entries
                ORDER BY updated_at DESC, id DESC
                """
            ).fetchall()

            deleted_invalid_rows = 0
            updated_rows = 0
            deleted_duplicate_rows = 0
            kept_phrase_ids: set[int] = set()

            grouped_rows: dict[str, list[sqlite3.Row]] = {}
            for row in rows:
                normalized_phrase = str(row["phrase"] or "").strip()
                normalized_numeric = " ".join(str(row["numeric_pinyin"] or "").split())
                if not normalized_phrase or not normalized_numeric:
                    connection.execute("DELETE FROM user_phrase_entries WHERE id = ?", (int(row["id"]),))
                    deleted_invalid_rows += 1
                    continue
                resolved_yime = resolve_yime_code_from_numeric_pinyin(repo_root, normalized_numeric)
                if not resolved_yime:
                    connection.execute("DELETE FROM user_phrase_entries WHERE id = ?", (int(row["id"]),))
                    deleted_invalid_rows += 1
                    continue
                grouped_rows.setdefault(normalized_phrase, []).append(row)

            for normalized_phrase, phrase_rows in grouped_rows.items():
                keeper = phrase_rows[0]
                keeper_id = int(keeper["id"])
                kept_phrase_ids.add(keeper_id)
                normalized_numeric = " ".join(str(keeper["numeric_pinyin"] or "").split())
                normalized_marked = " ".join(str(keeper["marked_pinyin"] or "").split())
                normalized_note = str(keeper["source_note"] or "").strip()
                resolved_yime = resolve_yime_code_from_numeric_pinyin(repo_root, normalized_numeric)

                if (
                    normalized_phrase != str(keeper["phrase"] or "")
                    or normalized_numeric != str(keeper["numeric_pinyin"] or "")
                    or normalized_marked != str(keeper["marked_pinyin"] or "")
                    or normalized_note != str(keeper["source_note"] or "")
                    or resolved_yime != str(keeper["yime_code"] or "").strip()
                ):
                    connection.execute(
                        """
                        UPDATE user_phrase_entries
                        SET phrase = ?, numeric_pinyin = ?, marked_pinyin = ?, yime_code = ?, source_note = ?, updated_at = CURRENT_TIMESTAMP
                        WHERE id = ?
                        """,
                        (
                            normalized_phrase,
                            normalized_numeric,
                            normalized_marked,
                            resolved_yime,
                            normalized_note,
                            keeper_id,
                        ),
                    )
                    updated_rows += 1

                for duplicate in phrase_rows[1:]:
                    connection.execute("DELETE FROM user_phrase_entries WHERE id = ?", (int(duplicate["id"]),))
                    deleted_duplicate_rows += 1

        return {
            "deleted_invalid_phrase_rows": deleted_invalid_rows,
            "updated_phrase_rows": updated_rows,
            "deleted_duplicate_phrase_rows": deleted_duplicate_rows,
        }

    def repair_candidate_frequency_entries(self) -> dict[str, int]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT rowid, lookup_code, text, freq, last_used_at
                FROM user_candidate_frequency
                ORDER BY last_used_at DESC, rowid DESC
                """
            ).fetchall()

            deleted_invalid_rows = 0
            updated_rows = 0
            deleted_duplicate_rows = 0
            grouped_rows: dict[tuple[str, str], list[sqlite3.Row]] = {}

            for row in rows:
                normalized_lookup = str(row["lookup_code"] or "").strip()
                normalized_text = str(row["text"] or "").strip()
                freq = int(row["freq"] or 0)
                if not normalized_lookup or not normalized_text or freq <= 0:
                    connection.execute(
                        "DELETE FROM user_candidate_frequency WHERE rowid = ?",
                        (int(row["rowid"]),),
                    )
                    deleted_invalid_rows += 1
                    continue
                grouped_rows.setdefault((normalized_lookup, normalized_text), []).append(row)

            for (normalized_lookup, normalized_text), frequency_rows in grouped_rows.items():
                keeper = frequency_rows[0]
                merged_freq = sum(int(row["freq"] or 0) for row in frequency_rows)
                latest_last_used_at = max(str(row["last_used_at"] or "") for row in frequency_rows)
                if (
                    normalized_lookup != str(keeper["lookup_code"] or "")
                    or normalized_text != str(keeper["text"] or "")
                    or merged_freq != int(keeper["freq"] or 0)
                    or latest_last_used_at != str(keeper["last_used_at"] or "")
                ):
                    connection.execute(
                        """
                        UPDATE user_candidate_frequency
                        SET lookup_code = ?, text = ?, freq = ?, last_used_at = ?
                        WHERE rowid = ?
                        """,
                        (
                            normalized_lookup,
                            normalized_text,
                            merged_freq,
                            latest_last_used_at,
                            int(keeper["rowid"]),
                        ),
                    )
                    updated_rows += 1

                for duplicate in frequency_rows[1:]:
                    connection.execute(
                        "DELETE FROM user_candidate_frequency WHERE rowid = ?",
                        (int(duplicate["rowid"]),),
                    )
                    deleted_duplicate_rows += 1

        return {
            "deleted_invalid_frequency_rows": deleted_invalid_rows,
            "updated_frequency_rows": updated_rows,
            "deleted_duplicate_frequency_rows": deleted_duplicate_rows,
        }

    def repair_meta_entries(self) -> dict[str, int]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT meta_key, meta_value FROM user_lexicon_meta ORDER BY meta_key"
            ).fetchall()

            updated_rows = 0
            deleted_invalid_rows = 0
            has_user_data = self.has_user_data()

            for row in rows:
                meta_key = str(row["meta_key"] or "").strip()
                meta_value = str(row["meta_value"] or "")
                normalized_value = meta_value.strip()

                if meta_key != "seed_import_completed":
                    if normalized_value != meta_value:
                        connection.execute(
                            "UPDATE user_lexicon_meta SET meta_value = ? WHERE meta_key = ?",
                            (normalized_value, meta_key),
                        )
                        updated_rows += 1
                    continue

                is_valid_seed_value = (
                    normalized_value.startswith(("imported:", "empty_seed:"))
                    or normalized_value == "skipped_existing_user_data"
                )
                should_delete = (
                    not normalized_value
                    or not is_valid_seed_value
                    or (normalized_value == "skipped_existing_user_data" and not has_user_data)
                )
                if should_delete:
                    connection.execute(
                        "DELETE FROM user_lexicon_meta WHERE meta_key = ?",
                        (meta_key,),
                    )
                    deleted_invalid_rows += 1
                    continue

                if normalized_value != meta_value:
                    connection.execute(
                        "UPDATE user_lexicon_meta SET meta_value = ? WHERE meta_key = ?",
                        (normalized_value, meta_key),
                    )
                    updated_rows += 1

        return {
            "deleted_invalid_meta_rows": deleted_invalid_rows,
            "updated_meta_rows": updated_rows,
        }

    def record_candidate_selection(self, lookup_code: str, text: str) -> int:
        normalized_lookup_code = lookup_code.strip()
        normalized_text = text.strip()
        if not normalized_lookup_code:
            raise ValueError("lookup_code 不能为空")
        if not normalized_text:
            raise ValueError("text 不能为空")

        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO user_candidate_frequency (lookup_code, text, freq)
                VALUES (?, ?, 1)
                ON CONFLICT(lookup_code, text) DO UPDATE SET
                    freq = user_candidate_frequency.freq + 1,
                    last_used_at = CURRENT_TIMESTAMP
                """,
                (normalized_lookup_code, normalized_text),
            )
            row = connection.execute(
                """
                SELECT freq
                FROM user_candidate_frequency
                WHERE lookup_code = ? AND text = ?
                """,
                (normalized_lookup_code, normalized_text),
            ).fetchone()
        return int(row["freq"] or 0) if row is not None else 0

    def load_phrase_candidates(
        self,
        pinyin_to_canonical: Mapping[str, str],
    ) -> Dict[str, List[Dict[str, object]]]:
        with self._connect(readonly=True) as connection:
            rows = connection.execute(
                """
                SELECT id, phrase, numeric_pinyin, yime_code, sort_weight, updated_at
                FROM user_phrase_entries
                ORDER BY sort_weight DESC, updated_at DESC, phrase
                """
            ).fetchall()

        grouped: Dict[str, List[Dict[str, object]]] = {}
        for row in rows:
            pinyin_tone = str(row["numeric_pinyin"] or "").strip()
            canonical_code = resolve_canonical_code_from_numeric_pinyin(
                pinyin_to_canonical,
                pinyin_tone,
            )
            if not canonical_code:
                continue
            phrase = str(row["phrase"] or "").strip()
            if not phrase:
                continue
            grouped.setdefault(canonical_code, []).append(
                {
                    "text": phrase,
                    "entry_type": "phrase",
                    "entry_id": f"user_phrase:{row['id']}",
                    "pinyin_tone": pinyin_tone,
                    "sort_weight": row["sort_weight"],
                    "is_common": True,
                    "text_length": len(phrase),
                    "updated_at": row["updated_at"],
                    "yime_code": row["yime_code"],
                }
            )
        return grouped

    def lookup_first_phrase(self, phrase: str) -> UserPhraseEntry | None:
        normalized_phrase = phrase.strip()
        if not normalized_phrase:
            return None

        with self._connect(readonly=True) as connection:
            row = connection.execute(
                """
                SELECT phrase, numeric_pinyin, marked_pinyin, yime_code, sort_weight
                FROM user_phrase_entries
                WHERE phrase = ?
                ORDER BY sort_weight DESC, updated_at DESC
                LIMIT 1
                """,
                (normalized_phrase,),
            ).fetchone()
        if row is None:
            return None
        return UserPhraseEntry(
            phrase=str(row["phrase"] or ""),
            numeric_pinyin=str(row["numeric_pinyin"] or ""),
            marked_pinyin=str(row["marked_pinyin"] or ""),
            yime_code=str(row["yime_code"] or ""),
            sort_weight=float(row["sort_weight"] or self.DEFAULT_PHRASE_SORT_WEIGHT),
        )
