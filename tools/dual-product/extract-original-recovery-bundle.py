"""Stage authenticated original bundle data; never execute archive contents."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

MANIFEST_SHA = '3f676b80b86f4c752e96c5ed06655bddb3b5b4aedd762ca8369483e7ae14b01d'


def extract(archive, output):
    output = Path(output).absolute()
    if output.exists():
        raise ValueError('Fresh output directory required')
    for p in [output.parent, *output.parent.parents]:
        if p.exists() and (p.is_symlink() or getattr(p.lstat(), 'st_file_attributes', 0) & 1024):
            raise ValueError('Indirect output ancestor')
    with zipfile.ZipFile(archive) as z:
        infos = z.infolist()
        if len(infos) > 4096 or len({i.filename for i in infos}) != len(infos):
            raise ValueError('Duplicate or excessive archive members')
        entry = z.getinfo('candidate.json')
        if entry.file_size > 1048576:
            raise ValueError('Manifest size invalid')
        raw = z.read(entry)
        if hashlib.sha256(raw).hexdigest() != MANIFEST_SHA:
            raise ValueError('Not the fixed original manifest')
        manifest = json.loads(raw)
        expected = {r['path']: (r['bytes'], r['sha256']) for r in manifest['files']}
        expected['candidate.json'] = (len(raw), MANIFEST_SHA)
        if set(expected) != {i.filename for i in infos}:
            raise ValueError('Archive differs from original manifest membership')
        # Validate the entire tree before creating any output.
        for i in infos:
            parts = i.filename.split('/')
            if i.is_dir() or any(p in ('', '.', '..') or ':' in p or '\\' in p for p in parts):
                raise ValueError('Unsafe member path')
            size, sha = expected[i.filename]
            if i.file_size != size or size > 536870912:
                raise ValueError('Member size mismatch')
            with z.open(i) as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != sha:
                    raise ValueError('Member digest mismatch')
        output.mkdir(parents=True, exist_ok=False)
        for i in infos:
            target = output.joinpath(*i.filename.split('/'))
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open(i) as src, target.open('xb') as dst:
                while chunk := src.read(1048576):
                    dst.write(chunk)
            with target.open('rb') as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != expected[i.filename][1]:
                    raise ValueError('Staged member changed; preserve evidence')
    return {'original_bundle_verified': True, 'member_count': len(expected), 'output': str(output), 'executed': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('archive')
    parser.add_argument('output')
    args = parser.parse_args()
    print(json.dumps(extract(args.archive, args.output)))
