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
FRONTEND_PROTOCOL = {'version': 2, 'pipePrefix': 'Yime18u.Frontend.v2.'}
FRONTEND_MODE = 'installed-tsf-auto-focus'

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

def amd64(path):
    raw = regular(path).read_bytes()
    if len(raw) < 64 or raw[:2] != b'MZ':
        raise ValueError('PE DOS header')
    offset = struct.unpack_from('<I', raw, 60)[0]
    if offset + 26 > len(raw) or raw[offset:offset+4] != b'PE\0\0' or struct.unpack_from('<H', raw, offset+4)[0] != 0x8664 or struct.unpack_from('<H', raw, offset+24)[0] != 0x20b:
        raise ValueError('native AMD64 PE required')

def frontend_protocol(info, frontend_exe, tip_dll):
    protocol = info.get('frontendProtocol')
    if (info.get('defaultMode') != FRONTEND_MODE or not isinstance(protocol, dict)
            or type(protocol.get('version')) is not int or protocol != FRONTEND_PROTOCOL):
        raise ValueError('frontend v2 protocol metadata required')
    # Static pairing guard, not publisher authentication or live-host acceptance.
    # Both binaries are built from the clean source commit in the same CI job.
    for path, encoding in ((frontend_exe, 'ascii'), (tip_dll, 'utf-16-le')):
        raw = regular(path).read_bytes()
        if any('Yime18u.Frontend.v1.'.encode(e) in raw for e in ('ascii', 'utf-16-le')):
            raise ValueError('frontend v1 binary protocol refused: ' + Path(path).name)
        if FRONTEND_PROTOCOL['pipePrefix'].encode(encoding) not in raw:
            raise ValueError('frontend v2 binary protocol marker missing: ' + Path(path).name)


def assemble(repo, native, go, data, output, source_commit, frontend=None):
    if not re.fullmatch('[0-9a-f]{40}', source_commit):
        raise ValueError('full source commit required')
    output = Path(output).absolute()
    for item in (output, *output.parents):
        if item.is_symlink() or (hasattr(item, 'is_junction') and item.is_junction()):
            raise ValueError('linked output refused')
    if output.exists():
        raise ValueError('new output required; no overwrite')
    inputs = {}
    for dest, (kind, name) in BINARIES.items():
        inputs[dest] = regular(Path(native if kind == 'native' else go) / name)
        amd64(inputs[dest])
    for dest, src in RESOURCES.items():
        inputs[dest] = regular(Path(repo) / src)
    for name in DATA:
        inputs['data/' + name] = regular(Path(data) / name)
    if frontend is not None:
        front = Path(frontend).absolute()
        info = load_json(front / 'manifest.json')
        if (info.get('scope') != 'installed-18u-tsf-frontend-candidate'
                or info.get('sourceCommit') != source_commit or info.get('sourceChanges') is not False
                or info.get('architecture') != 'windows-amd64' or info.get('sendInputFallback') is not False):
            raise ValueError('frontend must be a clean, matching-source x64 TSF build')
        inventory = info.get('files', {})
        names = {p.relative_to(front).as_posix() for p in front.rglob('*') if p.is_file()}
        if names != set(inventory) | {'manifest.json'} or 'YimeTouchKeyboard.exe' not in inventory:
            raise ValueError('frontend inventory mismatch')
        for name in names:
            path = regular(front / name)
            if name != 'manifest.json' and digest(path)['sha256'] != inventory[name]:
                raise ValueError('frontend file mismatch: ' + name)
            inputs['frontend/' + name] = path
        amd64(front / 'YimeTouchKeyboard.exe')
        frontend_protocol(info, front / 'YimeTouchKeyboard.exe', inputs['x64/YimeTextService18u.dll'])
    # This descriptor is a build-source assertion, not publisher authentication.
    # Runtime independently checks its content locks through the canonical loader.
    product = load_json(inputs['source/tools/yimecore/18u-touch-product.json'])
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
        if frontend is not None:
            member = inputs.get('frontend/data/' + name)
            if member is None or digest(member) != lock['files'][name]:
                raise ValueError('frontend locked resource mismatch: ' + name)
    if frontend is not None:
        for name in ('prototypes/touch-terminal/data/physical-layout.json',
                     'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json'):
            member = inputs.get('frontend/' + name)
            if member is None or digest(member) != digest(inputs['source/' + name]):
                raise ValueError('frontend projection mismatch: ' + name)
    projection = product['data']
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
                'architecture': 'native-x64', 'language': 'CN', 'mode': 'variable', 'autostart': False, 'files': rows}
    (output / 'installed-18u-product.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return manifest

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'native', 'go', 'data', 'output', 'source-commit'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--frontend', help='optional complete matching-source installed TSF frontend')
    args = parser.parse_args()
    assemble(args.repo, args.native, args.go, args.data, args.output, args.source_commit, args.frontend)

if __name__ == '__main__':
    main()
