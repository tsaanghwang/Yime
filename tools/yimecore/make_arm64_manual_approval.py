"""Create an UNAPPROVED review draft for a fixed 18u ARM64 ZIP.

The expected archive digest must come from an independent delivery channel.
This tool does not authenticate that channel, grant approval, or install Yime.
"""

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import stat
import zipfile

SCHEMA = 'yime-18u-arm64-manual-approval-v1'
COMMIT = '2bc222d92321daa29cea9951761cc1063db5f045'
REQUIRED = {'Product.psm1', 'Setup.ps1', 'Setup.cmd', 'product-package.json',
            'payload/installed-18u-product.json'}


def make_draft(archive: Path, expected_sha256: str, approved_user_sid: str) -> dict:
    if not re.fullmatch('[0-9a-f]{64}', expected_sha256):
        raise ValueError('independent archive SHA-256 required')
    if not re.fullmatch(r'S-1-5-(?:\d+-){1,14}\d+', approved_user_sid):
        raise ValueError('explicit initiating user SID required')
    archive = archive.absolute()
    for item in (archive, *archive.parents):
        if item.is_symlink() or (hasattr(item, 'is_junction') and item.is_junction()):
            raise ValueError('linked archive path refused')
    if not archive.is_file():
        raise ValueError('regular archive required')
    archive_bytes = archive.read_bytes()
    digest = hashlib.sha256(archive_bytes).hexdigest()
    if digest != expected_sha256:
        raise ValueError('archive differs from independently supplied SHA-256')
    rows = []
    seen = set()
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as package:
        for info in package.infolist():
            name = info.filename
            part = PurePosixPath(name)
            if (not name or name.endswith('/') or '\\' in name or ':' in name or
                    name.startswith('/') or any(p in ('', '.', '..') for p in name.split('/')) or
                    part.as_posix() != name or name.casefold() in seen or
                    stat.S_IFMT(info.external_attr >> 16) == stat.S_IFLNK):
                raise ValueError('unsafe or duplicate ZIP member')
            seen.add(name.casefold())
            with package.open(info) as member:
                data = member.read()
            if len(data) != info.file_size or not data:
                raise ValueError('empty or damaged ZIP member')
            rows.append({'path': name, 'bytes': len(data),
                         'sha256': hashlib.sha256(data).hexdigest()})
        if not {n.casefold() for n in REQUIRED} <= seen:
            raise ValueError('required maintenance member missing')
        manifest = json.loads(package.read('product-package.json'))
        descriptor = json.loads(package.read('payload/installed-18u-product.json'))
    if (manifest.get('format') != 'yime-simple-package-18u-1' or
            manifest.get('product') != 'yimecore-18u' or
            manifest.get('target') != 'windows-arm64' or
            manifest.get('host_architecture') != 'arm64' or
            manifest.get('tsf64_architecture') != 'arm64' or
            descriptor.get('schema') != 'installed-18u-product-v1' or
            descriptor.get('sourceCommit') != COMMIT or
            descriptor.get('architecture') != 'native-arm64'):
        raise ValueError('fixed 18u ARM64 package identity mismatch')
    return {'schema': SCHEMA, 'product': 'yimecore-18u', 'target': 'windows-arm64',
            'sourceCommit': COMMIT, 'archiveSha256': digest,
            'approvedUserSid': approved_user_sid, 'files': sorted(rows, key=lambda r: r['path'])}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--expected-sha256', required=True)
    parser.add_argument('--approved-user-sid', required=True)
    parser.add_argument('--draft-output', type=Path, required=True)
    args = parser.parse_args()
    draft = make_draft(args.archive, args.expected_sha256, args.approved_user_sid)
    with args.draft_output.open('x', encoding='utf-8') as output:
        json.dump(draft, output, ensure_ascii=False, indent=2)
        output.write('\n')


if __name__ == '__main__':
    main()
