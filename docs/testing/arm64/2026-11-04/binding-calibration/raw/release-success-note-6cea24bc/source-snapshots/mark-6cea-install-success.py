"""Prepare/review a body-only .4 release update; only explicit --apply edits GitHub.

No installer, product, upload, deletion, registration, or default-input calls.
Original release body is retained as an exact UTF-8 suffix, including CRLF.
Execution evidence lives separately from the sealed 90-member final archive.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse, hashlib, json, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.generated/18u-release-success-note-6cea24bc'
REPO = 'tsaanghwang/Yime'
SOURCE = '6cea24bc665a4ded31e083a42bebd5d2d039832d'
TAG = 'test-arm64-18u-wait-6cea24bc-20261104'
URL = 'https://github.com/' + REPO + '/releases/tag/' + TAG
ID = 433524279
VERSION = '0.2.0-18u-arm64.4'
MANIFEST = '572f66e68ad91effbdc994c6fbe1ca71a705d7ee4c5194b10d41447480ad83f3'
PINS = {
    '.generated/18u-wait-repair-release-6cea24bc/release-notes-publish.md': '0859601508409600bbb57b44ed7682b78eeac844673325ef99286b752ed4535d',
    '.generated/18u-wait-repair-release-6cea24bc/delivery-receipt.json': '7b8821f5b81bc17964d766731352353ad46b7205de16e5693afbce7e5b1c76ab',
    '.generated/complete-input-install/asus-18u-6cea24bc/install-result.json': '5b4cc5d7629a6bfee4e6d3848f3e8b60b3ded10772b66bfaec0e9c3395b9b2a5',
    '.generated/complete-input-install/asus-18u-6cea24bc/after.json': 'cf0f8fff4672afc88bd63bfb492b7cc64e007856f7268df50e114a7d0b96b1d2',
    '.generated/asus-18u-installed-6cea24bc-run/receipt.json': '588d5bfba846ade67f93308b4f358015fa5898db1c38f5bc2bd6e6a675090ed8',
    '.generated/asus-18u-installed-6cea24bc-run/checkpoints/receipt.json': 'bca1a80326c25f0d2266be59332e836b82815a9bb9b73075d6ffd5fee0884819',
    '.generated/asus-18u-installed-6cea24bc-run/restored-identity/identity.json': '9ae413d739160f8d438beb96bbb1b446bc76f78bbd7eb6946e1b2c67f8c4bb40',
    '.generated/armfull-tools/gh_repo.py': '4e5164e27b69a5f183f2ff6ec15c4860830ca3ae7220f474090a88371071608c',
    '.generated/18u-release-success-note-6cea24bc/prepared-remote-release.json': '68df3901c3868d48dd6b6aeb55cbd4be2998c704926fdf99fcf77249a30008b7',
}
UPDATE = '''## Installed/software update - 2026-11-04 13:07 (UTC+08)

On the ASUS ProArt P16 ARM64 test PC, one running upgrade from the verified original .1 Runtime/Broker/GUI completed successfully at 12:51 (UTC+08), with installer exit code 0. The installed .4 manifest and all 20 product payload files matched the fixed package. Standard YimeCore, Rime/PIME, and the default input override remained unchanged.

After installation, the existing physical observation (the 100 mm reference line measured 57.5 mm) was saved as this product's display calibration. The installed registered TSF/frontend chain passed all 18 controlled software checkpoints. The test Job was confirmed empty before restoring and verifying the ordinary-user Runtime, Broker, and keyboard GUI processes.

Physical ruler remeasurement after calibration and real finger input into the Notepad document remain pending. Controlled software checks and keyboard preview are not evidence of that physical/application acceptance. The earlier .2/.3 failures remain preserved, and the specific owner or cause of the historical .3 Broker sharing violation is still unproven.

This timestamped update supersedes only the installation/software pending status in the original publication text below. The original text and all four release assets are retained unchanged.

---

'''

def need(value, message):
    if not value:
        raise RuntimeError(message)

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def read(path):
    return json.loads(Path(path).read_bytes())

def save_once(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        need(path.read_bytes() == data, 'Prepared file changed; no overwrite: ' + str(path))
    else:
        path.write_bytes(data)

def save_json(path, value):
    save_once(path, (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))

def asset_identity(release):
    rows = release['assets']
    need(len(rows) == len({x['name'] for x in rows}) == 4, 'Exactly four unique release assets required')
    return sorted([{k: x[k] for k in ('id', 'name', 'size', 'digest', 'state', 'browser_download_url', 'created_at', 'updated_at')} for x in rows], key=lambda x: x['name'])

def validate_remote(release, original_body, expected_assets, delivery):
    need(release['id'] == ID and release['tag_name'] == TAG and release['target_commitish'] == SOURCE and release['html_url'] == URL, 'Release identity changed')
    need(release['draft'] is False and release['prerelease'] is True, 'Release publication state changed')
    need(release['body'].encode('utf-8') == original_body, 'Current body differs byte-for-byte from reviewed body; stop without editing')
    need(asset_identity(release) == expected_assets, 'Release assets changed since preparation')
    expected = {x['name']: x for x in delivery['assets']}
    need(set(expected) == {x['name'] for x in release['assets']} and len(expected) == 4, 'Delivery assets differ')
    for row in release['assets']:
        e = expected[row['name']]
        need(row['digest'] == e['digest'] and row['size'] == e['size'] and row['state'] == e['state'] == 'uploaded' and row['browser_download_url'] == e['url'], 'Asset digest/size/URL differs from delivery')

def run(*args):
    command = [sys.executable, '-B', '-X', 'utf8', str(ROOT / '.generated/armfull-tools/gh_repo.py'), *args]
    result = subprocess.run(command, capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError('gh exit ' + str(result.returncode) + ': ' + result.stderr.decode('utf-8', errors='replace'))
    return result.stdout

def current_release():
    tag = json.loads(run('api', 'repos/' + REPO + '/git/ref/tags/' + TAG))
    need(tag['ref'] == 'refs/tags/' + TAG and tag['object']['type'] == 'commit' and tag['object']['sha'] == SOURCE, 'Tag no longer resolves to the frozen source')
    release = json.loads(run('api', 'repos/' + REPO + '/releases/tags/' + TAG))
    return release, tag

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='Explicit single body-only edit after exact checks')
    args = parser.parse_args()
    for name, digest in PINS.items():
        need(sha(ROOT / name) == digest, 'Pinned evidence changed: ' + name)
    delivery = read(ROOT / '.generated/18u-wait-repair-release-6cea24bc/delivery-receipt.json')
    install = read(ROOT / '.generated/complete-input-install/asus-18u-6cea24bc/install-result.json')
    after = read(ROOT / '.generated/complete-input-install/asus-18u-6cea24bc/after.json')
    calibration = read(ROOT / '.generated/asus-18u-installed-6cea24bc-run/receipt.json')
    checks = read(ROOT / '.generated/asus-18u-installed-6cea24bc-run/checkpoints/receipt.json')
    restored = read(ROOT / '.generated/asus-18u-installed-6cea24bc-run/restored-identity/identity.json')
    need(delivery['source'] == SOURCE and delivery['url'] == URL and delivery['draft'] is False and delivery['prerelease'] is True, 'Delivery identity mismatch')
    need(install['sourceCommit'] == SOURCE and install['version'] == VERSION and install['installerExitCode'] == install['exitCode'] == 0, 'Installation is not the successful fixed source')
    need(all(install[x] is True for x in ('postInstallVerified', 'only18uChanged', 'unrelatedProductsAndDefaultUnchanged', 'runningUpgradeBaselineVerified')), 'Installed or product-protection claim unsupported')
    product = next(x for x in after['products'] if x['id'] == 'yimecore-18u')
    need(product['version'] == VERSION and len(product['payload']) == 20 and all(x['exists'] and x['match'] for x in product['payload']), '20 installed payload hashes not verified')
    need(calibration['sourceCommit'] == SOURCE and calibration['manifestSHA256'] == MANIFEST and calibration['packageVersion'] == VERSION and calibration['ok'] is True and calibration['checkpoints'] == 18, 'Calibration/checkpoint identity failed')
    need(calibration['calibrationExitCode'] == calibration['checkpointsControllerExitCode'] == 0 and calibration['testJobEmptyBeforeRestore'] is True, 'Software run or cleanup failed')
    need(calibration['calibration']['measurement']['referenceMM'] == 100 and calibration['calibration']['measurement']['observedMM'] == 57.5, 'Wrong physical observation')
    need(checks['hostResult']['ok'] is True and checks['hostResult']['checkpoints'] == 18 and checks['testJobEmptyBeforeRestore'] is True, 'Native host result failed')
    family = restored['runtimeAndDirectChildren']
    need(restored['sourceCommit'] == SOURCE and restored['allInstalledPayloadHashesVerified'] is True and len(family) == 3 and all(x['token']['integrity'] == 8192 and x['token']['elevated'] == 0 for x in family), 'Ordinary restored process claim unsupported')
    original = (ROOT / '.generated/18u-wait-repair-release-6cea24bc/release-notes-publish.md').read_bytes()
    prepared = read(OUT / 'prepared-remote-release.json')
    tag = read(OUT / 'prepared-remote-tag.json')
    need(tag['ref'] == 'refs/tags/' + TAG and tag['object']['type'] == 'commit' and tag['object']['sha'] == SOURCE, 'Prepared tag mismatch')
    assets = asset_identity(prepared)
    validate_remote(prepared, original, assets, delivery)
    prefix = UPDATE.replace('\n', '\r\n').encode('utf-8')
    notes = prefix + original
    notes_path = OUT / 'release-notes-after-install-success.md'
    save_once(OUT / 'original-body.md', original)
    save_once(OUT / 'success-update.md', prefix)
    save_once(notes_path, notes)
    save_once(OUT / 'source-snapshots/mark-6cea-install-success.py', Path(__file__).read_bytes())
    save_once(OUT / 'source-snapshots/gh_repo.py', (ROOT / '.generated/armfull-tools/gh_repo.py').read_bytes())
    for name in PINS:
        if name.endswith('gh_repo.py') or name.endswith('prepared-remote-release.json'):
            continue
        save_once(OUT / 'input-evidence' / name.removeprefix('.generated/'), (ROOT / name).read_bytes())
    plan = {'schema': 'yime-release-body-only-update-review-v1', 'source': SOURCE, 'releaseId': ID, 'tag': TAG, 'url': URL, 'preparedAtUTC': '2026-11-04T05:07:02Z', 'originalBodySHA256': hashlib.sha256(original).hexdigest(), 'notesSHA256': sha(notes_path), 'notesBytes': len(notes), 'originalBodyExactSuffix': notes.endswith(original), 'assets': assets, 'productCalls': 0, 'assetMutationCommands': 0, 'publicationRequested': False, 'physicalAcceptanceClaimed': False, 'historicalLockCauseProven': False}
    save_json(OUT / 'review-plan.json', plan)
    if not args.apply:
        print(json.dumps({'mode': 'offline-prepare', 'notes': str(notes_path), 'notesSHA256': sha(notes_path), 'notesBytes': len(notes), 'assets': len(assets), 'remoteMutations': 0}))
        return
    execution = OUT / 'apply-once'
    execution.mkdir(exist_ok=False) # Preserve the first failure and reject automatic retries.
    current, current_tag = current_release()
    save_json(execution / 'before-release.json', current)
    save_json(execution / 'before-tag.json', current_tag)
    validate_remote(current, original, assets, delivery)
    # Sole remote mutation. No asset, tag, title, draft, or prerelease options.
    need(notes_path.read_bytes() == notes, 'Reviewed notes changed before edit')
    run('release', 'edit', TAG, '--repo', REPO, '--notes-file', str(notes_path))
    updated, updated_tag = current_release()
    save_json(execution / 'after-release.json', updated)
    save_json(execution / 'after-tag.json', updated_tag)
    validate_remote(updated, notes, assets, delivery)
    for field in ('id', 'tag_name', 'target_commitish', 'name', 'draft', 'prerelease', 'published_at', 'created_at', 'html_url'):
        need(updated[field] == current[field], 'Unrequested release field changed: ' + field)
    receipt = {'source': SOURCE, 'url': URL, 'completedAtUTC': datetime.now(timezone.utc).isoformat(), 'notesSHA256': sha(notes_path), 'originalBodySHA256': hashlib.sha256(original).hexdigest(), 'originalBodyExactSuffix': updated['body'].encode('utf-8').endswith(original), 'bodyReadbackMatchedExactly': True, 'fourAssetIdentitiesUnchanged': True, 'assetsChanged': False, 'remoteMutations': 1, 'physicalAcceptanceClaimed': False, 'historicalLockCauseProven': False}
    save_json(execution / 'success-note-update-receipt.json', receipt)
    print(json.dumps(receipt))

if __name__ == '__main__':
    main()
