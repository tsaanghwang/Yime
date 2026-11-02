"""One bounded, read-only preflight from an independently pinned package.

Hashes detect mismatch, not provenance. Obtain the expected manifest digest from
an independently verified immutable CI artifact. This is not a defense against a
malicious same-account process replacing files between verification and launch.
No registration, recovery, activation or arbitrary-command entry point exists.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys


SCHEMA = 'mycomputer-activation-development-package-v1'
SCHEMA_V2 = 'mycomputer-activation-development-package-v2'
IDENTITY = {'product': 'YimeCore18uTouch', 'clsid': '6DFACE1F-562E-4773-A9D6-D5753A314711', 'profile': '1BD904AC-3194-4419-B70A-5574100F18B3', 'languageId': '0x0804'}
PAYLOAD = {'YimeTextService18u.dll', 'YimeMyComputerActivationStage1.exe', 'README.zh-CN.md', 'collect_mycomputer_preflight.py', 'windows_job_once.py'}
PAYLOAD_V2 = PAYLOAD | {'run_mycomputer_registration.py', 'validate_local_activation_evidence.py'}
EXE = 'YimeMyComputerActivationStage1.exe'
DLL = 'YimeTextService18u.dll'
MANIFEST = 'manifest.json'
HEX64 = re.compile(r'[0-9a-f]{64}\Z')
HEX40 = re.compile(r'[0-9a-f]{40}\Z')


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def regular(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or path.is_symlink() or getattr(info, 'st_file_attributes', 0) & 0x400:
        raise ValueError('package entries must be regular non-reparse files')


def pe_identity(path, dll):
    with path.open('rb') as stream:
        dos = stream.read(64)
        if len(dos) != 64 or dos[:2] != b'MZ':
            raise ValueError('invalid PE DOS header')
        offset = struct.unpack_from('<I', dos, 60)[0]
        if offset < 64 or offset > path.stat().st_size - 24:
            raise ValueError('invalid PE offset')
        stream.seek(offset)
        header = stream.read(24)
        if header[:4] != b'PE\0\0' or struct.unpack_from('<H', header, 4)[0] != 0x8664:
            raise ValueError('native AMD64 PE required')
        flags = struct.unpack_from('<H', header, 22)[0]
        if not flags & 0x0002 or bool(flags & 0x2000) != dll:
            raise ValueError('PE executable/DLL identity mismatch')


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key')
        result[key] = value
    return result


def validate_package(package, expected_manifest):
    if not HEX64.fullmatch(expected_manifest):
        raise ValueError('independently pinned lowercase manifest SHA256 required')
    if package.is_symlink() or getattr(package.stat(), 'st_file_attributes', 0) & 0x400:
        raise ValueError('package directory must not be a reparse point')
    manifest_path = package / MANIFEST
    regular(manifest_path)
    if digest(manifest_path) != expected_manifest:
        raise ValueError('manifest SHA256 mismatch')
    if manifest_path.stat().st_size > 1024 * 1024:
        raise ValueError('manifest too large')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'), object_pairs_hook=unique_object)
    if manifest.get('schema') not in (SCHEMA, SCHEMA_V2) or manifest.get('architecture') != 'native-x64' or manifest.get('scope') != 'registration-activation-only-development':
        raise ValueError('unsupported package identity')
    if manifest.get('identity') != IDENTITY:
        raise ValueError('fixed 18u product identity required')
    if manifest.get('targetHost') != 'MyComputer' or manifest.get('defaultOperation') != 'read-only-preflight':
        raise ValueError('unsupported target or default operation')
    for flag in ('userDesktopExecutionApproved', 'registrationExecutionApproved', 'brokerEditingVerified', 'physicalAcceptance'):
        if manifest.get(flag) is not False:
            raise ValueError('package must not claim execution or acceptance')
    if not isinstance(manifest.get('sourceCommit'), str) or not HEX40.fullmatch(manifest['sourceCommit']):
        raise ValueError('fixed source commit required')
    entries = manifest.get('files')
    if not isinstance(entries, list) or not entries or len(entries) > 32:
        raise ValueError('invalid manifest file list')
    files = {}
    for entry in entries:
        name = entry.get('path') if isinstance(entry, dict) else None
        if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9_.-]+', name) or name in ('.', '..', MANIFEST):
            raise ValueError('only flat named payload files allowed')
        if name.casefold() in {p.casefold() for p in files}:
            raise ValueError('duplicate payload path')
        sha = entry.get('sha256')
        size = entry.get('bytes')
        if not isinstance(sha, str) or not HEX64.fullmatch(sha) or type(size) is not int or size < 0:
            raise ValueError('invalid payload identity')
        path = package / name
        regular(path)
        if path.stat().st_size != size or digest(path) != sha:
            raise ValueError('payload identity mismatch')
        files[name] = entry
    expected_payload = PAYLOAD_V2 if manifest['schema'] == SCHEMA_V2 else PAYLOAD
    if set(files) != expected_payload or set(p.name for p in package.iterdir()) != expected_payload | {MANIFEST}:
        raise ValueError('package file set mismatch')
    for name in (EXE, DLL, 'collect_mycomputer_preflight.py', 'windows_job_once.py'):
        if name not in files:
            raise ValueError('required fixed payload missing')
    pe_identity(package / EXE, False)
    pe_identity(package / DLL, True)
    return manifest, files


def utc():
    return datetime.now(timezone.utc).isoformat()


def collect(package, evidence, expected_manifest, timeout=30, runner=None):
    package, evidence = Path(package).absolute(), Path(evidence).absolute()
    if type(timeout) is not int or not 1 <= timeout <= 120:
        raise ValueError('timeout must be 1..120 seconds')
    manifest, files = validate_package(package, expected_manifest)
    if evidence.is_symlink() or (evidence.exists() and getattr(evidence.lstat(), 'st_file_attributes', 0) & 0x400):
        raise ValueError('evidence must not be a reparse point')
    # Resolve existing ancestors too: a junction/symlink alias must not put the
    # supposedly external output directory inside the package.
    package = package.resolve(strict=True)
    evidence = evidence.resolve(strict=False)
    if evidence == package or package in evidence.parents:
        raise ValueError('evidence must be outside package')
    # Refuse a collector imported/executed from another unpinned location.
    if Path(__file__).resolve() != (package / 'collect_mycomputer_preflight.py').resolve():
        raise ValueError('run the verified package collector')
    if runner is None:
        # Load the helper only AFTER its bytes have been checked; do not create
        # __pycache__ inside the immutable package or resolve a PYTHONPATH module.
        import importlib.util
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location('pinned_preflight_job', package / 'windows_job_once.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        runner = helper.run_once
    evidence.mkdir(parents=False, exist_ok=False)
    command = [str(package / EXE), '--preflight', '--dll', str(package / DLL), '--sha256', files[DLL]['sha256']]
    receipt = {'schema': 'mycomputer-preflight-collection-v1', 'sourceCommit': manifest['sourceCommit'],
               'manifestSha256': expected_manifest, 'collectorSha256': files['collect_mycomputer_preflight.py']['sha256'],
               'jobHelperSha256': files['windows_job_once.py']['sha256'], 'exeSha256': files[EXE]['sha256'],
               'dllSha256': files[DLL]['sha256'], 'mode': 'preflight', 'startedUtc': utc(),
               'completedUtc': None, 'timeoutSeconds': timeout, 'process': None,
               'stdout': None, 'stderr': None, 'status': 'incomplete',
               'registrationAttemptedByCollector': False, 'noWritesProven': False}
    receipt_path = evidence / 'collection.json'
    def save():
        temporary = evidence / 'collection.json.tmp'
        with temporary.open('w', encoding='utf-8', newline='\n') as stream:
            stream.write(json.dumps(receipt, ensure_ascii=True, indent=2) + '\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, receipt_path)
    save()
    try:
        process = runner(command, evidence, evidence / 'stdout.txt', evidence / 'stderr.txt', timeout)
        receipt['process'] = process
        receipt['status'] = 'collected' if process.get('started') is True and process.get('treeStopped') is True and process.get('timedOut') is False and process.get('errorCode') is None and process.get('exitCode') == 0 else 'failed-or-inconclusive'
    except OSError:
        receipt['status'] = 'launch-error-or-inconclusive'
    finally:
        receipt['completedUtc'] = utc()
        for name in ('stdout', 'stderr'):
            path = evidence / (name + '.txt')
            if path.is_file():
                receipt[name] = {'path': path.name, 'bytes': path.stat().st_size, 'sha256': digest(path)}
        save()
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--timeout-seconds', type=int, default=30)
    args = parser.parse_args()
    try:
        receipt = collect(args.package, args.evidence, args.manifest_sha256, args.timeout_seconds)
        print(json.dumps(receipt, ensure_ascii=True))
        return 0 if receipt['status'] == 'collected' else 3
    except (ValueError, OSError, KeyError, TypeError):
        print('Preflight collection blocked: package, identity, path or evidence validation failed.', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
