"""Fail-closed boundary for data read from another source repository."""

from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
APPROVAL_DIRECTORY = REPO_ROOT / "tools" / "data_import_approvals"
APPROVAL_SCHEMA = "yime-repository-data-import-approval-v1"
KNOWN_DETACHED_REPOSITORIES = frozenset(
    {
        "yime-python-prototype",
        "yime-prototype",
    }
)
MAX_APPROVAL_LIFETIME = timedelta(days=31)


class RepositoryBoundaryError(RuntimeError):
    """Raised when a data source crosses a repository boundary without approval."""


def _normalized(path: Path) -> str:
    return os.path.normcase(os.path.abspath(path))


def _is_within(path: Path, root: Path) -> bool:
    try:
        return os.path.commonpath((_normalized(path), _normalized(root))) == _normalized(root)
    except ValueError:
        return False


def _source_repository_root(path: Path) -> Path | None:
    current = path if path.is_dir() else path.parent
    for candidate in (current, *current.parents):
        if (candidate / ".git").exists():
            return candidate.resolve()
        if candidate.name.casefold() in KNOWN_DETACHED_REPOSITORIES:
            return candidate.resolve()
    return None


def _reject_reparse_path(path: Path) -> None:
    absolute = Path(os.path.abspath(path.expanduser()))
    for candidate in (absolute, *absolute.parents):
        try:
            is_junction = bool(
                getattr(candidate, "is_junction", lambda: False)()
            )
            if candidate.is_symlink() or is_junction:
                raise RepositoryBoundaryError(
                    "data source paths must not traverse a symlink or junction: "
                    f"{candidate}"
                )
        except OSError as exc:
            raise RepositoryBoundaryError(
                f"cannot inspect data source path boundary: {candidate}"
            ) from exc


def _parse_timestamp(payload: dict[str, Any], field: str) -> datetime:
    value = payload.get(field)
    if not isinstance(value, str) or not value.strip():
        raise RepositoryBoundaryError(f"repository import approval has no {field}")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise RepositoryBoundaryError(
            f"repository import approval has invalid {field}"
        ) from exc
    if parsed.tzinfo is None:
        raise RepositoryBoundaryError(
            f"repository import approval {field} must include a timezone"
        )
    return parsed.astimezone(timezone.utc)


def _validate_approval(
    approval_path: Path,
    *,
    source_repository_root: Path,
    input_id: str,
) -> dict[str, Any]:
    resolved_approval = approval_path.resolve(strict=True)
    allowed_directory = APPROVAL_DIRECTORY.resolve()
    if not _is_within(resolved_approval, allowed_directory):
        raise RepositoryBoundaryError(
            "repository import approval must be stored under "
            f"{allowed_directory} for review"
        )
    try:
        payload = json.loads(resolved_approval.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RepositoryBoundaryError(
            f"cannot read repository import approval {resolved_approval}: {exc}"
        ) from exc
    if not isinstance(payload, dict):
        raise RepositoryBoundaryError("repository import approval root must be an object")
    if payload.get("schema_version") != APPROVAL_SCHEMA:
        raise RepositoryBoundaryError("unsupported repository import approval schema")
    if payload.get("decision") != "allow":
        raise RepositoryBoundaryError("repository import approval decision is not allow")
    if payload.get("target_repository") != "Yime":
        raise RepositoryBoundaryError("repository import approval target is not Yime")
    for field in ("approval_id", "approved_by", "reason", "authorization_reference"):
        if not isinstance(payload.get(field), str) or not payload[field].strip():
            raise RepositoryBoundaryError(
                f"repository import approval has no {field}"
            )
    approved_at = _parse_timestamp(payload, "approved_at")
    expires_at = _parse_timestamp(payload, "expires_at")
    now = datetime.now(timezone.utc)
    if approved_at > now:
        raise RepositoryBoundaryError("repository import approval is not active yet")
    if expires_at <= now:
        raise RepositoryBoundaryError("repository import approval has expired")
    if expires_at <= approved_at or expires_at - approved_at > MAX_APPROVAL_LIFETIME:
        raise RepositoryBoundaryError(
            "repository import approval lifetime must be positive and at most 31 days"
        )
    declared_root = payload.get("source_repository_root")
    if not isinstance(declared_root, str) or not declared_root.strip():
        raise RepositoryBoundaryError(
            "repository import approval has no source_repository_root"
        )
    if _normalized(Path(declared_root).expanduser().resolve()) != _normalized(
        source_repository_root
    ):
        raise RepositoryBoundaryError(
            "repository import approval source_repository_root does not match the data source"
        )
    allowed_inputs = payload.get("allowed_input_ids")
    if (
        not isinstance(allowed_inputs, list)
        or not allowed_inputs
        or any(not isinstance(item, str) or not item for item in allowed_inputs)
        or input_id not in allowed_inputs
    ):
        raise RepositoryBoundaryError(
            f"repository import approval does not allow input ID {input_id!r}"
        )
    return payload


def assert_data_source_allowed(
    path: Path,
    *,
    input_id: str,
    approval_path: Path | None = None,
) -> Path:
    """Return a resolved data path or reject an unapproved cross-repository read."""
    if not input_id.strip():
        raise RepositoryBoundaryError("data import input ID must not be empty")
    _reject_reparse_path(path)
    try:
        resolved = path.expanduser().resolve(strict=True)
    except OSError as exc:
        raise RepositoryBoundaryError(f"data source does not exist: {path}") from exc
    source_root = _source_repository_root(resolved)
    if source_root is None or _is_within(source_root, REPO_ROOT):
        return resolved
    if approval_path is None:
        raise RepositoryBoundaryError(
            "data source belongs to another repository and is blocked by default: "
            f"{resolved} (repository {source_root}); input ID {input_id!r}. "
            "A reviewed, time-limited repository import approval is required."
        )
    _validate_approval(
        approval_path,
        source_repository_root=source_root,
        input_id=input_id,
    )
    return resolved
