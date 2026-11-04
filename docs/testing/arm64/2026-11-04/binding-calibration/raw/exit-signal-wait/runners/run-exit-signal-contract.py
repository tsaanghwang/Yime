from pathlib import Path
import datetime,hashlib,json,subprocess
root=Path(__file__).resolve().parents[2]
out=root/'.generated/exit-signal-contract'
cmake=Path(r'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe')
results=[]
for name,command in [
 ('configure',[cmake,'-S',out/'source','-B',out/'native','-G','Visual Studio 17 2022','-A','ARM64']),
 ('compile',[cmake,'--build',out/'native','--config','Release','--parallel','2']),
 ('native-observation',[out/'native/Release/ExitSignalProbe.exe'])]:
    result=subprocess.run([str(x) for x in command],cwd=root,capture_output=True,timeout=120)
    (out/(name+'.stdout.log')).write_bytes(result.stdout);(out/(name+'.stderr.log')).write_bytes(result.stderr)
    results.append({'stage':name,'command':[str(x) for x in command],'exitCode':result.returncode})
    print(name,result.returncode,flush=True)
    if result.returncode:raise SystemExit(result.returncode)
rows=[]
for p in [*sorted((out/'source').iterdir()),*sorted((out/'native/Release').glob('*.exe')),*sorted((out/'native/Release').glob('*.dll'))]:
    rows.append({'path':str(p.relative_to(root)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
receipt={'schema':'private-exit-signal-build-observation-v1','observedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'results':results,'files':rows,'productTouched':False,'registrationOrInstallation':False}
(out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
print((out/'native-observation.stdout.log').read_text(encoding='utf-8'))
