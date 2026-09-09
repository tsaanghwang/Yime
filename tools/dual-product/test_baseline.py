"""Pure memory ownership fixtures and source-reader negative contracts."""
import copy
import sys
import stat
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).absolute().parent))
import baseline as subject


class OwnershipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.receipt = subject.source_baseline()
        cls.products = cls.receipt["products"]

    def model(self, installed=()):
        return subject.FixtureOwnership(self.products, installed)

    def test_single_rime_product_without_core(self):
        model = self.model(("rime-pime",))
        self.assertTrue(model.can_start("rime-pime"))
        self.assertFalse(model.can_start("yimecore"))
        root = model.roots("rime-pime")[1]
        model.apply("rime-pime", [{"kind": "file", "target": root + "\\fixture.json"}])
        self.assertEqual(set(model.resources.values()), {"rime-pime"})

    def test_single_core_product_without_rime(self):
        model = self.model(("yimecore",))
        self.assertTrue(model.can_start("yimecore"))
        self.assertFalse(model.can_start("rime-pime"))
        root = model.roots("yimecore")[1]
        model.apply("yimecore", [{"kind": "file", "target": root + "\\fixture.json"}])
        self.assertEqual(set(model.resources.values()), {"yimecore"})

    def test_both_install_orders_only_simulated(self):
        for order in (("rime-pime", "yimecore"), ("yimecore", "rime-pime")):
            with self.subTest(order=order):
                model = self.model(order)
                for owner in order:
                    self.assertTrue(model.can_start(owner))
                    model.apply(owner, [{"kind": "file", "target": model.roots(owner)[0] + "\\fixture.bin"}])
                self.assertEqual(set(model.resources.values()), set(order))

    def test_rejected_batch_does_not_partially_write(self):
        for owner, other in (("rime-pime", "yimecore"), ("yimecore", "rime-pime")):
            with self.subTest(owner=owner):
                model = self.model((owner, other))
                before = copy.deepcopy(model.resources)
                with self.assertRaises(ValueError):
                    model.apply(owner, [
                        {"kind": "file", "target": model.roots(owner)[1] + "\\settings.json"},
                        {"kind": "file", "target": model.roots(other)[1] + "\\settings.json"},
                    ])
                self.assertEqual(before, model.resources)

    def test_cross_product_files_rejected(self):
        model = self.model()
        for owner, other in (("rime-pime", "yimecore"), ("yimecore", "rime-pime")):
            for root in model.roots(other):
                with self.subTest(owner=owner, root=root), self.assertRaises(ValueError):
                    model.authorize(owner, "file", root + "\\fixture.json")

    def test_owned_paths_and_case_insensitivity(self):
        model = self.model()
        for owner in self.products:
            for root in model.roots(owner):
                self.assertTrue(model.authorize(owner, "file", (root + "\\fixture.json").upper()))

    def test_ambiguous_or_broad_paths_rejected(self):
        model = self.model()
        root = model.roots("yimecore")[1]
        for target in (root, root + "2\\evil", root + "\\..\\evil", root + "\\file:ads", root + "\\file.",
                       root + "\\file ", root + "\\.\\evil", root + "\\\\evil", r"\\?\C:\DP1-Fixture\evil",
                       r"C:relative", root.replace("\\", "/") + "/file", "PIMELauncher.exe", root + "\\NUL", root + "\\COM1.txt", root + "\\*"):
            with self.subTest(target=target), self.assertRaises(ValueError):
                model.authorize("yimecore", "file", target)

    def test_indirect_path_marker_fails_closed(self):
        model = self.model()
        with self.assertRaises(ValueError):
            model.authorize("yimecore", "file", model.roots("yimecore")[1] + "\\file", indirect=True)
        # This is an abstract fixture flag; it does not claim an OS symlink was made.

    def test_process_owner_uses_exact_image_and_sid(self):
        model = self.model()
        for owner, other in (("rime-pime", "yimecore"), ("yimecore", "rime-pime")):
            own = model.roots(owner)[0] + "\\" + self.products[owner]["process_paths"][0]
            foreign = model.roots(other)[0] + "\\" + self.products[other]["process_paths"][0]
            self.assertTrue(model.authorize(owner, "stop_process", own))
            for target, sid in ((foreign, subject.FIXTURE_SID), (own, "S-1-5-18"), (own + ".old", subject.FIXTURE_SID)):
                with self.subTest(owner=owner, target=target), self.assertRaises(ValueError):
                    model.authorize(owner, "stop_process", target, sid=sid)

    def test_endpoints_are_not_fallbacks(self):
        model = self.model()
        for owner, other in (("rime-pime", "yimecore"), ("yimecore", "rime-pime")):
            self.assertTrue(model.authorize(owner, "endpoint", self.products[owner]["endpoint"]))
            with self.assertRaises(ValueError):
                model.authorize(owner, "endpoint", self.products[other]["endpoint"])

    def test_registration_owned_exact_trees_both_views(self):
        model = self.model()
        for owner, other in (("rime-pime", "yimecore"), ("yimecore", "rime-pime")):
            own = "HKLM\\Software\\Classes\\CLSID\\" + self.products[owner]["clsid"]
            foreign = "HKLM\\Software\\Classes\\CLSID\\" + self.products[other]["clsid"]
            for view in ("32", "64"):
                self.assertTrue(model.authorize(owner, "registry", own + "\\InprocServer32", view=view))
                for target in (foreign, "HKLM\\Software\\Classes\\CLSID", own + "2", own + "\\..\\evil"):
                    with self.subTest(owner=owner, view=view, target=target), self.assertRaises(ValueError):
                        model.authorize(owner, "registry", target, view=view)

    def test_run_value_not_entire_parent(self):
        model = self.model()
        for owner in self.products:
            item = self.products[owner]
            hive = "HKLM" if owner == "rime-pime" else "HKU\\" + subject.FIXTURE_SID
            run = hive + "\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
            self.assertTrue(model.authorize(owner, "registry", run, value_name=item["run_name"]))
            for name in (None, "", "OtherProduct"):
                with self.subTest(owner=owner, name=name), self.assertRaises(ValueError):
                    model.authorize(owner, "registry", run, value_name=name)

    def test_uninstall_ownership(self):
        model = self.model()
        for owner, other in (("rime-pime", "yimecore"), ("yimecore", "rime-pime")):
            own_hive = "HKLM" if owner == "rime-pime" else "HKU\\" + subject.FIXTURE_SID
            other_hive = "HKLM" if other == "rime-pime" else "HKU\\" + subject.FIXTURE_SID
            self.assertTrue(model.authorize(owner, "registry", own_hive + "\\" + self.products[owner]["uninstall_key"]))
            with self.assertRaises(ValueError):
                model.authorize(owner, "registry", other_hive + "\\" + self.products[other]["uninstall_key"])

    def test_unknown_target_and_unapproved_purge_rejected(self):
        model = self.model()
        for operation in ("purge_user_data", "default_input_method", "install_other", "unknown"):
            with self.subTest(operation=operation), self.assertRaises(ValueError):
                model.authorize("yimecore", operation, "fixture")
        with self.assertRaises(ValueError):
            model.can_start("legacy-yimecore")

    def test_fixture_does_not_promote_installer_or_physical_evidence(self):
        self.assertEqual(self.receipt["test_level"], subject.EXPECTED_TEST_LEVEL)
        self.assertTrue(self.receipt["test_level"].endswith("not-installed-or-live"))
        self.assertFalse(self.receipt["dp1_full_implementation_passed"])
        self.assertFalse(self.receipt["dp2_physical_acceptance_passed"])
        self.assertFalse(self.receipt["installed_runtime_examined"])
        self.assertFalse(self.receipt["user_text_or_learning_read"])

    def test_current_source_manifest_and_declared_source_set_are_exact(self):
        contract = subject.json.loads(subject.CONTRACT.read_text(encoding="utf-8-sig"))
        self.assertEqual(len(contract["source_paths"]), 220)
        self.assertEqual(len(self.receipt["source_manifest"]), 227)
        for path in (
            "version.txt",
            "PIMELauncher/build.rs",
            "PIMETextService/PIMETextService.rc.in",
            "tools/dual-product/rime-pime-nsis-toolchain-closure.ps1",
            "tools/dual-product/rime-pime-nsis-toolchain-closure.psm1",
            "tools/dual-product/test-rime-pime-nsis-toolchain-closure.ps1",
            "tools/dual-product/rime-pime-nsis-compiler-interval.ps1",
            "tools/dual-product/test-rime-pime-nsis-compiler-interval.ps1",
            "tools/dual-product/rime-pime-package-receipt-v2.ps1",
            "tools/dual-product/rime-pime-package-receipt-v2.psm1",
            "tools/dual-product/finalize-rime-pime-package-receipt-v2.ps1",
            "tools/dual-product/test-rime-pime-package-receipt-v2.ps1",
            "tools/dual-product/test-rime-pime-receipt-no-downgrade.ps1",
            "tools/dual-product/rime-pime-installer-receipt-transaction.ps1",
            "tools/dual-product/rime-pime-installer-receipt-transaction.psm1",
            "tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1",
            "tools/dual-product/run-rime-pime-isolated-candidate.ps1",
            "tools/dual-product/test-rime-pime-isolated-candidate.ps1",
            "tools/dual-product/rime-pime-version-identity-admission.psm1",
            "tools/dual-product/test-rime-pime-version-identity-admission.ps1",
            "tools/dual-product/rime-pime-candidate-evidence-archive.ps1",
            "tools/dual-product/rime-pime-candidate-evidence-archive.psm1",
            "tools/dual-product/test-rime-pime-candidate-evidence-archive.ps1",
            "tools/dual-product/rime-pime-actual-migration-review.psm1",
            "tools/dual-product/test-rime-pime-actual-migration-review.ps1",
            "tools/dual-product/rime-pime-dp1r-trust-admission.psm1",
            "tools/dual-product/test-rime-pime-dp1r-trust-admission.ps1",
            "tools/dual-product/review-rime-pime-dp1r-trust.ps1",
            "tools/dual-product/publish-rime-pime-dp1s-off-repository-archive.ps1",
            "tools/dual-product/test-rime-pime-dp1s-off-repository-archive.ps1",
            "tools/dual-product/invoke-rime-pime-actual-canonical-migration.ps1",
            "tools/dual-product/test-rime-pime-actual-canonical-migration.ps1",
            "tools/dual-product/rime-pime-dp1u-isolated-preflight.psm1",
            "tools/dual-product/rime-pime-dp1u-isolated-preflight.schema.json",
            "tools/dual-product/fixtures/dp1u-isolated-preflight.synthetic.json",
            "tools/dual-product/test-rime-pime-dp1u-isolated-preflight.ps1",
            "tools/dual-product/rime-pime-dp1u-native-facts.cs",
            "tools/dual-product/rime-pime-dp1u-native-probe.psm1",
            "tools/dual-product/test-rime-pime-dp1u-native-probe.ps1",
            "tools/dual-product/test-rime-pime-dp1u-native-candidate.ps1",
            "tools/dual-product/rime-pime-dp1u-exact-file-removal.cs",
            "tools/dual-product/rime-pime-dp1u-exact-file-removal.psm1",
            "tools/dual-product/test-rime-pime-dp1u-exact-file-removal.ps1",
            "tools/yimecore/test-native-desktop-rehearsal.ps1",
            "tools/yimecore/test-local-product-build-result.ps1",
            "tools/yimecore/local12-maintenance-preparation.psm1",
            "tools/yimecore/prepare-local13-maintenance.ps1",
            "tools/yimecore/test-local13-maintenance-preparation.ps1",
            "tools/yimecore/native-maintenance-context.psm1",
            "tools/yimecore/native-maintenance-evidence.psm1",
            "tools/yimecore/capture-native-maintenance-registry.ps1",
            "tools/yimecore/test-native-maintenance-context.ps1",
            "tools/yimecore/test-native-maintenance-evidence.ps1",
            "tools/yimecore/local13-maintenance-inputs.psm1",
            "tools/yimecore/test-local13-maintenance-inputs.ps1",
            "tools/yimecore/native-maintenance-processes.psm1",
            "tools/yimecore/native-maintenance-process-facts.cs",
            "tools/yimecore/test-native-maintenance-processes.ps1",
            "tools/yimecore/test-native-rehearsal-outcome.ps1",
            "tools/yimecore/native-rehearsal-outcome-reader.psm1",
            "tools/yimecore/test-native-rehearsal-outcome-reader.ps1",
            "tools/yimecore/native-maintenance-child.psm1",
            "tools/yimecore/test-native-maintenance-child.ps1",
            "tools/yimecore/native-maintenance-data.psm1",
            "tools/yimecore/test-native-maintenance-data.ps1",
            "tools/yimecore/native-maintenance-backup.psm1",
            "tools/yimecore/test-native-maintenance-backup.ps1",
            "tools/yimecore/native-rollback-collection.psm1",
            "tools/yimecore/invoke-native-rollback-collection.ps1",
            "tools/yimecore/test-native-rollback-collection.ps1",
            "tools/yimecore/native-maintenance-deferred-delete.psm1",
            "tools/yimecore/test-native-maintenance-deferred-delete.ps1",
            "tools/yimecore/native-maintenance-visibility.psm1",
            "tools/yimecore/test-native-maintenance-visibility.ps1",
            "tools/yimecore/native-maintenance-runtime.psm1",
            "tools/yimecore/test-native-maintenance-runtime.ps1",
            "tools/yimecore/native-maintenance-health.psm1",
            "tools/yimecore/native-maintenance-health-client.cs",
            "tools/yimecore/test-native-maintenance-health.ps1",
            "tools/yimecore/restore-local-trial-state.ps1",
            "tools/yimecore/test-local-restore-evidence.ps1",
            "tools/yimecore/model-recovery-probe.go",
            "go-backend/input_methods/yime/yimebroker/usermodel_store.go",
            "tools/yimecore/test-native-health-interop.ps1",
            "tools/yimecore/test-local-product-health.ps1",
            "go-backend/cmd/yimebroker/main.go",
            "go-backend/cmd/yimebroker/health.go",
            "go-backend/cmd/yimebroker/health_test.go",
            "go-backend/cmd/yimebroker/health_windows_test.go",
            "go-backend/cmd/yimecore-trial-runtime/main_test.go",
            "go-backend/cmd/yimecore-trial-runtime/runtime_stub.go",
            "go-backend/cmd/yimecore-trial-runtime/runtime_windows.go",
            "go-backend/cmd/yimecore-trial-runtime/runtime_windows_test.go",
            "go-backend/cmd/yimecore-trial-runtime/health.go",
            "go-backend/cmd/yimecore-trial-runtime/health_test.go",
            "go-backend/input_methods/yime/yimebroker/named_pipe_stub.go",
            "go-backend/input_methods/yime/yimebroker/named_pipe_windows.go",
            "go-backend/input_methods/yime/yimebroker/health.go",
            "go-backend/input_methods/yime/yimebroker/health_stub.go",
            "go-backend/input_methods/yime/yimebroker/health_test.go",
            "go-backend/input_methods/yime/yimebroker/health_windows.go",
            "go-backend/input_methods/yime/yimebroker/health_windows_test.go",
            "tools/dual-product/test-rime-pime-transaction-replay-model.ps1",
            "tools/dual-product/rime-pime-fixture-transaction-journal.ps1",
            "tools/dual-product/rime-pime-fixture-transaction-journal.psm1",
            "tools/dual-product/test-rime-pime-fixture-transaction-journal.ps1",
            "tools/dual-product/rime-pime-nsis-membership-monitor-v1.ps1",
            "tools/dual-product/rime-pime-nsis-membership-monitor-v1.psm1",
            "tools/dual-product/invoke-rime-pime-nsis-membership-fixture-writer-v1.ps1",
            "tools/dual-product/test-rime-pime-nsis-membership-monitor-v1.ps1",
            "tools/dual-product/rime-pime-receipt-v2-supersession.ps1",
            "tools/dual-product/rime-pime-receipt-v2-supersession.psm1",
            "tools/dual-product/test-rime-pime-receipt-v2-supersession.ps1",
            "tools/dual-product/rime-pime-receipt-v2-store.ps1",
            "tools/dual-product/test-rime-pime-receipt-v2-store.ps1",
        ):
            with self.subTest(path=path):
                self.assertIn(path, contract["source_paths"])

    def test_rime_product_version_identity_is_reviewed_and_derived(self):
        contract = subject.json.loads(subject.CONTRACT.read_text(encoding="utf-8-sig"))
        product = self.products["rime-pime"]
        self.assertEqual(product["product_version"], contract["rime_pime_source_product_version"])
        self.assertEqual(product["installer_leaf"], "YIME-" + product["product_version"] + "-setup.exe")
        core = product["product_version"].split("-", 1)[0]
        self.assertEqual(product["numeric_file_version"], core + ".0")

    def test_rime_product_version_grammar_matches_windows_and_semver_contract(self):
        for version, expected_numeric in (
                ("1.4.0-dev", "1.4.0.0"),
                ("1.4.0-dev.1", "1.4.0.0"),
                ("1.4.0", "1.4.0.0"),
                ("65535.0.7-rc.1", "65535.0.7.0")):
            with self.subTest(version=version):
                _, numeric = subject.parse_rime_pime_product_version(version)
                self.assertEqual(numeric, expected_numeric)
        for version in (
                None, "", "1.4", "01.4.0-dev", "1.04.0-dev", "1.4.00-dev",
                "1.4.0+build.7", "1.4.0_dev", "1.4.0-dev.01", "65536.0.0-dev"):
            with self.subTest(version=version), self.assertRaisesRegex(
                    ValueError, "not a supported semantic Windows version"):
                subject.parse_rime_pime_product_version(version)

    def test_contract_evidence_level_drift_fails_closed(self):
        real_loads = subject.json.loads

        def load_with_drift(payload, *args, **kwargs):
            parsed = real_loads(payload, *args, **kwargs)
            if isinstance(parsed, dict) and parsed.get("schema_version") == "yime-dual-product-source-contract-v1":
                parsed["test_level"] = "source-and-pure-memory-fixtures-only"
            return parsed

        with mock.patch.object(subject.json, "loads", side_effect=load_with_drift):
            with self.assertRaisesRegex(ValueError, "evidence test level changed"):
                subject.source_baseline()

    def test_reviewed_rime_product_version_drift_fails_closed(self):
        real_loads = subject.json.loads

        def load_with_drift(payload, *args, **kwargs):
            parsed = real_loads(payload, *args, **kwargs)
            if isinstance(parsed, dict) and parsed.get("schema_version") == "yime-dual-product-source-contract-v1":
                parsed["rime_pime_source_product_version"] = "9.9.9-dev"
            return parsed

        with mock.patch.object(subject.json, "loads", side_effect=load_with_drift):
            with self.assertRaisesRegex(ValueError, "reviewed source product identity"):
                subject.source_baseline()

    def test_source_reader_paths_cannot_escape_checkout(self):
        for relative in ("../secret", "/absolute", "C:/secret", "a\\b", "a/./b", "a/../b", "a//b", "a/file:ads"):
            with self.subTest(relative=relative), self.assertRaises(ValueError):
                subject.child(subject.ROOT, relative)

    def test_source_reader_requires_unique_anchor(self):
        for source in ("no anchor", "id=one\nid=two"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                subject.one(r"^id=(.+)$", source, "fixture")

    def test_source_reader_reparse_metadata_rejected(self):
        for metadata in (SimpleNamespace(st_mode=stat.S_IFDIR, st_file_attributes=0x400),
                         SimpleNamespace(st_mode=stat.S_IFLNK, st_file_attributes=0)):
            with self.subTest(metadata=metadata), mock.patch.object(Path, "lstat", return_value=metadata):
                with self.assertRaisesRegex(ValueError, "indirect path"):
                    subject.plain(subject.ROOT / "fixture")

    def test_source_hash_mismatch_fails_closed(self):
        with mock.patch.object(subject, "digest", return_value="0" * 64):
            with self.assertRaisesRegex(ValueError, "locked build input hash mismatch"):
                subject.source_baseline()

    def maintenance_sources(self):
        contract = subject.json.loads(subject.CONTRACT.read_text(encoding="utf-8-sig"))
        return {path: subject.child(subject.ROOT, path).read_text(encoding="utf-8-sig").replace("\r\n", "\n")
                for path in contract["source_paths"]}

    def test_actual_uninstall_guard_cannot_disappear_behind_call_site(self):
        for anchor in ("Assert-YimePimeOwnedRoot -Root $Path -AllowAbsent", "Assert-YimePimeOwnedRoot -Root $Path).path"):
            sources = self.maintenance_sources()
            sources["tools/dev-uninstall.ps1"] = sources["tools/dev-uninstall.ps1"].replace(anchor, "removed_guard", 1)
            with self.subTest(anchor=anchor), self.assertRaisesRegex(ValueError, "guard missing"):
                subject.maintenance_source_status(sources)

    def test_missing_required_stop_helper_guard_rejected(self):
        sources = self.maintenance_sources()
        sources["tools/dual-product/rime-pime-ownership.ps1"] = sources["tools/dual-product/rime-pime-ownership.ps1"].replace(
            "if(-not (Test-Path -LiteralPath $script -PathType Leaf)){throw", "if($false){throw")
        with self.assertRaisesRegex(ValueError, "guard missing"):
            subject.maintenance_source_status(sources)

    def test_global_stop_reintroduced_is_rejected(self):
        sources = self.maintenance_sources()
        sources["installer/installer.nsi"] += '\nnsExec::Exec "taskkill.exe /F /IM PIMELauncher.exe"\n'
        with self.assertRaisesRegex(ValueError, "unsafe Rime"):
            subject.maintenance_source_status(sources)

    def test_directed_shutdown_source_does_not_promote_live_acceptance(self):
        self.assertFalse(self.receipt["maintenance_source"]["quiescent_admission_only"])
        self.assertTrue(self.receipt["maintenance_source"]["directed_graceful_shutdown_source_anchors_present"])
        self.assertTrue(self.receipt["maintenance_source"]["directed_graceful_shutdown_synthetic_contract_source_anchors_present"])
        self.assertFalse(self.receipt["maintenance_source"]["automatic_force_stop_source_present"])
        self.assertFalse(self.receipt["maintenance_source"]["installed_live_directed_shutdown_examined"])
        self.assertNotIn("directed_graceful_shutdown_synthetic_contract_passed", self.receipt["maintenance_source"])
        self.assertIn("DP1-PIME-DIRECTED-EXIT-04", {item["id"] for item in self.receipt["known_pending"]})
        self.assertNotIn("DP1-PIME-LEGACY-03", {item["id"] for item in self.receipt["known_pending"]})

    def test_transaction_contract_is_executable_but_not_installer_wiring(self):
        status = self.receipt["transaction_source"]
        self.assertTrue(status["synthetic_contract_source_anchors_present"])
        self.assertFalse(status["rime_pime_full_transaction_engine_wired_into_installer"])
        self.assertTrue(status["yimecore_same_sid_source_anchors_present"])
        self.assertTrue(status["yimecore_rollback_restore_source_anchors_present"])
        self.assertTrue(status["yimecore_desktop_rehearsal_guard_source_anchors_present"])
        self.assertTrue(status["yimecore_desktop_rehearsal_ci_ps5_ps7_present"])
        self.assertFalse(status["yimecore_desktop_rehearsal_actual_acceptance_passed"])
        self.assertNotIn("synthetic_contract_implemented", status)
        self.assertNotIn("synthetic_contract_wired_into_installers", status)
        self.assertEqual(
            {"DP1-PIME-REGISTRY-05", "DP1-PIME-TRANSACTION-06"},
            {item["id"] for item in self.receipt["known_pending"]} &
            {"DP1-PIME-REGISTRY-05", "DP1-PIME-TRANSACTION-06"},
        )

    def test_dp1i_replay_and_journal_are_source_anchors_only(self):
        status = self.receipt["transaction_source"]
        for field in (
            "rime_pime_transaction_replay_model_source_anchors_present",
            "rime_pime_uninstall_stage_catalog_source_anchors_present",
            "rime_pime_logical_leaf_first_nonrecursive_removal_plan_present",
            "rime_pime_fixture_transaction_journal_source_anchors_present",
            "rime_pime_fixture_transaction_journal_test_source_anchors_present",
            "rime_pime_fixture_journal_hash_chain_source_anchors_present",
            "rime_pime_fixture_journal_sidecar_last_flush_protocol_present",
            "rime_pime_fixture_journal_case_local_recovery_artifacts_bound",
            "rime_pime_fixture_registry_snapshot_closed_typed_privacy_safe",
            "rime_pime_fixture_exact_removal_source_anchors_present",
            "rime_pime_fixture_changed_or_foreign_content_preserved",
            "rime_pime_fixture_journal_ci_ps5_ps7_present",
        ):
            with self.subTest(field=field):
                self.assertTrue(status[field])
        for field in (
            "rime_pime_full_transaction_engine_wired_into_installer",
            "rime_pime_fixture_journal_test_executed_by_baseline",
            "rime_pime_fixture_filesystem_io_executed_by_baseline",
            "rime_pime_product_filesystem_mutation_executed_by_baseline",
            "rime_pime_real_durable_install_transaction_journal",
            "rime_pime_real_power_loss_recovery_passed",
            "rime_pime_cross_process_replay_passed",
            "rime_pime_concurrent_replacement_excluded",
            "rime_pime_real_registry_replay_passed",
            "rime_pime_installed_exact_removal_passed",
            "rime_pime_real_installer_transaction_passed",
            "rime_pime_installed_live_acceptance_passed",
            "rime_pime_delivery_admitted",
        ):
            with self.subTest(field=field):
                self.assertFalse(status[field])
        self.assertNotIn("rime_pime_fixture_journal_test_passed", status)

    def test_dp1i_pure_replay_model_anchor_tamper_fails_closed(self):
        cases = (
            ("tools/dual-product/rime-pime-transaction-engine.ps1",
             "function Get-YimePimeReplayDisposition", "function Get-RemovedReplayDisposition"),
            ("tools/dual-product/test-rime-pime-transaction-replay-model.ps1",
             "actual_filesystem_registry_process_native_installer_or_product_operation_executed=$false",
             "actual_filesystem_registry_process_native_installer_or_product_operation_executed=$true"),
        )
        for path, old, new in cases:
            sources = self.maintenance_sources()
            sources[path] = sources[path].replace(old, new, 1)
            with self.subTest(path=path), self.assertRaisesRegex(
                    ValueError, "source anchor changed|dedicated review required"):
                subject.transaction_source_status(sources)

    def test_dp1i_fixture_journal_anchor_and_boundary_tamper_fails_closed(self):
        cases = (
            ("tools/dual-product/rime-pime-fixture-transaction-journal.ps1",
             "$stream.Flush($true)", "$stream.Flush()"),
            ("tools/dual-product/test-rime-pime-fixture-transaction-journal.ps1",
             "fixture_only=$true", "fixture_only=$false"),
            ("tools/dual-product/test-rime-pime-fixture-transaction-journal.ps1",
             "cross_process_restart_executed=$false", "cross_process_restart_executed=$true"),
        )
        for path, old, new in cases:
            sources = self.maintenance_sources()
            sources[path] = sources[path].replace(old, new, 1)
            with self.subTest(path=path), self.assertRaisesRegex(
                    ValueError, "source anchor changed|dedicated review required"):
                subject.transaction_source_status(sources)

    def test_dp1i_ci_requires_ps5_ps7_fixture_only_commands(self):
        sources = self.maintenance_sources()
        replay_line = "          .\\tools\\dual-product\\test-rime-pime-transaction-replay-model.ps1\n"
        sources[".github/workflows/ci.yaml"] = sources[".github/workflows/ci.yaml"].replace(
            replay_line, "          Start-Process forbidden-product.exe\n" + replay_line, 1
        )
        with self.assertRaisesRegex(ValueError, "dedicated review required"):
            subject.transaction_source_status(sources)

        sources = self.maintenance_sources()
        sources[".github/workflows/ci.yaml"] = sources[".github/workflows/ci.yaml"].replace(
            ".tmp\\dual-product\\dp1-i-journal-ci-ps7-$runId",
            ".tmp\\dual-product\\dp1-i-journal-ci-ps5-$runId",
            1,
        )
        with self.assertRaisesRegex(ValueError, "dedicated review required"):
            subject.transaction_source_status(sources)

    def test_dp1h_toolchain_and_receipt_boundaries_are_not_overpromoted(self):
        status = self.receipt["transaction_source"]
        self.assertTrue(status["rime_pime_builder_safe_module_import_order"])
        self.assertEqual(status["rime_pime_nsis_toolchain_lock_schema"],
                         "yime-rime-pime-postbuild-toolchain-lock-v2")
        self.assertEqual(status["rime_pime_nsis_toolchain_id"],
                         "mycomputer-rime-pime-nsis-static-x86-x64-v2")
        self.assertEqual(status["rime_pime_nsis_toolchain_lock_sha256"],
                         "01e913d82b277ac9219148e9fb26df7851475ce0b70ff5d7b58df51179603c45")
        self.assertEqual(status["rime_pime_nsis_compiler_input_root_count"], 5)
        self.assertEqual(status["rime_pime_nsis_compiler_input_directory_count"], 17)
        self.assertEqual(status["rime_pime_nsis_compiler_input_file_count"], 303)
        self.assertEqual(status["rime_pime_nsis_compiler_required_input_count"], 51)
        self.assertEqual(status["rime_pime_nsis_compiler_input_tree_sha256"],
                         "a908c3b306098217a87a62f0eb4a18c3b2bb5391efde93420bbec1f38ec8d352")
        self.assertTrue(status["rime_pime_nsis_known_input_file_replacement_closure"])
        self.assertTrue(status["rime_pime_nsis_distribution_tree_exact_at_open_and_test"])
        self.assertFalse(status["rime_pime_active_same_sid_transient_tree_membership_interference_excluded"])
        self.assertFalse(status["rime_pime_nsis_non_os_compiler_input_closure"])
        self.assertFalse(status["rime_pime_full_nsis_toolchain_input_closure"])
        self.assertTrue(status["rime_pime_canonical_receipt_v2_source_contract_present"])
        self.assertTrue(status["rime_pime_legacy_build_v2_read_compatibility_wired"])
        self.assertTrue(status["rime_pime_current_membership_interval_build_admission_wired"])
        self.assertEqual(status["rime_pime_current_build_evidence_schema"],
                         "yime-rime-pime-staged-nsis-build-result-membership-interval-v1")
        self.assertTrue(status["rime_pime_canonical_v2_binds_postbuild_source_anchors_present"])
        self.assertFalse(status["rime_pime_canonical_receipt_v2_published_by_baseline"])
        self.assertFalse(status["rime_pime_canonical_receipt_v2_evidence_durable"])
        self.assertFalse(status["rime_pime_actual_canonical_migrated_to_current_build_evidence"])
        self.assertFalse(status["rime_pime_installer_identity_replacement_transaction_wired"])
        self.assertTrue(status["rime_pime_v2_to_v2_supersession_wired"])
        self.assertTrue(status["rime_pime_retained_receipt_ci_ps5_ps7_present"])
        self.assertTrue(status["rime_pime_nsis_compiler_stage_membership_detection_rejection_wired"])
        self.assertTrue(status["rime_pime_nsis_compiler_interval_ci_ps5_ps7_present"])
        self.assertFalse(status["rime_pime_nsis_compiler_interval_test_executed_by_baseline"])
        self.assertFalse(status["rime_pime_static_archive_exact_gate_wired_into_builder"])
        self.assertFalse(status["rime_pime_delivery_admitted"])
        self.assertTrue(status["rime_pime_synthetic_dp1h_ci_contracts_present"])

    def test_dp1n_isolated_installer_receipt_contract_is_wired_without_real_promotion(self):
        status = self.receipt["transaction_source"]
        for field in (
            "rime_pime_installer_receipt_transaction_fixture_source_anchors_present",
            "rime_pime_installer_receipt_transaction_preintent_durable_stage_present",
            "rime_pime_installer_receipt_transaction_unique_copy_checkpoints_present",
            "rime_pime_installer_receipt_transaction_no_replace_present",
            "rime_pime_installer_receipt_transaction_completed_preflight_present",
            "rime_pime_installer_receipt_transaction_physical_leases_present",
            "rime_pime_installer_receipt_transaction_exact_two_api_surface",
            "rime_pime_installer_receipt_transaction_nondurable_historical_v1_coverage_present",
            "rime_pime_installer_receipt_transaction_dynamic_result_and_limitations_present",
            "rime_pime_installer_receipt_transaction_ci_ps5_ps7_present",
            "rime_pime_installer_receipt_transaction_isolated_contract_wired",
        ):
            with self.subTest(field=field):
                self.assertTrue(status[field])
        for field in (
            "rime_pime_installer_receipt_transaction_test_executed_by_baseline",
            "rime_pime_installer_receipt_transaction_actual_canonical_migration_executed",
            "rime_pime_installer_receipt_transaction_full_real_transaction_passed",
            "rime_pime_installer_identity_replacement_transaction_wired",
            "rime_pime_actual_canonical_migrated_to_current_build_evidence",
            "rime_pime_real_installer_transaction_passed",
        ):
            with self.subTest(field=field):
                self.assertFalse(status[field])

    def test_dp1o_isolated_current_candidate_runner_is_wired_without_execution_or_promotion(self):
        status = self.receipt["transaction_source"]
        self.assertTrue(status["rime_pime_isolated_current_candidate_runner_source_contract_wired"])
        self.assertTrue(status["rime_pime_isolated_current_candidate_runner_contract_ci_ps5_ps7_present"])
        self.assertFalse(status["rime_pime_isolated_current_candidate_full_build_executed_by_baseline"])
        self.assertFalse(status["rime_pime_isolated_current_candidate_actual_canonical_migrated"])
        self.assertFalse(status["rime_pime_installer_identity_replacement_transaction_wired"])
        self.assertFalse(status["rime_pime_delivery_admitted"])

    def test_dp1q_pure_actual_migration_review_is_wired_without_promotion(self):
        status = self.receipt["transaction_source"]
        self.assertTrue(status["rime_pime_actual_migration_review_source_contract_wired"])
        self.assertTrue(status["rime_pime_actual_migration_review_ci_ps5_ps7_present"])
        self.assertFalse(status["rime_pime_actual_migration_review_test_executed_by_baseline"])
        self.assertFalse(status["rime_pime_actual_migration_review_ready_from_actual_evidence"])
        self.assertTrue(status["rime_pime_actual_migration_review_separate_execution_gate_required"])
        self.assertFalse(status["rime_pime_actual_evidence_archived_outside_repository_tmp"])

    def test_dp1r_static_trust_admission_is_wired_without_actual_promotion(self):
        status = self.receipt["transaction_source"]
        self.assertTrue(status["rime_pime_dp1r_trust_admission_source_contract_wired"])
        self.assertTrue(status["rime_pime_dp1r_trust_admission_ci_ps5_ps7_present"])
        self.assertFalse(status["rime_pime_dp1r_trust_admission_test_executed_by_baseline"])
        self.assertFalse(status["rime_pime_dp1r_actual_candidate_review_executed_by_baseline"])
        self.assertFalse(status["rime_pime_dp1r_full_payload_static_closure_from_actual_evidence"])
        self.assertFalse(status["rime_pime_dp1r_nsis_non_os_compiler_input_closure_from_actual_evidence"])
        self.assertFalse(status["rime_pime_dp1r_generated_uninstaller_trusted_static_scope_from_actual_evidence"])
        self.assertFalse(status["rime_pime_full_nsis_toolchain_input_closure"])
        self.assertFalse(status["rime_pime_delivery_admitted"])
        self.assertFalse(status["rime_pime_actual_canonical_migration_admitted"])
        self.assertFalse(status["rime_pime_actual_canonical_migration_executed"])

    def test_dp1s_off_repository_archive_is_wired_without_baseline_promotion(self):
        status = self.receipt["transaction_source"]
        self.assertTrue(status["rime_pime_dp1s_off_repository_archive_source_contract_wired"])
        self.assertTrue(status["rime_pime_dp1s_off_repository_archive_ci_ps5_ps7_present"])
        self.assertFalse(status["rime_pime_dp1s_actual_archive_executed_by_baseline"])
        self.assertFalse(status["rime_pime_dp1s_actual_archive_completed_from_tracked_source"])
        self.assertFalse(status["rime_pime_dp1s_directory_metadata_durability_verified"])
        self.assertFalse(status["rime_pime_dp1s_hardware_power_loss_verified"])
        self.assertFalse(status["rime_pime_dp1s_hostile_same_sid_physical_replacement_prevented"])

    def test_dp1t_actual_adapter_is_wired_without_baseline_execution(self):
        status = self.receipt["transaction_source"]
        self.assertTrue(status["rime_pime_dp1t_actual_adapter_source_contract_wired"])
        self.assertTrue(status["rime_pime_dp1t_actual_adapter_ci_ps5_ps7_present"])
        self.assertFalse(status["rime_pime_dp1t_actual_adapter_test_executed_by_baseline"])
        self.assertFalse(status["rime_pime_dp1t_actual_adapter_dry_run_executed_by_baseline"])
        self.assertFalse(status["rime_pime_dp1t_exact_authorization_consumed_by_baseline"])
        self.assertFalse(status["rime_pime_actual_canonical_migration_admitted"])

    def test_dp1u_gate_is_wired_without_installed_acceptance_promotion(self):
        status = self.receipt["transaction_source"]
        self.assertTrue(status["rime_pime_dp1u_maintenance_runtime_gate_source_contract_wired"])
        self.assertTrue(status["rime_pime_dp1u_maintenance_runtime_gate_ci_ps5_ps7_present"])
        self.assertTrue(status["rime_pime_dp1u_isolated_preflight_source_contract_wired"])
        self.assertTrue(status["rime_pime_dp1u_isolated_preflight_ci_ps5_ps7_present"])
        self.assertTrue(status["rime_pime_dp1u_native_readonly_probe_source_contract_wired"])
        self.assertTrue(status["rime_pime_dp1u_native_readonly_probe_ci_ps5_ps7_present"])
        self.assertTrue(status["rime_pime_dp1u_native_candidate_ci_ps5_ps7_present"])
        self.assertTrue(status["rime_pime_dp1u_exact_file_removal_source_contract_wired"])
        self.assertTrue(status["rime_pime_dp1u_exact_file_removal_ci_ps5_ps7_present"])
        self.assertFalse(status["rime_pime_dp1u_exact_file_removal_executed_by_baseline"])
        self.assertFalse(status["rime_pime_dp1u_native_readonly_probe_executed_by_baseline"])
        self.assertFalse(status["rime_pime_dp1u_native_execution_adapter_complete"])
        self.assertFalse(status["rime_pime_dp1u_isolated_preflight_test_executed_by_baseline"])
        self.assertFalse(status["rime_pime_dp1u_real_target_approved"])
        self.assertFalse(status["rime_pime_dp1u_execution_authorized"])
        self.assertFalse(status["rime_pime_dp1u_gate_test_executed_by_baseline"])
        self.assertFalse(status["rime_pime_dp1u_current_readiness_executed_by_baseline"])
        self.assertFalse(status["rime_pime_dp1u_acceptance_passed"])
        self.assertFalse(status["actual_installer_executed"])
        self.assertFalse(status["actual_uninstaller_executed"])
        self.assertFalse(status["actual_registry_mutation_executed"])
        self.assertFalse(status["actual_installed_runtime_examined"])

    def test_dp1u_exact_removal_cannot_gain_path_delete_or_lose_either_host(self):
        native = "tools/dual-product/rime-pime-dp1u-exact-file-removal.cs"
        for token in ("File.Delete(path);", "Directory.Delete(root);", "MoveFileEx(a,b,4);"):
            sources = self.maintenance_sources()
            sources[native] += "\n" + token
            with self.subTest(token=token), self.assertRaisesRegex(ValueError, "path-based deletion"):
                subject.transaction_source_status(sources)
        for host in ("ps5", "ps7"):
            sources = self.maintenance_sources()
            path = ".github/workflows/ci.yaml"
            old = f"dp1-u-exact-removal-test-ci-{host}-$runId"
            self.assertIn(old, sources[path])
            sources[path] = sources[path].replace(old, "lost-host-boundary", 1)
            with self.subTest(host=host), self.assertRaises(ValueError):
                subject.transaction_source_status(sources)

    def test_dp1q_candidate_evidence_archive_is_wired_without_actual_archive_claim(self):
        status = self.receipt["transaction_source"]
        self.assertTrue(status["rime_pime_candidate_evidence_archive_source_contract_wired"])
        self.assertTrue(status["rime_pime_candidate_evidence_archive_ci_ps5_ps7_present"])
        self.assertFalse(status["rime_pime_candidate_evidence_archive_test_executed_by_baseline"])
        self.assertTrue(status["rime_pime_candidate_evidence_archive_fixture_protocol_only"])
        self.assertFalse(status["rime_pime_candidate_evidence_archive_actual_root_published"])
        self.assertFalse(status["rime_pime_candidate_evidence_archive_actual_evidence_archived"])
        self.assertFalse(status["rime_pime_actual_evidence_archived_outside_repository_tmp"])
        self.assertFalse(status["rime_pime_actual_canonical_migration_admitted"])

    def test_dp1q_candidate_archive_export_claim_and_ci_boundaries_fail_closed(self):
        cases = (
            ("tools/dual-product/rime-pime-candidate-evidence-archive.psm1",
             "    'Read-RimePimeCandidateEvidenceArchive'",
             "    '*-RimePime*'"),
            ("tools/dual-product/rime-pime-candidate-evidence-archive.ps1",
             "MoveFileEx($nativeSource,$nativeDestination,8)",
             "MoveFileEx($nativeSource,$nativeDestination,9)"),
            ("tools/dual-product/rime-pime-candidate-evidence-archive.ps1",
             "$object.Data.Sha256 -cne [string]$row.sha256",
             "$object.Data.Length -lt 0"),
            ("tools/dual-product/rime-pime-candidate-evidence-archive.ps1",
             "actual_archive_root_published=$false;actual_evidence_archived_outside_repository_tmp=$false",
             "actual_archive_root_published=$true;actual_evidence_archived_outside_repository_tmp=$true"),
            (".github/workflows/ci.yaml",
             ".tmp\\dual-product\\dp1-candidate-evidence-archive-test-ci-$env:CI_TEST_TAG-$runId",
             ".tmp\\dual-product\\dp1-candidate-evidence-archive-test-ci-ps5-$runId"),
        )
        for path, old, new in cases:
            sources = self.maintenance_sources()
            self.assertIn(old, sources[path])
            sources[path] = sources[path].replace(old, new, 1)
            with self.subTest(path=path, old=old), self.assertRaises(ValueError):
                subject.transaction_source_status(sources)

    def test_dp1q_pure_review_export_action_and_ci_boundaries_fail_closed(self):
        cases = (
            ("tools/dual-product/rime-pime-actual-migration-review.psm1",
             "Export-ModuleMember -Function 'Get-RimePimeActualMigrationReview'",
             "Export-ModuleMember -Function '*'"),
            ("tools/dual-product/rime-pime-actual-migration-review.psm1",
             "actual_canonical_migration_admitted = $false",
             "actual_canonical_migration_admitted = $true"),
            ("tools/dual-product/rime-pime-actual-migration-review.psm1",
             "'tools/dual-product/invoke-rime-pime-actual-canonical-migration.ps1'",
             "'..\\..\\outside.ps1'"),
            ("tools/dual-product/rime-pime-actual-migration-review.psm1",
             "# no filesystem, registry, process, build, installer, signing, or product",
             "Get-Content 'actual-canonical.json'\n# action surface"),
            (".github/workflows/ci.yaml",
             ".tmp\\dual-product\\dp1-actual-migration-review-test-ci-ps7-$runId",
             ".tmp\\dual-product\\dp1-actual-migration-review-test-ci-ps5-$runId"),
        )
        for path, old, new in cases:
            sources = self.maintenance_sources()
            self.assertIn(old, sources[path])
            sources[path] = sources[path].replace(old, new, 1)
            with self.subTest(path=path, old=old), self.assertRaises(ValueError):
                subject.transaction_source_status(sources)

    def test_dp1o_sequence_or_negative_boundary_tamper_fails_closed(self):
        original = self.receipt["source_manifest"]
        contract_paths = subject.json.loads(
            subject.CONTRACT.read_text(encoding="utf-8-sig")
        )["source_paths"]
        for old, new in (
            ("'static-installer-manifest-check'", "'removed-static-installer-manifest-check'"),
            ("actual_canonical_migration_admitted = $false", "actual_canonical_migration_admitted = $true"),
            ("Runner file differs from exact source HEAD.", "Runner HEAD mismatch ignored."),
            ("'-C', $clone, 'config', '--local', 'core.autocrlf', 'false'",
             "'-C', $clone, 'config', '--local', 'core.autocrlf', 'true'"),
            ("'-C', $clone, 'checkout', '--detach', $head",
             "'-C', $clone, 'checkout', '--detach', $head, '--"),
        ):
            with self.subTest(anchor=old):
                sources = {path: (subject.ROOT / path).read_text(encoding="utf-8-sig")
                           for path in original if path in contract_paths}
                path = "tools/dual-product/run-rime-pime-isolated-candidate.ps1"
                sources[path] = sources[path].replace(old, new, 1)
                with self.assertRaisesRegex(
                    ValueError, "anchor changed|sequence changed|argument vector changed"
                ):
                    subject.transaction_source_status(sources)

    def test_dp1n_source_contract_anchor_tamper_fails_closed(self):
        cases = (
            ("tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1",
             "fixture_only=$true", "fixture_only=$false"),
            ("tools/dual-product/rime-pime-installer-receipt-transaction.ps1",
             "$null=Stage-RimePimeInstallerReceiptPhysicalLeaf $newObject.Lease.Stream",
             "$null=Write-Output $newObject.Lease.Stream"),
            ("tools/dual-product/rime-pime-installer-receipt-transaction.ps1",
             "Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'intent-copy'",
             "Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'intent-copy-removed'"),
            ("tools/dual-product/rime-pime-installer-receipt-transaction.ps1",
             "Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'installer-copy'",
             "Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'installer-copy-removed'"),
            ("tools/dual-product/rime-pime-installer-receipt-transaction.ps1",
             "[YimeReceiptStorage.Native]::MoveFileEx($Source,$Destination,8)",
             "[YimeReceiptStorage.Native]::MoveFileEx($Source,$Destination,9)"),
            ("tools/dual-product/rime-pime-installer-receipt-transaction.ps1",
             "$completed=Assert-RimePimeInstallerReceiptCompletionTargetAbsent $Pending $intent.operation_id",
             "$completed=Get-RimePimeInstallerReceiptCompletedPath $Pending $intent.operation_id"),
            ("tools/dual-product/rime-pime-installer-receipt-transaction.ps1",
             "$oldPhysical=Open-RimePimeInstallerReceiptPhysicalLeaf $bindings.OldInstaller.Path",
             "$oldPhysical=Get-YimePimePayloadFileRecord $bindings.OldInstaller.Path"),
            ("tools/dual-product/rime-pime-installer-receipt-transaction.ps1",
             "$newPhysical=Open-RimePimeInstallerReceiptPhysicalLeaf $bindings.NewInstaller.Path",
             "$newPhysical=Get-YimePimePayloadFileRecord $bindings.NewInstaller.Path"),
            ("tools/dual-product/rime-pime-installer-receipt-transaction.psm1",
             "    'Resume-RimePimeInstallerReceiptTransaction'",
             "    'Complete-RimePimeInstallerReceiptTransaction'"),
            ("tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1",
             "full_transaction_matrix=[bool]$fullMatrixVerified",
             "full_transaction_matrix=$true"),
            ("tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1",
             "hardware_power_loss_verified=$false",
             "hardware_power_loss_verified=$true"),
            ("tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1",
             "Check 'non-durable-old-clean-publish-binds-distinct-retention-and-history' {",
             "Check 'removed-non-durable-old-clean-publish' {"),
            ("tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1",
             "Check 'non-durable-old-intent-hard-exit-resumes-in-fresh-process' {",
             "Check 'removed-non-durable-old-intent-resume' {"),
            ("tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1",
             "'schema_version','Root','NextDigest','Before','HistoricalV1Path'",
             "'schema_version','Root','NextDigest','Before'"),
            ("tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1",
             "'schema_version','Root','NextDigest','Before','HistoricalV1Path'",
             "'schema_version','Root','NextDigest','Before','HistoricalV1Path','Unexpected'"),
            ("tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1",
             "HistoricalV1Path=[string]$Case.HistoricalV1Path",
             "HistoricalV1Path=''"),
            ("tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1",
             "-HistoricalV1Path $case.HistoricalV1Path",
             "-HistoricalV1Path ''"),
            ("tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1",
             "non_durable_old_retention_conversion_and_recovery=(Test-NamedChecksPassed @(",
             "non_durable_old_retention_conversion_and_recovery=$true #"),
        )
        for path, old, new in cases:
            sources = self.maintenance_sources()
            self.assertIn(old, sources[path])
            sources[path] = sources[path].replace(old, new, 1)
            with self.subTest(path=path, old=old), self.assertRaises(ValueError):
                subject.transaction_source_status(sources)

    def test_dp1n_ci_requires_ps5_ps7_fixture_only_commands(self):
        sources = self.maintenance_sources()
        sources[".github/workflows/ci.yaml"] = sources[".github/workflows/ci.yaml"].replace(
            ".tmp\\dual-product\\dp1-package-receipt-v2-test-dp1n-ci-$env:CI_TEST_TAG-$runId",
            ".tmp\\dual-product\\dp1-package-receipt-v2-test-dp1n-ci-ps5-$runId",
            1,
        )
        with self.assertRaisesRegex(ValueError, "dedicated review required"):
            subject.transaction_source_status(sources)

        matrix_output = (
            '            -OutputRoot (Join-Path $pwd "'
            '.tmp\\dual-product\\dp1-package-receipt-v2-test-dp1n-ci-$env:CI_TEST_TAG-$runId")'
        )
        for argument in (
            "-CheckPattern 'clean*'",
            "-WorkerCasePath '.tmp\\dual-product\\foreign\\worker.json'",
            "-Phase recover",
        ):
            sources = self.maintenance_sources()
            self.assertIn(matrix_output, sources[".github/workflows/ci.yaml"])
            sources[".github/workflows/ci.yaml"] = sources[".github/workflows/ci.yaml"].replace(
                matrix_output,
                matrix_output + " `\n            " + argument,
                1,
            )
            with self.subTest(argument=argument), self.assertRaisesRegex(
                    ValueError, "dedicated review required"):
                subject.transaction_source_status(sources)

        sources = self.maintenance_sources()
        invocation = (
            "          .\\tools\\dual-product\\test-rime-pime-installer-receipt-transaction.ps1 `\n"
        )
        self.assertIn(invocation, sources[".github/workflows/ci.yaml"])
        sources[".github/workflows/ci.yaml"] = sources[".github/workflows/ci.yaml"].replace(
            invocation,
            "          Start-Process forbidden-product.exe\n" + invocation,
            1,
        )
        with self.assertRaisesRegex(ValueError, "dedicated review required"):
            subject.transaction_source_status(sources)

    def assert_long_contract_ci_rejected(self, old, new):
        sources = self.maintenance_sources()
        path = ".github/workflows/ci.yaml"
        job = subject.one(
            r"(?ms)^  dp1-long-contracts:\n.*?(?=^  [A-Za-z0-9_-]+:\n|\Z)",
            sources[path], "long-contract regression fixture job",
        ).group()
        self.assertIn(old, job)
        sources[path] = sources[path].replace(job, job.replace(old, new, 1), 1)
        with self.assertRaises(ValueError):
            subject.transaction_source_status(sources)

    def test_long_contract_matrix_requires_real_ps5_ps7_and_complete_suites(self):
        cases = (
            ("shell: [powershell, pwsh]", "shell: [pwsh]"),
            ("shell: [powershell, pwsh]", "shell: [pwsh, pwsh]"),
            ("suite: [installer-transaction, receipt-store, evidence-archive]",
             "suite: [installer-transaction, receipt-store]"),
            ("suite: [installer-transaction, receipt-store, evidence-archive]",
             "suite: [installer-transaction, receipt-store, receipt-store]"),
            ("        shell: [powershell, pwsh]\n",
             "        shell: [powershell, pwsh]\n        exclude: [{shell: powershell}]\n"),
            ("fail-fast: true", "fail-fast: false"),
            ("max-parallel: 2", "max-parallel: 3"),
            ("        shell: ${{ matrix.shell }}", "        shell: pwsh"),
            ("CI_TEST_SHELL: ${{ matrix.shell }}", "CI_TEST_SHELL: pwsh"),
            ("CI_TEST_TAG: ${{ matrix.shell == 'powershell' && 'ps5' || 'ps7' }}",
             "CI_TEST_TAG: ps7"),
            ("$PSVersionTable.PSVersion.Major -ne 5", "$PSVersionTable.PSVersion.Major -ne 7"),
            ("$PSVersionTable.PSVersion.Major -lt 7", "$PSVersionTable.PSVersion.Major -lt 5"),
            ("    runs-on: windows-2022\n", "    runs-on: windows-2022\n    if: false\n"),
            ("    runs-on: windows-2022\n", "    runs-on: windows-2022\n    continue-on-error: true\n"),
            ("      - name: Verify actual PowerShell test host\n",
             "      - name: Verify actual PowerShell test host\n        if: false\n"),
            ("      - name: Verify actual PowerShell test host\n",
             "      - name: Verify actual PowerShell test host\n        shell: pwsh\n"),
            ("      - uses: actions/checkout@v6\n",
             "      - uses: actions/checkout@v6\n      - run: Write-Host skipped\n"),
        )
        for old, new in cases:
            with self.subTest(old=old, new=new):
                self.assert_long_contract_ci_rejected(old, new)

    def test_long_contract_matrix_requires_unfiltered_calls_and_retained_results(self):
        for suite, script in (
            ("receipt-store", "test-rime-pime-receipt-v2-store.ps1"),
            ("installer-transaction", "test-rime-pime-installer-receipt-transaction.ps1"),
            ("evidence-archive", "test-rime-pime-candidate-evidence-archive.ps1"),
        ):
            condition = f"        if: matrix.suite == '{suite}'\n"
            invocation = f"          .\\tools\\dual-product\\{script} `\n"
            cases = (
                (condition, ""),
                (condition, "        if: matrix.suite == 'missing-suite'\n"),
                (condition, condition + "        shell: pwsh\n"),
                (condition, condition + "        continue-on-error: true\n"),
                (invocation, invocation + "            -CheckPattern 'clean*' `\n"),
                (invocation, invocation + "            -WorkerCasePath '.tmp\\worker.json' `\n"),
                (invocation, invocation + "            -Phase recover `\n"),
                (invocation, "          Start-Process forbidden-product.exe\n" + invocation),
                (invocation, invocation + invocation),
            )
            for old, new in cases:
                with self.subTest(suite=suite, new=new):
                    self.assert_long_contract_ci_rejected(old, new)
        cases = (
            (".Substring(0,16)", ".Substring(0,32)"),
            ("        if: ${{ always() }}", "        if: ${{ success() }}"),
            ("          include-hidden-files: true", "          include-hidden-files: false"),
            ("          if-no-files-found: warn", "          if-no-files-found: ignore"),
            ("-${{ github.sha }}-${{ github.run_attempt }}", ""),
            ("-${{ matrix.suite }}-${{ matrix.shell }}", ""),
        )
        for result_glob in (
            ".tmp/dual-product/dp1-package-receipt-v2-test-store-*/store-result.json",
            ".tmp/dual-product/dp1-package-receipt-v2-test-dp1n-ci-*/transaction-result.json",
            ".tmp/dual-product/dp1-candidate-evidence-archive-test-ci-*/candidate-evidence-archive-result.json*",
        ):
            cases += ((result_glob, ".tmp/unrelated.json"),)
        for old, new in cases:
            with self.subTest(old=old, new=new):
                self.assert_long_contract_ci_rejected(old, new)

    def test_nsis_preflight_must_gate_both_packaging_jobs_after_preparation(self):
        for old, new in (
            ("    needs: [installer-payload, nsis-preflight]",
             "    needs: [installer-payload]"),
            ("    needs: [release-sign-payload, nsis-preflight]",
             "    needs: [release-sign-payload]"),
            ("  nsis-preflight:\n", "  nsis-preflight:\n    if: false\n"),
            ("  nsis-preflight:\n", "  nsis-preflight:\n    continue-on-error: true\n"),
            ("      - name: Prepare pinned NSIS in non-secret packaging job",
             "      - name: Preparation removed"),
        ):
            sources = self.maintenance_sources()
            path = ".github/workflows/ci.yaml"
            self.assertIn(old, sources[path])
            sources[path] = sources[path].replace(old, new, 1)
            with self.subTest(old=old), self.assertRaises(ValueError):
                subject.transaction_source_status(sources)

    def test_dp1j_fixtures_are_source_contracts_not_product_wiring(self):
        status = self.receipt["transaction_source"]
        for field in (
            "rime_pime_nsis_membership_monitor_fixture_source_anchors_present",
            "rime_pime_nsis_membership_monitor_fixture_test_source_anchors_present",
            "rime_pime_receipt_v2_supersession_fixture_source_anchors_present",
            "rime_pime_receipt_v2_supersession_fixture_test_source_anchors_present",
            "rime_pime_dp1j_fixture_ci_ps5_ps7_present",
            "rime_pime_receipt_v2_supersession_fixture_protocol_only",
        ):
            with self.subTest(field=field):
                self.assertTrue(status[field])
        for field in (
            "rime_pime_dp1j_fixture_tests_executed_by_baseline",
            "rime_pime_receipt_v2_supersession_canonical_receipt_mutated",
            "rime_pime_active_same_sid_transient_tree_membership_interference_excluded",
            "rime_pime_nsis_non_os_compiler_input_closure",
            "rime_pime_full_nsis_toolchain_input_closure",
            "rime_pime_canonical_receipt_v2_evidence_durable",
            "rime_pime_real_installer_transaction_passed",
            "rime_pime_installed_live_acceptance_passed",
        ):
            with self.subTest(field=field):
                self.assertFalse(status[field])

    def test_dp1j_fixture_boundary_tamper_fails_closed(self):
        cases = (
            ("tools/dual-product/rime-pime-nsis-membership-monitor-v1.ps1",
             "physical_membership_prevention_claimed = $false",
             "physical_membership_prevention_claimed = $true"),
            ("tools/dual-product/test-rime-pime-nsis-membership-monitor-v1.ps1",
             "actual_makensis_executed = $false", "actual_makensis_executed = $true"),
            ("tools/dual-product/rime-pime-receipt-v2-supersession.ps1",
             "power_loss_verified=$false", "power_loss_verified=$true"),
            ("tools/dual-product/test-rime-pime-receipt-v2-supersession.ps1",
             "cross_process_crash_or_replay_verified=$false",
             "cross_process_crash_or_replay_verified=$true"),
        )
        for path, old, new in cases:
            sources = self.maintenance_sources()
            self.assertIn(old, sources[path])
            sources[path] = sources[path].replace(old, new, 1)
            with self.subTest(path=path), self.assertRaisesRegex(
                    ValueError, "dedicated review required"):
                subject.transaction_source_status(sources)

    def test_dp1j_ci_requires_two_shell_fixture_only_commands(self):
        sources = self.maintenance_sources()
        sources[".github/workflows/ci.yaml"] = sources[".github/workflows/ci.yaml"].replace(
            ".tmp\\dual-product\\dp1-j-membership-test-ci-ps7-$runId",
            ".tmp\\dual-product\\dp1-j-membership-test-ci-ps5-$runId", 1)
        with self.assertRaisesRegex(ValueError, "dedicated review required"):
            subject.transaction_source_status(sources)

        sources = self.maintenance_sources()
        line = "          .\\tools\\dual-product\\test-rime-pime-receipt-v2-supersession.ps1 `\n"
        self.assertIn(line, sources[".github/workflows/ci.yaml"])
        sources[".github/workflows/ci.yaml"] = sources[".github/workflows/ci.yaml"].replace(
            line, "          Start-Process forbidden-product.exe\n" + line, 1)
        with self.assertRaisesRegex(ValueError, "dedicated review required"):
            subject.transaction_source_status(sources)

    def test_dp1k_interval_wiring_and_ci_fail_closed(self):
        cases = (
            ("tools/dual-product/rime-pime-nsis-compiler-interval.ps1",
             "physical_membership_prevention_claimed=$false",
             "physical_membership_prevention_claimed=$true"),
            ("tools/dual-product/test-rime-pime-nsis-compiler-interval.ps1",
             "actual_makensis_executed=$true", "actual_makensis_executed=$false"),
            ("tools/build-rime-pime-installer.ps1",
             "$membershipInterval=Complete-RimePimeMonitoredNsisStage $compilerStage",
             "$membershipInterval=$null"),
            ("tools/build-rime-pime-installer.ps1",
             "nsis_compiler_membership_interval=$membershipInterval",
             "nsis_compiler_membership_interval=$null"),
            (".github/workflows/ci.yaml",
             ".tmp\\dual-product\\dp1-nsis-interval-test-ci-ps7-$runId",
             ".tmp\\dual-product\\dp1-nsis-interval-test-ci-ps5-$runId"),
        )
        for path, old, new in cases:
            sources = self.maintenance_sources()
            self.assertIn(old, sources[path])
            sources[path] = sources[path].replace(old, new, 1)
            with self.subTest(path=path), self.assertRaises(ValueError):
                subject.transaction_source_status(sources)

    def test_dp1m_current_build_evidence_admission_fails_closed(self):
        cases = (
            ("tools/build-rime-pime-installer.ps1",
             "yime-rime-pime-staged-nsis-build-result-membership-interval-v1",
             "yime-rime-pime-staged-nsis-build-result-v3"),
            ("tools/dual-product/rime-pime-package-receipt-v2.ps1",
             "function Assert-RimePimeReceiptV2CompilerMembershipInterval",
             "function Assert-RemovedCompilerMembershipInterval"),
            ("tools/dual-product/rime-pime-package-receipt-v2.ps1",
             "New receipt preparation requires current membership-interval build evidence; legacy evidence is read-only.",
             "legacy evidence accepted"),
            ("tools/dual-product/rime-pime-package-receipt-v2.ps1",
             "(Split-Path -Parent $buildStage) -ine $allowedStageParent",
             "(Split-Path -Parent $buildStage) -ieq $allowedStageParent"),
            ("tools/dual-product/rime-pime-package-receipt-v2.ps1",
             "[int]$Build.package_plan_artifact_count -ne [int]$Build.staged_pe_unique_artifact_count",
             "[int]$Build.package_plan_artifact_count -ne [int]$Build.staged_pe_path_binding_count"),
            ("tools/dual-product/rime-pime-package-receipt-v2.ps1",
             "Current membership-interval build evidence has an invalid prebuild leased-input count.",
             "Current membership-interval build evidence accepts any leased-input count."),
            ("tools/dual-product/rime-pime-package-receipt-v2.ps1",
             "Current build publication paths contradict the actual predecessor identity.",
             "Current build publication paths trust self-reported predecessor identity."),
            ("tools/dual-product/rime-pime-package-receipt-v2.ps1",
             "Test-RimePimeReceiptV2Boolean $manifest.Value.final_payload_closure $false",
             "[bool]$manifest.Value.final_payload_closure"),
            ("tools/dual-product/rime-pime-package-receipt-v2.ps1",
             "Open-RimePimeReceiptV2FileLease $logicPath ([string]$row.sha256)",
             "Write-Output $logicPath ([string]$row.sha256)"),
            ("tools/dual-product/rime-pime-package-receipt-v2.ps1",
             "Current build evidence contradicts the leased repository NSIS toolchain lock.",
             "Current build evidence trusts a self-reported NSIS toolchain lock."),
            ("tools/dual-product/rime-pime-receipt-v2-store.ps1",
             "Changed receipt publication requires current membership-interval build evidence.",
             "changed legacy receipt accepted"),
            ("tools/dual-product/rime-pime-receipt-v2-store.ps1",
             "Changed receipt recovery requires current membership-interval build evidence.",
             "changed legacy recovery accepted"),
        )
        for path, old, new in cases:
            sources = self.maintenance_sources()
            self.assertIn(old, sources[path])
            sources[path] = sources[path].replace(old, new, 1)
            with self.subTest(path=path, old=old), self.assertRaisesRegex(
                    ValueError, "dedicated review required"):
                subject.transaction_source_status(sources)

    def test_retained_receipt_wiring_requires_module_test_ci_and_exact_exports(self):
        cases = (
            ("tools/dual-product/rime-pime-package-receipt-v2.psm1",
             ". (Join-Path $PSScriptRoot 'rime-pime-receipt-v2-store.ps1')",
             "# store import removed"),
            ("tools/dual-product/rime-pime-package-receipt-v2.psm1",
             "    'Resume-RimePimePackageReceiptV2Publication'",
             "    'Complete-RimePimeReceiptPublication'"),
            ("tools/dual-product/test-rime-pime-receipt-v2-store.ps1",
             "module-exports-only-six-explicit-receipt-apis", "module-export-check-removed"),
            (".github/workflows/ci.yaml",
             ".tmp\\dual-product\\dp1-package-receipt-v2-test-store-$env:CI_TEST_TAG-$runId",
             ".tmp\\dual-product\\dp1-package-receipt-v2-test-store-ps5-$runId"),
        )
        for path, old, new in cases:
            sources = self.maintenance_sources()
            self.assertIn(old, sources[path])
            sources[path] = sources[path].replace(old, new, 1)
            with self.subTest(path=path), self.assertRaises(ValueError):
                subject.transaction_source_status(sources)

    def test_builder_toolchain_import_order_regression_is_rejected(self):
        sources = self.maintenance_sources()
        safe = (
            "Import-Module -Name $nsisToolchainModule -Force\n"
            "Import-Module -Name $stagingModule -Force"
        )
        unsafe = (
            "Import-Module -Name $stagingModule -Force\n"
            "Import-Module -Name $nsisToolchainModule -Force"
        )
        self.assertIn(safe, sources["tools/build-rime-pime-installer.ps1"])
        sources["tools/build-rime-pime-installer.ps1"] = sources[
            "tools/build-rime-pime-installer.ps1"
        ].replace(safe, unsafe, 1)
        with self.assertRaisesRegex(ValueError, "module import safety order changed"):
            subject.transaction_source_status(sources)

    def test_dishonest_toolchain_boundary_promotion_is_rejected(self):
        for anchor in (
            "active_same_sid_transient_tree_membership_interference_excluded=$false",
            "nsis_non_os_compiler_input_closure=$false;full_nsis_toolchain_input_closure=$false",
        ):
            sources = self.maintenance_sources()
            sources["tools/dual-product/rime-pime-nsis-toolchain-closure.ps1"] = sources[
                "tools/dual-product/rime-pime-nsis-toolchain-closure.ps1"
            ].replace(anchor, anchor.replace("$false", "$true", 1), 1)
            with self.subTest(anchor=anchor), self.assertRaisesRegex(ValueError, "source anchor changed"):
                subject.transaction_source_status(sources)

    def test_receipt_v2_and_synthetic_only_ci_anchors_are_required(self):
        cases = (
            ("tools/dual-product/rime-pime-package-receipt-v2.ps1",
             "function Publish-RimePimePackageReceiptV2", "function Publish-Removed"),
            (".github/workflows/ci.yaml", "-SyntheticOnly", "-RepositoryToolchain"),
        )
        for path, old, new in cases:
            sources = self.maintenance_sources()
            sources[path] = sources[path].replace(old, new, 1)
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "dedicated review required|source anchor changed"):
                subject.transaction_source_status(sources)

    def test_rime_target_sid_source_is_wired_but_native_acceptance_is_not_promoted(self):
        status = self.receipt["transaction_source"]
        self.assertTrue(status["rime_pime_initiating_sid_chain_source_anchors_present"])
        self.assertTrue(status["rime_pime_target_user_cleanup_source_anchors_present"])
        self.assertTrue(status["rime_pime_target_user_synthetic_contract_source_anchors_present"])
        self.assertFalse(status["rime_pime_native_uac_and_registered_profile_acceptance_passed"])
        self.assertFalse(status["rime_pime_full_transaction_engine_wired_into_installer"])
        self.assertTrue(status["rime_pime_registration_exit_and_state_source_anchors_present"])
        self.assertFalse(status["rime_pime_legacy_registration_selected_root_only"])
        self.assertTrue(status["rime_pime_unowned_legacy_deletion_absent"])
        self.assertFalse(status["rime_pime_legacy_migration_wired"])
        self.assertTrue(status["rime_pime_current_upgrade_fail_closed"])
        self.assertTrue(status["rime_pime_fresh_install_final_vacancy_source_anchor_present"])
        self.assertTrue(status["rime_pime_synthetic_fault_matrix_source_anchors_present"])
        for promoted in (
            "rime_pime_target_user_synthetic_contract_passed",
            "rime_pime_registration_exit_and_state_verified",
            "rime_pime_synthetic_fault_matrix_implemented",
        ):
            with self.subTest(promoted=promoted):
                self.assertNotIn(promoted, status)

    def test_no_native_or_installed_action_is_inferred_from_source(self):
        status = self.receipt["transaction_source"]
        for field in (
            "actual_installer_executed",
            "actual_uninstaller_executed",
            "actual_elevation_executed",
            "actual_registry_mutation_executed",
            "actual_profile_mutation_executed",
            "actual_process_stop_executed",
            "actual_process_start_executed",
            "actual_filesystem_mutation_executed",
            "actual_installed_runtime_examined",
            "actual_native_probe_executed",
        ):
            with self.subTest(field=field):
                self.assertIs(status[field], False)

    def test_pending_statuses_report_source_anchors_not_unrun_passes(self):
        statuses = {item["id"]: item["status"] for item in self.receipt["known_pending"]}
        self.assertEqual(statuses["DP1-PIME-DIRECTED-EXIT-04"],
                         "source_anchors_present_installed_acceptance_pending")
        self.assertEqual(statuses["DP1-PIME-REGISTRY-05"],
                         "source_anchors_present_native_acceptance_pending")
        self.assertEqual(statuses["DP1-PIME-TRANSACTION-06"],
                         "fixture_journal_and_replay_source_anchors_present_real_transaction_pending")
        self.assertEqual(statuses["DP1-PIME-COMPILER-INPUT-07"],
                         "fresh_compiler_stage_and_strict_interval_build_admission_wired_actual_migration_external_physical_limits_pending")
        self.assertEqual(statuses["DP1-PIME-RECEIPT-08"],
                         "retained_v2_supersession_and_current_interval_admission_wired_actual_migration_external_physical_limits_pending")
        self.assertEqual(
            statuses["DP1-PIME-INSTALLER-RECEIPT-09"],
            "installer_receipt_transaction_contract_and_private_actual_adapter_wired_actual_migration_external_installed_transaction_pending",
        )
        self.assertEqual(
            statuses["DP1-PIME-CANDIDATE-EVIDENCE-10"],
            "actual_archive_adapter_and_canonical_migration_complete_external_to_source_baseline",
        )
        self.assertEqual(
            statuses["DP1-PIME-MAINTENANCE-RUNTIME-11"],
            "native_readonly_probe_and_source_gates_wired_ps5_ps7_execution_adapter_and_installed_acceptance_pending",
        )
        self.assertEqual(set(statuses), {
            "DP1-PIME-DIRECTED-EXIT-04", "DP1-PIME-REGISTRY-05", "DP1-PIME-TRANSACTION-06",
            "DP1-PIME-COMPILER-INPUT-07", "DP1-PIME-RECEIPT-08",
            "DP1-PIME-INSTALLER-RECEIPT-09", "DP1-PIME-CANDIDATE-EVIDENCE-10",
            "DP1-PIME-MAINTENANCE-RUNTIME-11",
        })

    def test_target_sid_bootstrap_cannot_revert_to_manifest_auto_elevation(self):
        sources = self.maintenance_sources()
        sources["installer/installer.nsi"] = sources["installer/installer.nsi"].replace(
            "RequestExecutionLevel user", "RequestExecutionLevel admin", 1
        )
        with self.assertRaisesRegex(ValueError, "registration/SID/transaction status changed"):
            subject.transaction_source_status(sources)

    def test_target_user_cleanup_cannot_reintroduce_hku_enumeration(self):
        sources = self.maintenance_sources()
        sources["tools/pime-registry-cleanup.ps1"] += (
            '\nGet-ChildItem -LiteralPath "Registry::HKEY_USERS"\n'
        )
        with self.assertRaisesRegex(ValueError, "registration/SID/transaction status changed"):
            subject.transaction_source_status(sources)

    def test_native_unregister_cannot_reintroduce_cross_sid_cleanup(self):
        sources = self.maintenance_sources()
        sources["libIME2/src/ImeModule.cpp"] = sources["libIME2/src/ImeModule.cpp"].replace(
            "HRESULT ImeModule::unregisterServer(bool ownsSharedTsfRegistration) {",
            "HRESULT ImeModule::unregisterServer(bool ownsSharedTsfRegistration) {\nHKEY user = HKEY_USERS;",
            1,
        )
        with self.assertRaisesRegex(ValueError, "registration/SID/transaction status changed"):
            subject.transaction_source_status(sources)

    def test_registration_verification_cannot_be_removed(self):
        sources = self.maintenance_sources()
        sources["installer/installer.nsi"] = sources["installer/installer.nsi"].replace(
            "Call verifyRegistrationOwnership", "Call validateExistingPimeRoot"
        )
        with self.assertRaisesRegex(ValueError, "registration/SID/transaction status changed"):
            subject.transaction_source_status(sources)

    def test_commented_registration_call_is_not_a_source_anchor(self):
        sources = self.maintenance_sources()
        sources["installer/installer.nsi"] = sources["installer/installer.nsi"].replace(
            "\tCall verifyRegistrationOwnership\n",
            "\t; Call verifyRegistrationOwnership\n",
            1,
        )
        with self.assertRaisesRegex(ValueError, "registration/SID/transaction status changed"):
            subject.transaction_source_status(sources)

    def test_unowned_legacy_deletion_cannot_be_added(self):
        sources = self.maintenance_sources()
        sources["installer/installer.nsi"] = sources["installer/installer.nsi"].replace(
            "Function uninstallOldVersion\n",
            'Function uninstallOldVersion\n\tDeleteRegKey HKLM "${LEGACY_PRODUCT_INSTALL_KEY}"\n',
            1,
        )
        with self.assertRaisesRegex(ValueError, "registration/SID/transaction status changed"):
            subject.transaction_source_status(sources)

    def test_current_family_upgrade_mutation_cannot_be_added(self):
        sources = self.maintenance_sources()
        sources["installer/installer.nsi"] = sources["installer/installer.nsi"].replace(
            "Function uninstallOldVersion\n",
            "Function uninstallOldVersion\n\tCall stopRunningBackend\n",
            1,
        )
        with self.assertRaisesRegex(ValueError, "registration/SID/transaction status changed"):
            subject.transaction_source_status(sources)

    def test_synthetic_transaction_engine_cannot_be_inferred_wired(self):
        sources = self.maintenance_sources()
        sources["installer/installer.nsi"] += (
            '\nFile "..\\tools\\dual-product\\rime-pime-transaction-engine.ps1"\n'
        )
        with self.assertRaisesRegex(ValueError, "registration/SID/transaction status changed"):
            subject.transaction_source_status(sources)

    def test_transaction_source_cannot_promote_a_synthetic_fixture(self):
        sources = self.maintenance_sources()
        sources["tools/dual-product/transaction-isolation.ps1"] = sources[
            "tools/dual-product/transaction-isolation.ps1"
        ].replace("actual_registry_or_install_mutation_executed = $false",
                  "actual_registry_or_install_mutation_executed = $true", 1)
        with self.assertRaisesRegex(ValueError, "transaction source anchor changed"):
            subject.transaction_source_status(sources)


if __name__ == "__main__":
    unittest.main()
