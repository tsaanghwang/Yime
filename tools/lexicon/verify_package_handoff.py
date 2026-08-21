#!/usr/bin/env python3
"""Verify that a staged Yime package contains the locked runtime handoff."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


MODULE_DIR = Path(__file__).resolve().parent
if str(MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_DIR))

from verify_target_lock import DEFAULT_LOCK, REPO_ROOT, VerificationError, verify


DATA_PREFIX = "go-backend/input_methods/yime/data/"
REQUIRED_HELP = (
    "README.md",
    "README.html",
    "settings-and-data.md",
    "settings-and-data.html",
)
FORBIDDEN_NAMES = {
    "python.exe",
    "pyvenv.cfg",
    "yime_core_fixed.dict.yaml",
    "yime_core_fixed.evidence.json",
    "selection.tsv",
    "pinyin_hanzi.db",
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise VerificationError(f"JSON root must be an object: {path}")
    return value


def verify_package(
    package_root: Path,
    *,
    lock_path: Path = DEFAULT_LOCK,
    repo_root: Path = REPO_ROOT,
) -> dict[str, Any]:
    locked = verify(lock_path.resolve(), repo_root.resolve())
    package_root = package_root.resolve()
    data_dir = package_root / "data"
    help_dir = package_root / "help"
    if not data_dir.is_dir() or not help_dir.is_dir():
        raise VerificationError(
            f"staged package lacks Yime data/help directories: {package_root}"
        )

    package_hashes: dict[str, str] = {}
    for artifact in locked["verified_artifacts"]:
        relative = str(artifact["path"])
        if not relative.startswith(DATA_PREFIX):
            continue
        name = Path(relative).name
        packaged = data_dir / name
        if not packaged.is_file():
            raise VerificationError(f"packaged locked artifact is missing: {name}")
        digest = _sha256(packaged)
        if digest != artifact["sha256"]:
            raise VerificationError(
                f"packaged locked artifact hash mismatch: {name}"
            )
        package_hashes[name] = digest

    profile = _read_json(data_dir / "yime_runtime_profile.json")
    if profile.get("default_schema") != "yime_variable":
        raise VerificationError("packaged default schema is not yime_variable")
    if profile.get("runtime_schemas") != [
        "yime_variable",
        "yime_full",
        "yime_shorthand",
    ]:
        raise VerificationError("packaged runtime schema order drifted")
    for field in ("runtime_manifest", "source_evidence_manifest"):
        name = str(profile.get(field) or "")
        if not name or not (data_dir / name).is_file():
            raise VerificationError(f"packaged runtime profile has missing {field}")

    help_hashes: dict[str, str] = {}
    source_help = repo_root / "go-backend" / "input_methods" / "yime" / "help"
    for name in REQUIRED_HELP:
        packaged = help_dir / name
        source = source_help / name
        if not packaged.is_file() or not source.is_file():
            raise VerificationError(f"packaged help file is missing: {name}")
        digest = _sha256(packaged)
        if digest != _sha256(source):
            raise VerificationError(f"packaged help file is stale: {name}")
        help_hashes[name] = digest

    forbidden: list[str] = []
    for path in package_root.rglob("*"):
        if not path.is_file():
            continue
        lower_name = path.name.lower()
        if (
            lower_name in FORBIDDEN_NAMES
            or lower_name.endswith((".py", ".pyc"))
            or (lower_name.startswith("python") and lower_name.endswith(".dll"))
        ):
            forbidden.append(path.relative_to(package_root).as_posix())
    if forbidden:
        raise VerificationError(
            "offline/prototype artifacts leaked into the Windows package: "
            + ", ".join(sorted(forbidden))
        )

    return {
        "decision": "pass",
        "lock_id": locked["lock_id"],
        "entry_count": locked["target"]["entry_count"],
        "package_root": str(package_root),
        "locked_runtime_artifacts": package_hashes,
        "help_files": help_hashes,
        "python_runtime_packaged": False,
        "prototype_database_packaged": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = verify_package(
            args.package_root,
            lock_path=args.lock,
            repo_root=args.repo_root,
        )
    except (OSError, json.JSONDecodeError, VerificationError) as exc:
        print(f"FAIL packaged handoff: {exc}", file=sys.stderr)
        return 1
    payload = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8")
    print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
