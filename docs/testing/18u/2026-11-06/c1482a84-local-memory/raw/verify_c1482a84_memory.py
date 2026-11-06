import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path('C:/dev/Yime')
HOME = Path(__file__).parent
OUT = HOME / 'c1482a84-local-memory-regressions'
BUILD = ROOT / '.generated/c1482a84-memory-regressions-20261106'
SHA = 'c1482a847e98ce756ecf6d3e5e9988c782d02322'

def git(*args):
    return subprocess.check_output(['git', '-c', 'core.fsmonitor=false', *args], cwd=ROOT)

def digest(p):
    with p.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def snapshot():
    assert git('rev-parse', 'HEAD').decode().strip() == SHA
    assert git('branch', '--show-current').decode().strip() == 'main'
    previous = json.loads((HOME / 'pr105-main-sync-after.json').read_text())
    evidence = {p: digest(Path(p)) for p in previous['evidence']}
    assert evidence == previous['evidence'], 'Original evidence changed'
    names = git('ls-files', '--others', '--exclude-standard', '-z').decode().split('\0')
    untracked = {n: {'sha256': digest(ROOT / n), 'bytes': (ROOT / n).stat().st_size} for n in names if n}
    assert untracked == previous['untracked'], 'Retained untracked files changed'
    source_paths = ['go-backend/input_methods/yime/librime.go', 'go-backend/input_methods/yime/librime_memory_windows_test.go', 'YimeTextServiceExperiment/TouchFrontendEndpoint.cpp', 'YimeTextServiceExperiment/tests/TouchFrontendEditTests.cpp', 'YimeTextServiceExperiment/CMakeLists.txt']
    return {'sha': SHA, 'branch': 'main', 'status': git('status', '--porcelain=v1', '-z', '--untracked-files=all').decode(), 'diff': git('diff', '--binary').hex(), 'cachedDiff': git('diff', '--cached', '--binary').hex(), 'untracked': untracked, 'evidence': evidence, 'sources': {p: digest(ROOT / p) for p in source_paths}}

stage = sys.argv[1]
if stage == 'before':
    state = snapshot()
    assert not state['diff'] and not state['cachedDiff'], 'Tracked edits must not enter validation'
    OUT.mkdir(exist_ok=False)
    (OUT / 'before.json').write_text(json.dumps(state, indent=2), encoding='utf-8')
    print('Before: main c1482a84; 174 untracked files and 41 original evidence files match retained hashes')
    sys.exit(0)
if stage == 'after':
    state = snapshot()
    assert state == json.loads((OUT / 'before.json').read_text()), 'Before/after mismatch'
    (OUT / 'after.json').open('x', encoding='utf-8').write(json.dumps(state, indent=2))
    rows = [digest(p) + '  ' + p.name for p in sorted(OUT.iterdir()) if p.is_file()]
    (OUT / 'SHA256SUMS.txt').open('x', encoding='utf-8', newline='\n').write('\n'.join(rows) + '\n')
    print('After: source/status unchanged; 174 untracked files and 41 original evidence files unchanged; new manifest entries:', len(rows))
    sys.exit(0)

assert git('rev-parse', 'HEAD').decode().strip() == SHA
env = os.environ.copy()
env.update(CGO_ENABLED='1', CC='gcc', GOCACHE=str(ROOT / '.tmp/gocache'), GOTMPDIR=str(ROOT / '.tmp/go-tmp'))
env['PATH'] = 'C:/msys64/ucrt64/bin;' + env['PATH']
tests = '^(TestRimeAPIFunctionAtValidatesDataSize|TestRimeAPIFunctionAtRejectsInvalidAddressAndIndex|TestCStringAtCopiesBoundedExternalMemory)$'
commands = {
    'rime-normal': ['go', 'test', './input_methods/yime', '-run', tests, '-count=1', '-timeout=120s', '-v'],
    'rime-race': ['go', 'test', '-race', './input_methods/yime', '-run', tests, '-count=20', '-timeout=120s', '-v'],
    'tsf-configure': ['cmake', '-S', str(ROOT / 'YimeTextServiceExperiment'), '-B', str(BUILD), '-G', 'Visual Studio 17 2022', '-A', 'x64', '-DYIME_TOUCH_PRODUCT=ON', '-DYIME_TOUCH_FRONTEND=ON'],
    'tsf-build': ['cmake', '--build', str(BUILD), '--config', 'Release', '--target', 'YimeTouchFrontendEditTests', '--parallel', '4'],
    'tsf-test': ['ctest', '--test-dir', str(BUILD), '-C', 'Release', '-R', '^YimeTouchFrontendEditTests$', '--output-on-failure', '-V'],
}
if stage == 'tsf-configure':
    assert not BUILD.exists(), 'Fresh build directory required'
cwd = ROOT / 'go-backend' if stage.startswith('rime-') else ROOT
command = commands[stage]
log = OUT / (stage + '.log')
with log.open('xb') as stream:
    result = subprocess.run(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
(OUT / (stage + '.json')).open('x', encoding='utf-8').write(json.dumps({'sourceCommit': SHA, 'command': command, 'cwd': str(cwd), 'exitCode': result.returncode, 'environment': {k: env[k] for k in ('CGO_ENABLED', 'CC', 'GOCACHE', 'GOTMPDIR')}, 'pathPrefix': 'C:/msys64/ucrt64/bin'}, indent=2))
print(log.read_text(encoding='utf-8', errors='replace')[-5000:])
print('Raw log:', log)
sys.exit(result.returncode)
