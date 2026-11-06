"""Protect PR/main package delivery and its offline-only execution boundary."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/installed-18u-compile.yml'


def validate(text):
    events = text.split('\non:\n', 1)[1].split('\npermissions:', 1)[0]
    if re.findall(r'^  (\w+):', events, re.M) != ['push', 'pull_request']:
        raise ValueError('Only ordinary push and PR events are allowed')
    for event in ('push', 'pull_request'):
        block = events.split('  ' + event + ':\n', 1)[1].split('\n  ', 1)[0]
        branches = re.search(r'branches: \[([^]]+)\]', block)
        if not branches or 'main' not in [b.strip().strip("'\"") for b in branches[1].split(',')]:
            raise ValueError('Main delivery event missing')
    if 'permissions:\n  contents: read\n' not in text or 'persist-credentials: false' not in text:
        raise ValueError('Read-only checkout boundary missing')
    job = text.split('  compile-offline:\n', 1)[1]
    if re.search(r'^    if:', job, re.M):
        raise ValueError('A branch-only job gate could silently skip PR/main')
    for field in ('registrationExecuted', 'installerExecuted', 'registeredHostExecuted',
                  'userMachineExecutionApproved'):
        if f"'{field}': False" not in job or re.search(r"scope\[['\"]" + field + r"['\"]\]\s*=\s*True", job):
            raise ValueError('Offline scope changed')
    for required in ("SOURCE_SHA: ${{ github.sha }}", "'--source-commit', os.environ['SOURCE_SHA']",
                     "'--installed-tsf'", "'--frontend'", 'YimeTouchFrontendEditTests.exe',
                     'installed-18u-x64-test-package-${{ github.sha }}',
                     'installed-18u-compile-evidence-${{ github.sha }}'):
        if required not in job:
            raise ValueError('Matching-source package or memory regression missing')
    # Maintenance executables may be compiled and packaged, never run here.
    if re.search(r"['\"][^'\"\n]*(?:Yime18uProductRegistration|YimeTouchRegisteredFormalHostTests|Yime18uInstalledRuntime)\.exe['\"]\s*,\s*['\"](?:register|unregister|--installed-host-check)", job):
        raise ValueError('Live lifecycle invocation is not an offline check')
    for required in ('  compile-arm64:', 'build_installed_18u_arm64.py',
                     'installed-18u-arm64-test-package-${{ github.sha }}',
                     'test_arm64_frontend_package.py', 'Test-18uArm64Contracts.ps1',
                     'Test-18uLegacyStartup.ps1', 'TestInstallationArchitectureAndLegacyDescriptorRefusedBeforeStart',
                     'Yime18uInstallationProofTests.exe'):
        if required not in text:
            raise ValueError('ARM64 package or maintenance regression missing')
    marker = re.search(r"marker = '(PASS frontend ownership:[^']+)'", text)
    fixture = (ROOT / 'installer/simple/tests/Test-Installed18uFrontend.ps1').read_text(encoding='utf-8-sig')
    if not marker or marker[1] not in fixture:
        raise ValueError('Frontend fixture success marker disagrees with CI')


class Installed18uWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_text(encoding='utf-8')

    def test_current_delivery(self):
        validate(self.text)

    def test_main_events_required(self):
        for before, after in [('branches: [main,', 'branches: [other,'),
                              ('branches: [main]', 'branches: [other]'),
                              ('  pull_request:', '  pull_request_target:')]:
            with self.subTest(before=before), self.assertRaises(ValueError):
                validate(self.text.replace(before, after, 1))

    def test_legacy_job_gate_rejected(self):
        with self.assertRaises(ValueError):
            validate(self.text.replace('  compile-offline:\n', "  compile-offline:\n    if: github.event_name == 'push'\n"))

    def test_matching_source_and_memory_checks_required(self):
        for value in ("'--source-commit', os.environ['SOURCE_SHA']", "'--frontend'",
                      'YimeTouchFrontendEditTests.exe', 'installed-18u-x64-test-package-${{ github.sha }}'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate(self.text.replace(value, 'omitted'))

    def test_offline_scope_cannot_claim_installation(self):
        with self.assertRaises(ValueError):
            validate(self.text.replace("'installerExecuted': False", "'installerExecuted': True"))

    def test_lifecycle_execution_rejected(self):
        with self.assertRaises(ValueError):
            validate(self.text + "\n          subprocess.run(['Yime18uProductRegistration.exe', 'register', dll])\n")

    def test_arm64_delivery_and_regressions_required(self):
        for value in ('compile-arm64:', 'build_installed_18u_arm64.py',
                      'Test-18uLegacyStartup.ps1', 'Yime18uInstallationProofTests.exe'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate(self.text.replace(value, 'omitted'))

    def test_stale_frontend_success_marker_rejected(self):
        with self.assertRaises(ValueError):
            validate(self.text.replace('PASS frontend ownership: x64 and ARM64 complete inventories',
                                       'PASS frontend ownership: 1 complete and 8 refusals'))


if __name__ == '__main__':
    unittest.main()
