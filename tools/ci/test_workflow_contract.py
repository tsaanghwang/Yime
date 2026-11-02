"""Check retained CI scheduling and complete success aggregation, without builds."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
REQUIRED = {'build-contract', 'lexicon-offline-tooling', 'rust-i686-host', 'native-build',
            'go-tests', 'real-rime-tests', 'go-race-msys2', 'shard-coverage', 'simple-installer'}

OPTIONAL_PROBE = 'one-shot-18u-registration-probe'
PROBE_PATH = './.github/workflows/touch-bridge-registered-probe.yml'
BASE_PROBE_GATE = ("github.event_name == 'workflow_dispatch' && "
              "github.ref == 'refs/heads/codex/18u-formal-tip-s3c-20261101' && "
              "inputs.confirm_18u_registration == 'once-18u-registration' && "
              "inputs.expected_18u_source_sha == github.sha && github.run_attempt == 1")

OPTIONAL_INVENTORY = 'one-shot-18u-language-inventory'
INVENTORY_PATH = './.github/workflows/touch-bridge-language-inventory.yml'
OPTIONAL_PREPARE = 'one-shot-18u-language-prepare'
PREPARE_PATH = './.github/workflows/touch-bridge-language-prepare.yml'

def caller_gate(confirm, value, others):
    gate = BASE_PROBE_GATE.replace('confirm_18u_registration', confirm).replace('once-18u-registration', value)
    exclusive = ''.join(" && inputs." + other + " == ''" for other in others)
    return gate.replace(' && inputs.expected_18u_source_sha', exclusive + ' && inputs.expected_18u_source_sha')

PROBE_OTHERS = ('confirm_18u_language_inventory', 'confirm_18u_language_prepare', 'confirm_18u_registry_adapter')
INVENTORY_OTHERS = ('confirm_18u_registration', 'confirm_18u_language_prepare', 'confirm_18u_registry_adapter')
PREPARE_OTHERS = ('confirm_18u_registration', 'confirm_18u_language_inventory', 'confirm_18u_registry_adapter')
PROBE_GATE = caller_gate('confirm_18u_registration', 'once-18u-registration', PROBE_OTHERS)
INVENTORY_GATE = caller_gate('confirm_18u_language_inventory', 'once-18u-language-inventory', INVENTORY_OTHERS)
PREPARE_GATE = caller_gate('confirm_18u_language_prepare', 'once-18u-language-prepare', PREPARE_OTHERS)
ADAPTER_PATH = './.github/workflows/owned-residue-registry-adapter.yml'
ADAPTER_OTHERS = ('confirm_18u_registration', 'confirm_18u_language_inventory', 'confirm_18u_language_prepare')
ADAPTER_GATE = caller_gate('confirm_18u_registry_adapter', 'once-18u-registry-adapter', ADAPTER_OTHERS)
OPTIONAL = {
    'one-shot-18u-registry-adapter': (ADAPTER_PATH, ADAPTER_GATE, 'confirm_18u_registry_adapter', 'registry-adapter', ADAPTER_OTHERS),
    OPTIONAL_PROBE: (PROBE_PATH, PROBE_GATE, 'confirm_18u_registration', 'registration-probe', PROBE_OTHERS),
    OPTIONAL_INVENTORY: (INVENTORY_PATH, INVENTORY_GATE, 'confirm_18u_language_inventory', 'language-inventory', INVENTORY_OTHERS),
    OPTIONAL_PREPARE: (PREPARE_PATH, PREPARE_GATE, 'confirm_18u_language_prepare', 'language-prepare', PREPARE_OTHERS),
}

def callee_gate(spec):
    _, gate, confirm, _, others = spec
    gate = (gate.replace('inputs.' + confirm, 'inputs.confirm')
            .replace('inputs.expected_18u_source_sha', 'inputs.expected_source_sha'))
    for other in others:
        gate = gate.replace('inputs.' + other, 'github.event.inputs.' + other)
    # Retain existing callee contracts; new fourth mutual exclusion is enforced
    # at their only approved callers, without changing old workflows.
    if spec[0] != ADAPTER_PATH:
        gate = gate.replace(" && github.event.inputs.confirm_18u_registry_adapter == ''", '')
    return gate

def job_blocks(text):
    if text.count("\njobs:\n") != 1: raise ValueError("Duplicate or absent jobs mapping")
    matches = list(re.finditer(r'^  ([a-z][a-z0-9-]+):\n.*?(?=^  [a-z][a-z0-9-]+:|\Z)', text.split('\njobs:\n')[1], re.M|re.S))
    jobs = {m[1]: m[0] for m in matches}
    if len(jobs) != len(matches): raise ValueError('Duplicate job')
    return jobs

def validate_probe_workflow(text, spec=OPTIONAL[OPTIONAL_PROBE]):
    # Only the four fixed local reusable workflows, never an arbitrary exception.
    if text.count('\non:\n') != 1: raise ValueError('Duplicate or absent probe events')
    events = text.split('\non:\n')[1].split('\npermissions:')[0]
    if re.findall(r'^  ([a-z_]+):', events, re.M) != ['workflow_call']:
        raise ValueError('Optional probes may only be explicitly called')
    jobs = job_blocks(text)
    if set(jobs) != {spec[3]}: raise ValueError('Unexpected probe job')
    body = jobs[spec[3]]
    gate = callee_gate(spec)
    if re.findall(r'^    if: (.*)$', body, re.M) != [gate]: raise ValueError('Weak probe callee gate')
    if not re.search(r'^    timeout-minutes: [1-9][0-9]?$', body, re.M): raise ValueError('Unbounded probe')
    if '    runs-on: windows-latest\n' not in body: raise ValueError('Unexpected probe runner')
    if 'permissions:\n  contents: read\n\n' not in text: raise ValueError('Probe permissions changed')
    if '  cancel-in-progress: false\n' not in text: raise ValueError('Registration cleanup could be superseded')

def validate(text):
    jobs = job_blocks(text)
    if set(jobs) != REQUIRED | {'core-build'} | set(OPTIONAL): raise ValueError('Missing or unexpected job')
    for name, spec in OPTIONAL.items():
        path, gate, confirm, _, _ = spec
        expected = (f'  {name}:\n'
                    f'    if: {gate}\n'
                    f'    uses: {path}\n'
                    '    with:\n'
                    f'      confirm: ${{{{ inputs.{confirm} }}}}\n'
                    '      expected_source_sha: ${{ inputs.expected_18u_source_sha }}')
        if jobs[name].strip() != expected.strip():
            raise ValueError('Optional caller must retain exact mutually exclusive gate and local target')
    dispatch = text.split('  workflow_dispatch:\n')[1].split('  push:')[0]
    for name in ('confirm_18u_registration', 'confirm_18u_language_inventory', 'confirm_18u_language_prepare', 'confirm_18u_registry_adapter', 'expected_18u_source_sha'):
        match = re.search(r'^      ' + name + r':\n(.*?)(?=^      [a-z0-9_]+:|\Z)', dispatch, re.M|re.S)
        if not match or not all(value in match[1] for value in ("        default: ''\n", '        required: false\n', '        type: string\n')):
            raise ValueError('Probe dispatch input must default to disabled')
    for name, body in jobs.items():
        if name in OPTIONAL: continue  # Reusable caller cannot specify timeout; callee is checked separately.
        if not re.search(r'^    timeout-minutes: [1-9][0-9]?$', body, re.M): raise ValueError('Unbounded job')
        match = re.search(r'^    needs: \[([^]]+)\]', body, re.M)
        dependencies = set(match[1].split(', ')) if match else set()
        if not dependencies <= jobs.keys(): raise ValueError('Dangling dependency')
        if dependencies & OPTIONAL.keys(): raise ValueError('Optional jobs must not gate retained Build jobs')
        if name == 'core-build' and dependencies != REQUIRED: raise ValueError('Incomplete aggregate')
    if "all(v['result']=='success'" not in jobs['core-build'] or 'toJSON(needs)' not in jobs['core-build']: raise ValueError('Aggregate permits failures')
    if 'cancel-in-progress:' not in text: raise ValueError('Superseded runs are not cancelled')
    retained = text
    for name in OPTIONAL: retained = retained.replace(jobs[name], '')
    if re.search(r'uses:\s+[^\s]+/\.github/workflows/', retained): raise ValueError('Unapproved reusable workflow')
    if 'run: python -X utf8 tools/ci/test_registration_query.py' not in jobs['native-build']:
        raise ValueError('Standalone registration-query regression is not covered')
    for spec in OPTIONAL.values(): validate_probe_workflow((ROOT/spec[0]).read_text(), spec)

class WorkflowTests(unittest.TestCase):
    def test_current(self): validate((ROOT/'.github/workflows/ci.yaml').read_text())
    def test_missing_and_weakened_aggregate(self):
        text=(ROOT/'.github/workflows/ci.yaml').read_text()
        for changed in [text.replace('native-build, ', ''), text.replace("=='success'", "!='failure'")]:
            with self.assertRaises(ValueError): validate(changed)
    def test_registration_query_regression_cannot_be_omitted(self):
        text=(ROOT/'.github/workflows/ci.yaml').read_text()
        with self.assertRaises(ValueError):
            validate(text.replace('run: python -X utf8 tools/ci/test_registration_query.py', 'run: echo omitted'))

    def test_probe_gate_cannot_be_weakened(self):
        text=(ROOT/'.github/workflows/ci.yaml').read_text()
        for name, spec in OPTIONAL.items():
            path, gate, confirm, _, _ = spec
            for clause in gate.split(' && '):
                changed=text.replace(gate, gate.replace(clause, 'true'))
                self.assertNotEqual(changed, text)
                with self.subTest(job=name, clause=clause), self.assertRaises(ValueError): validate(changed)
            for before,after in [(path, './.github/workflows/other.yml'),
                                 ('needs: [build-contract,', f'needs: [{name}, build-contract,')]:
                with self.subTest(job=name, before=before), self.assertRaises(ValueError): validate(text.replace(before,after))
            # Change each optional input independently, not all defaults at once.
            start=text.index('      '+confirm+':\n')
            end=text.index('        type: string',start)
            changed=text[:start]+text[start:end].replace("default: ''", "default: 'enabled'")+text[end:]
            with self.subTest(input=confirm), self.assertRaises(ValueError): validate(changed)
    def test_extra_job_or_reusable_is_rejected(self):
        text=(ROOT/'.github/workflows/ci.yaml').read_text()
        with self.assertRaises(ValueError): validate(text+'\n  other-job:\n    timeout-minutes: 1\n')
        with self.assertRaises(ValueError): validate(text.replace('    name: core-build', '    uses: ./.github/workflows/other.yml\n    name: core-build'))
    def test_probe_callee_gate_cannot_be_weakened(self):
        for name,spec in OPTIONAL.items():
            text=(ROOT/spec[0]).read_text()
            gate=callee_gate(spec)
            for clause in gate.split(' && '):
                changed=text.replace(gate,gate.replace(clause,'true'))
                self.assertNotEqual(changed, text)
                with self.subTest(job=name, clause=clause), self.assertRaises(ValueError):
                    validate_probe_workflow(changed,spec)
            with self.assertRaises(ValueError): validate_probe_workflow(text.replace('  workflow_call:', '  push:\n  workflow_call:'),spec)


class AdapterWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.text = (ROOT / ADAPTER_PATH).read_text()
    def execution_block(self):
        import ast
        lines = self.text.splitlines(); blocks = []; i = 0
        while i < len(lines):
            if lines[i] == '        run: |':
                i += 1; block = []
                while i < len(lines) and (lines[i].startswith('          ') or not lines[i].strip()):
                    block.append(lines[i][10:]); i += 1
                code = '\n'.join(block); ast.parse(code); blocks.append(code)
            else: i += 1
        return next(code for code in blocks if 'def validate_adapter(' in code)
    def test_explicit_single_target_and_execution_only(self):
        self.execution_block()
        self.assertIn("'-DYIME_OWNED_RESIDUE_REGISTRY_TESTS=ON'", self.text)
        self.assertIn("'--target', 'YimeOwnedResidueRegistryTests'", self.text)
        self.assertEqual(self.text.count('state = run_once('), 1)
        self.assertIn('result.testsRun == 2 and not result.skipped', self.text)
        self.assertIn('if: always()', self.text)
        for forbidden in ['--register-once', '--recover', 'regsvr32', 'Set-WinUserLanguageList', 'RegDeleteTree', 'SetSecurityInfo', '-DYIME_TOUCH_PRODUCT=ON', 'continue-on-error:']:
            self.assertNotIn(forbidden, self.text)
    def test_real_execution_block_with_fake_owned_runner(self):
        import copy, json, os, sys, tempfile
        from unittest.mock import patch
        sys.path.insert(0, str(ROOT / 'tools/ci'))
        import windows_job_once
        root = 'HKCU\\Software\\YimeOwnedResidueAdapterTest-{12345678-1234-1234-1234-123456789abc}'
        cases = ['absent', 'empty', 'enable-dword-zero', 'extra-value', 'subkey', 'query-access-denied', 'actual-view-observation', 'empty-disabled-delete', 'unexpected-shape-rejected', 'partial-delete-failure-stops']
        before = dict(schema='owned-residue-registry-test-v1', event='before-first-write', root=root)
        final = dict(schema=before['schema'], event='result', root=root, status='passed', writesAttempted=True, creationUnknown=False, cleanupVerified=True, view32Aliases64Observed=False, atomicCompareDelete=False, firstFailure=None, cleanupFailure=None, completedCases=cases)
        variants = [('pass', [before, final], False, True),
                    ('missing-case', [before, dict(final, completedCases=cases[:-1])], False, False),
                    ('cleanup-failed', [before, dict(final, cleanupVerified=False)], False, False),
                    ('timeout', [before, final], True, False),
                    ('missing-before-write', [final], False, False),
                    ('wrong-root', [before, dict(final, root='HKCU\\Software\\other')], False, False),
                    ('ownership-unknown', [before, dict(final, creationUnknown=True)], False, False),
                    ('duplicate-event', [before, before, final], False, False)]
        original = Path.cwd(); code = self.execution_block()
        for label, rows, timeout, expected in variants:
            with self.subTest(case=label), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                evidence = work / '.generated/registry-adapter-evidence'; evidence.mkdir(parents=True)
                (evidence / 'containment.json').write_text(json.dumps(dict(testsRun=2, skipped=0, passed=True)))
                binary = work / '.generated/registry-adapter-build/Release/YimeOwnedResidueRegistryTests.exe'; binary.parent.mkdir(parents=True); binary.write_bytes(b'non-executable-fixture')
                calls = []
                def fake(command, cwd, stdout, stderr, deadline, on_root_created=None):
                    calls.append(command)
                    identity = dict(pid=123, creationFileTime='123456789')
                    on_root_created(identity)
                    Path(stdout).write_text('\n'.join(json.dumps(row) for row in rows)+'\n')
                    Path(stderr).write_bytes(b'')
                    return dict(started=True, treeStopped=True, timedOut=timeout, errorCode=None, exitCode=0, rootIdentity=identity)
                env = dict(ADAPTER_SOURCE_SHA='a'*40, ADAPTER_EXPECTED_SHA='a'*40, ADAPTER_RUN_ID='123', ADAPTER_RUN_ATTEMPT='1')
                try:
                    os.chdir(work)
                    with patch.dict(os.environ, env), patch('subprocess.check_output', return_value='a'*40+'\n'), patch.object(windows_job_once, 'run_once', side_effect=fake):
                        if expected: exec(compile(code, '<adapter-workflow>', 'exec'), {})
                        else:
                            with self.assertRaises(SystemExit): exec(compile(code, '<adapter-workflow>', 'exec'), {})
                    self.assertEqual(len(calls), 1)
                    self.assertEqual(calls[0][1:], ['--confirm-disposable-hkcu-adapter-test'])
                    report = json.loads((evidence / 'result.json').read_text())
                    self.assertEqual(report['status'], 'passed' if expected else 'failed')
                    self.assertEqual(report['cleanupVerified'], expected)
                    if not expected: self.assertTrue(report.get('failureReason'))
                    self.assertFalse(report['atomicCompareDelete']); self.assertFalse(report['oldV2RecoveryValidated'])
                    self.assertTrue((evidence / 'stdout.jsonl').is_file())
                finally: os.chdir(original)

if __name__ == '__main__': unittest.main()
