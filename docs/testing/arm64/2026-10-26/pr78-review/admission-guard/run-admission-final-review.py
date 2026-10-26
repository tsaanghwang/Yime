from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import uuid

repo = Path(__file__).resolve().parent.parent
root = repo / '.tmp' / ('pr78-admission-final-' + uuid.uuid4().hex[:8])
root.mkdir()
env = {k: v for k, v in os.environ.items() if not k.upper().startswith('YIME_')}
for name in ('TEMP', 'TMP', 'LOCALAPPDATA', 'APPDATA'):
    folder = root / name.lower()
    folder.mkdir()
    env[name] = str(folder)
legacy = repo / '.tmp/yimecore-experiment' / ('speech-build-contract-pr78-' + uuid.uuid4().hex[:8])
legacy.parent.mkdir(exist_ok=True)
params = root / 'legacy.params.json'
params.write_text(json.dumps({'OutputRoot': str(legacy)}), encoding='utf-8')
cases = [('arm64-package-gate', 'tools/yimecore/test-arm64-speech-admission.ps1', 'ps7', []),
         ('legacy-speech-build', 'tools/yimecore/test-local-product-speech-build.ps1', 'ps5', ['--params-file', str(params)])]
result = {'reviewed_base_commit': '2b256afdeb45795aafcf11641ba04cba149acb46', 'working_patch_inputs': {}, 'tests': [],
          'scope': 'Synthetic admission envelopes and isolated staging contracts; no product build, registration, installation or live input'}
for name in ['build-arm64-product.ps1', 'local-product-speech-build.ps1', 'test-arm64-speech-admission.ps1']:
    path = repo / 'tools/yimecore' / name
    result['working_patch_inputs'][name] = hashlib.sha256(path.read_bytes()).hexdigest()
print('Evidence: ' + str(root), flush=True)
for name, script, edition, extra in cases:
    command = [sys.executable, '-X', 'utf8', 'tools/powershell/run_checked.py', '--script', script, '--edition', edition, *extra]
    with (root / (name + '.stdout.txt')).open('xb') as out, (root / (name + '.stderr.txt')).open('xb') as err:
        process = subprocess.run(command, cwd=repo, env=env, stdout=out, stderr=err)
    result['tests'].append({'name': name, 'command': command, 'exit_code': process.returncode,
                            'stdout': name + '.stdout.txt', 'stderr': name + '.stderr.txt'})
    print(name + ': exit ' + str(process.returncode), flush=True)
    print((root / (name + '.stdout.txt')).read_text(encoding='utf-8', errors='replace')[-1800:], flush=True)
result['legacy_fixture_root'] = str(legacy)
result['passed'] = all(item['exit_code'] == 0 for item in result['tests'])
(root / 'summary.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
raise SystemExit(0 if result['passed'] else 1)
