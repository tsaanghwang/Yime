"""Derive 17u desktop geometry from the user KLE while preserving key identities."""
from collections import defaultdict, deque
from pathlib import Path
import argparse
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / 'prototypes/touch-terminal'
sys.path.insert(0, str(HERE))
from physical_layout import parse_physical_kle

SOURCE = HERE / 'design/yime-cn-134k-23u-keyboard-layout.json'
BASE = HERE / 'data/physical-layout.json'
OUTPUT = HERE / 'desktop/profiles'

def generate():
    original = json.loads(BASE.read_text(encoding='utf-8'))
    compact = parse_physical_kle(json.loads(SOURCE.read_text(encoding='utf-8')))
    if len(compact['keys']) != 134 or compact['bounds']['width'] != 23.75:
        raise ValueError('Expected the reviewed 134-key, 23.75u source including gutters')
    source_by_legend = defaultdict(deque)
    for key in original['keys']:
        source_by_legend[(key['zone'], tuple(key['labels']))].append(key)
    geometry, moved = {}, []
    for key in compact['keys']:
        zone = 'left' if key['x'] < 3 else 'right' if key['x'] >= 20.75 else 'main'
        matches = source_by_legend[(zone, tuple(key['labels']))]
        if not matches:
            raise ValueError('Compact layout changed a legend or zone')
        old = matches.popleft()
        if zone != 'main':
            continue
        for rect in key['rectangles']:
            left = key['x'] + rect['x']
            if left < 12 and left + rect['width'] > 11.75:
                raise ValueError('Key crosses the common compact centre gutter')
        geometry[old['id']] = {field:key[field] for field in ('x','y','width','height','rectangles')}
        geometry[old['id']]['x'] -= 3.25 + (.25 if key['x'] >= 12 else 0)
        if old['y'] != key['y']:
            moved.append({'keyId':old['id'], 'yinyuanIds':old.get('yinyuanIds',[]), 'oldY':old['y'], 'newY':key['y']})
    if any(source_by_legend.values()) or len(geometry) != 100:
        raise ValueError('Compact layout must preserve the complete key inventory')
    moved_ids = {row['keyId'] for row in moved}
    if {tuple(row['yinyuanIds']) for row in moved} != {('N26',),('N27',)}:
        raise ValueError('Only the reviewed N26/N27 cross-row moves are allowed')
    if any(value['width'] < 1 for value in geometry.values()):
        raise ValueError('Compact geometry must not shrink keys below 1u')
    for y in {value['y'] for value in geometry.values()}:
        before = [key['id'] for key in sorted(original['keys'],key=lambda k:k['x'])
                  if key['id'] in geometry and key['id'] not in moved_ids and key['y'] == y]
        after = [identifier for identifier,value in sorted(geometry.items(),key=lambda pair:pair[1]['x'])
                 if identifier not in moved_ids and value['y'] == y]
        if before != after:
            raise ValueError('Compact layout changed another key relative order')
    files = {}
    for name, zones in [('main-17u.json','none'), ('full-23u.json','both')]:
        files[name] = {'numericZones':zones,'removeGutters':True,'mainWidthU':17,'mainGeometry':geometry}
    files['17u-provenance.json'] = {
        'source':str(SOURCE.relative_to(ROOT)).replace('\\','/'),
        'sourceSHA256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'baseSHA256':hashlib.sha256(BASE.read_bytes()).hexdigest(),
        'sourceWidthWithGuttersU':23.75, 'mainWidthWithoutGutterU':17,
        'ordinaryKeysRemain1U':True, 'keysMovedBetweenRows':moved,
        'englishView':'Existing per-key English actions and legends follow the stable key identity; no new English mapping is invented.',
        'hardwareAcceptance':False,
    }
    return {name:json.dumps(value, ensure_ascii=False, indent=2)+'\n' for name,value in files.items()}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    for name,text in generate().items():
        path=OUTPUT/name
        if args.check:
            if not path.exists() or path.read_text(encoding='utf-8') != text:
                raise SystemExit(f'FAIL: regenerate {path}')
        else:
            path.write_text(text,encoding='utf-8')
    print('PASS: user 17u geometry preserves 134 identities and all input mappings')

if __name__ == '__main__':
    main()
