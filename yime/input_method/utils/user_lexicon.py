from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
import json
import sqlite3
from pathlib import Path
from typing import Dict, List, Literal, Mapping


@dataclass(frozen=True)
class UserPhraseEntry:
    phrase: str
    numeric_pinyin: str
    marked_pinyin: str
    yime_code: str
    sort_weight: float


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
                """
            )

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
