#!/usr/bin/env python3
"""Create a deterministic, content-locked ZIP of external lexicon inputs."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from yime.lexicon_bundle.external_archive import create_external_input_bundle
from yime.lexicon_bundle.external_inputs import DEFAULT_LOCK, ExternalInputError


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    args = parser.parse_args()
    try:
        report = create_external_input_bundle(
            source_root=args.source_root,
            bundle_path=args.bundle,
            input_lock_path=args.lock,
        )
    except (OSError, ValueError, json.JSONDecodeError, ExternalInputError) as exc:
        print(f"FAIL external input archive packaging: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
