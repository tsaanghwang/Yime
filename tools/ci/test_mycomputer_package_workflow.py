"""Static contract for the sole approved compile/test/package workflow."""
import ast
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / '.github/workflows/mycomputer-activation-package.yml'


def scripts(text):
    lines = text.splitlines(); result = []; index = 0
    while index < len(lines):
        if lines[index] == '        run: |':
            index += 1; block = []
            while index < len(lines) and (lines[index].startswith('          ') or not lines[index].strip()):
                block.append(lines[index][10:]); index += 1
            result.append('\n'.join(block))
        else: index += 1
    return result


class PackageWorkflowContract(unittest.TestCase):
    def setUp(self): self.text = PATH.read_text(encoding='utf-8')
    def test_only_fixed_branch_push_and_read_permission(self):
        self.assertIn("branches: ['codex/18u-native-async-gates-20261102']", self.text)
        self.assertIn("if: github.event_name == 'push' && github.ref == 'refs/heads/codex/18u-native-async-gates-20261102'", self.text)
        self.assertIn('permissions:\n  contents: read\n', self.text)
        for forbidden in ['workflow_dispatch:', 'workflow_call:', 'pull_request:', 'contents: write', 'secrets:', 'secrets.']:
            self.assertNotIn(forbidden, self.text)
    def test_no_registration_or_old_workflow_calls(self):
        for forbidden in ['--register-once', '--recover', '--cleanup-only', 'regsvr32', 'Set-WinUserLanguageList', 'ActivateProfile', 'touch-bridge-registered-probe.yml', 'touch-bridge-language-prepare.yml', 'touch-bridge-language-inventory.yml']:
            self.assertNotIn(forbidden, self.text)
        self.assertNotRegex(self.text, r'uses:\s*\./\.github/workflows/')
    def test_exact_build_and_nonregister_test_gates(self):
        for required in ['-DYIME_TOUCH_PRODUCT=ON', '-DYIME_MYCOMPUTER_ACTIVATION_STAGE1=ON', "'YimeTextService18u', 'YimeMyComputerActivationStage1', 'MyComputerActivationPolicyTests'", 'test_mycomputer_activation_native.py', 'result.testsRun == 2 and not result.skipped', 'test_mycomputer_stage1_package', 'test_local_activation_evidence', 'result.testsRun == 0 or result.skipped']:
            self.assertIn(required, self.text)
        self.assertNotIn('continue-on-error:', self.text)
    def test_residue_fixture_drill_is_bounded_and_gates_the_package_upload(self):
        for required in ["'YimeResidueFixtureTests'", 'YimeResidueFixtureTests.exe', 'residue-fixture-drill.json', "report.get('registration') is not False", "'owned-shell-classified-snapshotted-removed'", "'foreign-language-kept'", "'foreign-category-kept'", "'foreign-profile-kept'", "'unknown-child-kept'", "'removal-of-absent-residue-refused'"]:
            self.assertIn(required, self.text)
        self.assertLess(self.text.index('Drill residue classification'), self.text.index('Upload the fixed development package'))
        self.assertLess(self.text.index('Validate the actual fixed package with its read-only collector'), self.text.index('Drill residue classification'))
    def test_python_blocks_parse_and_no_raw_powershell(self):
        blocks = scripts(self.text); self.assertGreaterEqual(len(blocks), 4)
        for block in blocks: ast.parse(block)
        self.assertIn('shell: python {0}', self.text)
        self.assertNotRegex(self.text, r'shell:\s*(pwsh|powershell)')
    def test_fixed_package_and_checked_signature_query(self):
        for required in ['build_mycomputer_stage1_package.py', 'collect_mycomputer_authenticode.ps1', 'run_checked.py', "'--edition', 'ps5'", "'--params-file'", "'--source-sha'", "'--signatures'", "'--job-helper'", 'test_collect_mycomputer_preflight', "report.get('caseCount') != 6"]:
            self.assertIn(required, self.text)
        self.assertIn('mycomputer-activation-protected-v2-x64-${{ github.sha }}', self.text)
    def test_v2_explicit_packaging_and_offline_only_companions(self):
        for required in ["'--package-version', 'v2'", "'--registration-runner'", "'--evidence-validator'", 'S3C_REGISTRATION_EXECUTION_GUARD.zh-CN.md', 'YimeMyComputerActivationProtected-v2-x64.zip', 'mycomputer-activation-development-package-v2', 'test_run_mycomputer_registration', 'test_windows_job_identity']:
            self.assertIn(required, self.text)
        self.assertNotIn('YimeMyComputerActivationStage1-x64.zip', self.text)
        # The execution orchestrator is a package input, never a CI command.
        self.assertIn("'--registration-runner', str(root / 'tools/ci/run_mycomputer_registration.py')", self.text)
        self.assertIn("'--pinned-registrations', str(root / 'tools/ci/mycomputer_recoverable_registrations.json')", self.text)
        for block in scripts(self.text):
            for node in ast.walk(ast.parse(block)):
                if isinstance(node, ast.List) and len(node.elts) > 1 and ast.unparse(node.elts[0]) == 'sys.executable':
                    self.assertNotIn('run_mycomputer_registration.py', ast.unparse(node.elts[1]))
    def test_actual_packaged_collector_readonly_gate(self):
        for required in ['Actual packaged read-only collector did not complete', "native.get('stage') != 'completed'", "['dllVerified', 'nativeX64', 'identityAbsent']", "native.get('actualDllActivationVerified') is not False", 'Read-only preflight emitted unexpected stderr', "'--manifest-sha256', manifest_hash", "process.get('treeStopped') is not True", "native.get('writesStarted') is not False", "native.get('prerequisitesSatisfied') is not False", "receipt.get('sourceCommit') != os.environ['PACKAGE_SOURCE_SHA']"]:
            self.assertIn(required, self.text)
    def test_evidence_always_preserved(self):
        self.assertIn('if: always()', self.text)
        self.assertIn('actions/upload-artifact@v6', self.text)
        self.assertIn('persist-credentials: false', self.text)
        self.assertIn('if-no-files-found: error', self.text)


if __name__ == '__main__': unittest.main()
