"""Verify a new isolated demo package; only static/in-memory package checks run."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from build_touch_keyboard_demo import HOST, SCOPE
from touch_keyboard_resources import digest, verify
from check_touch_keyboard_package import validate_execution_architecture, require_new_output
from yimecore.collect_arm64_host import read_pe_machine


def verify_inventory(package):
    package=package.resolve()
    m=json.loads((package/'manifest.json').read_text(encoding='utf-8'))
    if m.get('scope')!=SCOPE or m.get('architecture')!='windows-amd64' or m.get('completeChineseResources') is not True or m.get('userDesktopExecutionApproved') is not False:
        raise ValueError('isolated x64 demo identity required')
    if m.get('mode')!='variable' or m.get('inputLanguage')!='chinese' or m.get('physicalAcceptance') is not False or m.get('installedProductAcceptance') is not False:
        raise ValueError('demo mode/acceptance boundary mismatch')
    actual={p.relative_to(package).as_posix() for p in package.rglob('*') if p.is_file()}
    if actual!=set(m['files'])|{'manifest.json'}:
        raise ValueError('unexpected or missing package files')
    for name,want in m['files'].items():
        p=(package/name).resolve()
        if not p.is_relative_to(package) or digest(p)!=want:raise ValueError('package hash mismatch')
    if digest(package/'resources.json')!=m['portableResourcesSHA256'] or digest(package/HOST)!=m['nativeHostSHA256']:
        raise ValueError('bound inventory/host mismatch')
    r=json.loads((package/'resources.json').read_text(encoding='utf-8'))
    if r['files'].get(HOST)!=m['nativeHostSHA256']:raise ValueError('host is not inventory bound')
    verify(package/'data')
    return m


def check(package,report):
    package=package.resolve();report=report.absolute();require_new_output(report)
    if report.resolve().is_relative_to(package):raise ValueError('evidence must be outside package')
    m=verify_inventory(package)
    architecture,_=validate_execution_architecture(package,m)
    if read_pe_machine(package/HOST)['machine']!='0x8664':raise ValueError('native host architecture mismatch')
    with tempfile.TemporaryDirectory(prefix='Yime-own-demo-check-') as tmp:
        root=Path(tmp);copy=root/'relocated';shutil.copytree(package,copy);cwd=root/'empty';cwd.mkdir()
        result=root/'check.json'
        cmd=[str(copy/'YimeTouchKeyboard.exe'),'--check-package','--data-report',str(result)]
        run=subprocess.run(cmd,cwd=cwd,capture_output=True,timeout=240)
        if run.returncode:raise RuntimeError('demo package static check failed')
        r=json.loads(result.read_text(encoding='utf-8'))
        if r.get('hostInputSent') is not False or r.get('confirmedChineseInMemory')!=dict.fromkeys(('variable','full','shorthand'),'你'):
            raise ValueError('complete dictionary in-memory confirmation missing')
        # A modified child must be rejected before any TSF/window is launched.
        (copy/HOST).write_bytes(b'corrupt')
        bad=subprocess.run(cmd,cwd=cwd,capture_output=True,timeout=30)
        if bad.returncode==0:raise ValueError('corrupted native child accepted')
    report.parent.mkdir(parents=True,exist_ok=True)
    body=dict(scope='isolated-demo-package-static-and-in-memory-only',sourceCommit=m['sourceCommit'],
              manifestSHA256=digest(package/'manifest.json'),hostArchitecture=architecture,
              completeChineseResourcesVerified=True,modifiedHostRejected=True,
              nativeDemoStarted=False,physicalAcceptance=False,installedProductAcceptance=False)
    with report.open('x',encoding='utf-8') as f:json.dump(body,f,ensure_ascii=False,indent=2)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    a=p.parse_args();check(a.package,a.report)
