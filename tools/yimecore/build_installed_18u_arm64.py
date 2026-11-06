"""Build a complete native ARM64 v2 package without executing its product binaries.

Runs on Windows ARM64 (native compilation) or x64 (cross compilation). Neither
case is installation, registered-host, real application, or physical acceptance.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

import assemble_installed_18u as assembly

ROOT = Path(__file__).resolve().parents[2]
SIGNATURE_SCRIPT = r'''param([string]$InputPath,[string]$OutputPath,[string]$SourceCommit)
$ErrorActionPreference='Stop'
$rows=@(Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8 | ConvertFrom-Json)
$files=@(foreach($row in $rows){
    $signature=Get-AuthenticodeSignature -LiteralPath $row.file
    [ordered]@{path=$row.path;bytes=(Get-Item -LiteralPath $row.file).Length;sha256=(Get-FileHash -LiteralPath $row.file -Algorithm SHA256).Hash.ToLowerInvariant();status=$signature.Status.ToString();signerThumbprint=$(if($null -ne $signature.SignerCertificate){$signature.SignerCertificate.Thumbprint}else{$null})}
})
[IO.File]::WriteAllText($OutputPath,([ordered]@{schema='installed-18u-signatures-v1';sourceCommit=$SourceCommit;files=$files}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--go', default='go')
    parser.add_argument('--cmake', default='cmake')
    args = parser.parse_args()
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT, text=True)
    if source != args.source_commit or dirty:
        raise SystemExit('Exact clean source commit required before complete package build')
    out = args.output.absolute()
    generated = ROOT / '.generated'
    if out == generated or generated not in out.parents or out.exists():
        raise SystemExit('A fresh directory inside this checkout .generated is required')
    for path in (out, *out.parents):
        if path.is_symlink() or path.is_junction():
            raise SystemExit('Linked output refused')
    go = shutil.which(args.go)
    cmake = shutil.which(args.cmake)
    if not go or not cmake:
        raise SystemExit('Existing Go and CMake toolchains required')
    sys.path.insert(0, str(ROOT / 'tools'))
    from touch_keyboard_resources import verify
    verify(args.data)
    out.mkdir(parents=True)
    evidence = out / 'evidence'
    evidence.mkdir()
    env = os.environ.copy()
    env.update(GOOS='windows', GOARCH='arm64', CGO_ENABLED='0', GOTOOLCHAIN='local', PYTHONUTF8='1')
    env['PATH'] = str(Path(go).parent) + os.pathsep + env.get('PATH', '')
    scope = dict(sourceCommit=source, architecture='native-arm64', buildHost=platform.machine(),
                 scope='compile-and-package-only', packageGenerated=False,
                 productExecuted=False, installationExecuted=False, registrationExecuted=False,
                 installedHostAcceptance=False, physicalAcceptance=False)
    scope_path = evidence / 'scope.json'
    scope_path.write_text(json.dumps(scope, indent=2) + '\n', encoding='utf-8')

    def run(command, name, cwd=ROOT, timeout=600):
        print('Running ' + name, flush=True)
        with (evidence / (name + '.log')).open('w', encoding='utf-8') as log:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        if result.returncode:
            raise SystemExit('Failed ' + name + '; inspect ' + str(evidence / (name + '.log')))

    native, go_out, frontend = out / 'native', out / 'go', out / 'frontend'
    go_out.mkdir()
    run([cmake, '-S', str(ROOT / 'YimeTextServiceExperiment'), '-B', str(native),
         '-A', 'ARM64', '-DYIME_TOUCH_PRODUCT=ON', '-DYIME_TOUCH_FRONTEND=ON',
         '-DYIME_TOUCH_REGISTERED_FORMAL_HOST=ON', '-DYIME_18U_PRODUCT_REGISTRATION=ON'], 'configure')
    run([cmake, '--build', str(native), '--config', 'Release', '--target',
         'YimeTextService18u', 'Yime18uProductRegistration', 'YimeTouchRegisteredFormalHostTests'], 'native-build')
    run([go, 'build', '-trimpath', '-ldflags=-X main.installed18uOnly=1', '-o',
         str(go_out / 'Yime18uInstalledRuntime.exe'), './cmd/yimecore-trial-runtime'], 'runtime-build', ROOT / 'go-backend')
    run([go, 'build', '-trimpath', '-o', str(go_out / 'YimeBroker18u.exe'), './cmd/yimebroker-18u'],
        'broker-build', ROOT / 'go-backend')
    run([sys.executable, '-X', 'utf8', 'tools/build_touch_keyboard_desktop.py', '--installed-tsf',
         '--arch', 'arm64', '--data-dir', str(args.data.absolute()), '--output-dir', str(frontend)], 'frontend-build')
    rows = []
    for dest, (kind, name) in assembly.binary_map('arm64').items():
        directory = native / 'Release' if kind == 'native' else go_out
        rows.append(dict(path='payload/' + dest, file=str(directory / name)))
    rows.append(dict(path='payload/frontend/YimeTouchKeyboard.exe', file=str(frontend / 'YimeTouchKeyboard.exe')))
    inputs, signatures = evidence / 'signature-inputs.json', evidence / 'signatures.json'
    inputs.write_text(json.dumps(rows), encoding='utf-8')
    script, params = evidence / 'observe-signatures.ps1', evidence / 'signature-params.json'
    script.write_text(SIGNATURE_SCRIPT, encoding='utf-8')
    params.write_text(json.dumps(dict(InputPath=str(inputs), OutputPath=str(signatures), SourceCommit=source)), encoding='utf-8')
    run([sys.executable, 'tools/powershell/run_checked.py', '--edition', 'ps7', '--script', str(script),
         '--params-file', str(params)], 'signatures', timeout=90)
    run([sys.executable, '-X', 'utf8', 'tools/yimecore/package_installed_18u.py', '--architecture', 'arm64',
         '--repo', str(ROOT), '--native', str(native / 'Release'), '--go', str(go_out),
         '--data', str(args.data.absolute()), '--frontend', str(frontend), '--work', str(out / 'package'),
         '--signatures', str(signatures), '--source-commit', source], 'package', timeout=600)
    receipt = json.loads((out / 'package/package-receipt.json').read_text(encoding='utf-8'))
    (evidence / 'package-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    scope['packageGenerated'] = True
    scope_path.write_text(json.dumps(scope, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt, indent=2), flush=True)


if __name__ == '__main__':
    main()
