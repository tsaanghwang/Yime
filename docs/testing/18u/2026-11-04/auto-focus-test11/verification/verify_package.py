"""Read-only test.11 artifact verification; never runs package code or installs anything.

Only the unique inner archive and small evidence files are copied to a NEW output
directory. Product members are read directly from the inner ZIP, not extracted.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import stat
import struct
import sys
import zipfile

VERSION = '0.1.0-18u-test.11'
ZIP_NAME = 'YimeCore-18u-' + VERSION + '-windows-amd64.zip'
PROTOCOL = {'version': 2, 'pipePrefix': 'Yime18u.Frontend.v2.'}
IDENTITY = {'clsid': '{6DFACE1F-562E-4773-A9D6-D5753A314711}',
            'profile': '{1BD904AC-3194-4419-B70A-5574100F18B3}'}
LAYOUT_SHA = '995f1a74f129249febbd09ca11a8266f6e0c94bac8c05c57754859fc3be3349c'
LOCK_SHA = '51f09b493b96a2064022a99a1f46103d02c28e32d2883695b6ca24671037e313'
ARCHIVE_SHA = '9f01dc384aa2a52281a882a7fc5f675a0282bf073f9033610a3b0681b32b14bd'
DATA = {
    'ascii_keyboard_manifest.json': {'bytes': 3927, 'sha256': 'cc1f48ded862e0e25a2b799c076c7c79ce5fa6425093e124fe96b5985d940843'},
    'yime_full.dict.yaml': {'bytes': 81236859, 'sha256': '85ff8a88dfe5a66a22429c9551c2625815af83351973db30f8faeb52fced3790'},
    'yime_variable.dict.yaml': {'bytes': 77254107, 'sha256': '43a74f4e47c7100f222a744f487762f1c31222c5f80b9a34fd24cbebc7e96353'},
    'yime_shorthand.dict.yaml': {'bytes': 75381670, 'sha256': 'b58c85d6b1d18fa72d8134b581ccdec71e434d8ec20d086306ff8b4f94a23d49'},
}
PE_FILES = {
    'payload/x64/YimeTextService18u.dll',
    'payload/x64/Yime18uProductRegistration.exe',
    'payload/x64/YimeTouchRegisteredFormalHostTests.exe',
    'payload/bin/YimeBroker18u.exe',
    'payload/bin/Yime18uInstalledRuntime.exe',
    'payload/frontend/YimeTouchKeyboard.exe',
}
INSTALLER_FILES = {'Product.psm1', 'Setup.ps1', 'Setup.cmd'}
TOP_FILES = INSTALLER_FILES | {'product-package.json', 'package-evidence.json', 'signatures.json', 'README.zh-CN.md'}
FRONT = 'payload/frontend/'
SOURCE_RESOURCES = {
    'profile-icon.ico', 'source/prototypes/touch-terminal/desktop/resources.lock.json',
    'source/tools/yimecore/18u-touch-product.json',
    'source/prototypes/touch-terminal/data/physical-layout.json',
    'source/prototypes/touch-terminal/encoding/yime_yinyuan_layout.json',
    'source/internal_data/yime_syllable_decomposition.tsv',
}
FRONTEND_ASSETS = {
    'prototypes/touch-terminal/data/physical-layout.json',
    'prototypes/touch-terminal/encoding/manual_key_layout.resolved.json',
    'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json',
    'go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf',
    'internal_data/yime_syllable_decomposition.tsv',
} | {'prototypes/touch-terminal/desktop/profiles/' + name for name in
     ('main-only.json', 'main-17u.json', 'full-size.json', 'full-23u.json', '17u-provenance.json')}
FRONTEND_FIXED = FRONTEND_ASSETS | {
    'resources.lock.json', 'USER_GUIDE.zh-CN.md', 'README.txt',
    'Start Installed Touch Keyboard.cmd', 'Start Local Preview.cmd', 'Check Package.cmd',
    'resources.json', 'manifest.json', 'YimeTouchKeyboard.exe',
}
MAX_SMALL = 8 * 1024 * 1024
MAX_FILE = 2 * 1024 * 1024 * 1024
MAX_TOTAL = 4 * 1024 * 1024 * 1024
NO_ACTIONS = {
    'installerExecuted': False, 'installationExecuted': False,
    'registrationExecuted': False, 'defaultInputChanged': False,
    'test8Repeated': False, 'productBinaryExecuted': False,
    'installedHostAcceptance': False, 'physicalAcceptance': False,
}


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def safe_path(name):
    """Portable ZIP member names with Windows extraction aliases excluded."""
    require(isinstance(name, str) and name and '\\' not in name and not name.startswith('/'), 'unsafe archive path')
    require(not any(ord(c) < 32 for c in name) and not any(c in name for c in ':<>"|?*'), 'unsafe archive path characters')
    parts = name.split('/')
    reserved = {'CON', 'PRN', 'AUX', 'NUL', 'CONIN$', 'CONOUT$'} | {f'{p}{n}' for p in ('COM', 'LPT') for n in '123456789¹²³'}
    require(all(p and p not in ('.', '..') and not p.endswith((' ', '.')) and p.split('.')[0].upper() not in reserved for p in parts), 'unsafe archive path component')
    return '/'.join(parts)


def regular(path):
    path = Path(path).absolute()
    for part in (path, *path.parents):
        require(not part.is_symlink() and not (hasattr(part, 'is_junction') and part.is_junction()), 'linked filesystem path refused')
    require(path.is_file(), 'regular input file required: ' + str(path))
    return path


def new_output(path, inputs):
    path = Path(path).absolute()
    for part in (path, *path.parents):
        require(not part.is_symlink() and not (hasattr(part, 'is_junction') and part.is_junction()), 'linked output refused')
    require(not path.exists(), 'new output directory required; no overwrite')
    require(all(path != p and path not in p.parents for p in inputs), 'output overlaps inputs')
    path.mkdir(parents=True, exist_ok=False)
    return path


def digest_bytes(raw):
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


def digest_file(path):
    with regular(path).open('rb') as stream:
        return {'bytes': path.stat().st_size, 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}


def unique_json(raw):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            require(key not in value, 'duplicate JSON member: ' + key)
            value[key] = item
        return value
    def constant(value):
        raise ValueError('non-finite JSON number: ' + value)
    require(len(raw) <= MAX_SMALL, 'JSON input exceeds size bound')
    result = json.loads(raw.decode('utf-8-sig'), object_pairs_hook=unique, parse_constant=constant)
    require(isinstance(result, dict), 'JSON object required')
    return result


def record(value):
    require(isinstance(value, dict) and set(value) == {'bytes', 'sha256'}, 'invalid digest record')
    require(type(value['bytes']) is int and 0 <= value['bytes'] <= MAX_FILE, 'invalid byte count')
    require(isinstance(value['sha256'], str) and re.fullmatch('[0-9a-f]{64}', value['sha256']), 'invalid SHA-256')
    return value


def digest_inventory(value):
    require(isinstance(value, dict), 'inventory object required')
    folded = set()
    for name, item in value.items():
        safe_path(name)
        require(name.casefold() not in folded, 'case-insensitive duplicate inventory path')
        folded.add(name.casefold())
        record(item)
    return value


def rows_inventory(rows):
    require(isinstance(rows, list), 'inventory rows required')
    result = {}
    for row in rows:
        require(isinstance(row, dict) and set(row) == {'path', 'bytes', 'sha256'}, 'invalid inventory row')
        name = safe_path(row['path'])
        require(name not in result, 'duplicate inventory row')
        result[name] = record({k: row[k] for k in ('bytes', 'sha256')})
    return digest_inventory(result)


def sha_inventory(value):
    require(isinstance(value, dict), 'SHA inventory object required')
    return digest_inventory({name: {'bytes': 0, 'sha256': sha} for name, sha in value.items()})


def members(archive):
    entries = archive.infolist()
    require(0 < len(entries) <= 10000, 'archive entry count outside bounds')
    paths, files, kinds = {}, {}, {}
    total = 0
    for info in entries:
        require(info.filename == info.orig_filename, 'NUL or rewritten ZIP member')
        is_dir = info.is_dir()
        name = safe_path(info.filename[:-1] if is_dir else info.filename)
        key = name.casefold()
        require(key not in paths, 'duplicate or aliased ZIP member: ' + name)
        paths[key], kinds[key] = name, is_dir
        mode = (info.external_attr >> 16) & 0xFFFF
        file_type = stat.S_IFMT(mode)
        require(file_type in (0, stat.S_IFDIR if is_dir else stat.S_IFREG), 'linked or special ZIP member: ' + name)
        require(not info.flag_bits & 1, 'encrypted ZIP member refused')
        require(info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), 'unexpected ZIP compression')
        require(0 <= info.file_size <= MAX_FILE, 'archive member exceeds size bound')
        total += info.file_size
        require(total <= MAX_TOTAL, 'archive expanded size exceeds bound')
        if is_dir:
            require(info.file_size == 0, 'nonempty ZIP directory')
        else:
            files[name] = info
    for key in paths:
        parts = key.split('/')
        for n in range(1, len(parts)):
            parent = '/'.join(parts[:n])
            require(parent not in kinds or kinds[parent], 'file/directory ZIP collision')
    return files


def read_small(archive, files, name):
    require(name in files and files[name].file_size <= MAX_SMALL, 'missing or excessive small evidence: ' + name)
    return archive.read(files[name])


def scan(archive, files):
    actual, pe_names = {}, set()
    for name, info in files.items():
        sha, count, prefix = hashlib.sha256(), 0, b''
        with archive.open(info) as stream:
            while chunk := stream.read(1024 * 1024):
                if not prefix:
                    prefix = chunk[:2]
                count += len(chunk)
                sha.update(chunk)
        # Reading every member through EOF verifies ZIP CRC for that member.
        require(count == info.file_size, 'ZIP member size mismatch: ' + name)
        actual[name] = {'bytes': count, 'sha256': sha.hexdigest()}
        if prefix == b'MZ' or name.lower().endswith(('.exe', '.dll')):
            pe_names.add(name)
    return actual, pe_names


def protocol(value):
    require(isinstance(value, dict) and type(value.get('version')) is int and value == PROTOCOL, 'frontend v2 protocol metadata required')


def verify_pe(archive, info):
    # Only read bytes: even an EXE member is never launched or DLL-loaded.
    require(info.file_size <= 256 * 1024 * 1024, 'PE file exceeds verification bound')
    raw = archive.read(info)
    require(len(raw) >= 64 and raw[:2] == b'MZ', 'missing PE DOS header: ' + info.filename)
    offset = struct.unpack_from('<I', raw, 60)[0]
    require(offset >= 64 and offset + 26 <= len(raw) and raw[offset:offset + 4] == b'PE\0\0', 'invalid PE header: ' + info.filename)
    require(struct.unpack_from('<H', raw, offset + 4)[0] == 0x8664 and struct.unpack_from('<H', raw, offset + 24)[0] == 0x20B, 'native AMD64 PE required: ' + info.filename)
    require(all('Yime18u.Frontend.v1.'.encode(enc) not in raw for enc in ('ascii', 'utf-16-le')), 'v1 frontend binary refused: ' + info.filename)
    if info.filename == FRONT + 'YimeTouchKeyboard.exe':
        require(PROTOCOL['pipePrefix'].encode('ascii') in raw, 'EXE ASCII v2 marker missing')
    elif info.filename == 'payload/x64/YimeTextService18u.dll':
        require(PROTOCOL['pipePrefix'].encode('utf-16-le') in raw, 'TIP UTF16LE v2 marker missing')
    return {'machine': '0x8664', 'optionalHeader': '0x020b', 'v1MarkerAbsent': True}


def verify_inner(archive, receipt, source):
    files = members(archive)
    actual, pe_names = scan(archive, files)
    require({name for name in files if not name.startswith('payload/')} == TOP_FILES, 'unexpected package root inventory')
    def doc(name):
        return unique_json(read_small(archive, files, name))
    evidence = doc('package-evidence.json')
    require(evidence.get('schema') == 'installed-18u-package-evidence-v1' and evidence.get('sourceCommit') == source
            and evidence.get('version') == VERSION and evidence.get('product') == 'yimecore-18u'
            and evidence.get('architecture') == 'native-x64', 'package evidence identity mismatch')
    require(all(evidence.get(k) is False for k in ('installationExecuted', 'registrationExecuted', 'installedHostAcceptance')), 'package evidence claims execution')
    protocol(evidence.get('frontendProtocol'))
    expected = digest_inventory(evidence.get('files'))
    require(expected == {n: r for n, r in actual.items() if n != 'package-evidence.json'}, 'complete package inventory/hash mismatch')
    require(actual['package-evidence.json'] == record(receipt['packageEvidence']), 'CI receipt package evidence mismatch')

    simple = doc('product-package.json')
    require(set(simple) == {'format', 'product', 'version', 'target', 'host_architecture', 'tsf64_architecture', 'files'}, 'simple manifest fields mismatch')
    require(tuple(simple[k] for k in ('format', 'product', 'version', 'target', 'host_architecture', 'tsf64_architecture'))
            == ('yime-simple-package-18u-1', 'yimecore-18u', VERSION, 'windows-amd64', 'amd64', 'x64'), 'simple manifest identity mismatch')
    payload = {n[len('payload/'):]: r for n, r in actual.items() if n.startswith('payload/')}
    frontend_names = FRONTEND_FIXED | {'data/' + n for n in DATA}
    expected_payload_names = (SOURCE_RESOURCES | {'data/' + n for n in DATA}
                              | {n[len('payload/'):] for n in PE_FILES if not n.startswith(FRONT)}
                              | {'frontend/' + n for n in frontend_names} | {'installed-18u-product.json'})
    require(set(payload) == expected_payload_names, 'complete fixed test.11 payload inventory mismatch')
    require(rows_inventory(simple['files']) == payload, 'simple payload inventory/hash mismatch')
    descriptor = doc('payload/installed-18u-product.json')
    require(set(descriptor) == {'schema', 'product', 'sourceCommit', 'identity', 'architecture', 'language', 'mode', 'autostart', 'files'}, 'installed descriptor fields mismatch')
    require(descriptor['schema'] == 'installed-18u-product-v1' and descriptor['product'] == 'yimecore-18u'
            and descriptor['sourceCommit'] == source and descriptor['identity'] == IDENTITY
            and descriptor['architecture'] == 'native-x64' and descriptor['language'] == 'CN'
            and descriptor['mode'] == 'variable' and descriptor['autostart'] is False, 'installed descriptor identity mismatch')
    require(rows_inventory(descriptor['files']) == {n: r for n, r in payload.items() if n != 'installed-18u-product.json'}, 'installed descriptor inventory/hash mismatch')
    require(payload['installed-18u-product.json'] == record(receipt['installedDescriptor']), 'CI receipt descriptor mismatch')

    front = doc(FRONT + 'manifest.json')
    require(front.get('schemaVersion') == 2 and front.get('scope') == 'installed-18u-tsf-frontend-candidate'
            and front.get('sourceCommit') == source and front.get('sourceChanges') is False
            and front.get('architecture') == 'windows-amd64' and front.get('sendInputFallback') is False
            and front.get('defaultMode') == 'installed-tsf-auto-focus'
            and front.get('defaultLauncher') == 'Start Installed Touch Keyboard.cmd'
            and front.get('completeChineseResources') is True, 'frontend clean-source/mode/architecture mismatch')
    protocol(front.get('frontendProtocol'))
    require(all(front.get(k) is False for k in ('hardwareAcceptance', 'installedProductAcceptance', 'arm64NativeAcceptance')), 'frontend claims acceptance')
    front_actual = {n[len(FRONT):]: r for n, r in actual.items() if n.startswith(FRONT)}
    sha_inventory(front.get('files'))
    require(front['files'] == {n: r['sha256'] for n, r in front_actual.items() if n != 'manifest.json'}, 'frontend inventory/hash mismatch')
    resources = doc(FRONT + 'resources.json')
    require(resources.get('schemaVersion') == 1 and resources.get('scope') == 'isolated-cn134-portable-resources'
            and resources.get('sourceCommit') == source and resources.get('sourceChanges') is False
            and resources.get('architecture') == 'windows-amd64', 'frontend resources source mismatch')
    sha_inventory(resources.get('files'))
    require(resources['files'] == {n: r['sha256'] for n, r in front_actual.items() if n not in {'manifest.json', 'resources.json', 'YimeTouchKeyboard.exe'}}, 'frontend resources inventory/hash mismatch')
    require(front.get('portableResourcesSHA256') == front_actual['resources.json']['sha256'], 'frontend compiled resource identity mismatch')
    require(front.get('resourceArchiveSHA256') == ARCHIVE_SHA, 'frontend resource archive identity mismatch')

    lock_name = 'payload/source/prototypes/touch-terminal/desktop/resources.lock.json'
    require(actual[lock_name]['sha256'] == LOCK_SHA and actual[FRONT + 'resources.lock.json']['sha256'] == LOCK_SHA, 'independent resource lock hash mismatch')
    lock = doc(lock_name)
    require(lock.get('schemaVersion') == 1 and lock.get('layoutProjectionSHA256') == LAYOUT_SHA
            and lock.get('archiveSHA256') == ARCHIVE_SHA and lock.get('files') == DATA, 'resource lock contents mismatch')
    for name, value in DATA.items():
        require(actual.get('payload/data/' + name) == value and actual.get(FRONT + 'data/' + name) == value, 'fixed resource bytes/hash mismatch: ' + name)
    product = doc('payload/source/tools/yimecore/18u-touch-product.json')
    require(all(product.get('identity', {}).get(k) == v for k, v in IDENTITY.items()), 'independent product source identity mismatch')
    projection = product.get('data', {})
    require(projection.get('layout_sha256') == LAYOUT_SHA and projection.get('dictionary_sha256') == DATA['yime_variable.dict.yaml']['sha256']
            and projection.get('standard_index_fallback') is False, 'independent product resource identity mismatch')
    for name in ('prototypes/touch-terminal/data/physical-layout.json', 'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json'):
        require(actual['payload/source/' + name] == actual[FRONT + name], 'frontend/source projection bytes mismatch')
    require(doc('payload/source/prototypes/touch-terminal/data/physical-layout.json').get('layoutId') == LAYOUT_SHA, 'physical layout identity mismatch')

    require(pe_names == PE_FILES, 'unexpected or missing PE inventory')
    pe_results = {n: dict(actual[n], **verify_pe(archive, files[n])) for n in sorted(pe_names)}
    signatures = doc('signatures.json')
    require(set(signatures) == {'schema', 'sourceCommit', 'files'} and signatures['schema'] == 'installed-18u-signatures-v1'
            and signatures['sourceCommit'] == source and isinstance(signatures['files'], list), 'signature record identity mismatch')
    seen = set()
    for row in signatures['files']:
        require(isinstance(row, dict) and set(row) == {'path', 'bytes', 'sha256', 'status', 'signerThumbprint'}, 'signature fields mismatch')
        name = row['path']
        require(name in PE_FILES and name not in seen, 'signature inventory mismatch')
        seen.add(name)
        require(record({k: row[k] for k in ('bytes', 'sha256')}) == actual[name], 'signature recorded payload mismatch')
        require(row['status'] in {'Valid', 'UnknownError', 'NotSigned', 'HashMismatch', 'NotTrusted', 'NotSupportedFileFormat', 'Incompatible'}, 'invalid signature status')
        thumb = row['signerThumbprint']
        require(thumb is None or isinstance(thumb, str) and re.fullmatch('[0-9a-fA-F]{40}', thumb), 'invalid signer thumbprint')
        require(not (row['status'] == 'NotSigned' and thumb is not None) and not (row['status'] == 'Valid' and thumb is None), 'inconsistent signature claim')
        pe_results[name]['recordedAuthenticodeStatus'] = row['status']
    require(seen == PE_FILES, 'incomplete signature inventory')

    small = {
        'package-evidence.json': 'package-evidence.json', 'product-package.json': 'product-package.json',
        'signatures.json': 'signatures.json', 'README.zh-CN.md': 'README.zh-CN.md',
        'installed-18u-product.json': 'payload/installed-18u-product.json',
        'frontend-manifest.json': FRONT + 'manifest.json', 'frontend-resources.json': FRONT + 'resources.json',
        'frontend-USER_GUIDE.zh-CN.md': FRONT + 'USER_GUIDE.zh-CN.md',
        'resources.lock.json': lock_name, '18u-touch-product.json': 'payload/source/tools/yimecore/18u-touch-product.json',
        'ascii_keyboard_manifest.json': 'payload/data/ascii_keyboard_manifest.json',
    }
    copies = {dest: read_small(archive, files, name) for dest, name in small.items()}
    result = {
        'crcVerified': True, 'allFilesVerified': True, 'fileCount': len(files),
        'expandedBytes': sum(r['bytes'] for r in actual.values()),
        'packageEvidence': actual['package-evidence.json'], 'installedDescriptor': payload['installed-18u-product.json'],
        'frontendManifest': front_actual['manifest.json'], 'frontendResources': front_actual['resources.json'],
        'sourceCommit': source, 'sourceChanges': False, 'frontendProtocol': PROTOCOL,
        'installerFiles': {n: actual[n] for n in sorted(INSTALLER_FILES)}, 'peFiles': pe_results,
        'resourceLock': actual[lock_name], 'resourceArchiveSHA256': ARCHIVE_SHA, 'lockedData': DATA,
        'signatureObservation': 'CI-recorded metadata verified against payload; no local Authenticode execution',
        'publisherTrust': 'not-established',
    }
    return result, copies


def artifact_metadata(document, source):
    expected = 'installed-18u-x64-test-package-' + source
    if 'artifacts' in document:
        require(isinstance(document['artifacts'], list), 'artifact collection invalid')
        matched = [item for item in document['artifacts'] if isinstance(item, dict) and item.get('name') == expected]
        require(len(matched) == 1, 'unique expected artifact metadata required')
        document = matched[0]
    require(document.get('name') == expected and type(document.get('id')) is int and document['id'] > 0, 'artifact name/id mismatch')
    require(document.get('expired') is False, 'artifact expiration state missing or expired')
    require(type(document.get('size_in_bytes')) is int and document['size_in_bytes'] > 0, 'artifact byte count missing')
    workflow = document.get('workflow_run')
    require(isinstance(workflow, dict) and workflow.get('head_sha') == source and type(workflow.get('id')) is int, 'artifact workflow source identity mismatch')
    digest = document.get('digest')
    require(digest is None or isinstance(digest, str) and re.fullmatch('sha256:[0-9a-f]{64}', digest), 'unsupported artifact API digest')
    return document


def verify(args):
    require(re.fullmatch('[0-9a-f]{40}', args.source_commit) is not None, 'full lowercase source SHA required')
    outer, meta_path, receipt_path = (regular(p) for p in (args.artifact_zip, args.artifact_metadata, args.ci_receipt))
    output = new_output(args.output, [outer, meta_path, receipt_path])
    report = {'schema': 'installed-18u-test11-download-verification-v1', 'status': 'failed',
              'verifiedAtUTC': datetime.now(timezone.utc).isoformat(), 'sourceCommit': args.source_commit,
              'version': VERSION, 'scope': 'independent-static-download-verification-only',
              'verifierScript': digest_file(Path(__file__).absolute()), **NO_ACTIONS}
    report_path = output / 'download-verification.json'
    try:
        meta_raw, receipt_raw = meta_path.read_bytes(), receipt_path.read_bytes()
        metadata = artifact_metadata(unique_json(meta_raw), args.source_commit)
        receipt = unique_json(receipt_raw)
        require(set(receipt) == {'sourceCommit', 'zip', 'bytes', 'sha256', 'packageEvidence', 'installedDescriptor', 'frontendProtocol'}, 'CI receipt fields mismatch')
        require(receipt['sourceCommit'] == args.source_commit and receipt['zip'] == ZIP_NAME, 'CI receipt source/version mismatch')
        inner_expected = record({k: receipt[k] for k in ('bytes', 'sha256')})
        protocol(receipt.get('frontendProtocol'))
        outer_hash = digest_file(outer)
        require(outer_hash['bytes'] == metadata['size_in_bytes'], 'outer ZIP API byte count mismatch')
        api_digest = metadata.get('digest')
        require(api_digest is None or api_digest == 'sha256:' + outer_hash['sha256'], 'outer ZIP API digest mismatch')
        inner = output / ZIP_NAME
        with zipfile.ZipFile(outer) as archive:
            files = members(archive)
            require(set(files) == {ZIP_NAME}, 'outer ZIP must contain only the expected test.11 archive')
            with archive.open(files[ZIP_NAME]) as source, inner.open('xb') as target:
                while chunk := source.read(1024 * 1024):
                    target.write(chunk)
        require(digest_file(outer) == outer_hash, 'outer ZIP changed while verifying')
        inner_hash = digest_file(inner)
        require(inner_hash == inner_expected, 'inner ZIP differs from CI package receipt')
        with zipfile.ZipFile(inner) as archive:
            inner_result, copies = verify_inner(archive, receipt, args.source_commit)
        # Keep original small evidence bytes instead of reserializing their JSON.
        copies['artifact-metadata.json'] = meta_raw
        copies['package-receipt.json'] = receipt_raw
        evidence = output / 'evidence'
        evidence.mkdir(exist_ok=False)
        for name, raw in copies.items():
            with (evidence / name).open('xb') as stream:
                stream.write(raw)
        evidence_index = {name: digest_bytes(raw) for name, raw in sorted(copies.items())}
        (evidence / 'evidence-index.json').write_text(json.dumps(evidence_index, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        report.update(status='passed', outerArchive={
            **outer_hash, 'name': outer.name, 'artifactId': metadata['id'], 'artifactName': metadata['name'],
            'artifactURL': f"https://github.com/tsaanghwang/Yime/actions/runs/{metadata['workflow_run']['id']}/artifacts/{metadata['id']}",
            'apiDigest': api_digest, 'apiDigestVerified': api_digest is not None, 'crcVerified': True,
            'workflowHeadSHA': metadata['workflow_run']['head_sha'], 'expiresAt': metadata.get('expires_at')},
            innerArchive={'name': ZIP_NAME, **inner_hash, **inner_result}, evidenceFiles=evidence_index)
    except Exception as exc:
        report['error'] = f'{type(exc).__name__}: {exc}'
        raise
    finally:
        with report_path.open('x', encoding='utf-8') as stream:
            json.dump(report, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
    return report_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact-zip', required=True, type=Path)
    parser.add_argument('--artifact-metadata', required=True, type=Path)
    parser.add_argument('--ci-receipt', required=True, type=Path)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--output', required=True, type=Path, help='new directory; no overwrite')
    args = parser.parse_args()
    try:
        print(verify(args))
    except Exception as exc:
        print(f'VERIFICATION FAILED: {type(exc).__name__}: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
