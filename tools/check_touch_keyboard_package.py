"""Validate a relocated portable package without OS input or source fallback."""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess
import tempfile

from touch_keyboard_resources import digest


def check(package, report_path, render=False, native_edit=False):
    package = package.resolve()
    manifest = json.loads((package/'manifest.json').read_text(encoding='utf-8'))
    if manifest['scope'] != 'uninstalled-desktop-touch-keyboard-chinese-experiment' or not manifest['completeChineseResources']:
        raise ValueError('Expected complete Chinese package')
    for name, expected in manifest['files'].items():
        path = (package/name).resolve()
        if not path.is_relative_to(package) or digest(path) != expected:
            raise ValueError('Package inventory hash mismatch: '+name)
    if digest(package/'resources.json') != manifest['portableResourcesSHA256']:
        raise ValueError('Resource inventory identity mismatch')
    if manifest['architecture'] != 'windows-amd64':
        raise ValueError('This execution check requires the x64 Windows package; ARM64 is cross-build only')
    with tempfile.TemporaryDirectory(prefix='Yime portable 中文 ') as tmp:
        temp = Path(tmp)
        relocated = temp/'keyboard folder'
        shutil.copytree(package,relocated)
        cwd = temp/'empty cwd'; cwd.mkdir()
        exe = relocated/'YimeTouchKeyboard.exe'
        env = {k:v for k,v in os.environ.items() if not k.startswith('YIME_') and k not in ('GOFLAGS','GOPATH')}
        result_file = temp/'result.json'
        run = subprocess.run([str(exe),'--check-package','--data-report',str(result_file)],cwd=cwd,env=env,capture_output=True,timeout=240)
        if run.returncode:
            raise RuntimeError(run.stderr.decode('utf-8',errors='replace'))
        result = json.loads(result_file.read_text(encoding='utf-8'))
        if (result['confirmedChineseInMemory'] != dict.fromkeys(('variable','full','shorthand'),'你')
            or result['boardWidthU']!=18 or result['keyCount']!=100 or result['hostInputSent']):
            raise ValueError('Relocated package diagnostic did not confirm all modes/geometry')
        report_path.parent.mkdir(parents=True,exist_ok=True)
        if render:
            shot=temp/'portable-preview.png'
            rendered=subprocess.run([str(exe),'--preview','--screenshot',str(shot)],cwd=cwd,env=env,capture_output=True,timeout=240)
            if rendered.returncode or not shot.is_file():
                raise RuntimeError('Package rendering failed: '+rendered.stderr.decode('utf-8',errors='replace'))
            shutil.copyfile(shot,report_path.parent/'portable-preview.png')
        if native_edit:
            native=subprocess.run([str(exe),'--host-input','--host-self-test'],cwd=cwd,env=env,capture_output=True,timeout=240)
            (report_path.parent/'portable-native-edit.log').write_bytes(native.stdout+native.stderr)
            if native.returncode:
                raise RuntimeError('Package own EDIT check failed: '+native.stderr.decode('utf-8',errors='replace'))
        checks=[]
        # Corruption/missing files must fail before opening a UI or sending input.
        for name in ['resources.json','go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf',
                     'prototypes/touch-terminal/data/physical-layout.json','data/ascii_keyboard_manifest.json','data/yime_variable.dict.yaml']:
            path=relocated/name
            original=path.read_bytes()
            try:
                path.write_bytes(b'corrupt')
                bad=subprocess.run([str(exe),'--check-package'],cwd=cwd,env=env,capture_output=True,timeout=30)
                if bad.returncode==0: raise ValueError('Corrupt resource accepted: '+name)
                checks.append({'resource':name,'exitCode':bad.returncode,'error':bad.stderr.decode('utf-8',errors='replace').strip()})
            finally:
                path.write_bytes(original)
        font=relocated/'go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf'
        original=font.read_bytes(); font.unlink()
        try:
            bad=subprocess.run([str(exe),'--check-package'],cwd=cwd,env=env,capture_output=True,timeout=30)
            if bad.returncode==0: raise ValueError('Missing font accepted')
            checks.append({'resource':'missing font','exitCode':bad.returncode})
        finally:
            font.write_bytes(original)
        for flag in ['--root','--data-dir']:
            bad=subprocess.run([str(exe),'--check-package',flag,str(cwd)],cwd=cwd,env=env,capture_output=True,timeout=30)
            if bad.returncode==0: raise ValueError('External resources accepted: '+flag)
            checks.append({'option':flag,'exitCode':bad.returncode})
        body={'scope':'relocated-complete-portable-package','sourceCommit':manifest['sourceCommit'],
              'ci':manifest.get('ci'),
              'sourceChanges':manifest['sourceChanges'],'executableSHA256':digest(exe),
              'manifestSHA256':digest(package/'manifest.json'),'architecture':manifest['architecture'],
              'resourceArchiveSHA256':manifest['resourceArchiveSHA256'],
              'relocatedOutsideCheckout':True,'emptyWorkingDirectory':True,'runtime':result,
              'negativeChecks':checks,'hostInputSent':False,'hardwareAcceptance':False,
              'renderedPreview':render,'controlledOwnEDIT':native_edit,
              'arm64NativeAcceptance':False}
        if native_edit:
            body['hostInputSent']=True
            body['hostInputScope']='disposable own EDIT only; never physical acceptance'
    report_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.write_text(json.dumps(body,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('PASS relocated complete package, three modes and resource rejection checks: '+str(report_path))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--render',action='store_true',help='also render preview with package-private font, no input')
    parser.add_argument('--native-edit',action='store_true',help='explicit local-only check in disposable own EDIT controls')
    args=parser.parse_args()
    check(args.package,args.report,args.render,args.native_edit)
