"""Verify a portable candidate delivery against an independently supplied index hash.

This is byte-integrity verification only, never installation authorization.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re

ARTIFACTS = {'installer', 'receipt', 'manifest', 'static_payload', 'source_baseline', 'source_inventory'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def plain_child(root, relative):
    if not isinstance(relative, str) or '\\' in relative or ':' in relative:
        raise ValueError('Invalid delivery path')
    parts = PurePosixPath(relative)
    if parts.is_absolute() or any(p in ('', '.', '..') for p in relative.split('/')):
        raise ValueError('Delivery path escapes its root')
    current = root
    for part in parts.parts:
        current = current / part
        if current.is_symlink() or (hasattr(current, 'is_junction') and current.is_junction()):
            raise ValueError('Indirect delivery path')
    if not current.resolve().is_relative_to(root.resolve()):
        raise ValueError('Delivery path escapes its root')
    return current


def verify(root, expected):
    root = Path(root)
    if not re.fullmatch('[0-9a-f]{64}', expected):
        raise ValueError('A trusted lowercase SHA-256 is required')
    raw = (root / 'delivery-index.json').read_bytes()
    if digest(raw) != expected:
        raise ValueError('Delivery index hash differs from the independent pin')
    index = json.loads(raw.decode('utf-8-sig'))
    if index.get('schema_version') != 'yime-rime-pime-executable-candidate-delivery-v1' or index.get('product') != 'rime-pime':
        raise ValueError('Unsupported delivery identity')
    if set(index['artifacts']) != ARTIFACTS:
        raise ValueError('Incomplete artifact set')
    content = {}
    for name, record in index['artifacts'].items():
        data = plain_child(root, record['path']).read_bytes()
        if type(record['bytes']) is not int or len(data) != record['bytes'] or digest(data) != record['sha256']:
            raise ValueError('Artifact bytes differ: '+name)
        content[name] = data
    receipt = json.loads(content['receipt'].decode('utf-8-sig'))
    manifest = json.loads(content['manifest'].decode('utf-8-sig'))
    if receipt.get('schema_version') != 'yime-rime-pime-executable-build-receipt-v1' or manifest.get('schema_version') not in ('yime-rime-pime-executable-candidate-v1', 'yime-rime-pime-executable-candidate-v2'):
        raise ValueError('Unsupported receipt or manifest')
    for item in (receipt, manifest):
        if item.get('product') != 'rime-pime' or item.get('product_version') != index['product_version']:
            raise ValueError('Product/version binding differs')
        if item.get('installed_acceptance_passed') is not False or item.get('public_release_admitted') is not False:
            raise ValueError('Trial delivery cannot promote acceptance')
    if (receipt['installer']['sha256'] != digest(content['installer']) or
            receipt['installer']['bytes'] != len(content['installer']) or
            receipt['manifest_sha256'] != digest(content['manifest']) or
            receipt['source_inventory_sha256'] != digest(content['source_inventory']) or
            manifest['source_inventory_sha256'] != digest(content['source_inventory']) or
            receipt['static_payload']['tree_sha256'] != digest(content['static_payload'])):
        raise ValueError('Receipt cross-binding differs')
    return {'integrity_passed': True, 'artifact_count': len(content),
            'product_version': index['product_version'], 'execution_authorized': False,
            'installed_acceptance_passed': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--expected-index-sha256', required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.root, args.expected_index_sha256)))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, 'Delivery verification failed: '+str(error)+'\n')


if __name__ == '__main__':
    main()
