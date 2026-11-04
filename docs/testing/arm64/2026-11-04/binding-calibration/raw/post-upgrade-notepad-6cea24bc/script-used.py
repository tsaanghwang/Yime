"""Read current process architecture and loaded Yime modules; no input or retry."""
from pathlib import Path
import ctypes as c
from ctypes import wintypes as w
import datetime
import importlib.util
import json
import os
import struct

root = Path(__file__).resolve().parents[2]
out = root / '.generated/asus-notepad-prepared-6cea24bc'
out.mkdir(exist_ok=False)
spec = importlib.util.spec_from_file_location('identity_util', root / '.generated/touch-full-tools/run_installed_frontend_checkpoints.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class ProcessEntry(c.Structure):
    _fields_ = [('dwSize', w.DWORD), ('cntUsage', w.DWORD), ('pid', w.DWORD), ('heap', c.c_size_t), ('module', w.DWORD), ('threads', w.DWORD), ('parent', w.DWORD), ('priority', w.LONG), ('flags', w.DWORD), ('name', w.WCHAR * 260)]

class ModuleEntry(c.Structure):
    _fields_ = [('dwSize', w.DWORD), ('moduleID', w.DWORD), ('processID', w.DWORD), ('globalCount', w.DWORD), ('processCount', w.DWORD), ('base', c.c_void_p), ('size', w.DWORD), ('module', w.HMODULE), ('name', w.WCHAR * 256), ('path', w.WCHAR * 260)]

snapshot = m.api(m.K, 'CreateToolhelp32Snapshot', w.HANDLE, w.DWORD, w.DWORD)
pfirst = m.api(m.K, 'Process32FirstW', w.BOOL, w.HANDLE, c.POINTER(ProcessEntry))
pnext = m.api(m.K, 'Process32NextW', w.BOOL, w.HANDLE, c.POINTER(ProcessEntry))
mfirst = m.api(m.K, 'Module32FirstW', w.BOOL, w.HANDLE, c.POINTER(ModuleEntry))
mnext = m.api(m.K, 'Module32NextW', w.BOOL, w.HANDLE, c.POINTER(ModuleEntry))

def checked_snapshot(flags, pid):
    handle = snapshot(flags, pid)
    if handle == c.c_void_p(-1).value: raise c.WinError(c.get_last_error())
    return handle

def pe(path):
    with Path(path).open('rb') as stream:
        assert stream.read(2) == b'MZ'
        stream.seek(0x3c); offset = struct.unpack('<I', stream.read(4))[0]
        stream.seek(offset); assert stream.read(4) == b'PE\0\0'
        machine = struct.unpack('<H', stream.read(2))[0]
    return {'machine': hex(machine), 'machineName': {0xaa64:'ARM64', 0xa641:'ARM64EC', 0xa64e:'ARM64X', 0x8664:'AMD64', 0x14c:'x86'}.get(machine, 'other'), 'sha256': m.digest(path)}

def observe(pid, name, parent):
    row = m.observe(pid)
    row.update(name=name, parentPID=parent)
    handle = m.check(m.open_process(0x1000, False, pid))
    try:
        process, native = w.USHORT(), w.USHORT()
        m.check(m.is_wow(handle, c.byref(process), c.byref(native)))
        row['processMachine'] = hex(process.value)
        row['nativeMachine'] = hex(native.value)
    finally: m.close(handle)
    row['imagePE'] = pe(row['image'])
    row['nativeARM64Confirmed'] = process.value == 0 and native.value == 0xaa64 and row['imagePE']['machine'] == '0xaa64'
    return row

result = {'schema':'asus-notepad-post-upgrade-observation-v1', 'observedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(), 'readOnly':True, 'inputSent':False, 'bindRetried':False, 'processesLaunchedOrStopped':False, 'notepad':[], 'touchProcesses':[], 'userObservation':{'screenResolution':'3840x2400','windowsScalePercent':250,'rulerPrecisionMM':1,'referenceNominalMM':100,'referenceObservedMM':57.5,'wholeKeyboardVisible':True,'architectureReported':'unknown','PIDReported':'秋其秋千秋秋','binding':'cannot bind','expectedBody':'你','actualBody':'','stoppedAt':'binding','physicalCalibrationPassed':False,'fingerInputPassed':False}}
result['historicalFirstUserObservation'] = result.pop('userObservation')
result['phase'] = 'after-.4-software-checks-before-human-retest'
try:
    result['observer'] = m.observe(os.getpid())
    handle = checked_snapshot(2, 0)
    selected = []
    try:
        entry = ProcessEntry(); entry.dwSize = c.sizeof(entry)
        ok = pfirst(handle, c.byref(entry))
        while ok:
            if entry.name.lower() in ['notepad.exe','yime18uinstalledruntime.exe','yimebroker18u.exe','yimetouchkeyboard.exe']:
                selected.append((entry.pid, entry.name, entry.parent))
            ok = pnext(handle, c.byref(entry))
        if c.get_last_error() != 18: raise c.WinError(c.get_last_error())
    finally: m.close(handle)
    for pid, name, parent in selected:
        row = observe(pid, name, parent)
        if name.lower() != 'notepad.exe':
            result['touchProcesses'].append(row)
            continue
        modules = []
        handle = checked_snapshot(0x8 | 0x10, pid)
        try:
            entry = ModuleEntry(); entry.dwSize = c.sizeof(entry)
            ok = mfirst(handle, c.byref(entry))
            while ok:
                if any(term in entry.name.lower() for term in ['yime','rime','pime','msctf']):
                    modules.append({'name':entry.name,'path':entry.path,'imagePE':pe(entry.path)})
                ok = mnext(handle, c.byref(entry))
            if c.get_last_error() != 18: raise c.WinError(c.get_last_error())
        finally: m.close(handle)
        row['relatedLoadedModules'] = modules
        row['installed18uDLLLoaded'] = any(Path(item['path']) == Path(r'C:\Program Files\YimeCore 18u Touch\arm64\YimeTextService18u.dll') for item in modules)
        row['modulePresenceDoesNotProveActiveProfile'] = True
        result['notepad'].append(row)
    result['completed'] = True
except BaseException as error:
    result['completed'] = False
    result['error'] = str(error)
    result['stoppedWithoutRetry'] = True
finally:
    (out / 'observation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k not in ['observer','touchProcesses','userObservation']},ensure_ascii=False,indent=2))
raise SystemExit(0 if result['completed'] else 1)
