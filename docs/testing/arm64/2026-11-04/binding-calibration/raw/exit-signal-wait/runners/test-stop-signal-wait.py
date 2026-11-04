from pathlib import Path
import subprocess,sys,json
root=Path(__file__).resolve().parents[2]
out=root/'.generated/stop-process-signal-wait-regression'
out.mkdir(exist_ok=True)
edition=sys.argv[1]
if edition=='before-after':
    git=r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe'
    original=subprocess.run([git,'show','cb77b675ff6964c7b069294222200a5060316bd2:installer/simple/Setup.ps1'],cwd=root,capture_output=True,check=True).stdout
    p=root/'.generated/exit-signal-contract/source-snapshots/Setup-cb77-before.ps1';p.parent.mkdir(exist_ok=True);p.write_bytes(original)
    script='.generated/armfull-tools/test-stop-signal-before-after.ps1';selected='ps7'
else:script='installer/simple/tests/Test-StopProductProcesses.ps1';selected=edition
with (out/(edition+'.log')).open('wb') as log:
    code=subprocess.run([sys.executable,'-B','-X','utf8',str(root/'.generated/armfull-tools/run_checked_local.py'),'--edition',selected,'--script',script],cwd=root,stdout=log,stderr=subprocess.STDOUT).returncode
print((out/(edition+'.log')).read_text(encoding='utf-8-sig',errors='replace'))
print(json.dumps({'case':edition,'exitCode':code,'productTouched':False}))
raise SystemExit(code)
