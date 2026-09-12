"""Copy only original manifest members from the retained install; execute nothing."""
import argparse
import hashlib
import json
from pathlib import Path

MANIFEST_SHA = '256a9ab5d213093248001d2bb32f918bcb0c4431628ec40ea5295e8b14a76ddf'


def plain(path):
    for item in (path, *path.parents):
        if item.exists() and (item.is_symlink() or getattr(item.lstat(), 'st_file_attributes', 0) & 1024):
            raise ValueError('Indirect path')


def stage(source, manifest_path, output):
    source, manifest_path, output = map(lambda p: Path(p).absolute(), (source, manifest_path, output))
    for path in (source, manifest_path, output):
        plain(path)
    if output.exists() or output == source or source in output.parents or output in source.parents:
        raise ValueError('Fresh disjoint output required')
    raw = manifest_path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != MANIFEST_SHA:
        raise ValueError('Wrong original manifest')
    rows = json.loads(raw)['files']
    seen = set()
    for row in rows:
        parts = row['path'].split('/')
        if any(p in ('', '.', '..') or ':' in p or '\\' in p for p in parts) or row['path'].lower() in seen:
            raise ValueError('Unsafe or duplicate member')
        seen.add(row['path'].lower())
        path = source.joinpath(*parts)
        plain(path)
        with path.open('rb') as stream:
            if path.stat().st_size != row['bytes'] or hashlib.file_digest(stream, 'sha256').hexdigest() != row['sha256']:
                raise ValueError('Original source member mismatch: ' + row['path'])
    output.mkdir(parents=True, exist_ok=False)
    for row in rows:
        target = output / row['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        with (source / row['path']).open('rb') as src, target.open('xb') as dst:
            while chunk := src.read(1048576):
                dst.write(chunk)
        with target.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != row['sha256']:
                raise ValueError('Copy changed; retain staging evidence')
    with (output / 'candidate.json').open('xb') as dst:
        dst.write(raw)
    return {'original_bundle': str(output), 'members': len(rows), 'executed': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source')
    parser.add_argument('manifest')
    parser.add_argument('output')
    args = parser.parse_args()
    print(json.dumps(stage(args.source, args.manifest, args.output)))
