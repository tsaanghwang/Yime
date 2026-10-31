from pathlib import Path, PurePosixPath
from datetime import datetime, timezone
import hashlib
import json
import os
import shutil
import stat
import struct
import subprocess
import sys
import zipfile

repo = Path(__file__).resolve().parents[1]
delivery = Path(sys.argv[1]).resolve()
metadata = json.loads((delivery / 'artifact-metadata.json').read_text(encoding='utf-8'))
records = delivery / 'records'
records.mkdir(exist_ok=False)

def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def safe_path(base, name):
    name = name.replace('\\', '/')
    parts = PurePosixPath(name)
    assert not parts.is_absolute() and '..' not in parts.parts and ':' not in name, name
    out = (base / name).resolve()
    assert out.is_relative_to(base.resolve()), name
    return out

identities = {}
for arch in ('amd64', 'arm64'):
    artifact = metadata['packages'][arch]
    archive = delivery / artifact['localZip']
    archive_hash = digest(archive)
    assert archive_hash == artifact['digest'].removeprefix('sha256:'), arch
    package = delivery / arch
    package.mkdir(exist_ok=False)
    seen = set()
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None, arch
        assert sum(i.file_size for i in z.infolist()) < 2 * 1024 ** 3
        for info in z.infolist():
            assert not stat.S_ISLNK(info.external_attr >> 16), info.filename
            path = safe_path(package, info.filename)
            key = str(path).casefold()
            assert key not in seen, info.filename
            seen.add(key)
            if info.is_dir():
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                with z.open(info) as src, path.open('xb') as dst:
                    shutil.copyfileobj(src, dst)
    manifest = json.loads((package / 'manifest.json').read_text(encoding='utf-8'))
    assert manifest['sourceCommit'] == metadata['checkoutCommit']
    assert manifest['sourceChanges'] is False
    assert manifest['architecture'] == 'windows-' + arch
    assert manifest['ci']['runURL'] == metadata['runURL']
    assert manifest['ci']['event'] == 'pull_request'
    assert manifest['ci']['checkoutCommit'] == metadata['checkoutCommit']
    assert manifest['completeChineseResources'] is True
    for name, sha in manifest['files'].items():
        assert digest(safe_path(package, name)) == sha, (arch, name)
    actual_files = {p.relative_to(package).as_posix() for p in package.rglob('*') if p.is_file()}
    assert actual_files == set(manifest['files']) | {'manifest.json'}
    assert digest(package / 'resources.json') == manifest['portableResourcesSHA256']
    resources = json.loads((package / 'resources.json').read_text(encoding='utf-8'))
    assert resources['sourceCommit'] == metadata['checkoutCommit']
    assert resources['architecture'] == 'windows-' + arch
    assert resources['sourceChanges'] is False
    for name, sha in resources['files'].items():
        assert digest(safe_path(package, name)) == sha, (arch, name)
    exe = (package / 'YimeTouchKeyboard.exe').read_bytes()
    offset = struct.unpack_from('<I', exe, 0x3c)[0]
    assert exe[:2] == b'MZ' and exe[offset:offset+4] == b'PE\0\0'
    machine = struct.unpack_from('<H', exe, offset + 4)[0]
    assert machine == {'amd64': 0x8664, 'arm64': 0xaa64}[arch]
    touch = manifest['touchScreenView']
    assert (touch['version'], touch['keyCount'], touch['controlCount']) == ('touch-screen-v2', 102, 18)
    assert touch['candidateStyle']['version'] == 'raised-centered-v1'
    assert '--touch-ui' in (package / 'Start Touch Screen Preview.cmd').read_text(encoding='utf-8-sig')
    identities[arch] = dict(artifact, zipSHA256=archive_hash, manifestSHA256=digest(package / 'manifest.json'),
        executableSHA256=digest(package / 'YimeTouchKeyboard.exe'), architecture=manifest['architecture'],
        sourceCommit=manifest['sourceCommit'], sourceChanges=False, verifiedPayloadFiles=len(manifest['files']),
        portableResourcesSHA256=manifest['portableResourcesSHA256'], PEMachine=hex(machine),
        staticIntegrityPassed=True, physicalAcceptance=False)
    shutil.copyfile(package / 'manifest.json', records / f'{arch}-manifest.json')

identity = dict(scope='PR87 fixed CI complete packages', recordedAtUTC=datetime.now(timezone.utc).isoformat(),
    runID=metadata['runID'], runURL=metadata['runURL'], sourceHead=metadata['sourceHead'],
    checkoutCommit=metadata['checkoutCommit'], packages=identities,
    installedProductChanges=False, defaultInputMethodChanges=False, userDataChanges=False)
with (records / 'package-identities.json').open('x', encoding='utf-8', newline='\n') as out:
    json.dump(identity, out, ensure_ascii=False, indent=2)
    out.write('\n')
print('PASS: both fixed CI ZIP digests, CRCs, PE architectures, manifests and all payload/resource hashes', flush=True)

with (records / 'arm64-package-check.log').open('x', encoding='utf-8') as log:
    subprocess.run([sys.executable, '-X', 'utf8', str(repo / 'tools/check_touch_keyboard_package.py'),
        '--package', str(delivery / 'arm64'), '--report', str(records / 'arm64-package-check.json')],
        cwd=repo, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
state = delivery / 'check-state'
env = {k: v for k, v in os.environ.items() if not k.upper().startswith('YIME_')}
for key, child in (('TEMP', 'tmp'), ('TMP', 'tmp'), ('APPDATA', 'roaming'), ('LOCALAPPDATA', 'local')):
    p = state / child
    p.mkdir(parents=True, exist_ok=True)
    env[key] = str(p)
report = records / 'arm64-touch-ui-check.json'
with (records / 'arm64-touch-ui-check.log').open('x', encoding='utf-8') as log:
    subprocess.run([str(delivery / 'arm64/YimeTouchKeyboard.exe'), '--check-package', '--touch-ui',
        '--data-report', str(report)], cwd=state, env=env, stdout=log, stderr=subprocess.STDOUT,
        check=True, timeout=240)
result = json.loads(report.read_text(encoding='utf-8'))
assert result['screenView'] == 'touch-screen-v2'
assert (result['keyCount'], result['touchControls'], result['preservedBodyKeys']) == (102, 18, 84)
assert result['boardHeightU'] == 5.7 and result['boardWidthU'] == 18
assert result['hostInputSent'] is False
assert result['confirmedChineseInMemory'] == dict.fromkeys(('variable', 'full', 'shorthand'), '你')
for arch in ('amd64', 'arm64'):
    manifest = json.loads((delivery / arch / 'manifest.json').read_text(encoding='utf-8'))
    for name, sha in manifest['files'].items():
        assert digest(delivery / arch / name) == sha, (arch, name)
print('PASS: native ARM64 relocated package and touch-screen-v2 checks; no physical or host input', flush=True)
