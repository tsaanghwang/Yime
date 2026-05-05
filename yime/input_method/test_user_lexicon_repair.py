from pathlib import Path

from yime.input_method.utils.user_lexicon import UserLexiconStore, resolve_yime_code_from_numeric_pinyin


REPO_ROOT = Path(__file__).resolve().parents[2]


def test_repair_phrase_entries_normalizes_yime_code_and_drops_duplicates(tmp_path) -> None:
    store = UserLexiconStore(tmp_path / "user_lexicon.db")
    resolved_code = resolve_yime_code_from_numeric_pinyin(REPO_ROOT, "ri4 ben3")

    with store._connect() as connection:
        connection.execute(
            """
            INSERT INTO user_phrase_entries (phrase, numeric_pinyin, marked_pinyin, yime_code, source_note)
            VALUES (?, ?, ?, ?, ?)
            """,
            (" 日本 ", "ri4   ben3", "rì   běn", "WRONG", " note "),
        )
        connection.execute(
            """
            INSERT INTO user_phrase_entries (phrase, numeric_pinyin, marked_pinyin, yime_code, source_note)
            VALUES (?, ?, ?, ?, ?)
            """,
            ("日本", "ri4 ben3", "rì běn", resolved_code, "seed"),
        )

    result = store.repair_phrase_entries(REPO_ROOT)
    rows = store.list_phrase_entries(limit=10)

    assert result["deleted_duplicate_phrase_rows"] == 1
    assert len(rows) == 1
    assert rows[0].phrase == "日本"
    assert rows[0].numeric_pinyin == "ri4 ben3"
    assert rows[0].yime_code == resolved_code


def test_repair_candidate_frequency_entries_merges_trimmed_duplicates_and_drops_invalid(tmp_path) -> None:
    store = UserLexiconStore(tmp_path / "user_lexicon.db")

    with store._connect() as connection:
        connection.execute(
            "INSERT INTO user_candidate_frequency (lookup_code, text, freq, last_used_at) VALUES (?, ?, ?, ?)",
            (" code ", " 日本 ", 2, "2026-05-05 01:00:00"),
        )
        connection.execute(
            "INSERT INTO user_candidate_frequency (lookup_code, text, freq, last_used_at) VALUES (?, ?, ?, ?)",
            ("code", "日本", 3, "2026-05-05 02:00:00"),
        )
        connection.execute(
            "INSERT INTO user_candidate_frequency (lookup_code, text, freq, last_used_at) VALUES (?, ?, ?, ?)",
            ("", "", 0, "2026-05-05 03:00:00"),
        )

    result = store.repair_candidate_frequency_entries()
    rows = store.list_candidate_frequency_entries(limit=10)

    assert result["deleted_invalid_frequency_rows"] == 1
    assert result["deleted_duplicate_frequency_rows"] == 1
    assert len(rows) == 1
    assert rows[0].lookup_code == "code"
    assert rows[0].text == "日本"
    assert rows[0].freq == 5
    assert rows[0].last_used_at == "2026-05-05 02:00:00"


def test_repair_meta_entries_clears_stale_seed_skip_without_user_data(tmp_path) -> None:
    store = UserLexiconStore(tmp_path / "user_lexicon.db")
    store.set_meta("seed_import_completed", "skipped_existing_user_data")

    result = store.repair_meta_entries()

    assert result["deleted_invalid_meta_rows"] == 1
    assert store.get_meta("seed_import_completed") == ""
