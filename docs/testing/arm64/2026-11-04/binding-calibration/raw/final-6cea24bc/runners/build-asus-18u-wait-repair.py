from pathlib import Path
import ast
import concurrent.futures
import datetime
import hashlib
import json
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
source = sys.argv[1]
assert re.fullmatch('[0-9a-f]{40}', source)
git = r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe'
cmake = r'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'

def guard():
    assert subprocess.check_output([git, 'rev-parse', 'HEAD'], cwd=root, text=True).strip() == source
    assert not subprocess.check_output([git, 'status', '--porcelain', '--untracked-files=normal'], cwd=root, text=True).strip()

guard()
expected_version = '0.2.0-18u-arm64.4'
version_tree = ast.parse((root/'tools/yimecore/package_installed_18u.py').read_text(encoding='utf-8'))
versions = [ast.literal_eval(node.value) for node in version_tree.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'FRONTEND_VERSION' for target in node.targets)]
assert versions == [expected_version], 'frontend package version must be the new .4 product'
out = root / ('.generated/asus-18u-wait-repair-' + source[:8])
out.mkdir(exist_ok=False)
native = out / 'native'
go = out / 'bin'; go.mkdir()
configure = [cmake, '-S', str(root / 'YimeTextServiceExperiment'), '-B', str(native), '-G', 'Visual Studio 17 2022', '-A', 'ARM64', '-DYIME_TOUCH_PRODUCT=ON', '-DYIME_TOUCH_REGISTERED_FORMAL_HOST=ON', '-DYIME_18U_PRODUCT_REGISTRATION=ON']
cfg = subprocess.run(configure, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
(out / 'native-configure.log').write_bytes(cfg.stdout)
assert cfg.returncode == 0, 'native configuration failed'
jobs = {'native': [cmake, '--build', str(native), '--config', 'Release', '--target', 'YimeTextService18u', 'YimeDedicatedAsyncTests', 'YimeTouchInstalledFrontendHostTests', 'YimeTouchRegisteredFormalHostTests', 'Yime18uProductRegistration', '--parallel', '4']}
for name, package, flags in [('YimeBroker18u', 'yimebroker-18u', []), ('YimeTouchKeyboard', 'yime-touch-keyboard', ['-ldflags', '-H=windowsgui']), ('Yime18uInstalledRuntime', 'yimecore-trial-runtime', ['-ldflags', '-H=windowsgui -X main.installed18uOnly=1'])]:
    jobs[name] = [sys.executable, str(root / '.generated/touch-full-tools/run_go.py'), 'build', '-buildvcs=false', *flags, '-o', str(go / (name + '.exe')), './cmd/' + package]

def build(item):
    name, command = item
    result = subprocess.run(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / (name + '-build.log')).write_bytes(result.stdout)
    return {'target': name, 'exitCode': result.returncode, 'command': command}

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(build, jobs.items()))
assert all(item['exitCode'] == 0 for item in results), results
guard()
artifacts = [native / 'Release' / name for name in ['YimeTextService18u.dll', 'YimeDedicatedAsyncTests.exe', 'YimeTouchInstalledFrontendHostTests.exe', 'YimeTouchRegisteredFormalHostTests.exe', 'Yime18uProductRegistration.exe']]
artifacts += [go / (name + '.exe') for name in ['YimeBroker18u', 'YimeTouchKeyboard', 'Yime18uInstalledRuntime']]
report = {'schema': 'asus-18u-wait-repair-frozen-build-v1', 'sourceCommit': source, 'version': expected_version, 'sourceCleanBefore': True, 'sourceCleanAfter': True, 'builds': results, 'observedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'artifacts': [{'path': str(path.relative_to(root)), 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()} for path in artifacts]}
(out / 'build-receipt.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'built': True, 'source': source, 'nativeRoot': str(native / 'Release'), 'goRoot': str(go), 'receipt': str(out / 'build-receipt.json')}, indent=2), flush=True)
