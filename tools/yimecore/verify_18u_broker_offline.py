"""Verify native 18u Broker initialization without a pipe, TIP or real host.

Runs only named offline Go tests, including the exported production constructor
and the full locked resource session. A passing emulation-rejection test does
not count as native acceptance: the actual Windows API observation must match
the requested architecture and report accepted=true.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
MODULE = 'github.com/tsaanghwang/Yime/go-backend'
GROUPS = {
    'cmd/yimebroker-18u': (
        'TestBrokerPlatform',
        'TestNativeArchitectureIdentity',
        'TestNativeArchitectureCurrentProcess',
        'TestBrokerRunReachesProductionInitialization',
    ),
    'internal/touchbroker': (
        'TestNewProductionArchitectureDescriptor',
        'TestNewProductionRejectsDescriptorMismatch',
        'TestNewProductionRejectsLoadedResourceMismatch',
        'TestFullResourceDedicatedBroker',
    ),
}
NATIVE_TEST = 'TestNativeArchitectureCurrentProcess'
MACHINES = {'amd64': 0x8664, 'arm64': 0xaa64}
NATIVE_MARKER = re.compile(r'GOARCH=(\w+) process=(0x[0-9a-f]+) native=(0x[0-9a-f]+) accepted=(true|false)')


def test_environment(architecture, data, inherited=None):
    env = dict(os.environ if inherited is None else inherited)
    if env.get('GOFLAGS', '').strip():
        raise ValueError('GOFLAGS must be empty; overlays and alternate execution are refused')
    env.update(GOENV='off', GOFLAGS='', GOOS='windows', GOARCH=architecture,
               CGO_ENABLED='0', GOTOOLCHAIN='local', YIME_18U_FULL_DATA=str(data))
    return env


def validate_go_environment(info, architecture):
    expected = {'GOOS': 'windows', 'GOARCH': architecture, 'GOHOSTOS': 'windows',
                'CGO_ENABLED': '0', 'GOTOOLCHAIN': 'local', 'GOFLAGS': ''}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError('Go environment does not match the explicit Windows test target')


def validate_events(raw, package, expected, architecture, require_native=False):
    events = [json.loads(line) for line in raw.splitlines() if line.strip()]
    if not events or any(not isinstance(event, dict) for event in events):
        raise ValueError('Missing or invalid Go test events')
    if any(event.get('Action') in ('fail', 'skip') for event in events):
        raise ValueError('A required offline test failed or skipped')
    if any(event.get('Package') != package for event in events):
        raise ValueError('Unexpected package in Go test evidence')
    wanted = Counter(expected)
    for action in ('run', 'pass'):
        actual = Counter(event['Test'] for event in events
                         if event.get('Action') == action and 'Test' in event
                         and '/' not in event['Test'])
        if actual != wanted:
            raise ValueError('Required top-level test execution/pass set is incomplete or duplicated')
    if sum(event.get('Action') == 'pass' and 'Test' not in event for event in events) != 1:
        raise ValueError('Missing successful package completion')
    native = None
    if require_native:
        observations = [match.groups() for event in events
                        if event.get('Action') == 'output' and event.get('Test') == NATIVE_TEST
                        for match in NATIVE_MARKER.finditer(event.get('Output', ''))]
        if len(observations) != 1:
            raise ValueError('Exactly one actual native architecture observation is required')
        arch, process, machine, accepted = observations[0]
        native = {'goarch': arch, 'processMachine': int(process, 16),
                  'nativeMachine': int(machine, 16), 'accepted': accepted == 'true'}
        if (arch != architecture or native['processMachine'] != 0
                or native['nativeMachine'] != MACHINES[architecture] or not native['accepted']):
            raise ValueError('Native acceptance refused: emulated, foreign or rejected process')
    return {'passedTests': list(expected), 'nativeArchitecture': native}


def run(architecture, data, output, go='go'):
    if architecture not in MACHINES:
        raise ValueError('Only amd64 and arm64 native targets are supported')
    data = Path(data).resolve(strict=True)
    output = Path(output).absolute()
    for path in (output, *output.parents):
        if path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction()):
            raise ValueError('Linked evidence output refused')
    output.mkdir(parents=True, exist_ok=False)
    report = {
        'schema': '18u-broker-native-offline-v1', 'status': 'failed',
        'architecture': architecture, 'startedUTC': datetime.now(timezone.utc).isoformat(),
        'scope': 'production-initialization-and-in-memory-resource-session-only',
        'productServiceExecuted': False, 'namedPipeOpened': False,
        'installationExecuted': False, 'registrationExecuted': False,
        'realHostExecuted': False, 'physicalAcceptance': False, 'tests': {},
    }
    try:
        report['sourceCommit'] = subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        report['sourceChanges'] = bool(subprocess.check_output(
            ['git', 'status', '--porcelain', '--untracked-files=normal'], cwd=ROOT, text=True).strip())
        # Reuse the existing content lock; never fetch or generate substitute data.
        sys.path.insert(0, str(ROOT / 'tools'))
        from touch_keyboard_resources import verify, LOCK
        verify(data)
        report['resources'] = json.loads(LOCK.read_text(encoding='utf-8'))['files']
        report['resourceLockSHA256'] = hashlib.sha256(LOCK.read_bytes()).hexdigest()
        env = test_environment(architecture, data)
        executable = shutil.which(go)
        if executable is None:
            raise ValueError('Existing Go executable is required')
        report['goExecutable'] = executable
        info = json.loads(subprocess.check_output(
            [executable, 'env', '-json', 'GOOS', 'GOARCH', 'GOHOSTOS', 'GOHOSTARCH',
             'CGO_ENABLED', 'GOTOOLCHAIN', 'GOFLAGS', 'GOVERSION', 'GOROOT'],
            cwd=ROOT / 'go-backend', env=env, text=True, timeout=30))
        report['goEnvironment'] = info
        validate_go_environment(info, architecture)
        for package, expected in GROUPS.items():
            log = output / (package.replace('/', '-') + '.jsonl')
            command = [executable, 'test', '-count=1', '-json', '-timeout=240s',
                       '-run', '^(' + '|'.join(expected) + ')$', './' + package]
            with log.open('wb') as stream:
                result = subprocess.run(command, cwd=ROOT / 'go-backend', env=env,
                                        stdout=stream, stderr=subprocess.STDOUT, timeout=300)
            if result.returncode:
                raise ValueError('Offline Go tests failed: ' + package + '; inspect ' + log.name)
            raw = log.read_text(encoding='utf-8')
            report['tests'][package] = validate_events(
                raw, MODULE + '/' + package, expected, architecture,
                require_native=package == 'cmd/yimebroker-18u')
            report['tests'][package]['logSHA256'] = hashlib.sha256(log.read_bytes()).hexdigest()
        report['status'] = 'passed'
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        report['finishedUTC'] = datetime.now(timezone.utc).isoformat()
        (output / 'result.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--architecture', choices=MACHINES, required=True)
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='Fresh evidence directory')
    parser.add_argument('--go', default='go')
    args = parser.parse_args()
    try:
        result = run(args.architecture, args.data, args.output, args.go)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print('FAIL native 18u Broker offline verification: ' + str(error), file=sys.stderr)
        return 1
    print('PASS native ' + args.architecture + ' 18u Broker production initialization; '
          + str(sum(len(group['passedTests']) for group in result['tests'].values()))
          + ' required tests; no installation, registration or real host')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
