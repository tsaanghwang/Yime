"""Validate the fixed .5 package; upload a draft or publish that reviewed draft.

The check stage is completely local. No stage builds, installs, activates,
changes defaults, or retries host input. Draft and publish are separate calls.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
from datetime import datetime, timezone
import zipfile

ROOT = Path(__file__).resolve().parents[3]
SOURCE = '636cef681ee995a21a9c45fd750f8cb4b0acb4a1'
VERSION = '0.2.0-18u-arm64.5'
REPO = 'tsaanghwang/Yime'
TAG = 'test-arm64-18u-binding-636cef68-20261106'
BUILD = ROOT / '.generated/package-binding-636cef68'
OUT = ROOT / '.generated/binding-upgrade-20261106/release'
CI = ROOT / 'docs/testing/18u/2026-11-05/arm64-binding-focus/ci-receipt.json'
GIT = Path(r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe')
HELPER = Path(__file__).with_name('gh_repo.py')
WORKFLOWS = {'Build', 'Touch terminal prototype', 'ARM64 complete input contracts', '18u async route contracts'}
SKIPS = {'one-shot-18u-language-inventory', 'one-shot-18u-language-prepare', 'one-shot-18u-registration-probe'}


def require(value, message):
    if not value:
        raise ValueError(message)


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def digest(path):
    path = Path(path)
    with path.open('rb') as stream:
        sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    return {'bytes': path.stat().st_size, 'sha256': sha}


def write_once(path, data):
    path = Path(path)
    if path.exists():
        require(path.read_bytes() == data, 'Existing output differs; preserve and review: ' + str(path))
    else:
        with path.open('xb') as stream:
            stream.write(data)


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def validate_ci(ci):
    require(ci.get('schema') == '18u-binding-focus-ci-receipt-v1' and ci.get('sourceCommit') == SOURCE, 'CI source/schema mismatch')
    workflows = ci.get('workflows', [])
    require(len(workflows) == 4 and {w.get('name') for w in workflows} == WORKFLOWS, 'Expected exactly four CI workflows')
    require(len({w.get('id') for w in workflows}) == 4, 'Duplicate CI workflow id')
    jobs = []
    for workflow in workflows:
        require(workflow.get('headSha') == SOURCE and workflow.get('status') == 'completed' and workflow.get('conclusion') == 'success', 'Workflow not successful for fixed source')
        require(workflow.get('runAttempt') == 1 and workflow.get('event') == 'push', 'Unexpected workflow attempt/event')
        require(workflow.get('url') == f'https://github.com/{REPO}/actions/runs/{workflow["id"]}', 'Workflow URL mismatch')
        rows = workflow.get('jobs', [])
        require(isinstance(rows, list) and rows, 'Missing workflow jobs')
        for job in rows:
            require(job.get('status') == 'completed', 'Pending CI job')
            conclusion = job.get('conclusion')
            require(conclusion == 'success' or (conclusion == 'skipped' and workflow['name'] == 'Build' and job.get('name') in SKIPS), 'Unsuccessful or unexpected skipped CI job')
        jobs.extend(rows)
    require(len(jobs) == 24 and len({j.get('id') for j in jobs}) == 24, 'CI job identity/count mismatch')
    require(sum(j['conclusion'] == 'success' for j in jobs) == 21, 'Expected 21 successful CI jobs')
    require({j['name'] for j in jobs if j['conclusion'] == 'skipped'} == SKIPS, 'Expected the three specified manual-only skips')
    require(ci.get('summary') == {'workflows': 4, 'successfulJobs': 21, 'skippedJobs': 3, 'failedJobs': 0}, 'CI summary mismatch')
    return ci


def source_clean():
    source = BUILD / 'source'
    head = subprocess.run([str(GIT), '-C', str(source), 'rev-parse', 'HEAD'], check=True, capture_output=True, text=True).stdout.strip()
    status = subprocess.run([str(GIT), '-C', str(source), 'status', '--porcelain', '--untracked-files=all'], check=True, capture_output=True).stdout
    require(head == SOURCE and not status, 'Frozen package source checkout is not clean at the exact source commit')


def validate_local():
    receipt_path, build_path, version_path = (BUILD / name for name in ('complete-package-receipt.json', 'build-receipt.json', 'version-configuration.json'))
    receipt, build, version = read(receipt_path), read(build_path), read(version_path)
    require(receipt.get('schema') == 'arm64-binding-complete-package-v1' and receipt.get('sourceCommit') == SOURCE and receipt.get('version') == VERSION, 'Complete package identity mismatch')
    require(receipt.get('installed') is False and receipt.get('published') is False, 'Build receipt must not claim installation/publication')
    require(build.get('schema') == 'arm64-binding-frozen-build-v1' and build.get('sourceCommit') == SOURCE and build.get('version') == VERSION, 'Build receipt identity mismatch')
    require(build.get('sourceCleanBefore') is True and build.get('sourceCleanAfter') is True, 'Build source not clean')
    require(build.get('configure', {}).get('exitCode') == 0, 'Native configure failed')
    builds = build.get('builds', [])
    require(len(builds) == 4 and {b.get('name') for b in builds} == {'native-build', 'YimeBroker18u-build', 'YimeTouchKeyboard-build', 'Yime18uInstalledRuntime-build'} and all(b.get('exitCode') == 0 for b in builds), 'Missing or failed native build')
    require(version == receipt.get('versionOverride') and version.get('sourceCommit') == SOURCE and version.get('sourceConstant') == '0.2.0-18u-arm64.4' and version.get('effectiveFrontendVersion') == VERSION and version.get('sourceFileModified') is False and version.get('method') == 'package_installed_18u.FRONTEND_VERSION process-local build parameter', 'Version override provenance mismatch')
    source_clean()
    identity_path = Path(receipt['identity'])
    require(digest(identity_path) == receipt['identityDigest'], 'Archive identity digest mismatch')
    identity = read(identity_path)
    require(identity.get('schema') == 'yime-native-maintenance-archive-v1' and identity.get('deliveryState') == 'source-frozen' and identity.get('product') == 'yimecore-18u' and identity.get('target') == 'windows-arm64', 'Archive identity/schema mismatch')
    require(identity.get('source', {}).get('commit') == SOURCE and identity['source'].get('clean') is True, 'Archive source mismatch')
    require(identity.get('installed') is False and identity.get('published') is False, 'Archive must remain a packaging observation')
    require({k: receipt['zip'][k] for k in ('name', 'bytes', 'sha256')} == identity['zip'], 'ZIP receipts disagree')
    archive = Path(receipt['zip']['path'])
    require(archive.name == identity['zip']['name'] and digest(archive) == {k: identity['zip'][k] for k in ('bytes', 'sha256')}, 'ZIP hash/size mismatch')
    require(receipt['fileCount'] == identity['fileCount'] and receipt['payloadCount'] == 20, 'Package file count mismatch')
    require(receipt['planSHA256'] == identity['planSHA256'] and receipt['maintenanceSHA256'] == identity['maintenanceSHA256'], 'Maintenance receipts disagree')
    with zipfile.ZipFile(archive) as z:
        entries = [row for row in z.infolist() if not row.is_dir()]
        names = [row.filename for row in entries]
        require(len(names) == len(set(names)) == len({n.casefold() for n in names}) == identity['fileCount'] and set(names) == set(identity['files']), 'ZIP inventory has duplicates, omissions, or extra members')
        for name, expected in identity['files'].items():
            parts = PurePosixPath(name)
            require(not parts.is_absolute() and '..' not in parts.parts and '\\' not in name and ':' not in name, 'Invalid ZIP member name')
            with z.open(name) as stream:
                actual_sha = hashlib.file_digest(stream, 'sha256').hexdigest()
            require(z.getinfo(name).file_size == expected['bytes'] and actual_sha == expected['sha256'], 'ZIP member mismatch: ' + name)
        manifest = json.loads(z.read('payload/installed-18u-product.json'))
        package = json.loads(z.read('product-package.json'))
        require(package.get('product') == 'yimecore-18u' and package.get('version') == VERSION and package.get('target') == 'windows-arm64', 'Simple package identity mismatch')
        require(manifest.get('sourceCommit') == SOURCE and manifest.get('product') == 'yimecore-18u', 'Installed manifest source/product mismatch')
        require(identity['files']['payload/installed-18u-product.json'] == {k: receipt['installedManifest'][k] for k in ('bytes', 'sha256')}, 'Installed manifest receipt mismatch')
        require(identity['files']['maintenance-plan.json']['sha256'] == receipt['planSHA256'] and identity['files']['YimeMaintenance.exe']['sha256'] == receipt['maintenanceSHA256'], 'Maintenance file binding mismatch')
        built = build.get('artifacts', [])
        require(len(built) == 8 and len({Path(row['path']).name for row in built}) == 8, 'Build artifact count/identity mismatch')
        for row in built:
            expected = {k: row[k] for k in ('bytes', 'sha256')}
            require(digest(row['path']) == expected, 'Built artifact changed: ' + Path(row['path']).name)
            matches = [n for n in names if n.startswith('payload/') and PurePosixPath(n).name == Path(row['path']).name]
            if Path(row['path']).name not in {'YimeDedicatedAsyncTests.exe', 'YimeTouchInstalledFrontendHostTests.exe'}:
                require(len(matches) == 1 and identity['files'][matches[0]] == expected, 'Package binary differs from build receipt')
    ci = validate_ci(read(CI))
    OUT.mkdir(parents=True, exist_ok=True)
    copies = [(build_path, 'native-build-636cef68.json'), (CI, 'source-ci-636cef68.json'), (receipt_path, 'complete-package-636cef68.json'), (version_path, 'version-configuration-636cef68.json')]
    assets = [archive, identity_path]
    for original, name in copies:
        target = OUT / name
        write_once(target, original.read_bytes())
        assets.append(target)
    require(len({p.name for p in assets}) == len(assets), 'Duplicate release attachment name')
    return receipt, identity, ci, [(p, digest(p)) for p in assets]


def notes_for(assets):
    return (f'''18u ARM64 development package {VERSION}.

Frozen source: `{SOURCE}`. This package rebuilds the matching frontend, Broker and TIP from that source. Package version .5 is an explicit process-local build parameter; the source constant .4 was not modified. The attached version configuration records that distinction.

Fixes the installed Broker path's assumption that the foreground top-level window and focused text control share a thread. Discovery, routing and final TSF edits now check the exact focused control, its root/process/thread, context and lease. GUI errors preserve available rejection stages and backend detail instead of replacing everything with a generic preview-session error. Some native failures still lack a detailed error field; error messages are not a persistent diagnostic log.

Exact-source CI: four successful workflows, 21 successful jobs, three specified existing manual-only skips, zero failures. Direct workflow URLs and job identities are in the attached CI receipt. Local native ARM64 source build and per-member complete-archive hash verification passed.

Installed upgrade and real Notepad body input for this .5 package are PENDING at publication. Source/substitute-TSF checks do not establish the cause of the historical ASUS failure or physical acceptance. The existing ASUS ruler result and older successful/failed records remain separate. Standard YimeCore, Rime/PIME, the default input method and user data are outside this package update; no installation has been performed by publishing.

This is the complete matching ARM64 maintenance package. Do not replace only the DLL or mix .4/.5 frontend/Broker/TIP files. Development prerelease; not the latest stable release. Native ARM64 is the target; no new x64/x86/ARM64EC host acceptance is claimed.

Assets:
''' + ''.join(f'- `{p.name}`: SHA-256 `{d["sha256"]}`, {d["bytes"]} bytes\n' for p, d in assets)).encode('utf-8')


def gh(*args, missing=False):
    result = subprocess.run([sys.executable, '-B', '-X', 'utf8', str(HELPER), *args], cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace')
    if result.returncode:
        if missing and ('HTTP 404' in result.stderr or 'release not found' in result.stderr.lower()):
            return None
        # Never include helper credential output; only GitHub CLI's bounded error.
        raise RuntimeError('GitHub command failed: ' + result.stderr[-2000:])
    return result.stdout


def remote(missing=False):
    # Unpublished drafts do not have a resolvable tag REST endpoint yet.
    # Resolve the requested draft with the CLI, then read its exact REST id.
    value = gh('release', 'view', TAG, '--repo', REPO, '--json', 'databaseId,tagName,targetCommitish', missing=missing)
    if value is None:
        return None
    found = json.loads(value)
    require(found.get('tagName') == TAG and found.get('targetCommitish') == SOURCE, 'CLI release identity mismatch')
    return json.loads(gh('api', f'repos/{REPO}/releases/{found["databaseId"]}'))


def validate_remote(release, assets, draft, complete=True):
    require(release.get('tag_name') == TAG and release.get('target_commitish') == SOURCE, 'Remote release source/tag mismatch')
    require(release.get('draft') is draft and release.get('prerelease') is True, 'Remote release state mismatch')
    expected = {p.name: d for p, d in assets}
    rows = release.get('assets', [])
    require(len(rows) == len({a['name'] for a in rows}) and {a['name'] for a in rows}.issubset(expected), 'Unexpected/duplicate remote attachments')
    if complete:
        require(len(rows) == len(expected), 'Missing remote attachments')
    for row in rows:
        value = expected[row['name']]
        require(row.get('digest') == 'sha256:' + value['sha256'] and row.get('size') == value['bytes'] and row.get('state') == 'uploaded', 'Remote attachment digest/size/state mismatch: ' + row['name'])


def validate_tag(required=False):
    raw = gh('api', f'repos/{REPO}/git/ref/tags/{TAG}', missing=not required)
    if raw is None:
        return
    obj = json.loads(raw)['object']
    for _ in range(4):
        if obj.get('type') == 'commit':
            require(obj.get('sha') == SOURCE, 'Remote tag points to another source')
            return
        require(obj.get('type') == 'tag', 'Unexpected remote tag object')
        obj = json.loads(gh('api', f'repos/{REPO}/git/tags/{obj["sha"]}'))['object']
    raise ValueError('Remote tag nesting exceeds expected bound')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', required=True, choices=('check', 'draft', 'publish'))
    args = parser.parse_args()
    receipt, identity, ci, assets = validate_local()
    notes = OUT / 'release-notes.md'
    write_once(notes, notes_for(assets))
    plan = {'schema': '18u-binding-release-plan-v1', 'sourceCommit': SOURCE, 'version': VERSION, 'tag': TAG, 'prerelease': True, 'latest': False, 'ciSummary': ci['summary'], 'installed': False, 'realNotepadAcceptance': 'pending', 'fileCount': identity['fileCount'], 'assets': [{'path': str(p), 'name': p.name, **d} for p, d in assets], 'notes': str(notes), 'notesDigest': digest(notes)}
    write_once(OUT / 'prepared-plan.json', json_bytes(plan))
    if args.stage == 'check':
        print(json.dumps({'stage': 'check', 'localValidation': 'passed', 'remoteWrites': False, 'plan': str(OUT / 'prepared-plan.json'), 'archive': receipt['zip']}, ensure_ascii=False, indent=2))
        return
    require(not (OUT / 'delivery-receipt.json').exists(), 'Publication already recorded; do not republish')
    validate_tag()
    current = remote(missing=True)
    if args.stage == 'publish':
        draft_record = read(OUT / 'draft-receipt.json')
        require(draft_record.get('sourceCommit') == SOURCE and draft_record.get('tag') == TAG and draft_record.get('draft') is True and draft_record.get('planSHA256') == digest(OUT / 'prepared-plan.json')['sha256'], 'Publish requires the matching separately completed draft')
        require(current is not None and current.get('id') == draft_record.get('releaseId'), 'Remote draft identity changed')
        validate_remote(current, assets, True)
        require(current.get('body') == notes.read_text(encoding='utf-8'), 'Remote draft notes differ from reviewed notes')
        gh('release', 'edit', TAG, '--repo', REPO, '--draft=false', '--prerelease', '--latest=false', '--notes-file', str(notes))
    else:
        if current is None:
            gh('release', 'create', TAG, '--repo', REPO, '--target', SOURCE, '--draft', '--prerelease', '--latest=false', '--title', 'ARM64 18u .5: focused text-thread binding', '--notes-file', str(notes))
        else:
            require(current.get('target_commitish') == SOURCE and current.get('draft') is True and current.get('prerelease') is True and current.get('body') == notes.read_text(encoding='utf-8'), 'Existing draft identity/notes differ')
        for path, value in assets:
            current = remote()
            validate_remote(current, assets, True, complete=False)
            matches = [a for a in current['assets'] if a['name'] == path.name]
            require(len(matches) <= 1, 'Duplicate remote attachment')
            if not matches:
                print('Uploading ' + path.name, flush=True)
                gh('release', 'upload', TAG, str(path), '--repo', REPO)
                matches = [a for a in remote()['assets'] if a['name'] == path.name]
            require(len(matches) == 1 and matches[0].get('digest') == 'sha256:' + value['sha256'] and matches[0].get('size') == value['bytes'] and matches[0].get('state') == 'uploaded', 'Uploaded attachment failed digest/size/state verification')
    current = remote()
    validate_remote(current, assets, args.stage == 'draft')
    if args.stage == 'publish':
        validate_tag(required=True)
        latest = gh('api', f'repos/{REPO}/releases/latest', missing=True)
        require(latest is None or json.loads(latest).get('id') != current['id'], 'Prerelease unexpectedly became latest stable release')
    record = {'schema': '18u-binding-release-receipt-v1', 'sourceCommit': SOURCE, 'version': VERSION, 'tag': TAG, 'stage': args.stage, 'verifiedAtUTC': datetime.now(timezone.utc).isoformat(), 'releaseId': current['id'], 'url': current['html_url'], 'draft': current['draft'], 'prerelease': current['prerelease'], 'latestRequested': False, 'planSHA256': digest(OUT / 'prepared-plan.json')['sha256'], 'ciSummary': ci['summary'], 'installed': False, 'realNotepadAcceptance': 'pending', 'assets': [{'name': row['name'], 'size': row['size'], 'digest': row['digest'], 'url': row['browser_download_url'], 'state': row['state']} for row in sorted(current['assets'], key=lambda row: row['name'])]}
    record_path = OUT / ('delivery-receipt.json' if args.stage == 'publish' else 'draft-receipt.json')
    if record_path.exists():
        old = read(record_path)
        require(all(old.get(k) == record.get(k) for k in ('sourceCommit', 'version', 'tag', 'releaseId', 'draft', 'prerelease', 'planSHA256', 'assets')), 'Existing stage receipt differs')
        record = old
    else:
        write_once(record_path, json_bytes(record))
    print(json.dumps(record, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
