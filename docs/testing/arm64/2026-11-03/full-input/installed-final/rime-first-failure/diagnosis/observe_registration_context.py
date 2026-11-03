"""Record read-only PIME probe outputs and the observing process token."""
import argparse
import ctypes
from ctypes import wintypes as W
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--context', choices=('sandbox', 'ordinary-host'), required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
out = repo / 'docs/testing/arm64/2026-11-03/full-input/installed-final/rime-first-failure/diagnosis'
out.mkdir(parents=True, exist_ok=True)
root = Path('C:/Program Files/Yime Rime-PIME')
package = repo / '.generated/rime-final-6c1c0122/package/payload'
k = ctypes.WinDLL('kernel32', use_last_error=True)
a = ctypes.WinDLL('advapi32', use_last_error=True)
k.GetCurrentProcess.restype = W.HANDLE
a.OpenProcessToken.argtypes = [W.HANDLE, W.DWORD, ctypes.POINTER(W.HANDLE)]
a.GetTokenInformation.argtypes = [W.HANDLE, ctypes.c_int, W.LPVOID, W.DWORD, ctypes.POINTER(W.DWORD)]
k.CloseHandle.argtypes = [W.HANDLE]
token = W.HANDLE()
if not a.OpenProcessToken(k.GetCurrentProcess(), 8, ctypes.byref(token)):
    raise ctypes.WinError(ctypes.get_last_error())
try:
    elevated = W.DWORD()
    returned = W.DWORD()
    if not a.GetTokenInformation(token, 20, ctypes.byref(elevated), ctypes.sizeof(elevated), ctypes.byref(returned)):
        raise ctypes.WinError(ctypes.get_last_error())
finally:
    k.CloseHandle(token)

rows = []
for arch in ('x86', 'arm64'):
    relative = arch + '/PIMERegistrationStatus.exe'
    probe = root / relative
    data = probe.read_bytes()
    expected = (package / relative).read_bytes()
    if data != expected:
        raise ValueError('installed read-only probe differs from final package')
    command = [str(probe), 'verify-present']
    result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)
    raw = out / (args.context + '-' + arch + '.stdout.txt')
    with raw.open('x', encoding='utf-8', newline='\n') as stream:
        stream.write(result.stdout)
    err = out / (args.context + '-' + arch + '.stderr.txt')
    with err.open('x', encoding='utf-8', newline='\n') as stream:
        stream.write(result.stderr)
    rows.append({'architecture': arch, 'command': command, 'exitCode': result.returncode,
                 'probeSHA256': hashlib.sha256(data).hexdigest(), 'matchesFinalPackage': True,
                 'stdoutFile': raw.name, 'stderrFile': err.name})
report = {'schema': 'yime-rime-registration-observation-context-v1',
          'capturedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'context': args.context, 'observerTokenElevated': bool(elevated.value),
          'productSourceCommit': '6c1c01220b77406cfa5a90df111ea914882fa372',
          'readOnly': True, 'registrationMutated': False, 'profileActivated': False,
          'probeResults': rows}
with (out / (args.context + '.json')).open('x', encoding='utf-8', newline='\n') as stream:
    json.dump(report, stream, ensure_ascii=False, indent=2)
    stream.write('\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
