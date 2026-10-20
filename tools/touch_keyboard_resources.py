"""Publish/restore only the locked, derived CN134 runtime dictionaries for P5.

No canonical source import or generation happens on CI. The release archive is
an immutable input to this lab, identified by SHA-256 in resources.lock.json.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'prototypes/touch-terminal/desktop/resources.lock.json'
NAMES = ('ascii_keyboard_manifest.json', 'yime_full.dict.yaml',
         'yime_variable.dict.yaml', 'yime_shorthand.dict.yaml')
REPO = 'tsaanghwang/Yime'


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def generated(path):
    path = Path(path).resolve()
    if not path.is_relative_to(ROOT / '.generated'):
        raise ValueError('Output must be inside this checkout .generated/')
    return path


def validate_manifest(data):
    manifest = json.loads((data / NAMES[0]).read_text(encoding='utf-8'))
    layout = json.loads((ROOT / 'prototypes/touch-terminal/data/physical-layout.json').read_text(encoding='utf-8'))
    provenance = json.loads((ROOT / 'tools/lexicon/handoff/yime_core_fixed.evidence.json').read_text(encoding='utf-8'))
    if (manifest['scope'] != 'immutable_source_runtime_experiment'
        or manifest['layout_projection_sha256'] != layout['layoutId']
        or manifest['input_policy'] != 'concept-keyboard-modes-v2'
        or manifest['limit'] != 0 or manifest['disabled_yinyuan_ids']
        or manifest['source_database'] != provenance['provenance']['runtime_database']
        or manifest['source_reading_count'] <= 0
        or manifest['source_reading_count'] != manifest['exported_reading_count']
        or manifest['production_handoff_promoted'] is not False):
        raise ValueError('Incomplete, foreign or unapproved experimental corpus')
    for name in NAMES[1:]:
        if digest(data / name) != manifest['dictionary_sha256'][name]:
            raise ValueError('Dictionary identity mismatch: ' + name)
    return manifest


def verify(data, lock=None):
    lock = lock or json.loads(LOCK.read_text(encoding='utf-8'))
    if lock['schemaVersion'] != 1 or set(lock['files']) != set(NAMES):
        raise ValueError('Invalid resource lock inventory')
    for name, record in lock['files'].items():
        path = data / name
        if path.is_symlink() or path.stat().st_size != record['bytes'] or digest(path) != record['sha256']:
            raise ValueError('Locked resource mismatch: ' + name)
    return validate_manifest(data)


def bundle(data, archive, tag):
    manifest = validate_manifest(data)
    archive = generated(archive)
    archive.parent.mkdir(parents=True, exist_ok=True)
    # Fixed names/timestamps/order: identical derived bytes produce identical ZIP.
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for name in NAMES:
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, (data / name).read_bytes())
    lock = {'schemaVersion': 1, 'scope': 'isolated-cn134-complete-derived-runtime',
            'repository': REPO, 'releaseTag': tag, 'asset': archive.name,
            'url': f'https://github.com/{REPO}/releases/download/{tag}/{archive.name}',
            'archiveSHA256': digest(archive), 'archiveBytes': archive.stat().st_size,
            'sourceCommit': subprocess.check_output(['git', '-c', 'core.fsmonitor=false', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'layoutProjectionSHA256': manifest['layout_projection_sha256'],
            'sourceReadingCount': manifest['source_reading_count'],
            'files': {name: {'bytes': (data/name).stat().st_size, 'sha256': digest(data/name)} for name in NAMES}}
    LOCK.write_text(json.dumps(lock, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(lock, indent=2))


def extract(archive, output, lock):
    if archive.stat().st_size != lock['archiveBytes'] or digest(archive) != lock['archiveSHA256']:
        raise ValueError('Resource archive size/SHA-256 mismatch')
    output = generated(output)
    if output.exists() and any(output.iterdir()):
        # Idempotent CI/local restore, but never silently overwrite stale bytes.
        verify(output, lock)
        return
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        if len(z.infolist()) != len(NAMES) or set(z.namelist()) != set(NAMES):
            raise ValueError('Resource archive inventory mismatch')
        for name in NAMES:
            if z.getinfo(name).file_size != lock['files'][name]['bytes']:
                raise ValueError('Resource archive entry size mismatch')
            with z.open(name) as source, (output/name).open('wb') as target:
                shutil.copyfileobj(source, target)
    verify(output, lock)


def fetch(output, archive=None):
    lock = json.loads(LOCK.read_text(encoding='utf-8'))
    if lock['repository'] != REPO or set(lock['files']) != set(NAMES):
        raise ValueError('Resource lock must target this repository and exact runtime inventory')
    if archive:
        extract(Path(archive), output, lock)
    else:
        with tempfile.TemporaryDirectory(prefix='touch-keyboard-resource-download-') as tmp:
            subprocess.run(['gh', 'release', 'download', lock['releaseTag'], '--repo', REPO,
                            '--pattern', lock['asset'], '--dir', tmp], check=True)
            extract(Path(tmp)/lock['asset'], output, lock)
    print('PASS locked complete CN134 runtime resources: ' + str(output))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    b = commands.add_parser('bundle')
    b.add_argument('--data-dir', type=Path, required=True)
    b.add_argument('--archive', type=Path, required=True)
    b.add_argument('--tag', required=True)
    f = commands.add_parser('fetch')
    f.add_argument('--output-dir', type=Path, required=True)
    f.add_argument('--archive', type=Path)
    args = parser.parse_args()
    if args.command == 'bundle':
        bundle(args.data_dir, args.archive, args.tag)
    else:
        fetch(args.output_dir, args.archive)
