"""Regression coverage for NSIS drift between both packaging lanes and the lock."""

from __future__ import annotations

import unittest

from tools import verify_toolchain_lock as lockcheck


JOBS = ("unsigned-installer-package", "release-installer-package")


def workflow_with_pins(unsigned: str = "3.12", release: str = "3.12") -> str:
    return "jobs:\n" + "".join(
        f"  {job}:\n"
        "    runs-on: windows-2022\n"
        "    steps:\n"
        "      - name: Install NSIS\n"
        "        uses: repolevedavaj/install-nsis@pinned-test-revision\n"
        "        with:\n"
        f"          nsis-version: {version}\n"
        for job, version in zip(JOBS, (unsigned, release))
    )


class ToolchainLockTests(unittest.TestCase):
    def test_repository_matches_locked_nsis(self) -> None:
        self.assertEqual(lockcheck.verify()["decision"], "pass")

    def test_both_lanes_accept_explicit_quoted_or_unquoted_versions(self) -> None:
        for value in ("3.12", "'3.12'", '"3.12"', "3.12 # compiler pin"):
            with self.subTest(value=value):
                lockcheck.verify_ci_nsis_pin(workflow_with_pins(value, value), "3.12")

    def test_either_lane_drifting_fails_even_if_other_pin_matches(self) -> None:
        for pins in (("3.08", "3.12"), ("3.12", "3.08")):
            with self.subTest(pins=pins):
                with self.assertRaises(lockcheck.VerificationError):
                    lockcheck.verify_ci_nsis_pin(workflow_with_pins(*pins), "3.12")

    def test_expected_version_comes_from_lock_not_another_hardcoded_copy(self) -> None:
        lockcheck.verify_ci_nsis_pin(workflow_with_pins("3.99", "3.99"), "3.99")
        with self.assertRaises(lockcheck.VerificationError):
            lockcheck.verify_ci_nsis_pin(workflow_with_pins(), "3.99")

    def test_missing_or_duplicate_job_fails(self) -> None:
        workflow = workflow_with_pins()
        for changed in (
            workflow.replace("  release-installer-package:", "  unrelated-job:"),
            workflow + workflow,
        ):
            with self.subTest(changed=changed):
                with self.assertRaises(lockcheck.VerificationError):
                    lockcheck.verify_ci_nsis_pin(changed, "3.12")

    def test_missing_duplicate_comment_or_dynamic_input_fails(self) -> None:
        workflow = workflow_with_pins()
        pin = "          nsis-version: 3.12\n"
        for replacement in (
            "",
            pin + pin,
            "          # nsis-version: 3.12\n",
            "          nsis-version: ${{ inputs.nsis }}\n",
            "          nsis-version: 3.120\n",
        ):
            with self.subTest(replacement=replacement):
                with self.assertRaises(lockcheck.VerificationError):
                    lockcheck.verify_ci_nsis_pin(workflow.replace(pin, replacement, 1), "3.12")

    def test_comment_or_run_text_is_not_an_install_step(self) -> None:
        workflow = workflow_with_pins()
        for replacement in ("        # uses:", "        run:"):
            with self.subTest(replacement=replacement):
                with self.assertRaises(lockcheck.VerificationError):
                    lockcheck.verify_ci_nsis_pin(workflow.replace("        uses:", replacement, 1), "3.12")

    def test_duplicate_install_step_or_missing_with_fails(self) -> None:
        workflow = workflow_with_pins()
        first_step = workflow.split("    steps:\n", 1)[1].split("  release-installer-package:", 1)[0]
        for changed in (
            workflow.replace(first_step, first_step + first_step, 1),
            workflow.replace("        with:\n", "", 1),
        ):
            with self.subTest(changed=changed):
                with self.assertRaises(lockcheck.VerificationError):
                    lockcheck.verify_ci_nsis_pin(changed, "3.12")


if __name__ == "__main__":
    unittest.main()
