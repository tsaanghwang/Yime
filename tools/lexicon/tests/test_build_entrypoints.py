from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]


class BuildEntrypointTests(unittest.TestCase):
    def test_two_level_trial_requires_explicit_runtime_database(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(REPO_ROOT / "tools" / "build_two_level_runtime_trial.py"),
            ],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("--source-runtime-database", result.stderr)
        self.assertIn("required", result.stderr)

    def test_release_acceptance_requires_external_restore_evidence(self) -> None:
        script = (REPO_ROOT / "tools" / "lexicon" / "run-release-acceptance.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn("[Parameter(Mandatory = $true)]", script)
        self.assertIn("[string]$ExternalRestoreEvidence", script)
        self.assertIn("--external-restore-evidence $resolvedRestoreEvidence", script)


if __name__ == "__main__":
    unittest.main()
