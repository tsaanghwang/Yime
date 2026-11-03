"""Offline failure injection for the proposed protected native entry."""

from dataclasses import replace
import unittest

from arm64_maintenance_model import Evidence, decision


class TrustBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.valid = Evidence(**{name: True for name in Evidence.__dataclass_fields__})

    def test_all_independent_evidence_required(self):
        self.assertEqual(decision(self.valid), (True, "trusted_preconditions_complete"))
        for name in Evidence.__dataclass_fields__:
            with self.subTest(missing=name):
                self.assertEqual(decision(replace(self.valid, **{name: False})), (False, name))

    def test_package_self_hash_cannot_replace_external_authentication(self):
        # All other observations may be true, including matching payload bytes.
        # A manifest supplied by the candidate package is not a trust root.
        candidate = replace(self.valid, package_source_authenticated=False)
        self.assertFalse(decision(candidate)[0])

    def test_preprovisioned_launcher_needs_independent_approval(self):
        for name in ("launcher_in_admin_protected_location",
                     "launcher_hash_independently_approved",
                     "approval_record_admin_protected"):
            with self.subTest(fault=name):
                self.assertEqual(decision(replace(self.valid, **{name: False})), (False, name))

    def test_shell_does_not_authenticate_elevated_script(self):
        candidate = replace(self.valid, staged_script_and_module_verified=False)
        self.assertEqual(decision(candidate), (False, "staged_script_and_module_verified"))

    def test_missing_shell_and_wrong_identity_fail_before_mutation(self):
        for name in ("official_system_shell", "shell_native_process", "same_user_sid",
                     "elevated_administrator", "registration_tool_arm64"):
            with self.subTest(fault=name):
                self.assertFalse(decision(replace(self.valid, **{name: False}))[0])


if __name__ == "__main__":
    unittest.main()
