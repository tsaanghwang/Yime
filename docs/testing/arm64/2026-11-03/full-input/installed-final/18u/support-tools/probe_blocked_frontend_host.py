"""Start the exact test host blocked before its JSON config; no TSF/UI/input."""
import ctypes as c
import datetime
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time

root=Path(__file__).absolute().parents[2]
spec=importlib.util.spec_from_file_location('controller',Path(__file__).with_name('run_installed_frontend_checkpoints.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

def child():
    q=json.loads(sys.stdin.readline())
    if m.digest(q['exe'])!=q['sha256']:raise ValueError('host hash changed')
    with open(q['stdout'],'wb') as output,open(q['stderr'],'wb') as error:
        p=subprocess.Popen([q['exe']],cwd=q['cwd'],stdin=subprocess.PIPE,stdout=output,stderr=error,creationflags=subprocess.CREATE_NO_WINDOW)
        print(json.dumps(m.observe(p.pid)),flush=True)
        # No bytes, not even a newline/EOF, reach the native stdin. Source main
        # blocks in input() before Host.initialize or GUI.start. Parent kills
        # only this Job after observing all its members.
        sys.stdin.readline()
        raise RuntimeError('diagnostic gate unexpectedly released')

def main():
    cfg=json.loads((root/'.generated/touch-full-tools/frontend-checkpoints-config-final-46dd.template.json').read_text())
    exe=Path(cfg['hostExe'])
    if m.digest(exe)!=cfg['hostSHA256']:raise ValueError('fixed host hash mismatch')
    own=m.observe(os.getpid());m.same_token(own,own['token'])
    output=root/'.generated/18u-host-diagnostics/blocked-host-start';output.mkdir(exist_ok=False)
    job=m.check(m.create_job(None,None));limits=m.Limits();limits.basic.flags=0x2000
    m.check(m.set_job(job,9,c.byref(limits),c.sizeof(limits)))
    result={'schema':'18u-no-input-host-spawn-probe-v1','observedUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'controller':own,'sysExecutable':sys.executable,'hostExe':str(exe),'hostSHA256':cfg['hostSHA256'],
        'launcherFlags':subprocess.CREATE_NO_WINDOW,'hostFlags':subprocess.CREATE_NO_WINDOW,
        'nativeConfigBytesSent':0,'inputReplayed':False,'registeredHostInitializationRequested':False,
        'productRuntimeChanged':False,'observedMembers':[],'observationErrors':[]}
    p=subprocess.Popen([sys.executable,str(Path(__file__).absolute()),'--child'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8',creationflags=subprocess.CREATE_NO_WINDOW)
    result['launcherPID']=p.pid
    try:
        m.check(m.assign_job(job,m.w.HANDLE(int(p._handle))))
        request={'exe':str(exe),'sha256':cfg['hostSHA256'],'cwd':cfg['installRoot'],'stdout':str(output/'host.stdout.log'),'stderr':str(output/'host.stderr.log')}
        p.stdin.write(json.dumps(request)+'\n');p.stdin.flush()
        result['nativeHost']=json.loads(m.line_deadline(p.stdout,15))
        seen={};deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            for pid in m.job_processes(job):
                try:observed=m.observe(pid)
                except OSError as error:result['observationErrors'].append({'pid':pid,'error':str(error)});continue
                seen[(pid,observed['creationTicks'])]=observed
            result['observedMembers']=list(seen.values())
            (output/'observations.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
            if p.poll() is not None:raise RuntimeError('blocked native host launcher exited')
            time.sleep(.05)
    except BaseException as error:
        result['error']=str(error);raise
    finally:
        m.check(m.terminate_job(job,8));deadline=time.monotonic()+10
        while m.job_processes(job):
            if time.monotonic()>=deadline:raise TimeoutError('diagnostic Job did not empty')
            time.sleep(.05)
        result['jobEmptyBeforeClose']=True;m.close(job);p.wait(timeout=10)
        result['launcherStderr']=p.stderr.read()
        (output/'receipt.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))

if __name__=='__main__':
    if sys.argv[1:]==['--child']:child()
    else:main()
