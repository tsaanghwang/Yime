from pathlib import Path
import json

from yime.input_method.core.decoders import SQLiteRuntimeCandidateDecoder
from yime.input_method.utils.runtime_reverse_lookup import RuntimeReverseLookup
from yime.input_method.utils.user_lexicon import (
    UserLexiconStore,
    resolve_yime_code_from_numeric_pinyin,
)


def test_user_lexicon_store_persists_phrase_entry(tmp_path) -> None:
    store = UserLexiconStore(tmp_path / "user_lexicon.db")
    action = store.upsert_phrase(
        "日本",
        "ri4 ben3",
        marked_pinyin="rì běn",
        yime_code="TESTCODE",
    )

    reloaded = UserLexiconStore(tmp_path / "user_lexicon.db")
    entry = reloaded.lookup_first_phrase("日本")
    grouped = reloaded.load_phrase_candidates({"ri4": "ABCD", "ben3": "1234"})

    assert action == "inserted"
    assert entry is not None
    assert entry.marked_pinyin == "rì běn"
    assert grouped["ABCD1234"][0]["text"] == "日本"


def test_user_lexicon_store_reports_updated_for_existing_phrase(tmp_path) -> None:
    store = UserLexiconStore(tmp_path / "user_lexicon.db")
    store.upsert_phrase("日本", "ri4 ben3", marked_pinyin="rì běn", yime_code="CODE1")

    action = store.upsert_phrase(
        "日本",
        "ri4 ben3",
        marked_pinyin="rì běn",
        yime_code="CODE2",
    )

    assert action == "updated"
    assert store.lookup_first_phrase("日本").yime_code == "CODE2"


def test_user_lexicon_store_lists_phrase_entries(tmp_path) -> None:
    store = UserLexiconStore(tmp_path / "user_lexicon.db")
    store.upsert_phrase("日本", "ri4 ben3", marked_pinyin="rì běn", yime_code="CODE1")
    store.upsert_phrase("今日", "jin1 ri4", marked_pinyin="jīn rì", yime_code="CODE2")

    rows = store.list_phrase_entries("日", use_like=True, limit=10)

    assert [row.phrase for row in rows] == ["今日", "日本"]
    assert rows[0].numeric_pinyin == "jin1 ri4"


def test_user_lexicon_store_lists_and_resets_frequency_entries(tmp_path) -> None:
    store = UserLexiconStore(tmp_path / "user_lexicon.db")
    store.upsert_phrase("日本", "ri4 ben3", marked_pinyin="rì běn", yime_code="YIME")
    store.record_candidate_selection("ABCD1234", "日本")
    store.record_candidate_selection("ABCD1234", "日本")

    rows = store.list_candidate_frequency_entries("日", use_like=True, limit=10)

    assert len(rows) == 1
    assert rows[0].text == "日本"
    assert rows[0].freq == 2
    assert rows[0].numeric_pinyin == "ri4 ben3"

    deleted_rows = store.reset_candidate_frequency(text="日本", lookup_code="ABCD1234")

    assert deleted_rows == 1
    assert store.list_candidate_frequency_entries(limit=10) == []


def test_user_lexicon_store_exports_and_imports_backup(tmp_path) -> None:
    source_store = UserLexiconStore(tmp_path / "source_user_lexicon.db")
    source_store.upsert_phrase(
        "日本",
        "ri4 ben3",
        marked_pinyin="rì běn",
        yime_code="CODE1",
        source_note="seed",
    )
    source_store.record_candidate_selection("ABCD1234", "日本")
    backup_path = tmp_path / "backup.json"

    source_store.write_export_file(backup_path)
    backup_payload = json.loads(backup_path.read_text(encoding="utf-8"))

    assert backup_payload["phrase_entries"][0]["phrase"] == "日本"
    assert backup_payload["candidate_frequency"][0]["text"] == "日本"

    target_store = UserLexiconStore(tmp_path / "target_user_lexicon.db")
    result = target_store.import_file(backup_path)

    assert result == {"phrase_entries": 1, "candidate_frequency": 1}
    assert target_store.lookup_first_phrase("日本") is not None
    frequency_rows = target_store.list_candidate_frequency_entries(limit=10)
    assert len(frequency_rows) == 1
    assert frequency_rows[0].freq == 1


def test_user_lexicon_store_lists_recent_entries(tmp_path) -> None:
    store = UserLexiconStore(tmp_path / "user_lexicon.db")
    store.upsert_phrase("日本", "ri4 ben3", marked_pinyin="rì běn", yime_code="CODE1")
    store.upsert_phrase("今日", "jin1 ri4", marked_pinyin="jīn rì", yime_code="CODE2")

    rows = store.list_recent_phrase_entries(limit=1)

    assert len(rows) == 1
    assert rows[0].phrase in {"日本", "今日"}


def test_runtime_reverse_lookup_prefers_user_phrase_entry(tmp_path) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    user_db_path = tmp_path / "user_lexicon.db"
    store = UserLexiconStore(user_db_path)
    store.upsert_phrase(
        "今日",
        "jin1 ri4",
        marked_pinyin="jīn rì",
        yime_code=resolve_yime_code_from_numeric_pinyin(repo_root, "jin1 ri4"),
    )

    lookup = RuntimeReverseLookup(
        repo_root / "yime" / "pinyin_hanzi.db",
        user_db_path=user_db_path,
    )
    record = lookup.lookup_first("今日")

    assert record is not None
    assert record.marked_pinyin == "jīn rì"
    assert record.numeric_pinyin == "jin1 ri4"


def test_sqlite_runtime_decoder_merges_user_phrase_candidates(tmp_path) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    app_dir = repo_root / "yime"
    user_db_path = tmp_path / "user_lexicon.db"
    store = UserLexiconStore(user_db_path)
    code = resolve_yime_code_from_numeric_pinyin(repo_root, "ri4 ben3")
    store.upsert_phrase(
        "日本",
        "ri4 ben3",
        marked_pinyin="rì běn",
        yime_code=code,
    )

    decoder = SQLiteRuntimeCandidateDecoder(app_dir, user_db_path=user_db_path)
    canonical_code = (
        decoder.pinyin_to_canonical["ri4"]
        + decoder.pinyin_to_canonical["ben3"]
    )
    _canonical, _active, _pinyin, candidates, _status = decoder.decode_text(canonical_code)

    assert "日本" in candidates


def test_sqlite_runtime_decoder_persists_user_frequency_across_instances(tmp_path) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    app_dir = repo_root / "yime"
    user_db_path = tmp_path / "user_lexicon.db"

    decoder = SQLiteRuntimeCandidateDecoder(app_dir, user_db_path=user_db_path)
    decoder.by_code = {
        "abcdefgh": [
            {
                "text": "安全",
                "entry_type": "phrase",
                "pinyin_tone": "an1 quan2",
                "sort_weight": 100.0,
                "text_length": 2,
                "is_common": 1,
            },
            {
                "text": "安权",
                "entry_type": "phrase",
                "pinyin_tone": "an1 quan2",
                "sort_weight": 100.0,
                "text_length": 2,
                "is_common": 1,
            },
        ]
    }
    decoder._user_freq_by_candidate = decoder.user_lexicon.load_candidate_frequency()

    _canonical, _active, _pinyin, candidates, _status = decoder.decode_text("abcdefgh")
    assert candidates[:2] == ["安全", "安权"]

    decoder.record_selection("abcdefgh", "安权")

    reloaded = SQLiteRuntimeCandidateDecoder(app_dir, user_db_path=user_db_path)
    reloaded.by_code = decoder.by_code
    reloaded._user_freq_by_candidate = reloaded.user_lexicon.load_candidate_frequency()

    _canonical, _active, _pinyin, promoted, _status = reloaded.decode_text("abcdefgh")
    assert promoted[:2] == ["安权", "安全"]
