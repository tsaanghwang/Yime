"""Cheap scheduling regressions; no builds, installed products or network access.

This deliberately validates this repository's simple job/needs layout, not general
YAML. actionlint checks GitHub syntax separately. Mutations protect the expensive
work boundary and the success-only aggregate when jobs are split or reordered.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/ci.yaml'
QUICK = {'build-contract', 'lexicon-offline-tooling', 'rust-i686-host',
         'native-build', 'go-tests', 'real-rime-tests', 'go-race-msys2',
         'nsis-preflight'}
CONTRACTS = {'contract-tests', 'dp1-long-contracts'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def jobs(text):
    body = text.split('\njobs:\n', 1)[1]
    return {m[1]: m[0] for m in re.finditer(
        r'^  ([a-z][a-z0-9-]+):\n.*?(?=^  [a-z][a-z0-9-]+:|\Z)', body, re.M | re.S)}


def needs(job):
    match = re.search(r'^    needs: \[([^\]\n]*)\]$', job, re.M)
    return set(match[1].split(', ')) if match else set()


def validate(text):
    graph = jobs(text)
    expected = QUICK | CONTRACTS | {'installer-payload', 'release-sign-payload',
        'unsigned-installer-package', 'release-installer-package',
        'release-sign-installer', 'installer-package', 'core-build'}
    require(set(graph) == expected, 'Required CI stage missing or unreviewed stage added')
    for name, job in graph.items():
        timeout = re.search(r'^    timeout-minutes: ([0-9]+)$', job, re.M)
        require(timeout and 1 <= int(timeout[1]) <= 60, f'{name}: missing bounded timeout')
        require(needs(job) <= graph.keys(), f'{name}: unknown prerequisite')
        require('continue-on-error:' not in job, f'{name}: failures must propagate')
        if name in QUICK - {'build-contract'}:
            require(needs(job) == {'build-contract'}, f'{name}: bypasses cheap preflight')
        if name in QUICK | CONTRACTS | {'installer-payload'}:
            require(not re.search(r'^    if:', job, re.M), f'{name}: success gating overridden')
        if name in CONTRACTS:
            require(needs(job) == QUICK, f'{name}: bypasses quick regressions')
    require(needs(graph['installer-payload']) == QUICK | CONTRACTS,
            'Payload publication must require every regression stage')
    require(needs(graph['core-build']) == QUICK | CONTRACTS | {'installer-package'},
            'Protected aggregate must include every stage')
    core = graph['core-build']
    require('    if: ${{ always() }}' in core, 'Aggregate must run after failure/skip')
    for name in needs(core):
        match = re.search(r"^          ([A-Z_]+): \$\{\{ needs\['" +
                          re.escape(name) + r"'\]\.result \}\}$", core, re.M)
        require(match and f'          test "${match[1]}" = success' in core,
                f'Aggregate must reject failure/cancel/skip: {name}')
    require(needs(graph['unsigned-installer-package']) == {'installer-payload', 'nsis-preflight'},
            'Unsigned compiler preflight is not a prerequisite')
    require(needs(graph['release-installer-package']) == {'release-sign-payload', 'nsis-preflight'},
            'Tagged compiler preflight is not a prerequisite')
    native = graph['native-build']
    require('Stage native installer inputs' in native and
            'name: yime-native-${{ github.sha }}' in native,
            'Native checkpoint must be published in native-build')
    require('test-rime-pime-installer-receipt-transaction.ps1' not in native,
            'Long fixtures must not hold native artifacts hostage')
    require('test-rime-pime-staged-installer-build.ps1' in native,
            'Staged-build PE regression requires native artifacts')
    preflight = graph['build-contract']
    for command in ('test_workflow_contract.py', 'baseline.py',
                    'check-libime2-change-boundary.ps1', 'fetch-depth: 0'):
        require(command in preflight, f'Cheap preflight missing: {command}')
    long = graph['dp1-long-contracts']
    require('      fail-fast: true\n      max-parallel: 2\n' in long,
            'Long fixtures must stop sibling work on failure and bound parallelism')
    require('shell: [powershell, pwsh]' in long, 'Both PowerShell hosts are required')
    # Concurrency is deliberately separate per event; PR merge commits are not
    # equivalent to branch pushes. Manual/tag runs get unique, uncancelled groups.
    require("group: ${{ github.workflow }}-${{ github.event_name }}-${{ (github.event_name == 'workflow_dispatch' || startsWith(github.ref, 'refs/tags/')) && github.run_id || github.ref }}" in text,
            'Concurrency identity must protect manual/tag/PR runs')
    require("cancel-in-progress: ${{ github.event_name != 'workflow_dispatch' && !startsWith(github.ref, 'refs/tags/') }}" in text,
            'Only superseded automatic branch/PR runs may be cancelled')
    require('workflow_dispatch:' in text, 'Manual full validation must remain available')


class WorkflowContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = WORKFLOW.read_text(encoding='utf-8-sig')

    def test_current_workflow(self):
        validate(self.text)

    def reject_in_job(self, name, before, after):
        block = jobs(self.text)[name]
        self.assertIn(before, block)
        changed = self.text.replace(block, block.replace(before, after, 1), 1)
        with self.assertRaises(ValueError):
            validate(changed)

    def test_each_quick_job_requires_preflight(self):
        for name in QUICK - {'build-contract'}:
            with self.subTest(job=name):
                self.reject_in_job(name, '    needs: [build-contract]\n', '')

    def test_expensive_jobs_reject_each_missing_prerequisite(self):
        for name in CONTRACTS | {'installer-payload'}:
            for prerequisite in needs(jobs(self.text)[name]):
                with self.subTest(job=name, prerequisite=prerequisite):
                    old = re.search(r'^    needs: .*$', jobs(self.text)[name], re.M)[0]
                    remaining = sorted(needs(jobs(self.text)[name]) - {prerequisite})
                    self.reject_in_job(name, old, '    needs: [' + ', '.join(remaining) + ']')

    def test_aggregate_rejects_missing_success_assertion(self):
        for name in needs(jobs(self.text)['core-build']):
            var = re.search(r"([A-Z_]+): \$\{\{ needs\['" + re.escape(name) +
                            r"'\]\.result", jobs(self.text)['core-build'])[1]
            with self.subTest(job=name):
                self.reject_in_job('core-build', f'test "${var}" = success', ':')

    def test_failure_and_skip_bypasses_rejected(self):
        for name in CONTRACTS:
            self.reject_in_job(name, '    steps:', '    if: ${{ always() }}\n    steps:')
            self.reject_in_job(name, '    steps:', '    continue-on-error: true\n    steps:')

    def test_matrix_limits_and_timeout_cannot_disappear(self):
        for before, after in [('fail-fast: true', 'fail-fast: false'),
                              ('max-parallel: 2', 'max-parallel: 6'),
                              ('shell: [powershell, pwsh]', 'shell: [pwsh]'),
                              ('timeout-minutes: 60', 'timeout-minutes: 360')]:
            self.reject_in_job('dp1-long-contracts', before, after)

    def test_manual_and_tag_runs_cannot_be_cancelled_by_push(self):
        changed = re.sub(r'^  cancel-in-progress:.*$', '  cancel-in-progress: true', self.text, flags=re.M)
        with self.assertRaises(ValueError):
            validate(changed)


if __name__ == '__main__':
    unittest.main(verbosity=2)
