from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import uuid

repo = Path(__file__).resolve().parent.parent
root = repo / '.tmp' / ('pr78-multiple-go-' + uuid.uuid4().hex[:8])
root.mkdir()
shadow = root / 'shadow'
shadow.mkdir()
(shadow / 'go.exe').write_bytes(b'')
real_go = Path(r'C:\dev\Yime\.generated\arm64-toolchain\go1.25.14\go\bin\go.exe')
env = os.environ.copy()
env.update(GOENV='off', GOFLAGS='', GOTOOLCHAIN='local', GOWORK='off')
env['PATH'] = str(real_go.parent) + os.pathsep + str(shadow) + os.pathsep + env.get('PATH', '')
probe = root / 'verify-path.ps1'
probe.write_text("$ErrorActionPreference='Stop'\n$matches=@(Get-Command go -CommandType Application -ErrorAction Stop)\nif($matches.Count -lt 2){throw 'Multiple Go candidates were not reproduced'}\n$matches | ForEach-Object {$_.Source}\n", encoding='utf-8')
inputs = ['tools/yimecore/arm64-go-environment.ps1', 'tools/yimecore/build-arm64-product.ps1', 'tools/yimecore/development-scope.ps1', 'tools/yimecore/test-arm64-go-environment.ps1', 'tools/yimecore/test-arm64-speech-admission.ps1']
record = {'base_local_commit': 'f7ee8d60e9b0043be541fd6ded5cc752626ef64f', 'base_remote_commit': 'cbdf8266609decded743971bcc8edfa40773cdc0',
          'working_patch_inputs': {p: hashlib.sha256((repo/p).read_bytes()).hexdigest() for p in inputs},
          'scope': 'Multiple PATH candidates for Go; empty shadow executable must never execute; synthetic Go env/list only',
          'ci_failure': {'run_id': 40362619582, 'job_id': 121712308489}, 'tests': []}
print('Evidence: ' + str(root), flush=True)
for name, script in [('verify-multiple-path-candidates', str(probe)), ('arm64-admission-and-go-environment', 'tools/yimecore/test-arm64-speech-admission.ps1')]:
    command = [sys.executable, '-X', 'utf8', 'tools/powershell/run_checked.py', '--script', script, '--edition', 'ps7']
    with (root/(name+'.stdout.txt')).open('xb') as out, (root/(name+'.stderr.txt')).open('xb') as err:
        result = subprocess.run(command, cwd=repo, env=env, stdout=out, stderr=err)
    record['tests'].append({'name': name, 'command': command, 'exit_code': result.returncode})
    print(name, result.returncode, (root/(name+'.stdout.txt')).read_text(encoding='utf-8', errors='replace'), flush=True)
    if result.returncode != 0:
        break
record['passed'] = len(record['tests']) == 2 and all(t['exit_code'] == 0 for t in record['tests'])
record['source_unchanged'] = all(hashlib.sha256((repo/p).read_bytes()).hexdigest() == h for p,h in record['working_patch_inputs'].items())
assert record['source_unchanged']
(root/'summary.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
raise SystemExit(0 if record['passed'] else 1)
