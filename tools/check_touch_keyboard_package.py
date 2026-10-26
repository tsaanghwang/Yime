"""Validate a relocated portable package without OS input or source fallback."""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess
import tempfile

from touch_keyboard_resources import digest
from yimecore.collect_arm64_host import get_machine_architecture, read_pe_machine


PE_MACHINES = {'windows-amd64': 0x8664, 'windows-arm64': 0xaa64}
NATIVE_NAMES = {'windows-amd64': 'x64', 'windows-arm64': 'arm64'}


def validate_execution_architecture(package, manifest):
    """Permit only a native package; environment architecture labels are not proof."""
    architecture = manifest.get('architecture')
    if architecture not in PE_MACHINES:
        raise ValueError('Unsupported Windows package architecture: '+str(architecture))
    host = get_machine_architecture()
    if (host.get('source') != 'IsWow64Process2'
        or host.get('native_architecture') != NATIVE_NAMES[architecture]
        or host.get('native_machine') != f'0x{PE_MACHINES[architecture]:04x}'):
        raise ValueError('Package architecture does not match the verified native Windows host')
    pe = read_pe_machine(package/'YimeTouchKeyboard.exe')
    if pe['machine'] != f'0x{PE_MACHINES[architecture]:04x}' or pe['architecture'] != NATIVE_NAMES[architecture]:
        raise ValueError('Executable PE architecture does not match the package manifest')
    return host, pe['machine']


def require_new_output(path):
    if path.exists() or path.is_symlink():
        raise FileExistsError('Do not overwrite earlier evidence: '+str(path))


def check(package, report_path, render=False, native_edit=False):
    package = package.resolve()
    report_path = report_path.absolute()
    require_new_output(report_path)
    if report_path.resolve().is_relative_to(package):
        raise ValueError('Write execution evidence outside the original package')
    if render:
        require_new_output(report_path.parent/'portable-preview.png')
    if native_edit:
        require_new_output(report_path.parent/'portable-native-edit.log')
    manifest = json.loads((package/'manifest.json').read_text(encoding='utf-8'))
    if manifest['scope'] != 'uninstalled-desktop-touch-keyboard-chinese-experiment' or not manifest['completeChineseResources']:
        raise ValueError('Expected complete Chinese package')
    for name, expected in manifest['files'].items():
        path = (package/name).resolve()
        if not path.is_relative_to(package) or digest(path) != expected:
            raise ValueError('Package inventory hash mismatch: '+name)
    if digest(package/'resources.json') != manifest['portableResourcesSHA256']:
        raise ValueError('Resource inventory identity mismatch')
    host_architecture, executable_machine = validate_execution_architecture(package, manifest)
    with tempfile.TemporaryDirectory(prefix='Yime portable 中文 ') as tmp:
        temp = Path(tmp)
        relocated = temp/'keyboard folder'
        shutil.copytree(package,relocated)
        cwd = temp/'empty cwd'; cwd.mkdir()
        exe = relocated/'YimeTouchKeyboard.exe'
        isolated_names = ('GOFLAGS','GOPATH','TEMP','TMP','LOCALAPPDATA','APPDATA')
        env = {k:v for k,v in os.environ.items() if not k.upper().startswith('YIME_') and k.upper() not in isolated_names}
        for name, child in [('TEMP','tmp'),('TMP','tmp'),('LOCALAPPDATA','local'),('APPDATA','roaming')]:
            path = temp/'state'/child
            path.mkdir(parents=True, exist_ok=True)
            env[name] = str(path)
        result_file = temp/'result.json'
        run = subprocess.run([str(exe),'--check-package','--data-report',str(result_file)],cwd=cwd,env=env,capture_output=True,timeout=240)
        if run.returncode:
            raise RuntimeError(run.stderr.decode('utf-8',errors='replace'))
        result = json.loads(result_file.read_text(encoding='utf-8'))
        if (result['confirmedChineseInMemory'] != dict.fromkeys(('variable','full','shorthand'),'你')
            or result['boardWidthU']!=18 or result['keyCount']!=100 or result['hostInputSent']):
            raise ValueError('Relocated package diagnostic did not confirm all modes/geometry')
        full_file=temp/'full-board-result.json'
        full_run=subprocess.run([str(exe),'--check-package','--numeric-zones','both','--data-report',str(full_file)],cwd=cwd,env=env,capture_output=True,timeout=240)
        if full_run.returncode:
            raise RuntimeError(full_run.stderr.decode('utf-8',errors='replace'))
        full=json.loads(full_file.read_text(encoding='utf-8'))
        if full['boardWidthU']!=24.75 or full['keyCount']!=134:
            raise ValueError('Explicit both geometry was overridden by the portable default')
        report_path.parent.mkdir(parents=True,exist_ok=True)
        if render:
            shot=temp/'portable-preview.png'
            rendered=subprocess.run([str(exe),'--preview','--screenshot',str(shot)],cwd=cwd,env=env,capture_output=True,timeout=240)
            if rendered.returncode or not shot.is_file():
                raise RuntimeError('Package rendering failed: '+rendered.stderr.decode('utf-8',errors='replace'))
            with (report_path.parent/'portable-preview.png').open('xb') as output:
                output.write(shot.read_bytes())
        if native_edit:
            native=subprocess.run([str(exe),'--host-input','--host-self-test'],cwd=cwd,env=env,capture_output=True,timeout=240)
            with (report_path.parent/'portable-native-edit.log').open('xb') as output:
                output.write(native.stdout+native.stderr)
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
              'hostArchitecture':host_architecture,
              'nativeExecution':{'architectureMatched':True,'executableMachine':executable_machine,
                                 'targetExecuted':True,'packageCheckPassed':True,
                                 'scope':'portable package diagnostics; no installed-product or physical-input acceptance'},
              'resourceArchiveSHA256':manifest['resourceArchiveSHA256'],
              'relocatedOutsideCheckout':True,'emptyWorkingDirectory':True,'runtime':result,
              'explicitBothGeometry':{'boardWidthU':full['boardWidthU'],'keyCount':full['keyCount']},
              'negativeChecks':checks,'hostInputSent':False,'hardwareAcceptance':False,
              'renderedPreview':render,'controlledOwnEDIT':native_edit,
              'arm64NativeAcceptance':False}
        if native_edit:
            body['hostInputSent']=True
            body['hostInputScope']='disposable own EDIT only; never physical acceptance'
    report_path.parent.mkdir(parents=True,exist_ok=True)
    with report_path.open('x',encoding='utf-8',newline='\n') as output:
        output.write(json.dumps(body,ensure_ascii=False,indent=2)+'\n')
    print('PASS relocated complete package, three modes and resource rejection checks: '+str(report_path))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--render',action='store_true',help='also render preview with package-private font, no input')
    parser.add_argument('--native-edit',action='store_true',help='explicit local-only check in disposable own EDIT controls')
    args=parser.parse_args()
    check(args.package,args.report,args.render,args.native_edit)
