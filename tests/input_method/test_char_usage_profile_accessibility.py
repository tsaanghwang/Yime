from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

import pytest


DB_PATH = Path(__file__).resolve().parents[2] / "yime" / "pinyin_hanzi.db"
REAL_COLLISION_CODE = "\U00100005\U00100025\U00100030\U00100020"
FIRST_PAGE_LIMIT = 5


def _require_runtime_db() -> None:
    if not DB_PATH.exists():
        pytest.skip("runtime SQLite database is unavailable in this environment")
    header = DB_PATH.read_bytes()[:32]
    if header.startswith(b"version https://git-lfs.github.com/spec/v1"):
        pytest.skip("runtime SQLite database is only available as a Git LFS pointer")
    if not header.startswith(b"SQLite format 3\x00"):
        pytest.skip("runtime SQLite database is unavailable in this environment")


def _load_ranked_char_bucket(yime_code: str) -> list[sqlite3.Row]:
    _require_runtime_db()
    with sqlite3.connect(DB_PATH) as connection:
        connection.row_factory = sqlite3.Row
        return connection.execute(
            '''
            SELECT
                hanzi,
                usage_tier,
                COALESCE(tier_sort_weight, 0.0)
                    + CASE WHEN is_common_reading = 1 THEN COALESCE(modern_common_boost, 0.0) ELSE 0.0 END
                    + COALESCE(reading_phrase_prior_boost, 0.0)
                    + COALESCE(char_frequency_abs, 0)
                    + COALESCE(reading_weight, CASE WHEN is_common_reading = 1 THEN 1.0 ELSE 0.5 END) AS sort_weight
            FROM char_lexicon
            WHERE yime_code = ?
            ORDER BY sort_weight DESC, hanzi
            ''',
            (yime_code,),
        ).fetchall()


def test_require_runtime_db_skips_when_runtime_db_is_absent(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    missing_db_path = DB_PATH.parent / "pinyin_hanzi.absent.db"
    monkeypatch.setattr(sys.modules[__name__], "DB_PATH", missing_db_path)

    with pytest.raises(pytest.skip.Exception, match="runtime SQLite database is unavailable"):
        _require_runtime_db()


def test_special_tier_chars_remain_reachable_in_real_collision_bucket() -> None:
    ranked = _load_ranked_char_bucket(REAL_COLLISION_CODE)
    hanzi_order = [str(row["hanzi"] or "") for row in ranked]
    first_page = hanzi_order[:FIRST_PAGE_LIMIT]

    assert "魋" in first_page
    assert "𬯎" in first_page
    assert "𪨇" in hanzi_order
    assert hanzi_order.index("魋") < hanzi_order.index("𪨇")
