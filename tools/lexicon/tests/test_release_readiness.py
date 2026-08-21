from __future__ import annotations

import unittest

from tools.lexicon.verify_release_readiness import VerificationError, check_release_readiness


class ReleaseReadinessTests(unittest.TestCase):
    def test_current_source_reproducibility_is_release_ready(self) -> None:
        report = check_release_readiness()
        self.assertEqual(report["decision"], "pass")
        self.assertTrue(report["release_allowed"])
        self.assertEqual(report["latest_clean_rebuild"]["entry_count"], 1166753)

    def test_tagged_release_gate_accepts_reproduced_source_identity(self) -> None:
        report = check_release_readiness(require_release=True)
        self.assertTrue(report["release_allowed"])


if __name__ == "__main__":
    unittest.main()
