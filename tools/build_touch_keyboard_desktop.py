"""Build an isolated, portable English desktop touch-keyboard experiment."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def build(output: Path,arch: str):
    output=output.resolve()
    # Disposable packages cannot be staged into either product's source/data.
    if not output.is_relative_to(ROOT/'.generated'):
        raise ValueError('Desktop trial packages must stay under this checkout .generated/')
    output.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,GOOS='windows',GOARCH=arch,CGO_ENABLED='0')
    exe=output/'YimeTouchKeyboard.exe'
    subprocess.run(['go','build','-trimpath','-ldflags=-H=windowsgui','-o',str(exe),'./cmd/yime-touch-keyboard'],cwd=ROOT/'go-backend',env=env,check=True)
    layout=Path('prototypes/touch-terminal/data/physical-layout.json')
    (output/layout).parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/layout,output/layout)
    profiles=Path('prototypes/touch-terminal/desktop/profiles');shutil.copytree(ROOT/profiles,output/profiles,dirs_exist_ok=True)
    for name,args in [('Start Keyboard.cmd',' --profile prototypes/touch-terminal/desktop/profiles/main-only.json'),('Start Full Keyboard.cmd',' --profile prototypes/touch-terminal/desktop/profiles/full-size.json'),('Start 17u Main Area.cmd',' --profile prototypes/touch-terminal/desktop/profiles/main-17u.json'),('Start 23u Keyboard.cmd',' --profile prototypes/touch-terminal/desktop/profiles/full-23u.json'),('Start Main Area.cmd',' --profile prototypes/touch-terminal/desktop/profiles/main-only.json'),('Start Left Area.cmd',' --numeric-zones left --remove-gutters'),('Start Right Area.cmd',' --numeric-zones right --remove-gutters')]:
        body='@echo off\r\nstart "" /d "%~dp0" "%~dp0YimeTouchKeyboard.exe" --root "%~dp0."'+args+'\r\n'
        (output/name).write_bytes(body.encode('ascii'))
    (output/'README.txt').write_text('''Yime desktop touch keyboard - 18u development baseline / English milestone

Double-click Start Keyboard.cmd (same 18u profile as Start Main Area.cmd).
The main area is 342.90mm wide at 19.05mm/u, with 100 keys and no side zones.
Start Full Keyboard.cmd preserves the original 24.75u / 134-key full board.
Left/Right Area launchers retain one numeric zone (21u).
Start 17u Main Area.cmd and Start 23u Keyboard.cmd are frozen optional candidates,
not the active development or physical-acceptance baseline.
No 1mm pitch/width reduction is implemented.

Click a target application text field, then touch/type on the keyboard.
Ctrl+Alt+K hides/shows it. The top strip can move the window.
Read USER_GUIDE.zh-CN.md for Chinese instructions.

1u = 19.05mm. Default monitor width 597.73mm is a 27-inch 16:9 estimate.
Measure the 100mm ruler; use Ruler +/-1% only to correct pixels per millimetre.
Calibration never changes the key-unit geometry and is session-local.
For an exact observed ruler length, relaunch with --ruler-observed-mm VALUE.
Keys do not automatically shrink to fit the screen.

This milestone sends English literal characters and editing/shortcut keys.
Chinese composition, Caps Lock, Windows/Menu and Pause are not connected.
Disabled keys are gray. Installed products and default input-method selection
are unchanged. Physical finger/pen acceptance preparation is deferred;
mouse/simulated-touch/controlled EDIT results are development evidence only.

Developer data check: --check-data --data-dir <isolated-complete-dictionaries>
--data-report <report.json> validates the shared Chinese session runtime without
opening a window or sending input. This English package does not bundle those
dictionaries. Desktop Chinese composition/candidate UI remains pending.
''',encoding='utf-8')
    shutil.copyfile(ROOT/'prototypes/touch-terminal/desktop/USER_GUIDE.zh-CN.md',output/'USER_GUIDE.zh-CN.md')
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,encoding='utf-8').strip()
    manifest={'schemaVersion':1,'scope':'uninstalled-desktop-touch-keyboard-english-experiment','architecture':'windows-'+arch,'goVersion':subprocess.check_output(['go','version'],cwd=ROOT,text=True,encoding='utf-8').strip(),'sourceCommit':head,'sourceTrackedChanges':bool(subprocess.check_output(['git','status','--porcelain','-uno'],cwd=ROOT,text=True,encoding='utf-8').strip()),'unitMM':19.05,'defaultLauncher':'Start Keyboard.cmd','defaultProfile':'prototypes/touch-terminal/desktop/profiles/main-only.json','developmentBaseline':'main-18u','mainWidthU':18,'mainWidthMM':18*19.05,'fullWidthMM':24.75*19.05,'main17WidthMM':17*19.05,'main17Status':'frozen-optional-candidate','full23Status':'frozen-optional-candidate','physicalAcceptancePreparation':'deferred','calibration':'27-inch-16:9-estimate-ruler-required','installedProductAcceptance':False,'hardwareAcceptance':False,'files':{str(p.relative_to(output)).replace('\\','/'):digest(p) for p in output.rglob('*') if p.is_file() and p.name!='manifest.json'}}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8');print(output);print('Executable SHA-256:',digest(exe))
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-dir',type=Path,default=ROOT/'.generated/touch-keyboard-desktop');parser.add_argument('--arch',choices=['amd64','arm64'],default='amd64');args=parser.parse_args();build(args.output_dir,args.arch)
