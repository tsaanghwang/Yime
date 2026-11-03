"""Repackage a pinned standard runtime with separately identified maintenance source.

Build-Package runs through checked PS7 and invokes the existing Read-Package
hash/ARM64X/x86 validation. This tool never runs Setup or an Install action.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import zipfile

RUNTIME_COMMIT = '64a785a7ede5fb2a53e2560b873075950160668b'
RUNTIME_ARCHIVE_SHA256 = '7a8cff04fcc09f8a9908257c1f8ac7b8f5a37f123c192eebea62089f39a45e25'
RUNTIME_ARCHIVE_BYTES = 168189960
RUNTIME_PREFIX = 'YimeCore-0.1.0-local.13-main64a785a7-arm64-20261103/'
PAYLOAD_COUNT = 69
VERSION = '0.1.0-local.13-main64a785a7-arm64-maint.1'
MAINTENANCE = ('Product.psm1', 'Setup.ps1', 'Setup.cmd')


def plain(path):
    path = Path(path).absolute()
    for item in (path, *path.parents):
        if item.exists() or item.is_symlink():
            info = item.lstat()
            if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 1024:
                raise ValueError('reparse or symbolic-link path refused: ' + str(item))
    return path


def digest(path):
    path = plain(path)
    if not path.is_file():
        raise ValueError('regular file required: ' + str(path))
    with path.open('rb') as stream:
        return {'bytes': path.stat().st_size, 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}


def inventory(root):
    root = plain(root)
    result, folded = {}, set()
    for directory, dirs, names in os.walk(root, followlinks=False):
        for name in dirs + names:
            path = plain(Path(directory) / name)
            relative = path.relative_to(root).as_posix()
            if path.is_dir():
                continue
            if relative.casefold() in folded:
                raise ValueError('case-colliding package members')
            folded.add(relative.casefold())
            result[relative] = digest(path)
    return result


def load_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate JSON key')
            result[key] = value
        return result
    return json.loads(plain(path).read_text(encoding='utf-8-sig'), object_pairs_hook=unique)


def payload_rows(manifest):
    if (manifest.get('format'), manifest.get('product'), manifest.get('target'),
            manifest.get('host_architecture'), manifest.get('tsf64_architecture')) != (
            'yime-simple-package-2', 'yimecore', 'windows-arm64', 'arm64', 'arm64x'):
        raise ValueError('standard ARM64 package contract required')
    rows = manifest.get('files')
    if not isinstance(rows, list) or len(rows) != PAYLOAD_COUNT:
        raise ValueError('exact pinned payload count required')
    result, seen = {}, set()
    for row in rows:
        if not isinstance(row, dict) or set(row) != {'path', 'bytes', 'sha256'}:
            raise ValueError('invalid payload record')
        name = row['path']
        if (not isinstance(name, str) or not name or '\\' in name or ':' in name
                or any(part in ('', '.', '..') for part in name.split('/'))
                or name.casefold() in seen or type(row['bytes']) is not int or row['bytes'] <= 0
                or not isinstance(row['sha256'], str) or not re.fullmatch('[0-9a-f]{64}', row['sha256'])):
            raise ValueError('invalid or duplicate payload member')
        seen.add(name.casefold())
        result[name] = {key: row[key] for key in ('bytes', 'sha256')}
    return result


def verify_runtime(package, archive):
    package, archive = plain(package), plain(archive)
    if digest(archive) != {'bytes': RUNTIME_ARCHIVE_BYTES, 'sha256': RUNTIME_ARCHIVE_SHA256}:
        raise ValueError('runtime archive differs from the independently pinned release')
    files = inventory(package)
    rows = payload_rows(load_json(package / 'product-package.json'))
    expected = {'payload/' + name for name in rows} | set(MAINTENANCE) | {'product-package.json'}
    if set(files) != expected or inventory(package / 'payload') != rows:
        raise ValueError('runtime package does not contain the exact original payload')
    if load_json(package / 'payload/package-manifest.json').get('git_commit') != RUNTIME_COMMIT:
        raise ValueError('runtime source identity mismatch')
    verify_zip(archive, files, RUNTIME_PREFIX)
    return rows


def verify_zip(archive, files, prefix=''):
    with zipfile.ZipFile(archive) as source:
        expected = {prefix + name for name in files}
        if len(source.infolist()) != len(expected) or set(source.namelist()) != expected:
            raise ValueError('ZIP inventory differs from package')
        for name, record in files.items():
            member = source.getinfo(prefix + name)
            with source.open(member) as stream:
                sha = hashlib.file_digest(stream, 'sha256').hexdigest()
            if member.file_size != record['bytes'] or sha != record['sha256']:
                raise ValueError('ZIP member differs: ' + name)


def source_state(repo, commit, draft, git):
    if not re.fullmatch('[0-9a-f]{40}', commit):
        raise ValueError('full installer source commit required')
    actual = subprocess.check_output([git, 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
    status = subprocess.check_output([git, 'status', '--porcelain', '--untracked-files=normal'], cwd=repo, text=True)
    if actual != commit or (status and not draft):
        raise ValueError('installer HEAD must match; formal package requires a clean tree')
    return {'commit': actual, 'clean': not bool(status), 'statusSHA256': hashlib.sha256(status.encode()).hexdigest()}


def build(repo, runtime_package, runtime_archive, output, installer_commit, git, draft=False,
          bootstrap_directory=None, runner=subprocess.run):
    repo, original, archive, output = map(plain, (repo, runtime_package, runtime_archive, output))
    if output.exists() or output == repo or output in repo.parents or original == output or original in output.parents or output in original.parents:
        raise ValueError('choose fresh output separate from the runtime package and repository root')
    state = source_state(repo, installer_commit, draft, git)
    rows = verify_runtime(original, archive)
    source = repo / 'installer/simple'
    sources = {name: digest(source / name) for name in (*MAINTENANCE, 'Build-Package.ps1')}
    output.mkdir(parents=True)
    package = output / 'package'
    parameters = output / 'build-parameters.json'
    parameters.write_text(json.dumps({'Product': 'yimecore', 'Target': 'windows-arm64',
        'PayloadRoot': str(original / 'payload'), 'OutputRoot': str(package), 'Version': VERSION}), encoding='utf-8')
    env = os.environ.copy()
    temp = output / 'tmp'; temp.mkdir()
    env['TEMP'] = env['TMP'] = str(temp)
    if bootstrap_directory:
        env['PATH'] = str(plain(bootstrap_directory)) + os.pathsep + env.get('PATH', '')
    command = [sys.executable, str(repo / 'tools/powershell/run_checked.py'), '--edition', 'ps7',
        '--script', str(source / 'Build-Package.ps1'), '--params-file', str(parameters)]
    result = runner(command, cwd=repo, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=240)
    (output / 'build-read-package.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError('checked Build-Package / Read-Package failed; see build-read-package.log')
    manifest = load_json(package / 'product-package.json')
    if manifest.get('version') != VERSION or payload_rows(manifest) != rows or inventory(package / 'payload') != rows:
        raise ValueError('repack changed pinned runtime payload')
    expected = {'payload/' + name: value for name, value in rows.items()}
    expected.update({name: sources[name] for name in MAINTENANCE})
    expected['product-package.json'] = digest(package / 'product-package.json')
    if inventory(package) != expected or sources != {name: digest(source / name) for name in sources}:
        raise ValueError('maintenance source changed or unexpected package members')
    provenance = {'schema': 'yime-standard-arm64-component-sources-v1', 'version': VERSION,
        'deliveryState': 'draft' if draft else 'source-frozen',
        'runtimeSourceCommit': RUNTIME_COMMIT, 'installerSourceCommit': installer_commit,
        'runtimeArchive': {'sha256': RUNTIME_ARCHIVE_SHA256, 'bytes': RUNTIME_ARCHIVE_BYTES},
        'runtimePayloadCount': len(rows), 'runtimePayloadUnchanged': True, 'installerSource': state,
        'installerFiles': sources, 'readPackagePassed': True, 'sourceCICheckedByTool': False,
        'installationExecuted': False, 'registeredInputAcceptance': False}
    (package / 'component-sources.json').write_text(json.dumps(provenance, indent=2) + '\n', encoding='utf-8')
    (package / 'README.repack.md').write_text(
        '# Standard ARM64 maintenance repack\n\n' +
        ('Draft working-tree maintenance source.\n\n' if draft else 'Frozen maintenance source; source CI and release authorization are checked separately.\n\n') +
        'Runtime source: `' + RUNTIME_COMMIT + '`. All 69 original payload files are byte-identical.\n\n' +
        'Maintenance source: `' + installer_commit + '`. Only the package manifest and three maintenance scripts are regenerated; '
        'component-sources.json records both components. This package does not represent a single runtime/installer source build.\n\n'
        'Build-Package invokes Read-Package for existing hash and PE architecture checks. No Install, registration, '
        'runtime execution or input acceptance is performed by this repack tool.\n', encoding='utf-8')
    files = inventory(package)
    target = output / ('YimeCore-' + VERSION + '-' + installer_commit[:12] + ('-draft' if draft else '') + '.zip')
    with zipfile.ZipFile(target, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zipped:
        for name in sorted(files):
            zipped.write(package / name, name)
    verify_zip(target, files)
    if inventory(package) != files or inventory(original / 'payload') != rows:
        raise ValueError('runtime or output changed while packaging')
    final_state = source_state(repo, installer_commit, draft, git)
    if sources != {name: digest(source / name) for name in sources}:
        raise ValueError('maintenance source changed during ZIP creation')
    receipt = {**provenance, 'installerSourceAfter': final_state, 'fileCount': len(files),
        'files': files, 'zip': {'name': target.name, **digest(target)}}
    (output / 'repack-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[2])
    for name in ('runtime-package-root', 'runtime-archive', 'output-root', 'installer-source-commit'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--git', default='git')
    parser.add_argument('--bootstrap-directory', help='PS7 executable directory used only by the checked entry')
    parser.add_argument('--draft', action='store_true')
    args = parser.parse_args()
    receipt = build(args.repo, args.runtime_package_root, args.runtime_archive, args.output_root,
        args.installer_source_commit, args.git, args.draft, args.bootstrap_directory)
    print(json.dumps({key: receipt[key] for key in ('deliveryState', 'runtimeSourceCommit', 'installerSourceCommit', 'runtimePayloadCount', 'zip')}, indent=2))


if __name__ == '__main__':
    main()
