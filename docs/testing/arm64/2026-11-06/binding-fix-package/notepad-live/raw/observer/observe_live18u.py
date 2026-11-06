import json, os, subprocess, sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
out=root/'.generated/notepad-5-live-20261106'
out.mkdir(exist_ok=True)
label=sys.argv[1]
assert label.replace('-','').isalnum()
params=out/(label+'-params.json')
report=out/(label+'.json')
log=out/(label+'.log')
assert not any(p.exists() for p in (params,report,log))
params.write_text(json.dumps({'Report':str(report)}),encoding='utf-8')
env=os.environ.copy()
env['PATH']='C:/dev/Yime/.wt/armfull/.generated/arm64-maintenance-shell/powershell;'+env['PATH']
cmd=[sys.executable,'-B','-X','utf8',str(root/'tools/powershell/run_checked.py'),'--edition','ps7','--script',str(root/'.generated/observe-live18u.ps1'),'--params-file',str(params)]
r=subprocess.run(cmd,cwd=root,env=env,capture_output=True)
log.write_bytes(r.stdout+r.stderr)
print(r.stdout.decode('utf-8',errors='replace'))
if r.returncode: print(r.stderr.decode('utf-8',errors='replace'))
sys.exit(r.returncode)
