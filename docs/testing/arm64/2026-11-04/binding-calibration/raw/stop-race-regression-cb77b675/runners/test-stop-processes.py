from pathlib import Path
import subprocess,sys,json
root=Path(__file__).resolve().parents[2]
out=root/'.generated/stop-process-race-regression'
out.mkdir(exist_ok=True)
edition=sys.argv[1]
log=out/(edition+'.log')
with log.open('wb') as stream:
    code=subprocess.run([sys.executable,'-B','-X','utf8',str(root/'.generated/armfull-tools/run_checked_local.py'),'--edition',edition,'--script','installer/simple/tests/Test-StopProductProcesses.ps1'],cwd=root,stdout=stream,stderr=subprocess.STDOUT).returncode
print(log.read_text(encoding='utf-8-sig',errors='replace'))
print(json.dumps({'edition':edition,'exitCode':code,'log':str(log)}))
raise SystemExit(code)
