#!/usr/bin/env python3
"""Verify all content-locked large inputs required by the source builder."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from yime.lexicon_bundle.external_inputs import (
    DEFAULT_LOCK,
    ExternalInputError,
    resolve_external_inputs,
    verification_report,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--external-root", type=Path)
    parser.add_argument("--no-legacy-paths", action="store_true")
    args = parser.parse_args()
    try:
        paths = resolve_external_inputs(
            args.lock.resolve(),
            external_root=(args.external_root.resolve() if args.external_root else None),
            allow_legacy_paths=not args.no_legacy_paths,
        )
    except (OSError, ValueError, ExternalInputError) as exc:
        print(f"FAIL external input lock: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(verification_report(paths), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
