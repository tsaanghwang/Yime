"""Cheap scheduling regressions; no builds, installed products or network access.

This deliberately validates this repository's simple job/needs layout, not general
YAML. actionlint checks GitHub syntax separately. Mutations protect the expensive
work boundary and the success-only aggregate when jobs are split or reordered.
"""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/ci.yaml'
NSIS_ACTION = ROOT / '.github/actions/prepare-pinned-nsis/action.yml'
QUICK = {'build-contract', 'lexicon-offline-tooling', 'rust-i686-host',
         'native-build', 'go-tests', 'real-rime-tests', 'go-race-msys2',
         'nsis-preflight'}
CONTRACTS = {'contract-tests', 'dp1-long-contracts'}
AGGREGATES = {'shard-coverage'}
CONTROLLER_POLICY_CALLS = (
    r'& $ps5 -NoProfile -ExecutionPolicy Bypass -File .\tools\yimecore\test-local13-maintenance-preparation.ps1',
    'if ($LASTEXITCODE -ne 0) { throw "PowerShell 5.1 controller preparation policy test failed with exit code $LASTEXITCODE" }',
    r'          .\tools\yimecore\test-local13-maintenance-preparation.ps1',
)


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


def validate_nsis_action(text):
    for command in ('tools\\ci\\prepare-pinned-sevenzip.ps1',
                    '-BootstrapPath $bootstrap -ArchivePath $sevenZipArchive',
                    '-SevenZipRoot $sevenZip.Root',
                    'https://github.com/ip7z/7zip/releases/download/26.02/7zr.exe',
                    'https://github.com/ip7z/7zip/releases/download/26.02/7z2602-x64.exe',
                    "'sevenzip-root=' + $sevenZip.Root",
                    "'sevenzip-bootstrap=' + $bootstrap",
                    "'sevenzip-archive=' + $sevenZipArchive"):
        require(command in text, 'Pinned isolated 7-Zip bootstrap or handoff missing')
    require(text.index('tools\\ci\\prepare-pinned-sevenzip.ps1') <
            text.index('tools\\ci\\prepare-pinned-nsis.ps1'),
            'Pinned extractor must be prepared before NSIS')


def validate(text):
    graph = jobs(text)
    expected = QUICK | CONTRACTS | AGGREGATES | {'installer-payload', 'release-sign-payload',
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
        if name in QUICK | CONTRACTS | AGGREGATES | {'installer-payload'}:
            require(not re.search(r'^    if:', job, re.M), f'{name}: success gating overridden')
        if name in CONTRACTS:
            require(needs(job) == QUICK, f'{name}: bypasses quick regressions')
    require(needs(graph['shard-coverage']) == {'real-rime-tests', 'dp1-long-contracts'},
            'Coverage must wait for every shard family')
    require(needs(graph['installer-payload']) == QUICK | CONTRACTS | AGGREGATES,
            'Payload publication must require every regression stage')
    require(needs(graph['core-build']) == QUICK | CONTRACTS | AGGREGATES | {'installer-package'},
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
    for name in ('rust-i686-host', 'native-build'):
        for command in ('rustup toolchain install --help',
                        "$nonHostArgs = @()",
                        "if ($installHelp.Contains('--force-non-host')) { $nonHostArgs = @('--force-non-host') }",
                        'rustup toolchain install stable-i686-pc-windows-msvc --profile minimal @nonHostArgs',
                        "if ($LASTEXITCODE -ne 0) { throw 'Pinned i686 host toolchain installation failed.' }",
                        'rustup run stable-i686-pc-windows-msvc cargo --version',
                        "if ($LASTEXITCODE -ne 0) { throw 'Pinned i686 host toolchain cannot execute.' }"):
            require(command in graph[name], f'{name}: native i686 host installation compatibility lost')
    require('Stage native installer inputs' in native and
            'name: yime-native-${{ github.sha }}' in native,
            'Native checkpoint must be published in native-build')
    require('test-rime-pime-installer-receipt-transaction.ps1' not in native,
            'Long fixtures must not hold native artifacts hostage')
    require('test-rime-pime-staged-installer-build.ps1' in native,
            'Staged-build PE regression requires native artifacts')
    nsis = graph['nsis-preflight']
    require(nsis.count('test-prepare-pinned-sevenzip.ps1') == 2 and
            'PowerShell 5.1 pinned 7-Zip preparation test failed with exit code $LASTEXITCODE' in nsis and
            nsis.count('-SevenZipRoot $env:SEVENZIP_ROOT') == 2 and
            nsis.count('-BootstrapPath $env:SEVENZIP_BOOTSTRAP -ArchivePath $env:SEVENZIP_ARCHIVE') == 2,
            'NSIS regressions must exercise isolated pinned 7-Zip in both shells')
    for output in ('sevenzip-root', 'sevenzip-bootstrap', 'sevenzip-archive'):
        require('${{ steps.nsis.outputs.' + output + ' }}' in nsis,
                'NSIS bootstrap regression inputs must bind action outputs')
    preflight = graph['build-contract']
    for command in ('test_workflow_contract.py', 'baseline.py',
                    'test_shard_coverage.py',
                    'check-libime2-change-boundary.ps1', 'fetch-depth: 0'):
        require(command in preflight, f'Cheap preflight missing: {command}')
    for command in CONTROLLER_POLICY_CALLS:
        require(command in preflight, 'Reviewed controller policy must pass both shells before builds')
    require('test-local13-maintenance-preparation.ps1' not in graph['contract-tests'],
            'Controller policy should run once per shell in cheap preflight')
    long = graph['dp1-long-contracts']
    require('      fail-fast: true\n      max-parallel: 10\n' in long,
            'Long fixtures must stop sibling work on failure and bound parallelism')
    require('shell: [powershell, pwsh]' in long, 'Both PowerShell hosts are required')
    require('suite: [installer-transaction-0, installer-transaction-1, installer-transaction-2, receipt-store, evidence-archive]' in long,
            'All three transaction shards and both other suites are required')
    real = graph['real-rime-tests']
    require('        shard: [0, 1, 2]\n' in real and
            '        run: .\\tools\\test-real-rime.ps1 -ShardCount 3 -ShardIndex ${{ matrix.shard }}' in real and
            '          name: real-rime-${{ matrix.shard }}-${{ github.sha }}-${{ github.run_attempt }}' in real,
            'Real-Rime shard execution/evidence missing')
    lanes = json.loads((ROOT / 'tools/ci/contract-test-lanes.json').read_text())
    contract = graph['contract-tests']
    named = re.findall(r'^      - name: ([^\n]+)\n(.*?)(?=^      - |\Z)', contract, re.M | re.S)
    require(len(named) == len(lanes) and {name for name, _ in named} == set(lanes),
            'Contract test inventory missing or duplicated')
    for name, body in named:
        require(re.findall(r'^        if: (.+)$', body, re.M) == ["matrix.lane == '" + lanes[name] + "'"],
                'Contract test must run in exactly its reviewed lane')
    for job, dimension in ((real, 'shard: [0, 1, 2]'), (contract, 'lane: [core, package, maintenance]')):
        strategy = re.search(r'^    strategy:\n.*?(?=^    \S|\Z)', job, re.M | re.S)[0]
        require(strategy == '    strategy:\n      fail-fast: true\n      max-parallel: 3\n      matrix:\n        ' + dimension + '\n',
                'Parallel test matrix must be exact and complete')
    coverage = graph['shard-coverage']
    for required in ('pattern: real-rime-*-${{ github.sha }}-${{ github.run_attempt }}',
                     'pattern: dp1-contract-installer-transaction-*-${{ github.sha }}-${{ github.run_attempt }}',
                     'python tools/ci/verify_shard_coverage.py .tmp/shard-evidence --commit ${{ github.sha }}',
                     "if ($LASTEXITCODE -ne 0) { throw 'Required shard coverage did not pass' }"):
        require(required in coverage, 'Exact shard coverage gate missing')
    require(not re.search(r'^        if:', coverage, re.M), 'Coverage step may not be skipped')
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
        validate_nsis_action(NSIS_ACTION.read_text(encoding='utf-8-sig'))

    def test_nsis_preflight_cannot_drop_isolated_extractor_or_shell(self):
        for command in ('test-prepare-pinned-sevenzip.ps1',
                        '-SevenZipRoot $env:SEVENZIP_ROOT',
                        '${{ steps.nsis.outputs.sevenzip-root }}',
                        'PowerShell 5.1 pinned 7-Zip preparation test failed with exit code $LASTEXITCODE'):
            with self.subTest(command=command):
                self.reject_in_job('nsis-preflight', command, '')

    def test_nsis_action_cannot_fall_back_to_host_extractor(self):
        action = NSIS_ACTION.read_text(encoding='utf-8-sig')
        for command in ('tools\\ci\\prepare-pinned-sevenzip.ps1',
                        '-SevenZipRoot $sevenZip.Root',
                        "'sevenzip-root=' + $sevenZip.Root"):
            with self.subTest(command=command), self.assertRaises(ValueError):
                validate_nsis_action(action.replace(command, '', 1))

    def test_i686_host_install_capability_and_execution_cannot_disappear(self):
        for name in ('rust-i686-host', 'native-build'):
            for command in ("$nonHostArgs = @()", "if ($installHelp.Contains('--force-non-host')) { $nonHostArgs = @('--force-non-host') }",
                            'rustup toolchain install stable-i686-pc-windows-msvc --profile minimal @nonHostArgs',
                            'rustup run stable-i686-pc-windows-msvc cargo --version'):
                with self.subTest(job=name, command=command):
                    self.reject_in_job(name, command, '')

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
        for name in CONTRACTS | AGGREGATES | {'installer-payload'}:
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
        for name in CONTRACTS | AGGREGATES:
            self.reject_in_job(name, '    steps:', '    if: ${{ always() }}\n    steps:')
            self.reject_in_job(name, '    steps:', '    continue-on-error: true\n    steps:')

    def test_matrix_limits_and_timeout_cannot_disappear(self):
        for before, after in [('fail-fast: true', 'fail-fast: false'),
                              ('max-parallel: 10', 'max-parallel: 2'),
                              ('max-parallel: 10', 'max-parallel: 11'),
                              ('shell: [powershell, pwsh]', 'shell: [pwsh]'),
                              ('timeout-minutes: 60', 'timeout-minutes: 360')]:
            self.reject_in_job('dp1-long-contracts', before, after)

    def test_parallel_shards_and_coverage_cannot_be_skipped(self):
        for name, before, after in [
            ('real-rime-tests', 'shard: [0, 1, 2]', 'shard: [0, 1]'),
            ('real-rime-tests', '-ShardCount 3', '-ShardCount 1'),
            ('contract-tests', 'lane: [core, package, maintenance]', 'lane: [core, package]'),
            ('contract-tests', "if: matrix.lane == 'core'", "if: matrix.lane == 'missing'"),
            ('shard-coverage', 'verify_shard_coverage.py', 'ignore_coverage.py'),
            ('shard-coverage', '--commit ${{ github.sha }}', '--commit stale'),
        ]:
            with self.subTest(name=name, before=before):
                self.reject_in_job(name, before, after)

    def test_controller_policy_cannot_move_after_expensive_work_or_lose_a_shell(self):
        for command in CONTROLLER_POLICY_CALLS:
            with self.subTest(command=command):
                self.reject_in_job('build-contract', command, '')

    def test_manual_and_tag_runs_cannot_be_cancelled_by_push(self):
        changed = re.sub(r'^  cancel-in-progress:.*$', '  cancel-in-progress: true', self.text, flags=re.M)
        with self.assertRaises(ValueError):
            validate(changed)


if __name__ == '__main__':
    unittest.main(verbosity=2)
