"""Read installed 18u identity and exact runtime children; never start or stop.

Pass the runtime PID printed by the normal parent YimeMaintenance.exe after
Install. This script discovers only that PID's two direct named children, then
validates each image, token, creation time and every fixed package payload hash.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
import importlib.util
import json
import os
from pathlib import Path
import time

HERE = Path(__file__).absolute().parent
spec = importlib.util.spec_from_file_location('frontend_checkpoint_controller', HERE/'run_installed_frontend_checkpoints.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class Entry(c.Structure):
    _fields_ = [('dwSize', w.DWORD), ('cntUsage', w.DWORD), ('th32ProcessID', w.DWORD),
        ('th32DefaultHeapID', c.c_size_t), ('th32ModuleID', w.DWORD), ('cntThreads', w.DWORD),
        ('th32ParentProcessID', w.DWORD), ('pcPriClassBase', w.LONG), ('dwFlags', w.DWORD),
        ('szExeFile', w.WCHAR*260)]
snapshot = m.api(m.K, 'CreateToolhelp32Snapshot', w.HANDLE, w.DWORD, w.DWORD)
first = m.api(m.K, 'Process32FirstW', w.BOOL, w.HANDLE, c.POINTER(Entry))
next_process = m.api(m.K, 'Process32NextW', w.BOOL, w.HANDLE, c.POINTER(Entry))

def children(runtime_pid):
    handle = snapshot(2, 0)
    if handle == c.c_void_p(-1).value: raise c.WinError(c.get_last_error())
    expected = {'yimebroker18u.exe': 'bin/YimeBroker18u.exe', 'yimetouchkeyboard.exe': 'bin/YimeTouchKeyboard.exe'}
    found = {name: [] for name in expected.values()}
    try:
        entry = Entry(); entry.dwSize = c.sizeof(entry)
        ok = first(handle, c.byref(entry))
        while ok:
            name = entry.szExeFile.lower()
            if entry.th32ParentProcessID == runtime_pid and name in expected:
                found[expected[name]].append(entry.th32ProcessID)
            ok = next_process(handle, c.byref(entry))
        if c.get_last_error() != 18: raise c.WinError(c.get_last_error())
        return found
    finally: m.close(handle)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-pid', required=True, type=int, help='PID printed by the just-completed ordinary-parent install')
    parser.add_argument('--output', required=True, type=Path, help='Fresh directory within this worktree .generated')
    parser.add_argument('--template', type=Path, default=HERE/'frontend-checkpoints-config-final-6c1c.template.json')
    parser.add_argument('--wait-seconds', type=int, default=120, help='Read-only wait for the normal Broker and GUI to appear')
    args = parser.parse_args()
    if args.runtime_pid <= 0 or not 0 <= args.wait_seconds <= 180: raise ValueError('bounded wait and live runtime PID required')
    output = args.output.resolve()
    if not output.is_relative_to(HERE.parents[0]) or output == HERE.parents[0] or output.exists(): raise ValueError('fresh worktree .generated output required')
    cfg = json.loads(args.template.read_text(encoding='utf-8'))
    root = Path(cfg['installRoot'])
    own = m.observe(os.getpid()); m.same_token(own, own['token'])
    runtime = m.observe(args.runtime_pid); m.same_token(runtime, own['token'])
    if Path(runtime['image']) != root/'bin/Yime18uInstalledRuntime.exe': raise ValueError('runtime PID belongs to another image')
    deadline = time.monotonic()+args.wait_seconds
    while True:
        found = children(args.runtime_pid)
        if any(len(pids) > 1 for pids in found.values()): raise ValueError('multiple same-name direct children; do not guess a process')
        if all(len(pids) == 1 for pids in found.values()): break
        now = m.observe(args.runtime_pid)
        if now != runtime: raise ValueError('runtime identity changed while waiting')
        if time.monotonic() >= deadline: raise TimeoutError('normal runtime Broker/GUI not both observed')
        time.sleep(.25)
    rows = [('bin/Yime18uInstalledRuntime.exe', runtime)]
    rows.extend((relative, m.observe(pids[0])) for relative, pids in found.items())
    for relative, seen in rows:
        m.same_token(seen, own['token'])
        if Path(seen['image']) != root/relative: raise ValueError('unexpected child path')
        if seen['creationTicks'] < runtime['creationTicks']: raise ValueError('child predates the recorded runtime; parent PID may have been reused')
    cfg['runningProcesses'] = [{'relative': relative, 'pid': seen['pid'], 'creationTicks': seen['creationTicks']} for relative, seen in rows]
    _, _, _, held = m.validate(cfg)
    for handle in held: m.close(handle)
    user = c.WinDLL('user32', use_last_error=True)
    keyboard_layout = m.api(user, 'GetKeyboardLayout', w.HANDLE, w.DWORD)(0)
    evidence = {'schema': '18u-installed-frontend-identity-v1', 'sourceCommit': cfg['sourceCommit'],
        'manifestSHA256': cfg['manifestSHA256'], 'hostSHA256': cfg['hostSHA256'], 'controller': own,
        'runtimeAndDirectChildren': [dict(relative=relative, **seen) for relative, seen in rows],
        'creationTicksUnit': 'Windows FILETIME: unsigned integer 100ns ticks since 1601-01-01 UTC',
        'allInstalledPayloadHashesVerified': True, 'controllerKeyboardLanguage': hex(keyboard_layout & 0xffff),
        'hostRequiresChinese0804': True, 'processChanges': False, 'installationExecuted': False,
        'registeredHostExecuted': False, 'physicalAcceptance': False}
    output.mkdir(parents=True)
    (output/'config.json').write_text(json.dumps(cfg, indent=2)+'\n', encoding='utf-8')
    (output/'identity.json').write_text(json.dumps(evidence, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'validated': True, 'config': str(output/'config.json'), 'identity': str(output/'identity.json'), 'processes': cfg['runningProcesses'], 'processChanges': False}, indent=2))

if __name__ == '__main__': main()
