from __future__ import annotations

from pathlib import Path

import pytest

from yime.asset_paths import (
    generated_runtime_candidates_json_path,
    generated_lexicon_source_db_path,
    resolve_lexicon_source_db_path,
    resolve_runtime_candidates_json_path,
    resolve_source_pinyin_db_path,
)


def test_resolve_runtime_candidates_json_path_prefers_generated_file(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo_root = tmp_path
    app_dir = repo_root / "yime"
    app_dir.mkdir()
    generated_path = generated_runtime_candidates_json_path(repo_root)
    generated_path.parent.mkdir(parents=True)
    generated_path.write_text('{"by_code": {}}', encoding="utf-8")

    monkeypatch.delenv("YIME_RUNTIME_CANDIDATES_JSON", raising=False)

    assert resolve_runtime_candidates_json_path(app_dir) == generated_path


def test_resolve_runtime_candidates_json_path_prefers_env_override(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    app_dir = tmp_path / "yime"
    app_dir.mkdir()
    override_path = tmp_path / "external" / "runtime.json"
    monkeypatch.setenv("YIME_RUNTIME_CANDIDATES_JSON", str(override_path))

    assert resolve_runtime_candidates_json_path(app_dir) == override_path


def test_resolve_source_pinyin_db_path_uses_unified_lexicon_database(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    generated_path = generated_lexicon_source_db_path(tmp_path)
    generated_path.parent.mkdir(parents=True)
    generated_path.write_text("sqlite", encoding="utf-8")

    monkeypatch.delenv("YIME_LEXICON_SOURCE_DB", raising=False)

    assert resolve_lexicon_source_db_path(tmp_path) == generated_path


def test_resolve_source_pinyin_db_path_does_not_fall_back_to_legacy_path(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("YIME_LEXICON_SOURCE_DB", raising=False)

    expected = generated_lexicon_source_db_path(tmp_path)
    assert resolve_lexicon_source_db_path(tmp_path) == expected


def test_resolve_source_pinyin_db_path_honors_new_override(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    override = tmp_path / "external" / "source_lexicon.sqlite3"
    monkeypatch.setenv("YIME_LEXICON_SOURCE_DB", str(override))
    monkeypatch.setenv("YIME_SOURCE_PINYIN_DB", str(tmp_path / "legacy.db"))

    assert resolve_lexicon_source_db_path(tmp_path) == override
