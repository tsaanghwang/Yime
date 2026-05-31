from __future__ import annotations

from pathlib import Path

from internal_data.pinyin_source_db.build_source_pinyin_db import sync_legacy_fallback_db
from yime.asset_paths import (
    generated_runtime_candidates_json_path,
    generated_source_pinyin_db_path,
    resolve_runtime_candidates_json_path,
    resolve_source_pinyin_db_path,
)


def test_resolve_runtime_candidates_json_path_prefers_generated_file(tmp_path, monkeypatch) -> None:
    repo_root = tmp_path
    app_dir = repo_root / "yime"
    app_dir.mkdir()
    generated_path = generated_runtime_candidates_json_path(repo_root)
    generated_path.parent.mkdir(parents=True)
    generated_path.write_text('{"by_code": {}}', encoding="utf-8")

    monkeypatch.delenv("YIME_RUNTIME_CANDIDATES_JSON", raising=False)

    assert resolve_runtime_candidates_json_path(app_dir) == generated_path


def test_resolve_runtime_candidates_json_path_prefers_env_override(tmp_path, monkeypatch) -> None:
    app_dir = tmp_path / "yime"
    app_dir.mkdir()
    override_path = tmp_path / "external" / "runtime.json"
    monkeypatch.setenv("YIME_RUNTIME_CANDIDATES_JSON", str(override_path))

    assert resolve_runtime_candidates_json_path(app_dir) == override_path


def test_resolve_source_pinyin_db_path_prefers_generated_file(tmp_path, monkeypatch) -> None:
    generated_path = generated_source_pinyin_db_path(tmp_path)
    generated_path.parent.mkdir(parents=True)
    generated_path.write_text("sqlite", encoding="utf-8")

    monkeypatch.delenv("YIME_SOURCE_PINYIN_DB", raising=False)

    assert resolve_source_pinyin_db_path(tmp_path) == generated_path


def test_resolve_source_pinyin_db_path_falls_back_to_legacy_path(tmp_path, monkeypatch) -> None:
    monkeypatch.delenv("YIME_SOURCE_PINYIN_DB", raising=False)

    expected = tmp_path / "internal_data" / "pinyin_source_db" / "source_pinyin.db"
    assert resolve_source_pinyin_db_path(tmp_path) == expected


def test_sync_legacy_fallback_db_copies_built_database(tmp_path) -> None:
    db_path = tmp_path / ".generated" / "source_pinyin.db"
    db_path.parent.mkdir(parents=True)
    db_path.write_text("new schema", encoding="utf-8")
    legacy_path = tmp_path / "internal_data" / "pinyin_source_db" / "source_pinyin.db"

    synced = sync_legacy_fallback_db(db_path, legacy_path)

    assert synced is True
    assert legacy_path.read_text(encoding="utf-8") == "new schema"
