from pathlib import Path
import ast
import hashlib
import json
import os
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
source = sys.argv[1]
assert re.fullmatch('[0-9a-f]{40}', source)
expected_version = '0.2.0-18u-arm64.4'
version_tree = ast.parse((root/'tools/yimecore/package_installed_18u.py').read_text(encoding='utf-8'))
versions = [ast.literal_eval(node.value) for node in version_tree.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'FRONTEND_VERSION' for target in node.targets)]
assert versions == [expected_version], 'frontend package version must be the new .4 product'
git = r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe'

def guard():
    assert subprocess.check_output([git, 'rev-parse', 'HEAD'], cwd=root, text=True).strip() == source
    assert not subprocess.check_output([git, 'status', '--porcelain', '--untracked-files=normal'], cwd=root, text=True).strip()

guard()
out = root / ('.generated/asus-18u-wait-repair-' + source[:8])
build = json.loads((out / 'build-receipt.json').read_text(encoding='utf-8'))
assert build['sourceCommit'] == source and build['sourceCleanBefore'] and build['sourceCleanAfter'] and build['version'] == expected_version
for row in build['artifacts']:
    path = root / row['path']
    assert path.resolve().is_relative_to(out.resolve()), 'only this new isolated build may supply payload inputs'
    assert path.stat().st_size == row['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest() == row['sha256']
params = out / 'signatures-params.json'
params.write_text(json.dumps({'NativeRoot':str(out/'native/Release'), 'GoRoot':str(out/'bin'), 'SourceCommit':source, 'ReportPath':str(out/'six-signatures.json')}),encoding='utf-8')
env = os.environ.copy()
env['PATH'] = r'C:\Users\tsaan\AppData\Local\Microsoft\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe;' + env.get('PATH','')
tmp = out / 'package-temp'
if '--resume-verified-shell-access' in sys.argv[2:]:
    old_log = out / 'signatures.log'
    assert old_log.is_file() and b'ps7 executable unavailable' in old_log.read_bytes()
    assert not (out/'six-signatures.json').exists() and not (out/'simple').exists() and not (out/'complete').exists()
    first_log = out / 'signatures-first-sandbox-unavailable.log'
    assert not first_log.exists()
    first_log.write_bytes(old_log.read_bytes())
else:
    tmp.mkdir()
env['TEMP'] = env['TMP'] = str(tmp)

def run(label, command):
    result = subprocess.run(command, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / (label + '.log')).write_bytes(result.stdout)
    if result.returncode:
        print(result.stdout.decode('utf-8',errors='replace'), flush=True)
        raise SystemExit(result.returncode)
    print(label + ' passed', flush=True)

run('signatures', [sys.executable, '-B', '-X', 'utf8', str(root / '.generated/armfull-tools/run_checked_local.py'), '--edition', 'ps7', '--script', str(root / '.generated/touch-full-tools/observe_six_signatures.ps1'), '--params-file', str(params)])
run('simple-package', [sys.executable, 'tools/yimecore/package_installed_18u.py', '--repo', str(root), '--native', str(out/'native/Release'), '--go', str(out/'bin'), '--data', str(root/'.generated/touch-full-data'), '--work', str(out/'simple'), '--signatures', str(out/'six-signatures.json'), '--source-commit', source, '--frontend', '--architecture', 'arm64'])
run('complete-maintenance', [sys.executable, 'tools/rime-pime/package_native_maintenance.py', '--repo', str(root), 'attach', '--package-root', str(out/'simple/package'), '--output-root', str(out/'complete'), '--cache', str(root/'.generated/arm64-maintenance-shell'), '--source-commit', source, '--go', r'C:\dev\Yime\.generated\arm64-toolchain\go1.25.14\go\bin\go.exe', '--git', r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe'])
identity_path = out / 'complete' / ('yime-yimecore-18u-windows-arm64-' + source[:12] + '.identity.json')
identity = json.loads(identity_path.read_text(encoding='utf-8'))
manifest = json.loads((out/'simple/package/payload/installed-18u-product.json').read_text(encoding='utf-8'))
product = json.loads((out/'simple/package/product-package.json').read_text(encoding='utf-8-sig'))
assert product['version'] == expected_version and product['product'] == 'yimecore-18u' and product['target'] == 'windows-arm64'
guard()
receipt = {'sourceCommit':source, 'version':expected_version, 'package':str(out/'simple/package'), 'identity':str(identity_path), 'zip':identity['zip'], 'installedManifestSHA256':hashlib.sha256((out/'simple/package/payload/installed-18u-product.json').read_bytes()).hexdigest(), 'payloadCount':len(manifest['files'])+1, 'planSHA256':identity['planSHA256'], 'maintenanceSHA256':identity['maintenanceSHA256'], 'installed':False}
(out/'complete-package-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
print(json.dumps(receipt,indent=2),flush=True)
