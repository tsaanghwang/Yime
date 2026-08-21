#!/usr/bin/env python3
"""Gate tagged releases on source-level reproduction of the approved core."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


MODULE_DIR = Path(__file__).resolve().parent
if str(MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_DIR))

from verify_target_lock import DEFAULT_LOCK, REPO_ROOT, VerificationError, verify


DEFAULT_STATUS = MODULE_DIR / "data" / "source_reproducibility.status.json"


def _load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise VerificationError(f"status root must be an object: {path}")
    return value


def check_release_readiness(
    *,
    status_path: Path = DEFAULT_STATUS,
    lock_path: Path = DEFAULT_LOCK,
    repo_root: Path = REPO_ROOT,
    require_release: bool = False,
) -> dict[str, Any]:
    locked = verify(lock_path.resolve(), repo_root.resolve())
    status = _load(status_path.resolve())
    target = locked["target"]
    recorded_target = status.get("target")
    if not isinstance(recorded_target, dict):
        raise VerificationError("source reproducibility status has no target")
    for field in (
        "entry_count",
        "distinct_texts",
        "source_dictionary_sha256",
        "source_selection_sha256",
    ):
        if recorded_target.get(field) != target.get(field):
            raise VerificationError(
                f"source reproducibility target {field} does not match the lock"
            )
    decision = str(status.get("decision") or "")
    if decision not in {"pass", "blocked"}:
        raise VerificationError(f"invalid source reproducibility decision: {decision}")
    if decision == "pass":
        rebuilds = status.get("clean_rebuilds")
        if not isinstance(rebuilds, list) or len(rebuilds) < 2:
            raise VerificationError(
                "source reproducibility pass requires at least two clean rebuild records"
            )
        for index, rebuild in enumerate(rebuilds):
            if not isinstance(rebuild, dict):
                raise VerificationError(f"clean rebuild record {index} is invalid")
            for field in (
                "entry_count",
                "distinct_texts",
                "source_dictionary_sha256",
                "source_selection_sha256",
            ):
                if rebuild.get(field) != target.get(field):
                    raise VerificationError(
                        f"clean rebuild {index} {field} does not match the target"
                    )
        safeguards = status.get("safeguards")
        if not isinstance(safeguards, dict) or not safeguards.get(
            "tagged_release_allowed"
        ):
            raise VerificationError(
                "source reproducibility pass does not authorize tagged release"
            )
    report = {
        "decision": decision,
        "release_allowed": decision == "pass",
        "lock_id": locked["lock_id"],
        "target": target,
        "latest_clean_rebuild": status.get("latest_clean_rebuild"),
        "blocking_reason": status.get("blocking_reason", ""),
        "required_resolution": status.get("required_resolution", ""),
        "safeguards": status.get("safeguards", {}),
    }
    if require_release and decision != "pass":
        latest = status.get("latest_clean_rebuild") or {}
        raise VerificationError(
            "tagged release blocked: source-level reproducibility is not complete; "
            f"clean entries={latest.get('entry_count')}, "
            f"target entries={target.get('entry_count')}; "
            f"reason={status.get('blocking_reason')}"
        )
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--status", type=Path, default=DEFAULT_STATUS)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--require-release", action="store_true")
    args = parser.parse_args()
    try:
        report = check_release_readiness(
            status_path=args.status,
            lock_path=args.lock,
            repo_root=args.repo_root,
            require_release=args.require_release,
        )
    except (OSError, json.JSONDecodeError, VerificationError) as exc:
        print(f"FAIL release readiness: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
