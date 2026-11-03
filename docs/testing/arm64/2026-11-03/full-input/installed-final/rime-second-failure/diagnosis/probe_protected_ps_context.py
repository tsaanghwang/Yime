"""Only launch the read-only PS test through the standard checked entry."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
parser=argparse.ArgumentParser()
parser.add_argument('--label', choices=('administrator',), required=True)
parser.parse_args()
repo=Path(__file__).resolve().parents[2]
out=repo/'.generated/rime-live-preparation/second-failure'
for name in ('administrator-protected-ps.json','administrator-protected-ps.stdout.txt','administrator-protected-ps.stderr.txt'):
    if (out/name).exists(): raise ValueError('preserve previous observation')
stage=Path('C:/Program Files/Yime Maintenance/rime-pime/cb5bdf84f792130086fc86de41248c739dc94acfa089331183ee3137ab3c2dbd')
for arch in ('x86','arm64'):
    rel=arch+'/PIMERegistrationStatus.exe'
    if (Path('C:/Program Files/Yime Rime-PIME')/rel).read_bytes()!=(repo/'.generated/rime-final-46dd5896/package/payload'/rel).read_bytes():
        raise ValueError('exact installed probe mismatch')
system=Path(os.environ['SystemRoot'])
env={key:os.environ[key] for key in ('SystemRoot','ProgramFiles','USERPROFILE','LOCALAPPDATA','APPDATA')}
env.update({'WINDIR':str(system),'PATH':str(system/'System32'),'PATHEXT':'.EXE',
    'TEMP':str(system/'Temp'),'TMP':str(system/'Temp'),
    'PSModulePath':str(stage/'maintenance/powershell/Modules')+';'+str(system/'System32/WindowsPowerShell/v1.0/Modules')})
params=out/'administrator-protected-ps-params.json'
with params.open('x',encoding='utf-8') as f: json.dump({'Report':str(out/'administrator-protected-ps.json')},f)
command=[sys.executable,'-B','-X','utf8',str(Path(__file__).with_name('run_checked_protected.py')),
    '--edition','ps7','--script',str(Path(__file__).with_suffix('.ps1')),'--params-file',str(params)]
result=subprocess.run(command,cwd=stage,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
for name,text in (('administrator-protected-ps.stdout.txt',result.stdout),('administrator-protected-ps.stderr.txt',result.stderr)):
    with (out/name).open('x',encoding='utf-8',newline='\n') as f:f.write(text)
print(result.stdout+result.stderr)
raise SystemExit(result.returncode)
