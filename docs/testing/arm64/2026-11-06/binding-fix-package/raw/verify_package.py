"""Independently verify the final archive, expanded package and frozen source."""
from pathlib import Path
import datetime
import hashlib
import json
import struct
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent
receipt = json.loads((ROOT / 'complete-package-receipt.json').read_text(encoding='utf-8'))
identity = json.loads(Path(receipt['identity']).read_text(encoding='utf-8'))
package = Path(receipt['package'])
archive = Path(receipt['zip']['path'])

def digest(path):
    with path.open('rb') as stream:
        return {'bytes': path.stat().st_size, 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}

assert digest(archive) == {k: receipt['zip'][k] for k in ('bytes', 'sha256')}
assert digest(Path(receipt['identity'])) == receipt['identityDigest']
assert identity['source']['commit'] == receipt['sourceCommit'] and identity['source']['clean']
assert identity['deliveryState'] == 'source-frozen' and identity['fileCount'] == len(identity['files'])
expected = identity['files']
actual_names = {p.relative_to(package).as_posix() for p in package.rglob('*') if p.is_file()}
assert actual_names == set(expected)
for name, row in expected.items():
    path = package / name
    assert path.resolve().is_relative_to(package.resolve()) and not path.is_symlink()
    assert digest(path) == row, name
with zipfile.ZipFile(archive) as z:
    assert len(z.infolist()) == len(expected) and set(z.namelist()) == set(expected)
    for name, row in expected.items():
        with z.open(name) as stream:
            checksum = hashlib.file_digest(stream, 'sha256').hexdigest()
        assert z.getinfo(name).file_size == row['bytes'] and checksum == row['sha256'], name

product = json.loads((package / 'product-package.json').read_text(encoding='utf-8-sig'))
manifest = json.loads((package / 'payload/installed-18u-product.json').read_text(encoding='utf-8'))
assert product['version'] == receipt['version'] == '0.2.0-18u-arm64.5'
assert manifest['sourceCommit'] == receipt['sourceCommit'] == '636cef681ee995a21a9c45fd750f8cb4b0acb4a1'
assert product['product'] == manifest['product'] == 'yimecore-18u'
assert product['target'] == 'windows-arm64' and manifest['architecture'] == 'native-arm64'
assert manifest['schema'] == 'installed-18u-product-v2'
assert len(product['files']) == len(manifest['files']) + 1 == receipt['payloadCount']
for row in product['files']:
    assert digest(package / 'payload' / row['path']) == {k: row[k] for k in ('bytes', 'sha256')}
for row in manifest['files']:
    assert digest(package / 'payload' / row['path']) == {k: row[k] for k in ('bytes', 'sha256')}
pe = {}
for name in ['YimeMaintenance.exe'] + ['payload/' + row['path'] for row in manifest['files'] if row['path'].endswith(('.exe', '.dll'))]:
    raw = (package / name).read_bytes()
    offset = struct.unpack_from('<I', raw, 60)[0]
    assert raw[:2] == b'MZ' and raw[offset:offset+4] == b'PE\0\0'
    machine = struct.unpack_from('<H', raw, offset+4)[0]
    assert machine == 0xaa64, name
    pe[name] = '0xaa64'
assert len(pe) == 7
plan = json.loads((package / 'maintenance-plan.json').read_text(encoding='utf-8'))
assert plan['sourceCommit'] == receipt['sourceCommit']
assert digest(package / 'maintenance-plan.json')['sha256'] == receipt['planSHA256']
assert digest(package / 'YimeMaintenance.exe')['sha256'] == receipt['maintenanceSHA256']
assert set(plan['files']) == set(expected) - {'maintenance-plan.json', 'YimeMaintenance.exe'}
assert all(plan['files'][name] == expected[name] for name in plan['files'])
git = r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe'
assert subprocess.check_output([git, 'rev-parse', 'HEAD'], cwd=ROOT / 'source', text=True).strip() == receipt['sourceCommit']
assert not subprocess.check_output([git, 'status', '--porcelain', '--untracked-files=normal'], cwd=ROOT / 'source', text=True).strip()
result = {'schema': 'arm64-binding-independent-package-verification-v1',
    'observedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'sourceCommit': receipt['sourceCommit'],
    'version': receipt['version'], 'zip': receipt['zip'], 'archiveMembersVerified': len(expected),
    'expandedMembersVerified': len(expected), 'productPayloadMembersVerified': receipt['payloadCount'],
    'nativeProductPE': pe, 'sourceClean': True, 'maintenancePlanVerified': True, 'passed': True,
    'installed': False, 'registered': False, 'nativeHostAcceptance': False}
(ROOT / 'independent-verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)
