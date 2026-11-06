"""Read-only static ARM64 .9 artifact audit; only the new JSON report is written.

ZIP members are read in memory, never extracted, executed, imported, or loaded.
Authenticode observations are CI records bound to file hashes, not a new local
signature check. Successful static verification is not installed acceptance.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys
import zipfile

VERSION = '0.2.0-18u-arm64.9'
ZIP_NAME = 'YimeCore-18u-' + VERSION + '-windows-arm64.zip'
PROTOCOL = {'version': 2, 'pipePrefix': 'Yime18u.Frontend.v2.'}
IDENTITY = {'clsid': '{6DFACE1F-562E-4773-A9D6-D5753A314711}',
            'profile': '{1BD904AC-3194-4419-B70A-5574100F18B3}'}
INSTALLER = {'Setup.ps1', 'Product.psm1', 'Setup.cmd'}
TOP_FILES = INSTALLER | {'product-package.json', 'package-evidence.json',
                         'signatures.json', 'README.zh-CN.md'}
PE_FILES = {'payload/arm64/YimeTextService18u.dll',
            'payload/arm64/Yime18uProductRegistration.exe',
            'payload/arm64/YimeTouchRegisteredFormalHostTests.exe',
            'payload/bin/YimeBroker18u.exe',
            'payload/bin/Yime18uInstalledRuntime.exe',
            'payload/frontend/YimeTouchKeyboard.exe'}
FRONT = 'payload/frontend/'
DATA = {'ascii_keyboard_manifest.json', 'yime_variable.dict.yaml',
        'yime_full.dict.yaml', 'yime_shorthand.dict.yaml'}
SOURCE_MAP = {
    'payload/profile-icon.ico': 'go-backend/input_methods/yime/icons/yime_qin_seal_yin.ico',
    'payload/source/tools/yimecore/18u-touch-product-arm64.json': 'tools/yimecore/18u-touch-product-arm64.json',
    'payload/source/prototypes/touch-terminal/desktop/resources.lock.json': 'prototypes/touch-terminal/desktop/resources.lock.json',
    'payload/source/prototypes/touch-terminal/data/physical-layout.json': 'prototypes/touch-terminal/data/physical-layout.json',
    'payload/source/prototypes/touch-terminal/encoding/yime_yinyuan_layout.json': 'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json',
    'payload/source/internal_data/yime_syllable_decomposition.tsv': 'internal_data/yime_syllable_decomposition.tsv',
}
FRONT_ASSETS = {
    'prototypes/touch-terminal/data/physical-layout.json',
    'prototypes/touch-terminal/encoding/manual_key_layout.resolved.json',
    'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json',
    'go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf',
    'internal_data/yime_syllable_decomposition.tsv',
} | {'prototypes/touch-terminal/desktop/profiles/' + name for name in
     ('main-only.json', 'main-17u.json', 'full-size.json', 'full-23u.json', '17u-provenance.json')}
FRONT_FILES = FRONT_ASSETS | {'resources.lock.json', 'USER_GUIDE.zh-CN.md',
    'README.txt', 'Start Installed Touch Keyboard.cmd', 'Start Local Preview.cmd',
    'Check Package.cmd', 'resources.json', 'manifest.json', 'YimeTouchKeyboard.exe'} | {'data/' + n for n in DATA}
MAX_SMALL = 8 * 1024 * 1024
MAX_MEMBER = 512 * 1024 * 1024
MAX_TOTAL = 2 * 1024 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(raw):
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


def file_digest(path):
    with path.open('rb') as stream:
        sha, count = hashlib.sha256(), 0
        while chunk := stream.read(1024 * 1024):
            sha.update(chunk)
            count += len(chunk)
    return {'bytes': count, 'sha256': sha.hexdigest()}


def plain_path(path):
    path = Path(path).absolute()
    for item in (path, *path.parents):
        require(not item.is_symlink() and not (hasattr(item, 'is_junction') and item.is_junction()),
                'linked filesystem path refused: ' + str(item))
    return path


def safe_name(name):
    require(isinstance(name, str) and name and '\\' not in name and not name.startswith('/'), 'unsafe member path')
    require(not any(ord(c) < 32 or c in ':<>"|?*' for c in name), 'unsafe member characters')
    reserved = {'CON', 'PRN', 'AUX', 'NUL', 'CONIN$', 'CONOUT$'} | {p + n for p in ('COM', 'LPT') for n in '123456789¹²³'}
    require(all(p and p not in ('.', '..') and not p.endswith((' ', '.')) and
                p.split('.')[0].upper() not in reserved for p in name.split('/')), 'unsafe member component')
    return name


def json_object(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'duplicate JSON member: ' + key)
            result[key] = value
        return result
    def nonfinite(value):
        raise ValueError('non-finite JSON number: ' + value)
    require(len(raw) <= MAX_SMALL, 'JSON exceeds size bound')
    result = json.loads(raw.decode('utf-8-sig'), object_pairs_hook=unique, parse_constant=nonfinite)
    require(isinstance(result, dict), 'JSON object required')
    return result


def record(value):
    require(isinstance(value, dict) and set(value) == {'bytes', 'sha256'}, 'invalid digest record')
    require(type(value['bytes']) is int and 0 <= value['bytes'] <= MAX_MEMBER, 'invalid byte count')
    require(isinstance(value['sha256'], str) and re.fullmatch('[0-9a-f]{64}', value['sha256']), 'invalid SHA-256')
    return value


def inventory(value, hashes_only=False):
    require(isinstance(value, dict), 'inventory object required')
    seen = set()
    for name, value_record in value.items():
        safe_name(name)
        require(name.casefold() not in seen, 'aliased inventory path: ' + name)
        seen.add(name.casefold())
        record({'bytes': 0, 'sha256': value_record} if hashes_only else value_record)
    return value


def row_inventory(rows):
    require(isinstance(rows, list), 'inventory rows required')
    result = {}
    for row in rows:
        require(isinstance(row, dict) and set(row) == {'path', 'bytes', 'sha256'}, 'invalid inventory row')
        name = safe_name(row['path'])
        require(name not in result, 'duplicate inventory row: ' + name)
        result[name] = record({k: row[k] for k in ('bytes', 'sha256')})
    return inventory(result)


def zip_members(archive):
    result, folded, total = {}, set(), 0
    entries = archive.infolist()
    require(0 < len(entries) <= 100, 'ZIP member count outside bounds')
    for info in entries:
        require(info.filename == info.orig_filename and not info.is_dir(), 'rewritten or directory ZIP entry')
        name = safe_name(info.filename)
        require(name.casefold() not in folded, 'duplicate ZIP member: ' + name)
        folded.add(name.casefold())
        kind = stat.S_IFMT((info.external_attr >> 16) & 0xffff)
        require(kind in (0, stat.S_IFREG), 'linked or special ZIP entry: ' + name)
        require(not info.flag_bits & 1 and info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), 'unsupported ZIP encoding')
        require(0 <= info.file_size <= MAX_MEMBER, 'ZIP member exceeds bound')
        total += info.file_size
        require(total <= MAX_TOTAL, 'ZIP expanded size exceeds bound')
        result[name] = info
    for name in folded:
        parts = name.split('/')
        require(all('/'.join(parts[:n]) not in folded for n in range(1, len(parts))), 'file/directory path collision')
    return result


def scan(archive, files):
    actual, pe_names = {}, set()
    for name, info in files.items():
        sha, count, prefix = hashlib.sha256(), 0, b''
        with archive.open(info) as stream:
            while chunk := stream.read(1024 * 1024):
                if not prefix:
                    prefix = chunk[:2]
                sha.update(chunk)
                count += len(chunk)
        require(count == info.file_size, 'ZIP member length mismatch: ' + name)
        actual[name] = {'bytes': count, 'sha256': sha.hexdigest()}
        if prefix == b'MZ' or name.lower().endswith(('.exe', '.dll')):
            pe_names.add(name)
    return actual, pe_names  # Reading through EOF also verifies every ZIP CRC.


def git(repo, *args, raw=None):
    return subprocess.run(['git', '-c', 'core.fsmonitor=false', *args], cwd=repo,
                          input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          check=True, timeout=30).stdout


def source_bytes(repo, source, path):
    return git(repo, 'show', source + ':' + path)


def source_match(repo, source, path, raw):
    expected = git(repo, 'rev-parse', source + ':' + path).decode().strip()
    original = source_bytes(repo, source, path)
    # Do not run Git clean filters or let current checkout attributes define
    # source identity. Compare against the requested commit's actual blob;
    # known text assets may differ only by Windows checkout line endings.
    text_asset = Path(path).suffix.lower() in {'.ps1', '.psm1', '.cmd', '.json', '.md', '.tsv', '.py'}
    exact = raw == original
    equivalent_text = text_asset and raw.replace(b'\r\n', b'\n') == original.replace(b'\r\n', b'\n')
    require(exact or equivalent_text, 'fixed-source Git blob mismatch: ' + path)
    raw_blob = hashlib.sha1(b'blob ' + str(len(raw)).encode('ascii') + b'\0' + raw).hexdigest()
    return {'sourcePath': path, 'expectedGitBlob': expected, 'observedRawGitBlob': raw_blob,
            'sourceBlobBytes': digest(original),
            'comparison': 'exact bytes' if exact else 'text differs only by CRLF/LF checkout line endings',
            **digest(raw)}


def protocol(value):
    require(isinstance(value, dict) and type(value.get('version')) is int and value == PROTOCOL,
            'frontend v2 protocol mismatch')


def verify_inner(archive, source, repo):
    files = zip_members(archive)
    require(len(files) == 46, 'expected exactly 46 package files')
    actual, pe_names = scan(archive, files)
    require({n for n in files if not n.startswith('payload/')} == TOP_FILES, 'package root inventory mismatch')
    def read(name, limit=MAX_SMALL):
        require(name in files and files[name].file_size <= limit, 'missing or oversized member: ' + name)
        return archive.read(files[name])
    def doc(name):
        return json_object(read(name))
    evidence = doc('package-evidence.json')
    require(evidence.get('schema') == 'installed-18u-package-evidence-v1' and
            evidence.get('sourceCommit') == source and evidence.get('version') == VERSION and
            evidence.get('product') == 'yimecore-18u' and evidence.get('architecture') == 'native-arm64', 'package evidence identity mismatch')
    require(all(evidence.get(k) is False for k in ('installationExecuted', 'registrationExecuted', 'installedHostAcceptance')), 'package evidence claims execution')
    require(evidence.get('publisherTrust') == 'not-established' and evidence.get('nonPESignatureStatus') == 'not-evaluated', 'unexpected package trust claim')
    protocol(evidence.get('frontendProtocol'))
    require(inventory(evidence.get('files')) == {n: r for n, r in actual.items() if n != 'package-evidence.json'}, 'complete evidence size/hash mismatch')
    payload = {n[8:]: r for n, r in actual.items() if n.startswith('payload/')}
    expected_names = {n[8:] for n in SOURCE_MAP} | {'data/' + n for n in DATA} | {'frontend/' + n for n in FRONT_FILES} | {n[8:] for n in PE_FILES if not n.startswith(FRONT)} | {'installed-18u-product.json'}
    require(len(payload) == 39 and set(payload) == expected_names, 'exact 39-file payload inventory mismatch')
    simple = doc('product-package.json')
    require(set(simple) == {'format', 'product', 'version', 'target', 'host_architecture', 'tsf64_architecture', 'files'}, 'simple manifest fields mismatch')
    require(tuple(simple[k] for k in ('format', 'product', 'version', 'target', 'host_architecture', 'tsf64_architecture')) ==
            ('yime-simple-package-18u-1', 'yimecore-18u', VERSION, 'windows-arm64', 'arm64', 'arm64'), 'simple manifest identity mismatch')
    require(row_inventory(simple['files']) == payload, 'simple manifest payload size/hash mismatch')
    descriptor = doc('payload/installed-18u-product.json')
    require(set(descriptor) == {'schema', 'product', 'sourceCommit', 'identity', 'architecture', 'language', 'mode', 'autostart', 'files'}, 'installed descriptor fields mismatch')
    require(descriptor['schema'] == 'installed-18u-product-v1' and descriptor['product'] == 'yimecore-18u' and
            descriptor['sourceCommit'] == source and descriptor['identity'] == IDENTITY and descriptor['architecture'] == 'native-arm64' and
            descriptor['language'] == 'CN' and descriptor['mode'] == 'variable' and descriptor['autostart'] is False, 'installed descriptor identity mismatch')
    require(len(descriptor['files']) == 38 and row_inventory(descriptor['files']) == {n: r for n, r in payload.items() if n != 'installed-18u-product.json'}, 'descriptor 38-file size/hash mismatch')

    front_actual = {n[len(FRONT):]: r for n, r in actual.items() if n.startswith(FRONT)}
    front = doc(FRONT + 'manifest.json')
    require(front.get('schemaVersion') == 2 and front.get('scope') == 'installed-18u-tsf-frontend-candidate' and
            front.get('sourceCommit') == source and front.get('sourceChanges') is False and front.get('architecture') == 'windows-arm64' and
            front.get('sendInputFallback') is False and front.get('defaultMode') == 'installed-tsf-auto-focus' and
            front.get('defaultLauncher') == 'Start Installed Touch Keyboard.cmd' and front.get('completeChineseResources') is True, 'frontend identity mismatch')
    protocol(front.get('frontendProtocol'))
    require(all(front.get(k) is False for k in ('hardwareAcceptance', 'installedProductAcceptance', 'arm64NativeAcceptance')), 'frontend claims acceptance')
    require(inventory(front.get('files'), True) == {n: r['sha256'] for n, r in front_actual.items() if n != 'manifest.json'}, 'frontend file hashes mismatch')
    if 'ci' in front:
        require(isinstance(front['ci'], dict) and front['ci'].get('checkoutCommit') == source, 'frontend CI source mismatch')
    resources = doc(FRONT + 'resources.json')
    require(resources.get('schemaVersion') == 1 and resources.get('scope') == 'isolated-cn134-portable-resources' and
            resources.get('sourceCommit') == source and resources.get('sourceChanges') is False and resources.get('architecture') == 'windows-arm64', 'frontend resources identity mismatch')
    require(inventory(resources.get('files'), True) == {n: r['sha256'] for n, r in front_actual.items() if n not in {'manifest.json', 'resources.json', 'YimeTouchKeyboard.exe'}}, 'frontend resource inventory mismatch')
    require(front.get('portableResourcesSHA256') == front_actual['resources.json']['sha256'], 'portable resources hash mismatch')

    source_results = {name: source_match(repo, source, 'installer/simple/' + name, read(name)) for name in sorted(INSTALLER)}
    for name, path in SOURCE_MAP.items():
        source_results[name] = source_match(repo, source, path, read(name))
    for path in sorted(FRONT_ASSETS):
        # The fixed private font is 16,024,176 bytes; it is a binary asset,
        # not a small JSON/text record. Keep a bounded read and exact source match.
        limit = 64 * 1024 * 1024 if path.endswith('.ttf') else MAX_SMALL
        source_results[FRONT + path] = source_match(repo, source, path, read(FRONT + path, limit))
    for name, path in {'USER_GUIDE.zh-CN.md': 'prototypes/touch-terminal/desktop/INSTALLED_TSF.zh-CN.md',
                       'resources.lock.json': 'prototypes/touch-terminal/desktop/resources.lock.json'}.items():
        source_results[FRONT + name] = source_match(repo, source, path, read(FRONT + name))
    setup = read('Setup.ps1').decode('utf-8-sig')
    function = setup.split('function Clear-Owned18uLegacyStartup(', 1)
    require(len(function) == 2, 'legacy startup helper missing')
    body = function[1].split("\n$legacy18uStartup=", 1)[0]
    require('-MethodName EnumValues' in body and '-MethodName GetStringValue' in body and
            body.index('-MethodName EnumValues') < body.index('-MethodName GetStringValue') and
            '$runName -notin @($listed.sNames)' in body, 'EnumValues missing-value guard absent')
    lock_path = 'prototypes/touch-terminal/desktop/resources.lock.json'
    lock = json_object(source_bytes(repo, source, lock_path))
    package_lock = doc('payload/source/' + lock_path)
    require(lock == package_lock == doc(FRONT + 'resources.lock.json') and lock.get('schemaVersion') == 1 and set(lock.get('files', {})) == DATA, 'fixed source resource lock mismatch')
    require(front.get('resourceArchiveSHA256') == lock.get('archiveSHA256'), 'frontend source archive mismatch')
    locked_data = inventory(lock['files'])
    for name, expected in locked_data.items():
        require(actual['payload/data/' + name] == expected == actual[FRONT + 'data/' + name], 'locked dictionary mismatch: ' + name)
    product = doc('payload/source/tools/yimecore/18u-touch-product-arm64.json')
    canonical = json_object(source_bytes(repo, source, 'tools/yimecore/18u-touch-product.json'))
    require(canonical.get('scope', {}).get('architecture') == 'x64', 'canonical product architecture mismatch')
    canonical['scope']['architecture'] = 'arm64'
    require(product == canonical and all(product.get('identity', {}).get(k) == v for k, v in IDENTITY.items()), 'ARM64 source product mismatch')
    projection = product.get('data', {})
    require(projection.get('standard_index_fallback') is False and projection.get('layout_sha256') == lock.get('layoutProjectionSHA256') and
            projection.get('dictionary_sha256') == locked_data['yime_variable.dict.yaml']['sha256'], 'product resource identity mismatch')
    for name in ('prototypes/touch-terminal/data/physical-layout.json', 'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json'):
        require(actual['payload/source/' + name] == actual[FRONT + name], 'frontend/source projection mismatch')
    require(doc('payload/source/prototypes/touch-terminal/data/physical-layout.json').get('layoutId') == projection['layout_sha256'], 'physical layout identity mismatch')

    require(pe_names == PE_FILES, 'six-PE inventory mismatch')
    pe_results = {}
    for name in sorted(PE_FILES):
        raw = read(name, 128 * 1024 * 1024)
        require(len(raw) >= 64 and raw[:2] == b'MZ', 'invalid DOS header: ' + name)
        offset = struct.unpack_from('<I', raw, 60)[0]
        require(offset >= 64 and offset + 26 <= len(raw) and raw[offset:offset + 4] == b'PE\0\0', 'invalid PE header: ' + name)
        require(struct.unpack_from('<H', raw, offset + 4)[0] == 0xaa64 and struct.unpack_from('<H', raw, offset + 24)[0] == 0x20b, 'native ARM64 PE32+ required: ' + name)
        require(all('Yime18u.Frontend.v1.'.encode(e) not in raw for e in ('ascii', 'utf-16-le')), 'v1 frontend marker refused: ' + name)
        marker = None
        if name == FRONT + 'YimeTouchKeyboard.exe':
            marker = 'ascii'
            require(front['portableResourcesSHA256'].encode('ascii') in raw, 'compiled portable-resource hash missing')
        elif name == 'payload/arm64/YimeTextService18u.dll':
            marker = 'utf-16-le'
        if marker:
            require(PROTOCOL['pipePrefix'].encode(marker) in raw, 'v2 protocol marker missing: ' + name)
        pe_results[name] = {**actual[name], 'machine': '0xaa64', 'optionalHeader': '0x020b', 'v1MarkerAbsent': True, 'v2MarkerEncoding': marker}
    signatures = doc('signatures.json')
    require(set(signatures) == {'schema', 'sourceCommit', 'files'} and signatures['schema'] == 'installed-18u-signatures-v1' and
            signatures['sourceCommit'] == source and isinstance(signatures['files'], list), 'signature record identity mismatch')
    seen = set()
    for row in signatures['files']:
        require(isinstance(row, dict) and set(row) == {'path', 'bytes', 'sha256', 'status', 'signerThumbprint'}, 'invalid signature row')
        name = row['path']
        require(isinstance(name, str) and name in PE_FILES and name not in seen, 'signature inventory mismatch')
        seen.add(name)
        require(record({k: row[k] for k in ('bytes', 'sha256')}) == actual[name], 'signature file size/hash mismatch')
        require(row['status'] in {'Valid', 'UnknownError', 'NotSigned', 'HashMismatch', 'NotTrusted', 'NotSupportedFileFormat', 'Incompatible'}, 'invalid signature status')
        thumb = row['signerThumbprint']
        require(thumb is None or isinstance(thumb, str) and re.fullmatch('[0-9a-fA-F]{40}', thumb), 'invalid signer thumbprint')
        require(not (row['status'] == 'NotSigned' and thumb is not None) and not (row['status'] == 'Valid' and thumb is None), 'inconsistent signature claim')
        pe_results[name].update(recordedAuthenticodeStatus=row['status'], recordedSignerThumbprint=thumb)
    require(seen == PE_FILES, 'incomplete signatures')
    return {'fileCount': len(files), 'payloadCount': len(payload), 'descriptorFileCount': len(descriptor['files']),
            'expandedBytes': sum(r['bytes'] for r in actual.values()), 'allFilesVerified': True, 'crcVerified': True,
            'packageEvidence': actual['package-evidence.json'], 'installedDescriptor': actual['payload/installed-18u-product.json'],
            'productManifest': actual['product-package.json'], 'frontendManifest': actual[FRONT + 'manifest.json'],
            'frontendResources': actual[FRONT + 'resources.json'], 'signatures': actual['signatures.json'],
            'frontendProtocol': PROTOCOL, 'lockedData': locked_data, 'resourceLock': actual['payload/source/' + lock_path],
            'fixedSourceFiles': source_results, 'legacyStartupEnumValuesVerified': True, 'peFiles': pe_results,
            'files': actual, 'signatureObservation': 'CI-recorded observations bound to payload hashes; no local Authenticode execution',
            'publisherTrust': 'not-established'}


def verify(args):
    require(re.fullmatch('[0-9a-f]{40}', args.source_commit), 'full lowercase source SHA required')
    require(re.fullmatch('[0-9a-f]{64}', args.expected_outer_sha256), 'expected outer SHA-256 required')
    outer, output = plain_path(args.archive), plain_path(args.output)
    require(outer.is_file(), 'archive must be a regular file')
    require(not output.exists() and output != outer and output != Path(__file__).absolute(), 'new report path required; no overwrite')
    require(output.parent.is_dir(), 'report parent must already exist')
    repo = Path(git(Path(__file__).parent, 'rev-parse', '--show-toplevel').decode().strip())
    require(git(repo, 'rev-parse', args.source_commit + '^{commit}').decode().strip() == args.source_commit, 'source must identify an existing exact commit')
    report = {'schema': 'installed-18u-arm64-dot9-static-verification-v1', 'status': 'failed',
              'verifiedAtUTC': datetime.now(timezone.utc).isoformat(), 'sourceCommit': args.source_commit,
              'version': VERSION, 'scope': 'read-only-archive-static-verification',
              'verifierScript': file_digest(Path(__file__)), 'installerExecuted': False, 'productBinaryExecuted': False,
              'installationExecuted': False, 'registrationExecuted': False, 'defaultInputChanged': False,
              'userDataChanged': False, 'installedHostAcceptance': False, 'physicalAcceptance': False}
    try:
        outer_digest = file_digest(outer)
        report['outerArchive'] = {'path': str(outer), **outer_digest, 'expectedSHA256': args.expected_outer_sha256}
        require(outer_digest['sha256'] == args.expected_outer_sha256, 'outer archive SHA-256 mismatch')
        with zipfile.ZipFile(outer) as archive:
            files = zip_members(archive)
            require(set(files) == {ZIP_NAME}, 'outer archive must contain only the expected .9 ZIP')
            inner_raw = archive.read(files[ZIP_NAME])
        inner_digest = digest(inner_raw)
        report['innerArchive'] = {'name': ZIP_NAME, **inner_digest}
        with zipfile.ZipFile(io.BytesIO(inner_raw)) as archive:
            report['verification'] = verify_inner(archive, args.source_commit, repo)
        require(file_digest(outer) == outer_digest, 'outer archive changed during verification')
        report['outerArchive']['crcVerified'] = True
        report['status'] = 'passed'
    except Exception as exc:
        report['error'] = f'{type(exc).__name__}: {exc}'
        raise
    finally:
        with output.open('x', encoding='utf-8', newline='\n') as stream:
            json.dump(report, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--output', type=Path, required=True, help='new JSON file in an existing evidence directory')
    parser.add_argument('--expected-outer-sha256', required=True)
    args = parser.parse_args()
    try:
        print(verify(args))
    except Exception as exc:
        print(f'VERIFICATION FAILED: {type(exc).__name__}: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
