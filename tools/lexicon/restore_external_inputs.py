#!/usr/bin/env python3
"""Run a fail-closed restore drill for content-locked external lexicon inputs."""

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
    run_external_input_restore_drill,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-root", type=Path, required=True)
    parser.add_argument("--restore-root", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--repository-import-approval", type=Path)
    args = parser.parse_args()
    evidence_path = args.evidence.resolve()
    try:
        evidence = run_external_input_restore_drill(
            archive_root=args.archive_root,
            restore_root=args.restore_root,
            evidence_path=evidence_path,
            lock_path=args.lock,
            repository_import_approval=args.repository_import_approval,
        )
    except (OSError, ValueError, json.JSONDecodeError, ExternalInputError) as exc:
        print(f"FAIL external input restore drill: {exc}", file=sys.stderr)
        if evidence_path.is_file():
            print(f"Failure evidence: {evidence_path}", file=sys.stderr)
        return 1
    print(json.dumps(evidence, ensure_ascii=False, indent=2))
    print(f"Restore evidence: {evidence_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
