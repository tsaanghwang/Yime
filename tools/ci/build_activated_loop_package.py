"""Build a fixed, non-executing activated-loop development archive.

This does not run any PE, register a TIP, or establish publisher trust. Signature
observations must be collected independently by the Windows read-only helper.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import tempfile
import zipfile

from run_activated_registration_loop import BINARIES, SOURCES, DATA, DICTIONARY_SHA, LAYOUT_SHA, digest, bounded, strict_json, require

BASE = 'e3962604d333df098f31ad689e11801c8b1622c5'
SCHEMA = 'activated-loop-package-v1'
SCOPE = 'activated-instance-single-edit-development'
PE_NAMES = {x for x in BINARIES if x.endswith(('.exe', '.dll'))}
ROOT_FILES = {'run_activated_registration_loop.py', 'prepare_activated_loop_package.py', 'README.zh-CN.md', 'signatures.json'}
PAYLOAD = {f'bin/{x}' for x in BINARIES} | {f'source/{x}' for x in SOURCES} | {f'data/{x}' for x in DATA} | ROOT_FILES
STATUSES = {'Valid', 'UnknownError', 'NotSigned', 'HashMismatch', 'NotTrusted', 'NotSupportedFileFormat', 'Incompatible'}


def pe_check(path, dll):
    with path.open('rb') as f:
        header = f.read(64)
        require(len(header) == 64 and header[:2] == b'MZ', 'pe-dos-header')
        offset = struct.unpack_from('<I', header, 60)[0]
        require(64 <= offset <= 1024 * 1024, 'pe-header-offset')
        f.seek(offset); pe = f.read(26)
    require(len(pe) == 26 and pe[:4] == b'PE\0\0', 'pe-signature')
    require(struct.unpack_from('<H', pe, 4)[0] == 0x8664, 'pe-amd64-required')
    require(struct.unpack_from('<H', pe, 24)[0] == 0x20b, 'pe32plus-required')
    flags = struct.unpack_from('<H', pe, 22)[0]
    require(bool(flags & 0x2000) == dll and bool(flags & 2), 'pe-file-type')


def check_signatures(value, files, source_commit):
    require(isinstance(value, dict) and set(value) == {'schema', 'sourceCommit', 'files'}, 'signature-fields')
    require(value['schema'] == 'activated-loop-signatures-v1' and value['sourceCommit'] == source_commit, 'signature-source')
    rows = value['files']; require(isinstance(rows, list) and len(rows) == 5, 'signature-count')
    seen = set()
    for row in rows:
        require(isinstance(row, dict) and set(row) == {'path', 'sha256', 'bytes', 'status', 'signerThumbprint'}, 'signature-row')
        name = row['path']; require(isinstance(name, str) and name in {f'bin/{x}' for x in PE_NAMES} and name not in seen, 'signature-path')
        seen.add(name)
        require(type(row['bytes']) is int and {'bytes': row['bytes'], 'sha256': row['sha256']} == files[name], 'signature-payload-binding')
        require(isinstance(row['status'], str) and row['status'] in STATUSES, 'signature-status')
        thumb = row['signerThumbprint']
        require(thumb is None or isinstance(thumb, str) and re.fullmatch('[0-9A-Fa-f]{40}', thumb), 'signature-thumbprint')
        require(row['status'] != 'Valid' or thumb is not None, 'valid-signature-needs-signer')
        require(row['status'] != 'NotSigned' or thumb is None, 'unsigned-has-no-signer')


def build(binary_directory, source_root, data_directory, runner, prepare, readme, signatures, output, source_commit):
    require(isinstance(source_commit, str) and re.fullmatch('[0-9a-f]{40}', source_commit), 'source-commit')
    binary_directory, source_root, data_directory, output = map(Path, [binary_directory, source_root, data_directory, output])
    require(not output.exists() and not output.is_symlink(), 'fresh-output-required')
    require(set(p.name for p in binary_directory.iterdir()) == BINARIES, 'binary-inventory')
    require(set(p.name for p in data_directory.iterdir()) == DATA, 'data-inventory')
    mapping = {f'bin/{x}': binary_directory / x for x in BINARIES}
    mapping.update({f'source/{x}': source_root / x for x in SOURCES})
    mapping.update({f'data/{x}': data_directory / x for x in DATA})
    mapping.update(dict(zip(['run_activated_registration_loop.py', 'prepare_activated_loop_package.py', 'README.zh-CN.md', 'signatures.json'], map(Path, [runner, prepare, readme, signatures]))))
    records = {name: digest(path.absolute()) for name, path in mapping.items()}
    require(all(v['bytes'] > 0 for v in records.values()), 'empty-payload')
    lock = strict_json(bounded(source_root / 'prototypes/touch-terminal/desktop/resources.lock.json'))
    require(lock.get('schemaVersion') == 1 and isinstance(lock.get('files'), dict) and set(lock['files']) == DATA, 'resource-lock')
    for name in DATA:
        require(records['data/' + name] == lock['files'][name], 'locked-resource-mismatch')
    require(records['data/yime_variable.dict.yaml']['sha256'] == DICTIONARY_SHA, 'variable-identity')
    product = strict_json(bounded(mapping['source/tools/yimecore/18u-touch-product.json']))
    require(isinstance(product, dict) and product.get('schema_version') == 'yimecore-18u-touch-product-v1' and product.get('installable') is False, 'product-descriptor')
    identity = product.get('identity', {}); scope = product.get('scope', {})
    require(isinstance(identity, dict) and identity.get('product_key') == 'YimeCore18uTouch' and identity.get('clsid') == '{6DFACE1F-562E-4773-A9D6-D5753A314711}' and identity.get('profile') == '{1BD904AC-3194-4419-B70A-5574100F18B3}' and identity.get('language_id') == '0804', 'product-identity')
    require(isinstance(scope, dict) and scope.get('architecture') == 'x64' and scope.get('language') == 'CN' and scope.get('mode') == 'variable' and scope.get('persistent_learning') is False and scope.get('registration_validated') is False and scope.get('user_machine_execution_approved') is False, 'product-scope')
    require(isinstance(product.get('data'), dict), 'product-data-object')
    require(product.get('data', {}).get('layout_sha256') == LAYOUT_SHA and product.get('data', {}).get('dictionary_sha256') == DICTIONARY_SHA and product.get('data', {}).get('standard_index_fallback') is False, 'product-data-identity')
    for name in PE_NAMES: pe_check(mapping['bin/' + name], name.endswith('.dll'))
    check_signatures(strict_json(bounded(Path(signatures))), records, source_commit)
    manifest = {'schema': SCHEMA, 'sourceCommit': source_commit, 'baseImplementation': BASE,
                'architecture': 'native-x64', 'scope': SCOPE, 'registrationExecuted': False,
                'userMachineExecutionApproved': False, 'files': records}
    # Copy first, then rehash: concurrent changes cannot produce a falsely listed archive.
    with tempfile.TemporaryDirectory(prefix='activated-loop-package-') as temporary:
        stage = Path(temporary)
        for name, source in mapping.items():
            target = stage / name; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            require(digest(target) == records[name], 'payload-changed-during-copy')
        (stage / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
        with output.open('xb') as target:
            with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
                for name in sorted(PAYLOAD | {'manifest.json'}):
                    info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0)); info.compress_type = zipfile.ZIP_DEFLATED
                    with (stage / name).open('rb') as src, archive.open(info, 'w', force_zip64=True) as dst:
                        shutil.copyfileobj(src, dst)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['binary-directory', 'source-root', 'data-directory', 'runner', 'prepare', 'readme', 'signatures', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--source-commit', required=True)
    args = parser.parse_args(); build(**vars(args))
    print(json.dumps({'archive': digest(args.output.absolute()), 'registrationExecuted': False}))


if __name__ == '__main__': main()
