"""Synthetic evidence and source wiring only; no native/Go invocation."""
import json
from pathlib import Path
import unittest
from validate_same_process_edit import FIELDS, TRUE_FIELDS, validate

ROOT = Path(__file__).resolve().parents[2]


class SameProcessEvidenceTests(unittest.TestCase):
    def fixture(self):
        return dict(schema="18u-same-process-registered-edit-v1", stage="result", scenario="commit",
                    status="pass", activationIdentity="windows-activated-profile",
                    windowsActivatedInstance=True, sendInput=False, operationPendingObserved=True,
                    editAttempts=1, appliedReceipt=True, readbackMatches=True,
                    registrationOwnerPID=37, brokerTargetPID=37, registrationLifecycleOwned=True,
                    cleanupVerified=True, routeRevoked=True)

    def stream(self, record):
        return '{"stage":"connected","accepted":true}\n' + json.dumps(record) + '\n'

    def test_complete_evidence_is_only_consistency(self):
        result = validate(self.stream(self.fixture()), 0, 37)
        self.assertEqual(result["status"], "evidence-consistent")
        self.assertFalse(result["nativeExecutionVerified"])
        self.assertFalse(result["sourceAuthenticityVerified"])

    def test_each_missing_null_or_unknown_field_rejects(self):
        for key in FIELDS:
            bad = self.fixture()
            del bad[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(self.stream(bad), 0, 37)
            bad[key] = None
            with self.assertRaises(ValueError):
                validate(self.stream(bad), 0, 37)
        bad = self.fixture()
        bad["extra"] = "private"
        with self.assertRaises(ValueError):
            validate(self.stream(bad), 0, 37)

    def test_each_unobserved_stage_rejects(self):
        for key in TRUE_FIELDS:
            bad = self.fixture()
            bad[key] = False
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(self.stream(bad), 0, 37)
        bad = self.fixture()
        bad["sendInput"] = True
        with self.assertRaises(ValueError):
            validate(self.stream(bad), 0, 37)

    def test_no_second_edit_wrong_process_or_bool_pid(self):
        for key, value in [("editAttempts", 0), ("editAttempts", 2), ("editAttempts", True),
                           ("registrationOwnerPID", 38), ("brokerTargetPID", 38), ("brokerTargetPID", True),
                           ("activationIdentity", "owned-host-activation-client")]:
            bad = self.fixture()
            bad[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                validate(self.stream(bad), 0, 37)

    def test_failed_process_duplicates_and_extra_records_reject(self):
        good = self.stream(self.fixture())
        for code in (1, 3, 4, False):
            with self.assertRaises(ValueError):
                validate(good, code, 37)
        duplicate = good.rstrip()[:-1] + ',"cleanupVerified":true}\n'
        for bad in (duplicate, good + '{}\n', good.replace('"accepted":true', '"accepted":false'),
                    good.replace('"editAttempts": 1', '"editAttempts": NaN')):
            with self.assertRaises(ValueError):
                validate(bad, 0, 37)


class SameProcessSourceTests(unittest.TestCase):
    def test_real_activation_lookup_stays_in_transaction(self):
        text = (ROOT / "YimeTextServiceExperiment/tests/RegisteredEditProbeMain.h").read_text(encoding="utf-8")
        run = text.index("transaction.run(argv[2])")
        lookup = text.index("transaction.manager->GetFunctionProvider")
        edit = text.index("proof.issue()")
        read = text.index("readback=editRead(transaction)")
        cleanup = text.index("transaction.cleanup()")
        absent = text.index("registryAbsent();apiAbsent(")
        self.assertTrue(run < lookup < edit < read < cleanup < absent)
        for prohibited in ("DllGetClassObject", "CreateInstance(", "tip->ActivateEx", "new YimeTextService", "SendInput("):
            self.assertNotIn(prohibited, text)
        self.assertIn("providerIdentity.Get()==routeIdentity.Get()", text)
        self.assertIn("actual==module.value", text)
        self.assertIn("==TF_E_DISCONNECTED", text)

    def test_one_owner_and_persistent_ledger_in_driver(self):
        driver = (ROOT / "go-backend/internal/touchhostbridge/formalhost_windows_test.go").read_text(encoding="utf-8")
        self.assertIn('"--tip-host-pid", strconv.Itoa(host.Process.Pid)', driver)
        self.assertIn('filepath.Join(dir, "registration-ledger.json")', driver)
        self.assertIn('YIME_SAME_PROCESS_REGISTERED_EDIT_EVIDENCE', driver)
        self.assertIn('os.Mkdir(dir, 0700)', driver)
        self.assertIn('validateSameProcessEditResult(line, uint32(host.Process.Pid))', driver)
        self.assertNotIn('"--recover"', driver)
        self.assertNotIn('"--cleanup-only"', driver)

    def test_default_off_without_registration_workflow_widening(self):
        cmake = (ROOT / "YimeTextServiceExperiment/CMakeLists.txt").read_text(encoding="utf-8")
        self.assertRegex(cmake, r'option\(YIME_TOUCH_REGISTERED_EDIT_PROBE "[^"]+" OFF\)')
        self.assertIn("add_executable(Yime18uRegisteredEditProbe tests/RegistrationProbe.cpp)", cmake)
        for path in (ROOT / ".github/workflows").glob("*"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("TestNativeSameProcessRegisteredEdit", text)
            self.assertNotIn("YIME_SAME_PROCESS_REGISTERED_EDIT_HOST", text)
            self.assertNotIn("YIME_TOUCH_REGISTERED_EDIT_PROBE=ON", text)


if __name__ == "__main__":
    unittest.main()
