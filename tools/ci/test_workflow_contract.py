"""Check retained CI scheduling and complete success aggregation, without builds."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
REQUIRED = {'build-contract', 'lexicon-offline-tooling', 'rust-i686-host', 'native-build',
            'go-tests', 'real-rime-tests', 'go-race-msys2', 'shard-coverage', 'simple-installer'}

OPTIONAL_PROBE = 'one-shot-18u-registration-probe'
PROBE_PATH = './.github/workflows/touch-bridge-registered-probe.yml'
PROBE_GATE = ("github.event_name == 'workflow_dispatch' && "
              "github.ref == 'refs/heads/codex/18u-formal-tip-s3c-20261101' && "
              "inputs.confirm_18u_registration == 'once-18u-registration' && "
              "inputs.expected_18u_source_sha == github.sha && github.run_attempt == 1")

def job_blocks(text):
    if text.count("\njobs:\n") != 1: raise ValueError("Duplicate or absent jobs mapping")
    matches = list(re.finditer(r'^  ([a-z][a-z0-9-]+):\n.*?(?=^  [a-z][a-z0-9-]+:|\Z)', text.split('\njobs:\n')[1], re.M|re.S))
    jobs = {m[1]: m[0] for m in matches}
    if len(jobs) != len(matches): raise ValueError('Duplicate job')
    return jobs

def validate_probe_workflow(text):
    # One fixed local reusable workflow, not an arbitrary reusable-job exception.
    if text.count('\non:\n') != 1: raise ValueError('Duplicate or absent probe events')
    events = text.split('\non:\n')[1].split('\npermissions:')[0]
    if re.findall(r'^  ([a-z_]+):', events, re.M) != ['workflow_call']:
        raise ValueError('Registration probe may only be explicitly called')
    jobs = job_blocks(text)
    if set(jobs) != {'registration-probe'}: raise ValueError('Unexpected probe job')
    body = jobs['registration-probe']
    gate = PROBE_GATE.replace('inputs.confirm_18u_registration', 'inputs.confirm').replace('inputs.expected_18u_source_sha', 'inputs.expected_source_sha')
    if re.findall(r'^    if: (.*)$', body, re.M) != [gate]: raise ValueError('Weak probe callee gate')
    if not re.search(r'^    timeout-minutes: [1-9][0-9]?$', body, re.M): raise ValueError('Unbounded probe')
    if '    runs-on: windows-latest\n' not in body: raise ValueError('Unexpected probe runner')
    if 'permissions:\n  contents: read\n\n' not in text: raise ValueError('Probe permissions changed')
    if '  cancel-in-progress: false\n' not in text: raise ValueError('Registration cleanup could be superseded')

def validate(text):
    jobs = job_blocks(text)
    if set(jobs) != REQUIRED | {'core-build', OPTIONAL_PROBE}: raise ValueError('Missing or unexpected job')
    expected_probe = (f'  {OPTIONAL_PROBE}:\n'
                      f'    if: {PROBE_GATE}\n'
                      f'    uses: {PROBE_PATH}\n'
                      '    with:\n'
                      '      confirm: ${{ inputs.confirm_18u_registration }}\n'
                      '      expected_source_sha: ${{ inputs.expected_18u_source_sha }}')
    if jobs[OPTIONAL_PROBE].strip() != expected_probe.strip():
        raise ValueError('Registration caller must retain the exact one-shot gate and local target')
    dispatch = text.split('  workflow_dispatch:\n')[1].split('  push:')[0]
    for name in ('confirm_18u_registration', 'expected_18u_source_sha'):
        match = re.search(r'^      ' + name + r':\n(.*?)(?=^      [a-z_]+:|\Z)', dispatch, re.M|re.S)
        if not match or not all(value in match[1] for value in ("        default: ''\n", '        required: false\n', '        type: string\n')):
            raise ValueError('Probe dispatch input must default to disabled')
    for name, body in jobs.items():
        if name == OPTIONAL_PROBE: continue  # Reusable caller cannot specify timeout; callee is checked separately.
        if not re.search(r'^    timeout-minutes: [1-9][0-9]?$', body, re.M): raise ValueError('Unbounded job')
        match = re.search(r'^    needs: \[([^]]+)\]', body, re.M)
        dependencies = set(match[1].split(', ')) if match else set()
        if not dependencies <= jobs.keys(): raise ValueError('Dangling dependency')
        if OPTIONAL_PROBE in dependencies: raise ValueError('Optional registration must not gate retained Build jobs')
        if name == 'core-build' and dependencies != REQUIRED: raise ValueError('Incomplete aggregate')
    if "all(v['result']=='success'" not in jobs['core-build'] or 'toJSON(needs)' not in jobs['core-build']: raise ValueError('Aggregate permits failures')
    if 'cancel-in-progress:' not in text: raise ValueError('Superseded runs are not cancelled')
    if re.search(r'uses:\s+[^\s]+/\.github/workflows/', text.replace(jobs[OPTIONAL_PROBE], '')): raise ValueError('Unapproved reusable workflow')
    if 'run: python -X utf8 tools/ci/test_registration_query.py' not in jobs['native-build']:
        raise ValueError('Standalone registration-query regression is not covered')
    validate_probe_workflow((ROOT/PROBE_PATH).read_text())

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
        for clause in PROBE_GATE.split(' && '):
            changed=text.replace(PROBE_GATE, PROBE_GATE.replace(clause, 'true'))
            with self.subTest(clause=clause), self.assertRaises(ValueError): validate(changed)
        for before,after in [(PROBE_PATH, './.github/workflows/other.yml'),
                             ("        default: ''", "        default: 'once-18u-registration'"),
                             ('needs: [build-contract,', 'needs: [one-shot-18u-registration-probe, build-contract,')]:
            with self.subTest(before=before), self.assertRaises(ValueError): validate(text.replace(before,after))
    def test_extra_job_or_reusable_is_rejected(self):
        text=(ROOT/'.github/workflows/ci.yaml').read_text()
        with self.assertRaises(ValueError): validate(text+'\n  other-job:\n    timeout-minutes: 1\n')
        with self.assertRaises(ValueError): validate(text.replace('    name: core-build', '    uses: ./.github/workflows/other.yml\n    name: core-build'))
    def test_probe_callee_gate_cannot_be_weakened(self):
        text=(ROOT/PROBE_PATH).read_text()
        gate=PROBE_GATE.replace('inputs.confirm_18u_registration','inputs.confirm').replace('inputs.expected_18u_source_sha','inputs.expected_source_sha')
        for clause in gate.split(' && '):
            with self.subTest(clause=clause), self.assertRaises(ValueError): validate_probe_workflow(text.replace(gate,gate.replace(clause,'true')))
        with self.assertRaises(ValueError): validate_probe_workflow(text.replace('  workflow_call:', '  push:\n  workflow_call:'))

if __name__ == '__main__': unittest.main()
