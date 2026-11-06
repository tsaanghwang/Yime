"""Fixed-source overlay acceptance. No installation, real host, or global environment changes."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import os
import shutil
import subprocess

OUT = Path(__file__).resolve().parent
WORKTREE = OUT.parents[1]
SOURCE = WORKTREE / '.generated/package-binding-636cef68/source'
SHA = '636cef681ee995a21a9c45fd750f8cb4b0acb4a1'
PAYLOAD = Path('C:/dev/Yime-deliveries/18u-binding-636cef68-20261106/package/payload')
GO = Path('C:/dev/Yime/.generated/arm64-toolchain/go1.25.14/go/bin/go.exe')
GIT = shutil.which('git')

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def write(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def git(*args):
    return subprocess.check_output([GIT, '-C', str(SOURCE), *args], text=True).strip()

assert git('rev-parse', 'HEAD') == SHA
assert git('status', '--porcelain') == ''
manifest_path = PAYLOAD / 'installed-18u-product.json'
assert digest(manifest_path) == 'd536a76448ab755f5995a01370f541e7bbb76fca7b9b3bfd23186e0eb9dc61be'
manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
assert manifest['sourceCommit'] == SHA
resources = []
for row in manifest['files']:
    if row['path'].startswith('data/') or row['path'].startswith('source/prototypes/touch-terminal/'):
        path = PAYLOAD / row['path']
        assert path.stat().st_size == row['bytes'] and digest(path) == row['sha256'], path
        if row['path'].startswith('source/'):
            assert digest(SOURCE / row['path'][7:]) == row['sha256'], 'source/data projection mismatch'
        resources.append(row)

env = os.environ.copy()
for key, child in [('GOCACHE', 'go-cache'), ('GOTMPDIR', 'tmp'), ('TEMP', 'tmp'), ('TMP', 'tmp'), ('GOPATH', 'go-path')]:
    directory = OUT / child
    directory.mkdir(exist_ok=True)
    env[key] = str(directory)
env.update(GOOS='windows', GOARCH='arm64', CGO_ENABLED='0', GOENV='off', GOTOOLCHAIN='local', GOFLAGS='', GOPROXY='off',
    YIME_ACCEPTANCE_ROOT=str(SOURCE), YIME_ACCEPTANCE_LAB_DATA=str(PAYLOAD / 'data'), YIME_ACCEPTANCE_REPORT=str(OUT / 'result.json'))
overlay_test = OUT / 'acceptance_overlay_test.go'
subprocess.run([str(GO.with_name('gofmt.exe')), '-w', str(overlay_test)], check=True, env=env, creationflags=subprocess.CREATE_NO_WINDOW)
overlay = {'Replace': {str(SOURCE / 'go-backend/cmd/yime-touch-keyboard/acceptance_20261106_windows_test.go'): str(overlay_test)}}
write('overlay.json', overlay)
command = [str(GO), 'test', '-buildvcs=false', '-overlay', str(OUT / 'overlay.json'), './cmd/yime-touch-keyboard',
    '-run', '^TestAcceptanceFullNiiiSyntheticRoutes20261106$', '-count=1', '-timeout=10m', '-json']
receipt = {'schema': '18u-fullcode-pen-overlay-run-v1', 'startedUtc': datetime.now(timezone.utc).isoformat(), 'sourceCommit': SHA,
    'sourceRoot': str(SOURCE), 'sourceCleanBefore': True, 'command': command, 'cwd': str(SOURCE / 'go-backend'),
    'processLocalEnvironment': {k: env[k] for k in ['GOOS', 'GOARCH', 'CGO_ENABLED', 'GOENV', 'GOTOOLCHAIN', 'GOFLAGS', 'GOPROXY', 'GOCACHE', 'GOTMPDIR', 'GOPATH', 'YIME_ACCEPTANCE_ROOT', 'YIME_ACCEPTANCE_LAB_DATA', 'YIME_ACCEPTANCE_REPORT']},
    'manifestSha256': digest(manifest_path), 'verifiedLabResources': resources,
    'testOverlaySha256': digest(overlay_test), 'overlaySha256': digest(OUT / 'overlay.json'),
    'sourceFilesEdited': False, 'installedRuntimeChanged': False, 'externalHostInputSent': False, 'physicalAcceptance': False}
write('run-receipt.json', receipt)
print('Starting one fixed-source acceptance test (three synthetic routes); hidden own windows only.', flush=True)
with (OUT / 'go-test.jsonl').open('xb') as output:
    completed = subprocess.run(command, cwd=SOURCE / 'go-backend', env=env, stdout=output, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
receipt.update(exitCode=completed.returncode, finishedUtc=datetime.now(timezone.utc).isoformat(), sourceCleanAfter=git('status', '--porcelain') == '', logSha256=digest(OUT / 'go-test.jsonl'))
write('run-receipt.json', receipt)
print(json.dumps({'exitCode': completed.returncode, 'sourceCleanAfter': receipt['sourceCleanAfter'], 'resultExists': (OUT / 'result.json').exists()}, ensure_ascii=False), flush=True)
raise SystemExit(completed.returncode)
