#!/usr/bin/env python3
"""Verify the detached external-input archive identity and restore policy."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from yime.lexicon_bundle.external_archive import (
    DEFAULT_ARCHIVE_LOCK,
    verify_external_archive_lock,
)
from yime.lexicon_bundle.external_inputs import DEFAULT_LOCK, ExternalInputError


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-lock", type=Path, default=DEFAULT_ARCHIVE_LOCK)
    parser.add_argument("--input-lock", type=Path, default=DEFAULT_LOCK)
    args = parser.parse_args()
    try:
        lock = verify_external_archive_lock(
            args.archive_lock.resolve(), args.input_lock.resolve()
        )
        policy = lock.get("restore_policy")
        if not isinstance(policy, dict) or policy.get("maximum_evidence_age_days") != 90:
            raise ExternalInputError("external archive restore policy must require 90-day evidence")
    except (OSError, ValueError, json.JSONDecodeError, ExternalInputError) as exc:
        print(f"FAIL external archive lock: {exc}", file=sys.stderr)
        return 1
    print(
        json.dumps(
            {
                "decision": "pass",
                "archive_id": lock["archive_id"],
                "bundle": lock["bundle"],
                "restore_policy": policy,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
