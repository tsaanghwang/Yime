#!/usr/bin/env python3
"""Verify or download the content-locked external lexicon archive."""

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
    materialize_external_archive,
)
from yime.lexicon_bundle.external_inputs import DEFAULT_LOCK, ExternalInputError


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-root", type=Path)
    parser.add_argument("--archive-url")
    parser.add_argument("--archive-lock", type=Path, default=DEFAULT_ARCHIVE_LOCK)
    parser.add_argument("--input-lock", type=Path, default=DEFAULT_LOCK)
    args = parser.parse_args()
    try:
        report = materialize_external_archive(
            archive_root=args.archive_root,
            archive_url=args.archive_url,
            archive_lock_path=args.archive_lock,
            input_lock_path=args.input_lock,
        )
    except (OSError, ValueError, json.JSONDecodeError, ExternalInputError) as exc:
        print(f"FAIL external archive materialization: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
