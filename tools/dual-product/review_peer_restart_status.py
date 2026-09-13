"""Read only the fixed recovery's operational index status; never rebase or apply."""
import argparse
import hashlib
import json
from pathlib import Path
import platform

ORIGINAL = '9fbcf26fc7b557f6393b4a8ae890048e0231a708591ad66fa044cf7e5f12b447'
CURRENT = '0d2321343da063aa57f79a24973187d69d89e63ef6b5ccb733eb970c20b0e23a'
STATUS_PATH = 'index-control/status.json'
STATS = {'active_version', 'active_source_id', 'active_sha256', 'previous_version',
         'active_sessions', 'switches', 'rollbacks', 'rejected', 'load_mode'}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def unique_object(pairs):
    result = {}
    for name, value in pairs:
        if name in result:
            raise ValueError('Duplicate status property')
        result[name] = value
    return result


def inspect_status(raw, original, current):
    if len(raw) > 65536:
        raise ValueError('Operational status exceeds read bound')
    value = json.loads(raw.decode('utf-8-sig'), object_pairs_hook=unique_object)
    allowed = {'schema_version', 'observed_at', 'request_id', 'action', 'mode',
               'accepted', 'error', 'manager', 'managers', 'manifest_sha256'}
    if not isinstance(value, dict) or set(value) - allowed:
        raise ValueError('Unknown operational status shape; no content exported')
    if value.get('schema_version') != 'yime-index-control-v1':
        raise ValueError('Unknown operational status schema')
    managers = value.get('managers')
    if not isinstance(managers, dict) or set(managers) != {'variable', 'full', 'shorthand'}:
        raise ValueError('Three known index modes required')
    hashes = {row['sha256'] for row in original['payload']['files']}
    rows = []
    for mode, stats in sorted(managers.items()):
        if not isinstance(stats, dict) or set(stats) - STATS:
            raise ValueError('Unknown index manager shape; no content exported')
        active = stats.get('active_sha256', '')
        if not isinstance(active, str) or len(active) != 64 or any(c not in '0123456789abcdef' for c in active):
            raise ValueError('Invalid active index digest')
        counters = {}
        for name in ('active_sessions', 'switches', 'rollbacks', 'rejected'):
            n = stats.get(name)
            if type(n) is not int or n < 0:
                raise ValueError('Invalid operational counter')
            counters[name] = n
        # No source IDs, error strings, paths or arbitrary status text leave this tool.
        rows.append({'mode': mode, 'active_sha256': active,
                     'hash_in_original_payload': active in hashes, **counters})
    recorded = [r for r in current['state']['files'] if r['path'] == STATUS_PATH]
    if len(recorded) != 1:
        raise ValueError('Recorded status member missing or duplicated')
    return {'status_sha256': digest(raw), 'status_bytes': len(raw),
            'matches_reported_snapshot': digest(raw) == recorded[0]['sha256'] and len(raw) == recorded[0]['bytes'],
            'startup_observation': value.get('request_id') == 'startup' and value.get('action') == 'observe',
            'accepted': value.get('accepted') is True, 'error_present': bool(value.get('error')),
            'manifest_digest_present': bool(value.get('manifest_sha256')),
            'indexes': rows, 'baseline_replaced': False, 'recovery_admitted': False}


def read_plain(path, expected=None, limit=262144):
    path = Path(path).absolute()
    for item in (path, *path.parents):
        if item.is_symlink() or getattr(item.lstat(), 'st_file_attributes', 0) & 1024:
            raise ValueError('Indirect input path')
    with path.open('rb') as stream:
        raw = stream.read(limit + 1)
    if len(raw) > limit or (expected and digest(raw) != expected):
        raise ValueError('Input size or pinned digest mismatch')
    return raw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original-snapshot', required=True)
    parser.add_argument('--current-snapshot', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    if platform.node() != '\u8ba1\u7b97\u673a':
        raise ValueError('Fixed test PC only')
    original = json.loads(read_plain(args.original_snapshot, ORIGINAL))
    current = json.loads(read_plain(args.current_snapshot, CURRENT))
    if original['state']['root'] != current['state']['root']:
        raise ValueError('Peer state root changed')
    status = Path(current['state']['root']) / STATUS_PATH
    raw = read_plain(status, limit=65536)
    report = inspect_status(raw, original, current)
    if read_plain(status, limit=65536) != raw:
        raise ValueError('Status changed during observation')
    output = Path(args.output).absolute()
    archive = Path.home() / 'Yime Rime-PIME Test Archives'
    if archive not in output.parents:
        raise ValueError('Output must be a new file in the recovery archives')
    for snapshot in (original, current):
        for tree in ('payload', 'state', 'recovery'):
            protected = Path(snapshot[tree]['root'])
            if output == protected or protected in output.parents:
                raise ValueError('Output overlaps a protected product')
    for item in output.parents:
        if item.is_symlink() or getattr(item.lstat(), 'st_file_attributes', 0) & 1024:
            raise ValueError('Indirect output path')
    with output.open('xb') as stream:
        stream.write((json.dumps(report, indent=2) + '\n').encode())
    print('Read-only index status review saved; no baseline or product changes.')


if __name__ == '__main__':
    main()
