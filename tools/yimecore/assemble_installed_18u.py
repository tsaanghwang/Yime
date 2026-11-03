"""Prepare installer/simple payload from explicitly built x64 outputs. Never executes them."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct

LAYOUT_SHA = '995f1a74f129249febbd09ca11a8266f6e0c94bac8c05c57754859fc3be3349c'
DICTIONARY_SHA = '43a74f4e47c7100f222a744f487762f1c31222c5f80b9a34fd24cbebc7e96353'

BINARIES = {
    'x64/YimeTextService18u.dll': ('native', 'YimeTextService18u.dll'),
    'x64/Yime18uProductRegistration.exe': ('native', 'Yime18uProductRegistration.exe'),
    'x64/YimeTouchRegisteredFormalHostTests.exe': ('native', 'YimeTouchRegisteredFormalHostTests.exe'),
    'bin/YimeBroker18u.exe': ('go', 'YimeBroker18u.exe'),
    'bin/Yime18uInstalledRuntime.exe': ('go', 'Yime18uInstalledRuntime.exe'),
}
RESOURCES = {
    'profile-icon.ico': 'go-backend/input_methods/yime/icons/yime_qin_seal_yin.ico',
    'source/prototypes/touch-terminal/desktop/resources.lock.json': 'prototypes/touch-terminal/desktop/resources.lock.json',
    'source/tools/yimecore/18u-touch-product.json': 'tools/yimecore/18u-touch-product.json',
    'source/prototypes/touch-terminal/data/physical-layout.json': 'prototypes/touch-terminal/data/physical-layout.json',
    'source/prototypes/touch-terminal/encoding/yime_yinyuan_layout.json': 'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json',
    'source/internal_data/yime_syllable_decomposition.tsv': 'internal_data/yime_syllable_decomposition.tsv',
}
DATA = ('ascii_keyboard_manifest.json', 'yime_variable.dict.yaml', 'yime_full.dict.yaml', 'yime_shorthand.dict.yaml')
FRONTEND_RESOURCES = {
    'source/prototypes/touch-terminal/encoding/manual_key_layout.resolved.json': 'prototypes/touch-terminal/encoding/manual_key_layout.resolved.json',
    'source/prototypes/touch-terminal/desktop/profiles/main-only.json': 'prototypes/touch-terminal/desktop/profiles/main-only.json',
    'source/go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf': 'go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf',
}
FRONTEND_CAPABILITIES = ['installed-tsf-frontend', 'composition', 'candidates', 'literal', 'host-editing']

def regular(path):
    path = Path(path).absolute()
    for item in (path, *path.parents):
        if item.is_symlink() or (hasattr(item, 'is_junction') and item.is_junction()):
            raise ValueError('linked input refused')
    if not path.is_file():
        raise ValueError(f'missing regular input: {path}')
    return path

def load_json(path):
    def unique(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("duplicate JSON member")
            result[key] = value
        return result
    return json.loads(regular(path).read_text(encoding="utf-8-sig"), object_pairs_hook=unique)

def digest(path):
    raw = regular(path).read_bytes()
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}

def check_pe(path, architecture):
    raw = regular(path).read_bytes()
    if len(raw) < 64 or raw[:2] != b'MZ':
        raise ValueError('PE DOS header')
    offset = struct.unpack_from('<I', raw, 60)[0]
    if offset + 26 > len(raw) or raw[offset:offset+4] != b'PE\0\0' or struct.unpack_from('<H', raw, offset+4)[0] != {'x64': 0x8664, 'arm64': 0xaa64}[architecture] or struct.unpack_from('<H', raw, offset+24)[0] != 0x20b:
        raise ValueError('native ' + ('AMD64' if architecture == 'x64' else 'ARM64') + ' PE required')

def amd64(path):
    return check_pe(path, 'x64')


def binary_map(architecture):
    if architecture not in ('x64', 'arm64'):
        raise ValueError('unsupported native architecture')
    return {(architecture + name[3:] if name.startswith('x64/') else name): value for name, value in BINARIES.items()}


def resource_map(architecture):
    binary_map(architecture)  # fail closed for unknown targets
    result = dict(RESOURCES)
    if architecture == 'arm64':
        del result['source/tools/yimecore/18u-touch-product.json']
        result['source/tools/yimecore/18u-touch-product-arm64.json'] = 'tools/yimecore/18u-touch-product-arm64.json'
    return result


def assemble(repo, native, go, data, output, source_commit, architecture='x64', frontend=False):
    if not re.fullmatch('[0-9a-f]{40}', source_commit):
        raise ValueError('full source commit required')
    output = Path(output).absolute()
    for item in (output, *output.parents):
        if item.is_symlink() or (hasattr(item, 'is_junction') and item.is_junction()):
            raise ValueError('linked output refused')
    if output.exists():
        raise ValueError('new output required; no overwrite')
    inputs = {}
    for dest, (kind, name) in binary_map(architecture).items():
        inputs[dest] = regular(Path(native if kind == 'native' else go) / name)
        check_pe(inputs[dest], architecture)
    for dest, src in resource_map(architecture).items():
        inputs[dest] = regular(Path(repo) / src)
    if frontend:
        inputs['bin/YimeTouchKeyboard.exe'] = regular(Path(go) / 'YimeTouchKeyboard.exe')
        check_pe(inputs['bin/YimeTouchKeyboard.exe'], architecture)
        for dest, src in FRONTEND_RESOURCES.items():
            inputs[dest] = regular(Path(repo) / src)
    for name in DATA:
        inputs['data/' + name] = regular(Path(data) / name)
    # This descriptor is a build-source assertion, not publisher authentication.
    # Runtime independently checks its content locks through the canonical loader.
    descriptor_name = 'source/tools/yimecore/18u-touch-product' + ('-arm64' if architecture == 'arm64' else '') + '.json'
    product = load_json(inputs[descriptor_name])
    if architecture == 'arm64':
        if product.get('scope', {}).get('architecture') != architecture:
            raise ValueError('descriptor architecture mismatch')
        canonical = load_json(Path(repo) / 'tools/yimecore/18u-touch-product.json')
        expected = dict(canonical)
        expected['scope'] = dict(canonical['scope'])
        expected['scope']['architecture'] = 'arm64'
        if product != expected:
            raise ValueError('ARM descriptor differs from canonical product beyond architecture')
    identity = product['identity']
    if identity['clsid'].upper().strip('{}') != '6DFACE1F-562E-4773-A9D6-D5753A314711' or identity['profile'].upper().strip('{}') != '1BD904AC-3194-4419-B70A-5574100F18B3':
        raise ValueError('independent product identity required')
    # Reuse the existing desktop resource-lock contract; never accept merely
    # self-consistent wrong dictionaries. No new dictionary or projection here.
    lock = load_json(inputs['source/prototypes/touch-terminal/desktop/resources.lock.json'])
    if lock.get('schemaVersion') != 1 or set(lock.get('files', {})) != set(DATA):
        raise ValueError('complete desktop resource lock required')
    for name in DATA:
        if digest(inputs['data/' + name]) != lock['files'][name]:
            raise ValueError('locked resource mismatch: ' + name)
    projection = product['data']
    if frontend:
        scope = product.get('scope', {})
        if (product.get('schema_version') != 'yimecore-18u-touch-product-v2' or product.get('installable') is not True
                or scope.get('installed_frontend') is not True or scope.get('languages') != ['CN', 'EN']
                or scope.get('modes') != ['full', 'variable', 'shorthand']
                or scope.get('capabilities') != FRONTEND_CAPABILITIES):
            raise ValueError('complete installed frontend source scope required')
        by_mode = {mode: lock['files']['yime_' + mode + '.dict.yaml']['sha256']
                   for mode in ('full', 'variable', 'shorthand')}
        if projection.get('dictionary_sha256_by_mode') != by_mode:
            raise ValueError('frontend three-mode dictionary identity mismatch')
    if projection.get('standard_index_fallback') is not False or projection.get('layout_sha256') != LAYOUT_SHA or projection.get('dictionary_sha256') != DICTIONARY_SHA:
        raise ValueError('fixed dedicated resource identity required')
    if lock.get('layoutProjectionSHA256') != projection['layout_sha256'] or lock['files']['yime_variable.dict.yaml']['sha256'] != projection['dictionary_sha256']:
        raise ValueError('descriptor and resource lock disagree')
    if load_json(inputs['source/prototypes/touch-terminal/data/physical-layout.json']).get('layoutId') != projection['layout_sha256']:
        raise ValueError('physical layout identity mismatch')
    before = {dest: digest(path) for dest, path in inputs.items()}
    for path in inputs.values():
        if output == path or output in path.parents:
            raise ValueError('output overlaps inputs')
    output.mkdir(parents=True, exist_ok=False)
    rows = []
    for dest, path in sorted(inputs.items()):
        target = output / dest
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        raw = target.read_bytes()
        if digest(target) != before[dest]:
            raise ValueError('input changed during copy; preserve incomplete output')
        rows.append({'path': dest, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
    manifest = {'schema': 'installed-18u-product-v1', 'product': 'yimecore-18u', 'sourceCommit': source_commit,
                'identity': {'clsid': '{6DFACE1F-562E-4773-A9D6-D5753A314711}', 'profile': '{1BD904AC-3194-4419-B70A-5574100F18B3}'},
                'architecture': 'native-' + architecture, 'language': 'CN', 'mode': 'variable', 'autostart': False, 'files': rows}
    if frontend:
        manifest.update(schema='installed-18u-product-v2', languages=['CN', 'EN'],
                        modes=['full', 'variable', 'shorthand'], capabilities=FRONTEND_CAPABILITIES,
                        autostart=True)
        del manifest['language']
        del manifest['mode']
    (output / 'installed-18u-product.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return manifest

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'native', 'go', 'data', 'output', 'source-commit'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--architecture', choices=('x64', 'arm64'), default='x64')
    parser.add_argument('--frontend', action='store_true')
    args = parser.parse_args()
    assemble(args.repo, args.native, args.go, args.data, args.output, args.source_commit, args.architecture, frontend=args.frontend)

if __name__ == '__main__':
    main()
