"""One process-scoped activation in an owned empty TSF host; no product maintenance."""
from pathlib import Path
import ctypes as c
from ctypes import wintypes as w
import datetime, hashlib, importlib.util, json, os, subprocess

root=Path(__file__).resolve().parents[2]
out=root/'.generated/18u-cold-load-20261104/activation-once'
out.mkdir(exist_ok=False)
spec=importlib.util.spec_from_file_location('read_identity',root/'.generated/touch-full-tools/run_installed_frontend_checkpoints.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
install=Path(r'C:\Program Files\YimeCore 18u Touch')
dll=install/'arm64/YimeTextService18u.dll'
exe=root/'.generated/18u-cold-load-20261104/build/Release/YimeTouchRegisteredFormalHostTests.exe'
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
class Entry(c.Structure):
    _fields_=[('size',w.DWORD),('usage',w.DWORD),('pid',w.DWORD),('heap',c.c_size_t),('module',w.DWORD),('threads',w.DWORD),('parent',w.DWORD),('priority',w.LONG),('flags',w.DWORD),('name',w.WCHAR*260)]
snapshot=m.api(m.K,'CreateToolhelp32Snapshot',w.HANDLE,w.DWORD,w.DWORD)
first=m.api(m.K,'Process32FirstW',w.BOOL,w.HANDLE,c.POINTER(Entry))
next_=m.api(m.K,'Process32NextW',w.BOOL,w.HANDLE,c.POINTER(Entry))
def protected_processes():
    h=snapshot(2,0)
    if h==c.c_void_p(-1).value:raise c.WinError(c.get_last_error())
    rows=[]
    try:
        e=Entry();e.size=c.sizeof(e);ok=first(h,c.byref(e))
        while ok:
            if e.name.lower() in ('notepad.exe','yime18uinstalledruntime.exe','yimebroker18u.exe','yimetouchkeyboard.exe'):
                rows.append(dict(name=e.name,parentPID=e.parent,**m.observe(e.pid)))
            ok=next_(h,c.byref(e))
        if c.get_last_error()!=18:raise c.WinError(c.get_last_error())
    finally:m.close(h)
    return sorted(rows,key=lambda x:x['pid'])
report=dict(schema='18u-single-cold-activation-v1',startedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),registrationMutation=False,textInputRequested=False,newBrokerOrFrontend=False,otherProcessesStopped=False)
try:
    report['observer']=m.observe(os.getpid())
    assert report['observer']['token']['elevated']==0 and report['observer']['token']['integrity']==8192,report['observer']
    manifest=json.loads((install/'installed-18u-product.json').read_text(encoding='utf-8-sig'))
    assert manifest['sourceCommit']=='46dd58967266edcab3f0d3bb131015d81dc4b951'
    row=next(x for x in manifest['files'] if x['path']=='arm64/YimeTextService18u.dll')
    assert row['sha256']==digest(dll)=='83bd48bf38fa9653ad87ee75112e5d1f467f549ca87d99ccdd4ce55a1a179b8a'
    report['installedDLL']=dict(path=str(dll),sha256=digest(dll),bytes=dll.stat().st_size)
    report['installedManifestSHA256']=digest(install/'installed-18u-product.json')
    report['testHost']=dict(path=str(exe),sha256=digest(exe),bytes=exe.stat().st_size)
    report['before']=protected_processes()
    data=(json.dumps(dict(scenario='activation-only',dll=str(dll)))+'\n').encode()
    (out/'input.json').write_bytes(data)
    with (out/'stdout.jsonl').open('wb') as stdout,(out/'stderr.jsonl').open('wb') as stderr:
        process=subprocess.Popen([str(exe)],cwd=root,stdin=subprocess.PIPE,stdout=stdout,stderr=stderr)
        report['testPID']=process.pid
        try:
            process.communicate(data,timeout=25)
            report['exitCode']=process.returncode
        except subprocess.TimeoutExpired:
            process.kill();process.communicate();report['ownHostKilledAfterTimeout']=True;report['exitCode']=process.returncode
        report['testProcessExited']=process.poll() is not None
    report['after']=protected_processes()
    report['protectedProcessesUnchanged']=report['before']==report['after']
    report['installedDLLUnchanged']=digest(dll)==report['installedDLL']['sha256']
    report['stdout']=(out/'stdout.jsonl').read_text(encoding='utf-8',errors='replace')
    report['stderr']=(out/'stderr.jsonl').read_text(encoding='utf-8',errors='replace')
except Exception as e:
    report['observerError']=repr(e)
finally:
    report['finishedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    (out/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))
