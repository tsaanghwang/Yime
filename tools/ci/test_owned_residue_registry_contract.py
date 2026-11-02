"""Static wiring only: never imports or executes a Windows registry test."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / 'YimeTextServiceExperiment/tests'


class RegistryAdapterContract(unittest.TestCase):
    def test_build_is_explicit_and_not_automatically_executed(self):
        cmake = (ROOT / 'YimeTextServiceExperiment/CMakeLists.txt').read_text()
        self.assertIn('option(YIME_OWNED_RESIDUE_REGISTRY_TESTS "Build disposable HKCU registry adapter tests" OFF)', cmake)
        self.assertIn('add_executable(YimeOwnedResidueRegistryTests EXCLUDE_FROM_ALL', cmake)
        self.assertNotIn('add_test(NAME YimeOwnedResidueRegistryTests', cmake)
        for path in (ROOT / '.github/workflows').glob('*'):
            if path.name == 'owned-residue-registry-adapter.yml':
                self.assertTrue((ROOT / 'tools/ci/test_workflow_contract.py').is_file())
                continue  # Sole explicit one-shot adapter workflow; its gates are separately tested.
            self.assertNotIn('YimeOwnedResidueRegistryTests', path.read_text())
            self.assertNotIn('confirm-disposable-hkcu-adapter-test', path.read_text())

    def test_test_entry_has_no_arbitrary_path_argument(self):
        text = (TESTS / 'OwnedResidueRegistryTests.cpp').read_text()
        main = text.split('int wmain(', 1)[1]
        self.assertIn('argc!=2', main)
        self.assertIn('--confirm-disposable-hkcu-adapter-test', main)
        self.assertLess(main.index('return 3;'), main.index('fixture.start()'))
        self.assertNotIn('argv[2]', text)
        self.assertIn('CoCreateGuid', text)
        self.assertIn('YimeOwnedResidueAdapterTest-', text)
        start = text.split(' void start(){', 1)[1].split(' std::wstring path(', 1)[0]
        self.assertLess(start.index('std::flush'), start.index('Require(static_cast<bool>(std::cout))'))
        self.assertLess(start.index('Require(static_cast<bool>(std::cout))'), start.index('create(L"")'))

    def test_no_real_product_registry_or_security_operations(self):
        text = (TESTS / 'OwnedResidueRegistryTests.cpp').read_text()
        for forbidden in ('HKEY_LOCAL_MACHINE', 'HKEY_CLASSES_ROOT', 'RegDeleteTree', 'RegSetKeySecurity', 'SetSecurityInfo', 'RegisterProfile', 'ActivateProfile', 'CLSID_Yime', 'GUID_Yime', 'CTF', 'InprocServer32'):
            self.assertNotIn(forbidden, text)
        self.assertIn('HKEY_CURRENT_USER', text)
        self.assertIn('REG_CREATED_NEW_KEY', text)

    def test_production_and_test_share_win32_mechanisms(self):
        source = (TESTS / 'RegistrationProbe.cpp').read_text()
        adapter = (TESTS / 'OwnedResidueRegistry.h').read_text()
        wrapper = (TESTS / 'NewTransactionResidue.h').read_text()
        native = (TESTS / 'OwnedResidueRegistryTests.cpp').read_text()
        self.assertIn('registry::Observe(', wrapper)
        self.assertIn('registry::EraseOne(', source)
        self.assertIn('throw Failure{e.stage,e.code}', wrapper)
        self.assertIn('throw Failure{e.stage,e.code}', source)
        self.assertIn('reg::Observe(', native)
        self.assertIn('reg::EraseOne(', native)
        self.assertIn('RegQueryInfoKeyW', adapter)
        self.assertIn('RegDeleteKeyExW', adapter)
        self.assertNotIn('RegDeleteTree', adapter)

    def test_old_ledger_rejection_and_scope_still_present(self):
        source = (TESTS / 'RegistrationProbe.cpp').read_text()
        self.assertIn('legacy-v2-no-item-provenance', source)
        self.assertIn('data.value("schema",std::string())!="18u-mycomputer-ledger-v3"', source)
        self.assertIn('validateLocalAbsence(data.at("itemAbsence"))', source)


if __name__ == '__main__':
    unittest.main()
