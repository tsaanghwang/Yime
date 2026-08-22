#!/usr/bin/env python3
"""Audit the fail-closed boundary around data imported into Yime."""

from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
LOCK_PATH = REPO_ROOT / "tools" / "lexicon" / "data" / "external_inputs.lock.json"
APPROVAL_ROOT = REPO_ROOT / "tools" / "data_import_approvals"

FORBIDDEN_FUNCTIONAL_FRAGMENTS = {
    "ROOT.parent / \"Yime-keyboard-layout\"",
    "REPO_ROOT.parent / \"RIME-LMDG\"",
    "WORKSPACE_ROOT.parent / \"RIME-LMDG\"",
    "YIME_KEYBOARD_LAYOUT_REPO",
    "--no-legacy-external-paths",
    "--no-legacy-paths",
    "C:/dev/Yime-python-prototype",
    "C:\\dev\\Yime-python-prototype",
    "C:/dev/Yime-prototype",
    "C:\\dev\\Yime-prototype",
    "C:/dev/RIME-LMDG",
    "C:\\dev\\RIME-LMDG",
    "C:/dev/Yime-keyboard-layout",
    "C:\\dev\\Yime-keyboard-layout",
}
SCANNED_SUFFIXES = {
    ".bat",
    ".cmd",
    ".cmake",
    ".cpp",
    ".go",
    ".h",
    ".json",
    ".ps1",
    ".py",
    ".rs",
    ".yaml",
    ".yml",
}
EXCLUDED_PREFIXES = (
    "docs/",
    "tools/data_import_approvals/",
)


def _tracked_files() -> list[Path]:
    result = subprocess.run(
        [
            "git",
            "-C",
            str(REPO_ROOT),
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
        ],
        check=True,
        capture_output=True,
    )
    return [
        REPO_ROOT / raw.decode("utf-8")
        for raw in result.stdout.split(b"\0")
        if raw
    ]


def _relative(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def _check_lock() -> list[str]:
    failures: list[str] = []
    payload = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    if payload.get("external_root_environment") != "YIME_LEXICON_EXTERNAL_ROOT":
        failures.append("external input lock must use YIME_LEXICON_EXTERNAL_ROOT")
    records = payload.get("inputs")
    if not isinstance(records, list) or not records:
        failures.append("external input lock is empty")
        return failures
    for record in records:
        if not isinstance(record, dict):
            failures.append("external input lock contains a non-object record")
            continue
        if "legacy_path" in record:
            failures.append(
                f"external input {record.get('id')!r} reintroduced legacy_path"
            )
        relative_path = str(record.get("relative_path") or "")
        if Path(relative_path).is_absolute() or ":" in relative_path or "\\" in relative_path:
            failures.append(
                f"external input {record.get('id')!r} has a non-portable path"
            )
    return failures


def _check_functional_sources() -> list[str]:
    failures: list[str] = []
    for path in _tracked_files():
        relative = _relative(path)
        if (
            relative == "tools/lexicon/check_repository_data_boundary.py"
            or relative.startswith(EXCLUDED_PREFIXES)
            or path.suffix.lower() not in SCANNED_SUFFIXES
        ):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for fragment in FORBIDDEN_FUNCTIONAL_FRAGMENTS:
            if fragment in text:
                failures.append(f"{relative} contains forbidden data-source fallback {fragment!r}")
    required_guards = {
        "yime/lexicon_bundle/external_inputs.py": "assert_data_source_allowed",
        "yime/lexicon_bundle/builder.py": "assert_data_source_allowed",
        "tools/lexicon/prepare_reproducible_handoff.py": "assert_data_source_allowed",
        "tools/import-yime-core-lexicon.ps1": "assert-data-source-boundary.ps1",
    }
    for relative, marker in required_guards.items():
        text = (REPO_ROOT / relative).read_text(encoding="utf-8")
        if marker not in text:
            failures.append(f"{relative} is missing repository boundary guard {marker!r}")
    return failures


def _check_active_approvals() -> list[str]:
    failures: list[str] = []
    now = datetime.now(timezone.utc)
    for path in APPROVAL_ROOT.glob("*.json"):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            expires = datetime.fromisoformat(
                str(payload["expires_at"]).replace("Z", "+00:00")
            )
        except (KeyError, OSError, ValueError, json.JSONDecodeError) as exc:
            failures.append(f"invalid repository import approval {path.name}: {exc}")
            continue
        if payload.get("schema_version") != "yime-repository-data-import-approval-v1":
            failures.append(f"unsupported repository import approval {path.name}")
        if payload.get("decision") != "allow" or payload.get("target_repository") != "Yime":
            failures.append(f"non-allow repository import approval {path.name}")
        if expires.tzinfo is None or expires.astimezone(timezone.utc) <= now:
            failures.append(f"expired repository import approval {path.name}")
    return failures


def main() -> int:
    failures = _check_lock() + _check_functional_sources() + _check_active_approvals()
    if failures:
        for failure in failures:
            print(f"FAIL repository data boundary: {failure}")
        return 1
    print("PASS repository data boundary: no unapproved repository fallback is active")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
