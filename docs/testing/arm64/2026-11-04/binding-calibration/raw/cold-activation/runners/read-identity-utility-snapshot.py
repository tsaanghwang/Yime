"""One ordinary-user 18u registered frontend test; never install or register.

The configuration is an independent hash/PID/creation-time anchor made by the
installation controller. Validate it before --run. This script is not acceptance
evidence until the registered host returns all 18 actual TSF readbacks.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import stat
import subprocess
import sys
import threading
import time

K = c.WinDLL('kernel32', use_last_error=True)
A = c.WinDLL('advapi32', use_last_error=True)
def api(dll, name, result, *args):
    f = getattr(dll, name); f.restype = result; f.argtypes = args; return f
close = api(K, 'CloseHandle', w.BOOL, w.HANDLE)
open_process = api(K, 'OpenProcess', w.HANDLE, w.DWORD, w.BOOL, w.DWORD)
wait_process = api(K, 'WaitForSingleObject', w.DWORD, w.HANDLE, w.DWORD)
query_image = api(K, 'QueryFullProcessImageNameW', w.BOOL, w.HANDLE, w.DWORD, w.LPWSTR, c.POINTER(w.DWORD))
get_times = api(K, 'GetProcessTimes', w.BOOL, w.HANDLE, c.POINTER(w.FILETIME), c.POINTER(w.FILETIME), c.POINTER(w.FILETIME), c.POINTER(w.FILETIME))
open_token = api(A, 'OpenProcessToken', w.BOOL, w.HANDLE, w.DWORD, c.POINTER(w.HANDLE))
token_info = api(A, 'GetTokenInformation', w.BOOL, w.HANDLE, c.c_int, c.c_void_p, w.DWORD, c.POINTER(w.DWORD))
sid_string = api(A, 'ConvertSidToStringSidW', w.BOOL, c.c_void_p, c.POINTER(w.LPWSTR))
free = api(K, 'LocalFree', w.HANDLE, w.HANDLE)
create_job = api(K, 'CreateJobObjectW', w.HANDLE, c.c_void_p, w.LPCWSTR)
set_job = api(K, 'SetInformationJobObject', w.BOOL, w.HANDLE, c.c_int, c.c_void_p, w.DWORD)
assign_job = api(K, 'AssignProcessToJobObject', w.BOOL, w.HANDLE, w.HANDLE)
query_job = api(K, 'QueryInformationJobObject', w.BOOL, w.HANDLE, c.c_int, c.c_void_p, w.DWORD, c.POINTER(w.DWORD))
terminate_job = api(K, 'TerminateJobObject', w.BOOL, w.HANDLE, w.UINT)
is_wow = api(K, 'IsWow64Process2', w.BOOL, w.HANDLE, c.POINTER(w.USHORT), c.POINTER(w.USHORT))

class Basic(c.Structure):
    _fields_ = [('processTime', c.c_int64), ('jobTime', c.c_int64), ('flags', w.DWORD), ('minWork', c.c_size_t), ('maxWork', c.c_size_t), ('activeLimit', w.DWORD), ('affinity', c.c_size_t), ('priority', w.DWORD), ('schedule', w.DWORD)]
class IO(c.Structure):
    _fields_ = [(name, c.c_uint64) for name in ('readOps', 'writeOps', 'otherOps', 'readBytes', 'writeBytes', 'otherBytes')]
class Limits(c.Structure):
    _fields_ = [('basic', Basic), ('io', IO), ('processMemory', c.c_size_t), ('jobMemory', c.c_size_t), ('peakProcess', c.c_size_t), ('peakJob', c.c_size_t)]

def check(value):
    if not value: raise c.WinError(c.get_last_error())
    return value
def digest(path):
    path = Path(path).absolute()
    for p in (path, *path.parents):
        s = p.lstat()
        if stat.S_ISLNK(s.st_mode) or getattr(s, 'st_file_attributes', 0) & 1024: raise ValueError('reparse path')
    with path.open('rb') as f: return hashlib.file_digest(f, 'sha256').hexdigest()
def token(h):
    t = w.HANDLE(); check(open_token(h, 8, c.byref(t)))
    def get(kind):
        n = w.DWORD(); token_info(t, kind, None, 0, c.byref(n)); b = c.create_string_buffer(n.value)
        check(token_info(t, kind, b, n, c.byref(n))); return b
    def sid(b):
        p = w.LPWSTR(); check(sid_string(c.cast(b, c.POINTER(c.c_void_p))[0], c.byref(p)))
        try: return p.value
        finally: free(c.cast(p, w.HANDLE))
    try:
        stats = get(10).raw
        return {'sid': sid(get(1)), 'integrity': int(sid(get(25)).split('-')[-1]), 'elevated': int.from_bytes(get(20).raw[:4], 'little'), 'session': int.from_bytes(get(12).raw[:4], 'little'), 'authenticationLuid': stats[8:16].hex()}
    finally: close(t)
def observe(pid, handle=None):
    h = handle or check(open_process(0x1000 | 0x100000, False, pid))
    try:
        b = c.create_unicode_buffer(32768); n = w.DWORD(len(b)); check(query_image(h, 0, b, c.byref(n)))
        times = [w.FILETIME() for _ in range(4)]; check(get_times(h, *(c.byref(t) for t in times)))
        return {'pid': pid, 'image': b.value, 'creationTicks': (times[0].dwHighDateTime << 32) | times[0].dwLowDateTime, 'token': token(h)}
    finally:
        if handle is None: close(h)
def same_token(observation, own):
    if observation['token'] != own or own['integrity'] != 0x2000 or own['elevated']:
        raise ValueError('ordinary same-user/session/logon token required')
def line_deadline(stream, seconds):
    q = queue.Queue()
    def reader():
        try: q.put(stream.readline())
        except BaseException as error: q.put(error)
    threading.Thread(target=reader, daemon=True).start()
    result = q.get(timeout=seconds)
    if isinstance(result, BaseException): raise result
    return result

def job_processes(job):
    # Header DWORD count/assigned, followed by ULONG_PTR process IDs.
    b = c.create_string_buffer(8+128*c.sizeof(c.c_size_t)); n = w.DWORD()
    check(query_job(job, 3, b, len(b), c.byref(n)))
    count = int.from_bytes(b.raw[4:8], 'little')
    if count > 128: raise ValueError('unexpected test Job size')
    return [c.c_size_t.from_buffer(b, 8+i*c.sizeof(c.c_size_t)).value for i in range(count)]

def child():
    # Parent assigns this inert waiting launcher to its kill-on-close Job before
    # releasing this one message. Every later descendant inherits that Job.
    q = json.loads(sys.stdin.readline())
    if digest(q['exe']) != q['sha256']: raise ValueError('child image changed')
    with open(q['stdout'], 'wb') as output, open(q['stderr'], 'wb') as error:
        p = subprocess.Popen(q['args'], executable=q['exe'], cwd=q['cwd'], stdin=subprocess.PIPE, stdout=output, stderr=error, creationflags=subprocess.DETACHED_PROCESS)
        print(json.dumps(observe(p.pid)), flush=True)
        p.communicate(q.get('stdin', '').encode('utf-8'))
        return p.returncode

def validate(cfg):
    root = Path(cfg['installRoot'])
    if not root.is_absolute() or root.name != 'YimeCore 18u Touch': raise ValueError('explicit installed YimeCore 18u Touch root required')
    anchor = cfg['manifestSHA256']
    if not re.fullmatch('[0-9a-f]{64}', anchor) or digest(root/'installed-18u-product.json') != anchor: raise ValueError('installed manifest anchor')
    m = json.loads((root/'installed-18u-product.json').read_text(encoding='utf-8'))
    if m['schema'] != 'installed-18u-product-v2' or m['product'] != 'yimecore-18u' or m['architecture'] != 'native-arm64' or m['sourceCommit'] != cfg['sourceCommit']: raise ValueError('full installed frontend identity')
    rows = {}
    for r in m['files']:
        name = r['path']
        if not name or '\\' in name or ':' in name or any(p in ('', '.', '..') for p in name.split('/')) or name.lower() in rows: raise ValueError('manifest member')
        if (root/name).stat().st_size != r['bytes'] or digest(root/name) != r['sha256']: raise ValueError('installed payload changed: '+name)
        rows[name.lower()] = r['sha256']
    for name in ('bin/Yime18uInstalledRuntime.exe', 'bin/YimeBroker18u.exe', 'bin/YimeTouchKeyboard.exe', 'arm64/YimeTextService18u.dll'):
        if name.lower() not in rows: raise ValueError('required image absent')
    host = Path(cfg['hostExe'])
    if not host.is_absolute() or host.name != 'YimeTouchInstalledFrontendHostTests.exe' or digest(host) != cfg['hostSHA256']: raise ValueError('registered frontend host anchor')
    current = observe(os.getpid()); own = current['token']; same_token(current, own)
    h = check(open_process(0x1000, False, os.getpid()))
    try:
        process, native = w.USHORT(), w.USHORT(); check(is_wow(h, c.byref(process), c.byref(native)))
        if process.value != 0 or native.value != 0xaa64: raise ValueError('native ARM64 controller required')
    finally: close(h)
    if len(cfg['runningProcesses']) != 3 or {p['relative'] for p in cfg['runningProcesses']} != {'bin/Yime18uInstalledRuntime.exe', 'bin/YimeBroker18u.exe', 'bin/YimeTouchKeyboard.exe'}: raise ValueError('exact current runtime/Broker/GUI receipt required')
    handles = []
    try:
        for expected in cfg['runningProcesses']:
            h = check(open_process(0x1000 | 0x100000, False, expected['pid'])); handles.append(h)
            actual = observe(expected['pid'], h); same_token(actual, own)
            if Path(actual['image']) != root/expected['relative'] or actual['creationTicks'] != expected['creationTicks'] or wait_process(h, 0) != 258: raise ValueError('stale or foreign running process')
        return root, rows, own, handles
    except BaseException:
        for h in handles: close(h)
        raise

def run(cfg, output, execute):
    root, rows, own, prior = validate(cfg)
    if not execute:
        for h in prior: close(h)
        print(json.dumps({'validated': True, 'installation': False, 'processChanges': False, 'token': own})); return
    output.mkdir(parents=True, exist_ok=False)
    job = None; children = []; stopped = False; stop_requested = False; result = {'sourceCommit': cfg['sourceCommit'], 'manifestSHA256': cfg['manifestSHA256'], 'hostSHA256': cfg['hostSHA256'], 'token': own, 'previousProcesses': cfg['runningProcesses'], 'sendInput': False, 'physicalAcceptance': False, 'checkpoints': 0}
    script = Path(__file__).absolute()
    result['controllerPath'] = str(script)
    result['controllerSHA256'] = digest(script)
    result['spawnFlags'] = {'launcher': subprocess.DETACHED_PROCESS, 'nativeChild': subprocess.DETACHED_PROCESS}
    (output/'controller-used.py').write_bytes(script.read_bytes())
    runtime = root/'bin/Yime18uInstalledRuntime.exe'
    arguments = [str(runtime), '--installed-18u-run', '--install-root', str(root), '--manifest-sha256', cfg['manifestSHA256']]
    def launch(exe, args, label, stdin=''):
        p = subprocess.Popen([sys.executable, str(Path(__file__).absolute()), '--child'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8', creationflags=subprocess.DETACHED_PROCESS)
        children.append(p)
        try: check(assign_job(job, w.HANDLE(int(p._handle))))
        except BaseException: p.kill(); p.wait(); raise
        expected = rows[exe.relative_to(root).as_posix().lower()] if exe.is_relative_to(root) else cfg['hostSHA256']
        request = {'exe': str(exe), 'sha256': expected, 'args': args, 'cwd': str(root), 'stdout': str(output/(label+'.stdout.log')), 'stderr': str(output/(label+'.stderr.log')), 'stdin': stdin}
        p.stdin.write(json.dumps(request)+'\n'); p.stdin.flush(); p.stdin.close()
        seen = json.loads(line_deadline(p.stdout, 15)); same_token(seen, own)
        if Path(seen['image']) != exe: raise ValueError('child image mismatch')
        result[label] = seen
        return p, seen['pid']
    try:
        stop_requested = True
        stop = subprocess.run(arguments+['--stop'], cwd=root, capture_output=True, text=True, timeout=30, creationflags=subprocess.CREATE_NO_WINDOW)
        if stop.returncode: raise RuntimeError('verified runtime --stop failed')
        for h in prior:
            if wait_process(h, 20000) != 0: raise RuntimeError('previous runtime child still active; do not launch competing GUI')
        stopped = True
        job = check(create_job(None, None)); limits = Limits(); limits.basic.flags = 0x2000
        check(set_job(job, 9, c.byref(limits), c.sizeof(limits)))
        broker = root/'bin/YimeBroker18u.exe'
        bp, pid = launch(broker, [str(broker), '--installed-desktop', '--install-root', str(root), '--manifest-sha256', cfg['manifestSHA256']], 'broker')
        deadline = time.monotonic()+120
        while time.monotonic() < deadline:
            if bp.poll() is not None: raise RuntimeError('test Broker exited')
            p = output/'broker.stdout.log'
            if p.exists() and p.read_text(encoding='utf-8').splitlines()[:1] == ['READY yimebroker-18u-desktop']: break
            time.sleep(.1)
        else: raise TimeoutError('test Broker ready timeout')
        host = Path(cfg['hostExe'])
        config = {'dll': str(root/'arm64/YimeTextService18u.dll'), 'installRoot': str(root), 'manifestSHA256': cfg['manifestSHA256'], 'brokerPID': pid}
        hp, _ = launch(host, [str(host)], 'host', json.dumps(config)+'\n')
        observed_processes = {}
        allowed_images = {Path(sys.executable), host, broker, root/'bin/YimeTouchKeyboard.exe'}
        deadline = time.monotonic()+300
        while hp.poll() is None:
            if time.monotonic() >= deadline: raise TimeoutError('registered frontend host timeout')
            for member in job_processes(job):
                if member in observed_processes: continue
                try: seen = observe(member)
                except OSError as error:
                    result.setdefault('jobObservationErrors', []).append({'pid': member, 'error': str(error)})
                    continue  # May have exited between Job query and opening the handle.
                observed_processes[member] = seen
            # Persist the entire observation before validating any member. A
            # rejected member must retain its actual path/token/creation time.
            result['testJobProcesses'] = list(observed_processes.values())
            (output/'job-members.json').write_text(json.dumps({'members': result['testJobProcesses'], 'errors': result.get('jobObservationErrors', [])}, indent=2)+'\n', encoding='utf-8')
            for seen in observed_processes.values():
                same_token(seen, own)
                if Path(seen['image']) not in allowed_images:
                    raise ValueError('unexpected child image in test Job: pid='+str(seen['pid'])+' image='+seen['image'])
            time.sleep(.05)
        result['testJobProcesses'] = list(observed_processes.values())
        if hp.returncode: raise RuntimeError('registered frontend host failed; inspect host logs')
        if not any(Path(p['image']) == root/'bin/YimeTouchKeyboard.exe' for p in observed_processes.values()): raise ValueError('smoke GUI token not observed in test Job')
        lines = (output/'host.stdout.log').read_text(encoding='utf-8').splitlines()
        observed = json.loads(lines[-1])
        if observed.get('ok') is not True or observed.get('checkpoints') != 18 or observed.get('sendInput') is not False or observed.get('physicalAcceptance') is not False or observed.get('frontendPipeChain') is not True or observed.get('registered') is not True: raise ValueError('18 real registered checkpoints not proved')
        result.update({'checkpoints': 18, 'hostResult': observed})
    except BaseException as error:
        result['error'] = str(error)
        raise
    finally:
        if job:
            # Only this run's Broker/host/GUI and launchers. Observe the Job
            # empty before a normal runtime can re-use its named endpoints.
            try:
                check(terminate_job(job, 8))
                deadline = time.monotonic()+20
                while job_processes(job):
                    if time.monotonic() >= deadline: raise TimeoutError('test Job did not become empty')
                    time.sleep(.05)
                result['testJobEmptyBeforeRestore'] = True
            except BaseException as error:
                result['jobCleanupFailure'] = str(error)
            finally: close(job)
        for p in children:
            try: p.wait(timeout=20)
            except subprocess.TimeoutExpired: result['jobCleanupFailure'] = True
        if stop_requested and not stopped:
            # --stop may have delivered its event before a controller timeout
            # or wait error. Consult the original held process handles again.
            statuses = [wait_process(h, 5000) for h in prior]
            result['previousExitWaitResults'] = statuses
            stopped = all(status == 0 for status in statuses)
            if not stopped: result['restoreSkipped'] = 'At least one original process remains active or its wait failed; no competing runtime/GUI was launched.'
        for h in prior: close(h)
        if result.get('jobCleanupFailure'):
            result['restoreSkipped'] = 'Test Job cleanup was not proved complete; no competing runtime/GUI was launched.'
        if stopped and not result.get('jobCleanupFailure'):
            try:
                # Verify every image again before restoring from this ordinary
                # controller, outside the test Job. Runtime owns its new Job.
                if digest(root/'installed-18u-product.json') != cfg['manifestSHA256'] or digest(runtime) != rows['bin/yime18uinstalledruntime.exe']: raise ValueError('restore anchor changed')
                with open(output/'restored-runtime.log', 'wb') as log:
                    restored = subprocess.Popen(arguments, cwd=root, stdin=subprocess.DEVNULL, stdout=log, stderr=log, creationflags=subprocess.CREATE_NO_WINDOW)
                time.sleep(2)
                if restored.poll() is not None: raise RuntimeError('restored runtime exited')
                seen = observe(restored.pid); same_token(seen, own); result['restoredRuntime'] = seen
            except BaseException as error: result['restoreError'] = str(error)
        (output/'receipt.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    if result.get('restoreError') or result.get('jobCleanupFailure'): raise RuntimeError('test cleanup or restoration failed; inspect receipt')
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    if sys.argv[1:] == ['--child']: raise SystemExit(child())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--run', action='store_true', help='Without this flag only validate hashes and existing process identity')
    args = parser.parse_args(); run(json.loads(args.config.read_text(encoding='utf-8-sig')), args.output.absolute(), args.run)
