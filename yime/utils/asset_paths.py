from __future__ import annotations

import os
from pathlib import Path


def _read_env_path(name: str) -> Path | None:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return None
    return Path(raw).expanduser()


def generated_runtime_candidates_json_path(repo_root: Path) -> Path:
    return repo_root / ".generated" / "runtime_candidates_by_code_true.json"


def resolve_runtime_candidates_json_path(app_dir: Path) -> Path:
    override = _read_env_path("YIME_RUNTIME_CANDIDATES_JSON")
    if override is not None:
        return override

    generated_path = generated_runtime_candidates_json_path(app_dir.parent)
    if generated_path.exists():
        return generated_path

    return app_dir / "reports" / "runtime_candidates_by_code_true.json"


def generated_lexicon_source_db_path(workspace_root: Path) -> Path:
    return (
        workspace_root
        / ".generated"
        / "lexicon_source_bundle"
        / "source_lexicon.sqlite3"
    )


def resolve_lexicon_source_db_path(workspace_root: Path) -> Path:
    override = _read_env_path("YIME_LEXICON_SOURCE_DB")
    if override is not None:
        return override
    return generated_lexicon_source_db_path(workspace_root)


def resolve_source_pinyin_db_path(workspace_root: Path) -> Path:
    """Deprecated API name; resolves only the unified lexicon source database."""
    return resolve_lexicon_source_db_path(workspace_root)
