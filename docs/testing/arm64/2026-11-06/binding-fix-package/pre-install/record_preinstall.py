"""Archive read-only observations; no installation or application input."""
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path('C:/dev/Yime/.wt/bindfix')
SESSION = ROOT / '.generated/binding-upgrade-20261106'
DELIVERY = Path('C:/dev/Yime-deliveries/18u-binding-636cef68-20261106')
DEST = ROOT / 'docs/testing/arm64/2026-11-06/binding-fix-package/pre-install'

def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

before, after = read(SESSION / 'initial.json'), read(SESSION / 'prepared-state.json')
assert before['computer'] == after['computer'] == 'HUASHUONOTEBOOK'
assert before['defaultInputOverride'] == after['defaultInputOverride']
before_products = {p['id']: p for p in before['products']}
after_products = {p['id']: p for p in after['products']}
assert before_products == after_products, 'Installed product state changed during preparation.'
assert all(row['match'] for p in after['products'] for row in p['payload'])
calibration = read(SESSION / 'calibration-before.json')
calibration_root = Path(calibration['root'])
current_calibration = [{'relativePath': p.relative_to(calibration_root).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p)} for p in calibration_root.rglob('*') if p.is_file()]
assert current_calibration == calibration['files']
locks = read(SESSION / 'prepared-dll-users.json')
assert locks['users'] and locks['shutdownOrRestartRequested'] is False
assert not (DELIVERY / 'installation-output.log').exists()
record = {
    'schema': '18u-binding-install-preparation-v1',
    'observedUTC': datetime.now(timezone.utc).isoformat(),
    'computer': after['computer'],
    'status': 'complete-package-ready-install-not-started-existing-hosts-load-old-dll',
    'installedVersion': after_products['yimecore-18u']['version'],
    'preparedVersion': '0.2.0-18u-arm64.5',
    'preparedSourceCommit': '636cef681ee995a21a9c45fd750f8cb4b0acb4a1',
    'localDelivery': str(DELIVERY),
    'nativePackageCheckExitCode': read(DELIVERY / 'local-delivery-receipt.json')['nativeCheckExitCode'],
    'allThreeProductSnapshotsEqual': True,
    'allInstalledPayloadHashesMatch': True,
    'defaultInputOverrideUnchanged': True,
    'calibrationBytesUnchanged': True,
    'productProcessesUnchanged': True,
    'installedFileUsers': locks['users'],
    'notepadObservation': 'Computer Use showed an existing unsaved document; no document edits or close were attempted.',
    'installationAttempted': False,
    'installedNotepadBindingRetested': False,
    'installedChineseInputRetested': False,
    'physicalFingerPenAcceptance': 'not performed',
    'continuation': 'Save documents and normally restart Windows; before reopening Codex/Notepad or selecting 18u, run the prepared standard installer. Return for fresh installed identity checks and real Notepad input testing.',
}
DEST.mkdir(parents=True, exist_ok=False)
files = [SESSION / name for name in ['initial.json', 'initial.log', 'initial-dll-users.json', 'initial-dll-users.log', 'calibration-before.json', 'prepared-state.json', 'prepared-state.log', 'prepared-dll-users.json', 'prepared-dll-users.log', 'snapshot-tool-provenance.json', 'capture-installed.ps1', 'query-asus-18u-locks.ps1']]
files += [DELIVERY / name for name in ['local-delivery-receipt.json', 'native-package-check.log', 'Install-18u-ARM64.cmd', 'README.zh-CN.md']]
files += [SESSION / 'tools' / name for name in ['prepare_local_delivery.py', 'capture_final_baseline.py', 'record_preinstall.py']]
for source in files:
    shutil.copy2(source, DEST / source.name)
(DEST / 'status.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
index = [{'path': p.name, 'bytes': p.stat().st_size, 'sha256': sha(p)} for p in sorted(DEST.iterdir()) if p.is_file()]
(DEST / 'evidence-index.json').write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(record, ensure_ascii=False, indent=2))
