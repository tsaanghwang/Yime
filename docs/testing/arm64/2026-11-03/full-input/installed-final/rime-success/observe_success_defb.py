"""Read existing Rime processes only; never run a product, probe, UI or controller.run."""
import ctypes as c
from ctypes import wintypes as w
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import struct

repo=Path(__file__).resolve().parents[2]
evidence=repo/'.generated/complete-input-install/final-defbf9f8-rime'
out=repo/'.generated/rime-live-preparation/final-defbf9f8-success'
out.mkdir(exist_ok=False)
controller=repo/'.generated/touch-full-tools/run_installed_frontend_checkpoints.py'
spec=importlib.util.spec_from_file_location('readonly_process_utilities',controller)
observe_module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(observe_module)
K=observe_module.K
api=observe_module.api
close=observe_module.close
check=observe_module.check

class ProcessEntry(c.Structure):
    _fields_=[('dwSize',w.DWORD),('cntUsage',w.DWORD),('pid',w.DWORD),('heap',c.c_size_t),
              ('module',w.DWORD),('threads',w.DWORD),('parentPID',w.DWORD),
              ('priority',w.LONG),('flags',w.DWORD),('name',w.WCHAR*260)]
snapshot=api(K,'CreateToolhelp32Snapshot',w.HANDLE,w.DWORD,w.DWORD)
first=api(K,'Process32FirstW',w.BOOL,w.HANDLE,c.POINTER(ProcessEntry))
next_entry=api(K,'Process32NextW',w.BOOL,w.HANDLE,c.POINTER(ProcessEntry))

def ticks(text):
    match=re.fullmatch(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,7}))?Z',text)
    if not match:raise ValueError('unexpected snapshot time')
    date=dt.datetime.strptime(match[1],'%Y-%m-%dT%H:%M:%S')
    delta=date-dt.datetime(1601,1,1)
    return (delta.days*86400+delta.seconds)*10000000+int((match[2] or '').ljust(7,'0'))

after=json.loads((evidence/'after.json').read_text(encoding='utf-8-sig'))
installed=next(p for p in after['products'] if p['id']=='rime-pime')
result=json.loads((evidence/'setup-result.json').read_text(encoding='utf-8'))
if result['exitCode']!=0 or result['source']!='defbf9f805b52146bd79048620058f48c6c29f23':
    raise ValueError('expected successful exact-source installation')
root=Path(installed['root'])
package=Path(result['package'])
manifest=json.loads((package/'product-package.json').read_text(encoding='utf-8-sig'))
files={row['path']:row for row in manifest['files']}
setup_output=(evidence/'setup-output.log').read_text(encoding='utf-8')
match=re.search(r'Started installed rime-pime runtime as the original non-administrator account; pid=(\d+)\.',setup_output)
if not match:raise ValueError('missing ordinary runtime launch receipt')
watchdog=int(match[1])
own=observe_module.observe(os.getpid())
observe_module.same_token(own,own['token'])
raw_snapshot=snapshot(2,0)
if raw_snapshot==c.c_void_p(-1).value:raise c.WinError(c.get_last_error())
entries={}
try:
    entry=ProcessEntry();entry.dwSize=c.sizeof(entry)
    ok=first(raw_snapshot,c.byref(entry))
    while ok:
        entries[int(entry.pid)]={'parentPID':int(entry.parentPID),'baseName':entry.name}
        ok=next_entry(raw_snapshot,c.byref(entry))
finally:close(raw_snapshot)

expected={row['pid']:row for row in installed['processes']}
candidate_pids=set(expected)
for pid,entry in entries.items():
    if entry['baseName'].lower() in ('pimelauncher.exe','server.exe'):
        try:
            seen=observe_module.observe(pid)
            if Path(seen['image']).is_relative_to(root):candidate_pids.add(pid)
        except OSError:
            if pid in expected:raise

held=[]
rows=[]
try:
    for pid in sorted(candidate_pids):
        handle=check(observe_module.open_process(0x1000|0x100000,False,pid));held.append(handle)
        if observe_module.wait_process(handle,0)!=258:raise ValueError('recorded process exited')
        row=observe_module.observe(pid,handle)
        observe_module.same_token(row,own['token'])
        image=Path(row['image'])
        relative=image.relative_to(root).as_posix()
        if relative not in ('PIMELauncher.exe','go-backend/server.exe'):raise ValueError('unexpected owned runtime')
        record=files[relative]
        data=image.read_bytes()
        sha=hashlib.sha256(data).hexdigest()
        if sha!=record['sha256'] or len(data)!=record['bytes']:raise ValueError('running image path differs from final package')
        machine=struct.unpack_from('<H',data,struct.unpack_from('<I',data,60)[0]+4)[0]
        process,native=w.USHORT(),w.USHORT()
        check(observe_module.is_wow(handle,c.byref(process),c.byref(native)))
        if machine!=0xaa64 or process.value!=0 or native.value!=0xaa64:raise ValueError('runtime is not native ARM64')
        if pid in expected:
            if image!=Path(expected[pid]['path']) or row['creationTicks']!=ticks(expected[pid]['startUtc']):
                raise ValueError('snapshot PID identity changed')
        row.update({'relative':relative,'parentPID':entries[pid]['parentPID'],'imageSHA256':sha,
                    'imageBytes':len(data),'peMachine':hex(machine),'processMachine':hex(process.value),
                    'nativeMachine':hex(native.value),'nativeARM64':True,'matchesFinalPackage':True,
                    'matchesAfterSnapshot':pid in expected,'sameOrdinaryUserSessionLogon':True})
        if pid==watchdog:row['role']='launcher started by ordinary installation parent'
        elif relative=='PIMELauncher.exe' and row['parentPID']==watchdog:
            row['role']='direct Launcher child, worker role inferred from PIMELauncher/src/main.rs:18-27'
        else:row['role']='lazy backend' if relative=='go-backend/server.exe' else 'other owned Launcher'
        rows.append(row)
    if watchdog not in expected or not any(r['pid']==watchdog for r in rows):raise ValueError('ordinary launch PID is not live')
    workers=[r['pid'] for r in rows if r['relative']=='PIMELauncher.exe' and r['parentPID']==watchdog]
    if len(workers)!=1:raise ValueError('expected one directly derived Launcher worker')
    if any(observe_module.wait_process(h,0)!=258 for h in held):raise ValueError('process exited during observation')
    backend=[r['pid'] for r in rows if r['relative']=='go-backend/server.exe']
    report={'schema':'yime-rime-installed-live-process-identity-v1',
            'capturedAtUTC':dt.datetime.now(dt.timezone.utc).isoformat(),'sourceCommit':result['source'],
            'installRoot':str(root),'packageRoot':str(package),'archiveSHA256':result['archiveSHA256'],
            'afterSnapshot':str(evidence/'after.json'),'afterSnapshotSHA256':hashlib.sha256((evidence/'after.json').read_bytes()).hexdigest(),
            'processUtility':{'path':str(controller),'sha256':hashlib.sha256(controller.read_bytes()).hexdigest(),
                              'calledFunctions':['observe','same_token','read-only Win32 process/token queries'],'controllerRunCalled':False},
            'observer':own,'watchdogPID':watchdog,'workerPIDs':workers,'backendPIDs':backend,
            'backendNote':'Backend is lazy; absence before profile activation is not a failure.',
            'processes':rows,'passed':True,'scope':{'readOnly':True,'registrationProbeRepeated':False,
            'processStartedOrStopped':False,'profileActivated':False,'documentInputExecuted':False,'physicalAcceptance':False}}
    (out/'live-process-identity.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))
finally:
    for handle in held:close(handle)
