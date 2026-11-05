"""Build a fresh, source-frozen ARM64 18u package; never install or publish."""
from pathlib import Path
import concurrent.futures
import datetime
import hashlib
import importlib.util
import json
import os
import subprocess
import sys

OUT = Path(__file__).resolve().parent
REPO = OUT / 'source'
SOURCE = '636cef681ee995a21a9c45fd750f8cb4b0acb4a1'
VERSION = '0.2.0-18u-arm64.5'
GIT = Path(r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe')
CMAKE = Path(r'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe')
GO = Path(r'C:\dev\Yime\.generated\arm64-toolchain\go1.25.14\go\bin\go.exe')
DATA = Path(r'C:\dev\Yime\.wt\armfull\.generated\touch-full-data')
SHELL_CACHE = Path(r'C:\dev\Yime\.wt\armfull\.generated\arm64-maintenance-shell')
NATIVE = OUT / 'native'
BIN = OUT / 'bin'

def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def digest(path):
    with path.open('rb') as stream:
        return {'bytes': path.stat().st_size, 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}

def guard():
    assert subprocess.check_output([GIT, 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip() == SOURCE
    assert not subprocess.check_output([GIT, 'status', '--porcelain', '--untracked-files=normal'], cwd=REPO, text=True).strip()

def environment():
    env = os.environ.copy()
    for name, child in [('GOCACHE', 'go-cache'), ('GOTMPDIR', 'tmp'), ('TEMP', 'tmp'), ('TMP', 'tmp'), ('GOPATH', 'go-path')]:
        directory = OUT / child
        directory.mkdir(exist_ok=True)
        env[name] = str(directory)
    env.update(GOOS='windows', GOARCH='arm64', CGO_ENABLED='0', GOENV='off', GOTOOLCHAIN='local', GOFLAGS='', GOPROXY='off')
    env['PATH'] = str(SHELL_CACHE / 'powershell') + os.pathsep + env.get('PATH', '')
    return env

def run(label, command, cwd=REPO):
    result = subprocess.run([str(x) for x in command], cwd=cwd, env=environment(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (OUT / (label + '.log')).write_bytes(result.stdout)
    row = {'name': label, 'command': [str(x) for x in command], 'cwd': str(cwd), 'exitCode': result.returncode}
    write_json(OUT / (label + '.command.json'), row)
    print(label + ' exit=' + str(result.returncode), flush=True)
    if result.returncode:
        print(result.stdout.decode('utf-8', errors='replace')[-6000:], flush=True)
        raise RuntimeError(label + ' failed; original log preserved')
    return row

def build():
    guard()
    assert not NATIVE.exists() and not BIN.exists(), 'fresh binary output required'
    BIN.mkdir()
    configure = run('native-configure', [CMAKE, '-S', REPO / 'YimeTextServiceExperiment', '-B', NATIVE,
        '-G', 'Visual Studio 17 2022', '-A', 'ARM64', '-DYIME_TOUCH_PRODUCT=ON',
        '-DYIME_TOUCH_REGISTERED_FORMAL_HOST=ON', '-DYIME_18U_PRODUCT_REGISTRATION=ON'])
    targets = ['YimeTextService18u', 'YimeDedicatedAsyncTests', 'YimeTouchInstalledFrontendHostTests',
        'YimeTouchRegisteredFormalHostTests', 'Yime18uProductRegistration']
    jobs = [('native-build', [CMAKE, '--build', NATIVE, '--config', 'Release', '--target', *targets, '--parallel', '4'], REPO)]
    for name, package, flags in [
        ('YimeBroker18u', 'yimebroker-18u', []),
        ('YimeTouchKeyboard', 'yime-touch-keyboard', ['-ldflags', '-H=windowsgui']),
        ('Yime18uInstalledRuntime', 'yimecore-trial-runtime', ['-ldflags', '-H=windowsgui -X main.installed18uOnly=1'])]:
        jobs.append((name + '-build', [GO, 'build', '-buildvcs=false', *flags, '-o', BIN / (name + '.exe'), './cmd/' + package], REPO / 'go-backend'))
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        builds = list(executor.map(lambda item: run(*item), jobs))
    guard()
    files = [NATIVE / 'Release' / (name + ('.dll' if name == 'YimeTextService18u' else '.exe')) for name in targets]
    files += [BIN / (name + '.exe') for name in ['YimeBroker18u', 'YimeTouchKeyboard', 'Yime18uInstalledRuntime']]
    receipt = {'schema': 'arm64-binding-frozen-build-v1', 'sourceCommit': SOURCE, 'version': VERSION,
        'sourceCleanBefore': True, 'sourceCleanAfter': True, 'observedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'configure': configure, 'builds': builds, 'artifacts': [{'path': str(p), **digest(p)} for p in files],
        'nativeHostTestsExecuted': False, 'installed': False}
    write_json(OUT / 'build-receipt.json', receipt)

def package():
    guard()
    build_receipt = json.loads((OUT / 'build-receipt.json').read_text(encoding='utf-8'))
    assert build_receipt['sourceCommit'] == SOURCE and build_receipt['sourceCleanBefore'] and build_receipt['sourceCleanAfter']
    for row in build_receipt['artifacts']:
        assert digest(Path(row['path'])) == {k: row[k] for k in ('bytes', 'sha256')}
    signature_script = OUT / 'observe_six_signatures.ps1'
    params = OUT / 'signature-parameters.json'
    write_json(params, {'NativeRoot': str(NATIVE / 'Release'), 'GoRoot': str(BIN),
        'SourceCommit': SOURCE, 'ReportPath': str(OUT / 'six-signatures.json')})
    run('signatures', [sys.executable, '-B', '-X', 'utf8', REPO / 'tools/powershell/run_checked.py',
        '--edition', 'ps7', '--script', signature_script, '--params-file', params])
    sys.path.insert(0, str(REPO / 'tools/yimecore'))
    import package_installed_18u as pack
    original_version = pack.FRONTEND_VERSION
    assert original_version == '0.2.0-18u-arm64.4'
    # Packaging configuration only: no source bytes or executable are patched.
    pack.FRONTEND_VERSION = VERSION
    write_json(OUT / 'version-configuration.json', {'sourceCommit': SOURCE, 'sourceConstant': original_version,
        'effectiveFrontendVersion': VERSION, 'method': 'package_installed_18u.FRONTEND_VERSION process-local build parameter',
        'sourceFileModified': False})
    def checked_runner(command, **kwargs):
        result = subprocess.run(command, env=environment(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            **{k: v for k, v in kwargs.items() if k != 'check'})
        (OUT / 'simple-package.log').write_bytes(result.stdout)
        write_json(OUT / 'simple-package.command.json', {'command': command, 'exitCode': result.returncode})
        if result.returncode:
            raise RuntimeError('simple package failed: ' + result.stdout.decode('utf-8', errors='replace')[-4000:])
        return result
    summary = pack.build(REPO, NATIVE / 'Release', BIN, DATA, OUT / 'simple', OUT / 'six-signatures.json', SOURCE,
        runner=checked_runner, architecture='arm64', frontend=True)
    write_json(OUT / 'simple-package-summary.json', summary)
    run('complete-maintenance', [sys.executable, '-B', '-X', 'utf8', REPO / 'tools/rime-pime/package_native_maintenance.py',
        '--repo', REPO, 'attach', '--package-root', OUT / 'simple/package', '--output-root', OUT / 'complete',
        '--cache', SHELL_CACHE, '--source-commit', SOURCE, '--go', GO, '--git', GIT])
    guard()
    identity_path = OUT / 'complete' / ('yime-yimecore-18u-windows-arm64-' + SOURCE[:12] + '.identity.json')
    identity = json.loads(identity_path.read_text(encoding='utf-8'))
    package_root = OUT / 'simple/package'
    product = json.loads((package_root / 'product-package.json').read_text(encoding='utf-8-sig'))
    manifest = json.loads((package_root / 'payload/installed-18u-product.json').read_text(encoding='utf-8'))
    assert product['version'] == VERSION and manifest['sourceCommit'] == SOURCE and identity['source']['clean']
    receipt = {'schema': 'arm64-binding-complete-package-v1', 'sourceCommit': SOURCE, 'version': VERSION,
        'package': str(package_root), 'identity': str(identity_path), 'identityDigest': digest(identity_path),
        'zip': {'path': str(identity_path.parent / identity['zip']['name']), **identity['zip']},
        'installedManifest': {'path': str(package_root / 'payload/installed-18u-product.json'), **digest(package_root / 'payload/installed-18u-product.json')},
        'payloadCount': len(manifest['files']) + 1, 'fileCount': identity['fileCount'],
        'planSHA256': identity['planSHA256'], 'maintenanceSHA256': identity['maintenanceSHA256'],
        'versionOverride': json.loads((OUT / 'version-configuration.json').read_text(encoding='utf-8')),
        'installed': False, 'published': False}
    write_json(OUT / 'complete-package-receipt.json', receipt)
    print(json.dumps(receipt, ensure_ascii=False, indent=2), flush=True)

if __name__ == '__main__':
    if sys.argv[1:] == ['build']: build()
    elif sys.argv[1:] == ['package']: package()
    else: raise SystemExit('choose build or package')
