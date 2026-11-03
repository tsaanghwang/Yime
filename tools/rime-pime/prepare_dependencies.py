"""Acquire pinned Rime build sources and private Rust bootstrap; never installs a product."""
import argparse
import configparser
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile
import urllib.request

REPOSITORIES = {
    'librime': ('rime/librime', '1.17.0'),
    'librime/plugins/lua': ('hchunhui/librime-lua', 'ec52e48'),
    'librime/plugins/octagram': ('lotem/librime-octagram', 'dfcc151'),
    'librime/plugins/predict': ('rime/librime-predict', '920bd41'),
    'librime/plugins/lua/thirdparty': ('hchunhui/librime-lua', 'thirdparty'),
}
BOOST = ('https://archives.boost.io/release/1.89.0/source/boost_1_89_0.tar.gz',
         '9de758db755e8330a01d995b0a24d09798048400ac25c03fc5ea9be364b13c93')

def request(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Yime-ARM64-build'}), timeout=180)

def api(path):
    with request('https://api.github.com/repos/' + path) as response:
        return json.load(response)

def sha256(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()

def download(url, path, expected=None):
    path = Path(path)
    if not path.exists():
        with request(url) as response, path.with_suffix(path.suffix + '.part').open('wb') as output:
            length = response.headers.get('Content-Length')
            received = 0
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
                received += len(chunk)
            if length is not None and received != int(length):
                raise ValueError('truncated download; preserve .part: ' + str(path))
        path.with_suffix(path.suffix + '.part').rename(path)
    digest = sha256(path)
    if expected and digest != expected:
        raise ValueError('download SHA-256 mismatch: ' + str(path))
    return {'url': url, 'sha256': digest, 'bytes': path.stat().st_size}

def unpack(archive, destination):
    destination = Path(destination)
    marker = destination / '.yime-source-archive.sha256'
    digest = sha256(archive)
    if marker.exists():
        if marker.read_text() != digest:
            raise ValueError('existing source does not match archive')
        return
    if destination.exists() and any(destination.iterdir()):
        raise ValueError('refuse existing source directory: ' + str(destination))
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as source:
        members = source.getmembers()
        prefixes = {PurePosixPath(m.name).parts[0] for m in members}
        if len(prefixes) != 1:
            raise ValueError('archive needs one root')
        for member in members:
            parts = PurePosixPath(member.name).parts[1:]
            if not parts:
                continue
            if member.issym() or member.islnk() or any(p in ('..', '') or ':' in p for p in parts):
                raise ValueError('unsafe source archive member: ' + member.name)
            member.name = str(PurePosixPath(*parts))
            source.extract(member, destination, filter='data')
    marker.write_text(digest)

def resolve_repository(repository, ref):
    return api(repository + '/commits/' + ref)['sha']

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True)
    parser.add_argument('--lock', required=True)
    args = parser.parse_args()
    root = Path(args.root).resolve()
    downloads = root / 'downloads'
    sources = root / 'sources'
    downloads.mkdir(parents=True, exist_ok=True)
    lock_path = Path(args.lock)
    lock = json.loads(lock_path.read_text()) if lock_path.exists() else {'schema': 1, 'sources': {}}

    def acquire(destination, repository, ref):
        prior = lock['sources'].get(destination)
        sha = prior['commit'] if prior else resolve_repository(repository, ref)
        archive = downloads / (repository.replace('/', '-') + '-' + sha + '.tar.gz')
        record = download('https://codeload.github.com/' + repository + '/tar.gz/' + sha, archive,
                          prior['sha256'] if prior else None)
        record.update(repository=repository, commit=sha, requestedRef=ref)
        lock['sources'][destination] = record
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        lock_path.write_text(json.dumps(lock, indent=2) + '\n')
        unpack(archive, sources / destination)
        print('SOURCE', destination, sha, flush=True)
        gitmodules = sources / destination / '.gitmodules'
        if gitmodules.exists():
            config = configparser.ConfigParser()
            config.read(gitmodules, encoding='utf-8')
            tree = api(repository + '/git/trees/' + sha + '?recursive=1')['tree']
            commits = {row['path']: row['sha'] for row in tree if row['type'] == 'commit'}
            for section in config.sections():
                relative = config[section]['path']
                url = config[section]['url']
                if not url.startswith('https://github.com/'):
                    raise ValueError('review non-GitHub submodule source: ' + url)
                child_repository = url.removeprefix('https://github.com/').removesuffix('.git')
                acquire(destination + '/' + relative, child_repository, commits[relative])

    for destination, (repository, ref) in REPOSITORIES.items():
        acquire(destination, repository, ref)
    archive = downloads / 'boost_1_89_0.tar.gz'
    lock['boost'] = download(BOOST[0], archive, BOOST[1])
    unpack(archive, sources / 'boost')
    bootstrap = downloads / 'rustup-init-arm64.exe'
    rust_url = 'https://static.rust-lang.org/rustup/dist/aarch64-pc-windows-msvc/rustup-init.exe'
    expected = lock.get('rustup', {}).get('sha256')
    if not expected:
        with request(rust_url + '.sha256') as response:
            expected = response.read().decode().split()[0]
    lock['rustup'] = download(rust_url, bootstrap, expected)
    manifest_url = 'https://static.rust-lang.org/dist/channel-rust-1.97.0.toml'
    lock['rustManifest'] = download(manifest_url, downloads / 'channel-rust-1.97.0.toml',
                                    lock.get('rustManifest', {}).get('sha256'))
    lock_path.write_text(json.dumps(lock, indent=2) + '\n')
    print('READY', root, flush=True)

if __name__ == '__main__':
    main()
