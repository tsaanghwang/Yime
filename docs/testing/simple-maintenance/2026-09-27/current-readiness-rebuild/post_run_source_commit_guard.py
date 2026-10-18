"""Post-run exact source-commit guard added after the original delivery."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


EXPECTED_SOURCE_COMMIT = "0ab8631266736775bf1386f456d4a1d53e8e2eb3"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=Path)
    args = parser.parse_args()
    commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=args.repo_root, text=True
    ).strip()
    if commit != EXPECTED_SOURCE_COMMIT:
        raise SystemExit(
            f"Unexpected source {commit}; expected {EXPECTED_SOURCE_COMMIT}"
        )
    print(f"Verified exact source commit {commit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
