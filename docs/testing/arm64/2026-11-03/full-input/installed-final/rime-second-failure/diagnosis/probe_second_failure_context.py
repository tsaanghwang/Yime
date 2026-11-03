"""Read-only exact installed Rime probe: inherited versus maintenance environment."""
import argparse
import ctypes
from ctypes import wintypes as W
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--label', required=True, choices=('ordinary', 'administrator'))
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
output = repo / '.generated/rime-live-preparation/second-failure'
output.mkdir(parents=True, exist_ok=True)
report_path = output / (args.label + '.json')
if report_path.exists():
    raise ValueError('preserve prior observation; output exists')
kernel = ctypes.WinDLL('kernel32', use_last_error=True)
advapi = ctypes.WinDLL('advapi32', use_last_error=True)
kernel.GetCurrentProcess.restype = W.HANDLE
kernel.CloseHandle.argtypes = [W.HANDLE]
kernel.LocalFree.argtypes = [W.HLOCAL]
advapi.OpenProcessToken.argtypes = [W.HANDLE, W.DWORD, ctypes.POINTER(W.HANDLE)]
advapi.GetTokenInformation.argtypes = [W.HANDLE, ctypes.c_int, W.LPVOID, W.DWORD, ctypes.POINTER(W.DWORD)]
advapi.ConvertSidToStringSidW.argtypes = [W.LPVOID, ctypes.POINTER(W.LPWSTR)]
token = W.HANDLE()
if not advapi.OpenProcessToken(kernel.GetCurrentProcess(), 8, ctypes.byref(token)):
    raise ctypes.WinError(ctypes.get_last_error())
try:
    elevated, count = W.DWORD(), W.DWORD()
    if not advapi.GetTokenInformation(token, 20, ctypes.byref(elevated), ctypes.sizeof(elevated), ctypes.byref(count)):
        raise ctypes.WinError(ctypes.get_last_error())
    advapi.GetTokenInformation(token, 1, None, 0, ctypes.byref(count))
    buf = ctypes.create_string_buffer(count.value)
    if not advapi.GetTokenInformation(token, 1, buf, len(buf), ctypes.byref(count)):
        raise ctypes.WinError(ctypes.get_last_error())
    sid_pointer = ctypes.cast(buf, ctypes.POINTER(W.LPVOID))[0]
    sid_text = W.LPWSTR()
    if not advapi.ConvertSidToStringSidW(sid_pointer, ctypes.byref(sid_text)):
        raise ctypes.WinError(ctypes.get_last_error())
    sid = sid_text.value
    kernel.LocalFree(ctypes.cast(sid_text, W.HLOCAL))
finally:
    kernel.CloseHandle(token)
if bool(elevated.value) != (args.label == 'administrator'):
    raise ValueError('observer token does not match requested label')

stage = Path('C:/Program Files/Yime Maintenance/rime-pime/cb5bdf84f792130086fc86de41248c739dc94acfa089331183ee3137ab3c2dbd')
shell = stage / 'maintenance/powershell/pwsh.exe'
system = Path(os.environ['SystemRoot'])
clean = {k: os.environ[k] for k in ('SystemRoot', 'ProgramFiles', 'USERPROFILE', 'LOCALAPPDATA', 'APPDATA')}
clean.update({'WINDIR': str(system), 'PATH': str(system / 'System32'), 'PATHEXT': '.EXE',
              'TEMP': str(system / 'Temp'), 'TMP': str(system / 'Temp'),
              'PSModulePath': str(shell.parent / 'Modules') + ';' + str(system / 'System32/WindowsPowerShell/v1.0/Modules')})
root = Path('C:/Program Files/Yime Rime-PIME')
payload = repo / '.generated/rime-final-46dd5896/package/payload'
rows = []
for environment, values in (('inherited', dict(os.environ)), ('maintenance-clean', clean)):
    for arch in ('x86', 'arm64'):
        relative = arch + '/PIMERegistrationStatus.exe'
        probe = root / relative
        data = probe.read_bytes()
        if data != (payload / relative).read_bytes():
            raise ValueError('installed exact probe mismatch')
        command = [str(probe), 'verify-registered']
        result = subprocess.run(command, cwd=stage, env=values, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)
        stem = args.label + '-' + environment + '-' + arch
        for suffix, text in (('.stdout.txt', result.stdout), ('.stderr.txt', result.stderr)):
            with (output / (stem + suffix)).open('x', encoding='utf-8', newline='\n') as stream:
                stream.write(text)
        rows.append({'environment': environment, 'environmentKeys': sorted(values), 'architecture': arch,
                     'command': command, 'cwd': str(stage), 'exitCode': result.returncode,
                     'probeSHA256': hashlib.sha256(data).hexdigest(),
                     'stdoutFile': stem + '.stdout.txt', 'stderrFile': stem + '.stderr.txt',
                     'status': dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)})
report = {'schema': 'yime-rime-registration-token-environment-probe-v1',
          'capturedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'sourceCommit': '46dd58967266edcab3f0d3bb131015d81dc4b951',
          'observerTokenElevated': bool(elevated.value), 'observerSID': sid, 'label': args.label,
          'readOnly': True, 'registrationMutated': False, 'profileActivated': False, 'results': rows}
with report_path.open('x', encoding='utf-8', newline='\n') as stream:
    json.dump(report, stream, ensure_ascii=False, indent=2)
    stream.write('\n')
print(json.dumps({k:v for k,v in report.items() if k != 'results'}, ensure_ascii=False))
for row in rows:
    print(row['environment'], row['architecture'], row['exitCode'], row['status'].get('exact_profile_registered_count'))
