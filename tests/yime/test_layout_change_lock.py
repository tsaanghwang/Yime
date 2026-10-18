import json
from pathlib import Path

import tools.check_layout_change_lock as layout_change_lock
from tools.check_layout_change_lock import (
    check_layout_change_lock,
    compare_pinyin_chain_entry,
    pinyin_yinyuan_chain_digest,
    semantic_registry_digest,
    syllable_provenance_digest,
    syllable_rule_catalog_digest,
)
from yime.utils.yinyuan_id_chain import encode_numeric_pinyin_to_yinyuan_ids


ROOT = Path(__file__).resolve().parents[2]


def test_numeric_pinyin_reaches_ids_before_any_keyboard_projection() -> None:
    assert encode_numeric_pinyin_to_yinyuan_ids("ba1") == ("N01", "M10", "M10", "M10")
    assert encode_numeric_pinyin_to_yinyuan_ids("ka1") == ("N10", "M10", "M10", "M10")
    assert encode_numeric_pinyin_to_yinyuan_ids("zhong1") == ("N16", "M04", "M13", "M31")


def test_semantic_registry_matches_reviewed_layout_lock() -> None:
    lock = json.loads(
        (ROOT / "internal_data" / "layout_change_lock.json").read_text(encoding="utf-8")
    )
    assert semantic_registry_digest(ROOT) == lock["semantic_registry_sha256"]
    assert pinyin_yinyuan_chain_digest(ROOT) == lock["pinyin_yinyuan_chain_sha256"]
    assert syllable_rule_catalog_digest(ROOT) == lock["syllable_rule_catalog_sha256"]
    assert syllable_provenance_digest(ROOT) == lock["syllable_provenance_sha256"]


def test_middle_entry_is_rejected() -> None:
    semantic = encode_numeric_pinyin_to_yinyuan_ids("ba1")
    injected = encode_numeric_pinyin_to_yinyuan_ids("ka1")
    message = compare_pinyin_chain_entry("ba1", semantic, injected)
    assert "middle-entry code detected for ba1" in message
    assert "N01" in message
    assert "N10" in message


def test_repository_layout_change_lock_is_closed() -> None:
    assert check_layout_change_lock(ROOT) == []


def test_clean_checkout_uses_locked_provenance_audit(
    monkeypatch,
    tmp_path: Path,
) -> None:
    missing_source_db = tmp_path / "source_lexicon.sqlite3"
    monkeypatch.setattr(
        layout_change_lock,
        "resolve_lexicon_source_db_path",
        lambda _repo_root: missing_source_db,
    )

    lock = json.loads((ROOT / "internal_data" / "layout_change_lock.json").read_text(encoding="utf-8"))
    assert not missing_source_db.exists()
    assert syllable_provenance_digest(ROOT) == lock["syllable_provenance_sha256"]
    assert check_layout_change_lock(ROOT) == []
