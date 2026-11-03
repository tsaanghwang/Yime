"""Elevate only the fixed checked, read-only PowerShell observer."""
import ctypes
from ctypes import wintypes as W
import json
from pathlib import Path
import subprocess
import sys
repo=Path(__file__).resolve().parents[2]
observer=Path(__file__).with_name('probe_protected_ps_context.py')
class ExecuteInfo(ctypes.Structure):
    _fields_=[('cbSize',W.DWORD),('fMask',W.ULONG),('hwnd',W.HWND),('lpVerb',W.LPCWSTR),
              ('lpFile',W.LPCWSTR),('lpParameters',W.LPCWSTR),('lpDirectory',W.LPCWSTR),
              ('nShow',ctypes.c_int),('hInstApp',W.HINSTANCE),('lpIDList',W.LPVOID),
              ('lpClass',W.LPCWSTR),('hkeyClass',W.HKEY),('dwHotKey',W.DWORD),
              ('hIconOrMonitor',W.HANDLE),('hProcess',W.HANDLE)]
shell=ctypes.WinDLL('shell32',use_last_error=True)
kernel=ctypes.WinDLL('kernel32',use_last_error=True)
shell.ShellExecuteExW.argtypes=[ctypes.POINTER(ExecuteInfo)]
shell.ShellExecuteExW.restype=W.BOOL
kernel.WaitForSingleObject.argtypes=[W.HANDLE,W.DWORD]
kernel.GetExitCodeProcess.argtypes=[W.HANDLE,ctypes.POINTER(W.DWORD)]
kernel.CloseHandle.argtypes=[W.HANDLE]
info=ExecuteInfo()
info.cbSize=ctypes.sizeof(info)
info.fMask=0x40|0x100|0x400
info.lpVerb='runas'
info.lpFile=sys.executable
info.lpParameters=subprocess.list2cmdline(['-B','-X','utf8',str(observer),'--label','administrator'])
info.lpDirectory=str(repo)
info.nShow=0
if not shell.ShellExecuteExW(ctypes.byref(info)):raise ctypes.WinError(ctypes.get_last_error())
try:
    wait=kernel.WaitForSingleObject(info.hProcess,60000)
    if wait!=0:raise RuntimeError('read-only checked observer wait did not complete: '+str(wait))
    code=W.DWORD()
    if not kernel.GetExitCodeProcess(info.hProcess,ctypes.byref(code)):raise ctypes.WinError(ctypes.get_last_error())
finally:kernel.CloseHandle(info.hProcess)
print('read-only elevated checked observer exit',code.value)
out=repo/'.generated/rime-live-preparation/second-failure'
report=out/'administrator-protected-ps.json'
if report.exists():print(report.read_text(encoding='utf-8'))
for suffix in ('stdout','stderr'):
    path=out/('administrator-protected-ps.'+suffix+'.txt')
    if path.exists():print(path.read_text(encoding='utf-8'))
raise SystemExit(code.value)
