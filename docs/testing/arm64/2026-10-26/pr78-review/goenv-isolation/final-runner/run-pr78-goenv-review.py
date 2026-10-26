from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import os
import subprocess
import sys
import uuid

repo = Path(__file__).resolve().parent.parent
git = r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe'
go = Path(r'C:\dev\Yime\.generated\arm64-toolchain\go1.25.14\go\bin\go.exe')
root = repo / '.tmp' / ('pr78-goenv-final-' + uuid.uuid4().hex[:8])
root.mkdir()
env = {k: v for k, v in os.environ.items() if not k.upper().startswith('YIME_')}
env.update(GOENV='off', GOFLAGS='', GOTOOLCHAIN='local', GOWORK='off')
env['PATH'] = str(go.parent) + os.pathsep + env.get('PATH', '')
for name in ('TEMP', 'TMP', 'LOCALAPPDATA', 'APPDATA', 'GOCACHE', 'GOTMPDIR'):
    folder = root / name.lower()
    folder.mkdir()
    env[name] = str(folder)
legacy = repo / '.tmp/yimecore-experiment' / ('speech-build-contract-goenv-' + uuid.uuid4().hex[:8])
legacy.parent.mkdir(exist_ok=True)
params = root / 'legacy.params.json'
params.write_text(json.dumps({'OutputRoot': str(legacy)}), encoding='utf-8')
cases = [('arm64-admission-and-go-environment', 'tools/yimecore/test-arm64-speech-admission.ps1', 'ps7', []),
         ('arm64-build-scope', 'tools/yimecore/test-arm64-build-scope.ps1', 'ps7', []),
         ('platform-contract', 'tools/yimecore/test-platform-experiment.ps1', 'ps7', []),
         ('legacy-speech-build', 'tools/yimecore/test-local-product-speech-build.ps1', 'ps5', ['--params-file', str(params)])]
changed = subprocess.check_output([git, 'diff', '--name-only', 'HEAD', '--', 'tools/yimecore'], cwd=repo, text=True).splitlines()
added = subprocess.check_output([git, 'ls-files', '--others', '--exclude-standard', 'tools/yimecore'], cwd=repo, text=True).splitlines()
paths = sorted(set(changed + added + [case[1] for case in cases]))
source_hashes = {p: hashlib.sha256((repo / p).read_bytes()).hexdigest() for p in paths}
result = {'schema_version': 'yimecore-pr78-goenv-review-run-v1',
          'started_at': datetime.now(timezone.utc).isoformat(),
          'base_commit': subprocess.check_output([git, 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
          'published_base_commit': '35cc358a0fbc9464e72ca0bd8cd2010d20ee1a5d',
          'go_executable': str(go), 'working_patch_inputs': source_hashes, 'tests': [],
          'scope': 'Synthetic Go environment/admission/platform contracts; no product build, registration, installation or live input'}
identity = subprocess.run([str(go), 'version'], cwd=repo, env=env, capture_output=True)
result['go_version'] = {'exit_code': identity.returncode, 'stdout': identity.stdout.decode('utf-8'), 'stderr': identity.stderr.decode('utf-8')}
assert identity.returncode == 0 and b'windows/arm64' in identity.stdout
print('Evidence: ' + str(root), flush=True)
for name, script, edition, extra in cases:
    command = [sys.executable, '-X', 'utf8', 'tools/powershell/run_checked.py', '--script', script, '--edition', edition, *extra]
    with (root / (name + '.stdout.txt')).open('xb') as out, (root / (name + '.stderr.txt')).open('xb') as err:
        process = subprocess.run(command, cwd=repo, env=env, stdout=out, stderr=err)
    result['tests'].append({'name': name, 'command': command, 'exit_code': process.returncode,
                            'stdout': name + '.stdout.txt', 'stderr': name + '.stderr.txt'})
    print(name + ': exit ' + str(process.returncode), flush=True)
    print((root / (name + '.stdout.txt')).read_text(encoding='utf-8', errors='replace')[-2200:], flush=True)
result['source_unchanged_during_tests'] = all(hashlib.sha256((repo / p).read_bytes()).hexdigest() == digest for p, digest in source_hashes.items())
result['legacy_fixture_root'] = str(legacy)
result['passed'] = result['source_unchanged_during_tests'] and all(item['exit_code'] == 0 for item in result['tests'])
result['finished_at'] = datetime.now(timezone.utc).isoformat()
(root / 'summary.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
raise SystemExit(0 if result['passed'] else 1)
