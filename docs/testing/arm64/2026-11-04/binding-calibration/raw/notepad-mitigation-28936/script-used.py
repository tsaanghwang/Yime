"""One identity-bound metadata query. No activation, injection, loading or input."""
from pathlib import Path
import ctypes as c
from ctypes import wintypes as w
import datetime
import hashlib
import importlib.util
import json
import os

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'.generated/notepad-mitigation-28936-20261104'
ANCHOR = ROOT/'.generated/asus-notepad-binding-stop-20261104/observation.json'
PID = 28936
EXPECTED_CREATION = 134382279754397239
EXPECTED_IMAGE = r'C:\Program Files\WindowsApps\Microsoft.WindowsNotepad_11.2607.14.0_arm64__8wekyb3d8bbwe\Notepad\Notepad.exe'
EXPECTED_SHA = '229e2d1684e89f054c0907f73028b111819124376a3eb7b87027e996b16747c6'
spec = importlib.util.spec_from_file_location('existing_identity_functions', ROOT/'.generated/touch-full-tools/run_installed_frontend_checkpoints.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

OUT.mkdir(exist_ok=False)
result = {
    'schema': 'notepad-exact-process-mitigation-observation-v1',
    'observedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'pid': PID, 'readOnly': True, 'activationAttempted': False, 'moduleSnapshotExecuted': False,
    'DLLLoadOrInjectionAttempted': False, 'inputSent': False, 'bindRetried': False,
    'targetProcessesStartedOrStopped': False, 'queryRetryCount': 0, 'policies': [],
    'scriptSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'sourceObservation': str(ANCHOR), 'sourceObservationSHA256': hashlib.sha256(ANCHOR.read_bytes()).hexdigest(),
    'definitionSources': {
        'query': 'https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocessmitigationpolicy',
        'enum': 'https://learn.microsoft.com/en-us/windows/win32/api/winnt/ne-winnt-process_mitigation_policy',
        'signature': 'https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-process_mitigation_binary_signature_policy',
        'extension': 'https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-process_mitigation_extension_point_disable_policy',
        'legacyExtensionScope': 'https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute',
    },
    'limits': ['Policy metadata is not binding or text input acceptance.', 'This query does not inspect current modules; the earlier no-18u-DLL snapshot is not a claim that it was never loaded.', 'DisableExtensionPoints describes legacy extension points; it is not a universal TSF success/failure predicate.'],
}
handle = None
try:
    baseline = next(row for row in json.loads(ANCHOR.read_text(encoding='utf-8'))['notepad'] if row['pid'] == PID)
    if baseline['creationTicks'] != EXPECTED_CREATION or baseline['image'] != EXPECTED_IMAGE or baseline['imagePE']['sha256'] != EXPECTED_SHA:
        raise ValueError('historical process identity anchor changed')
    result['expectedIdentity'] = {key: baseline[key] for key in ('pid', 'image', 'creationTicks', 'token')}
    own = m.observe(os.getpid())
    m.same_token(own, baseline['token'])
    result['observer'] = own
    # PROCESS_QUERY_INFORMATION is required by the documented query. SYNCHRONIZE
    # permits observing whether this original process has exited; no VM rights.
    c.set_last_error(0)
    handle = m.open_process(0x400 | 0x100000, False, PID)
    result['openProcess'] = {'accessMask': '0x00100400', 'succeeded': bool(handle), 'lastError': c.get_last_error()}
    if not handle:
        raise c.WinError(c.get_last_error())
    before = m.observe(PID, handle)
    result['identityBefore'] = before
    if before != result['expectedIdentity'] or m.wait_process(handle, 0) != 258:
        raise ValueError('PID identity changed or exited; no policy queries performed')
    if m.digest(before['image']) != EXPECTED_SHA:
        raise ValueError('Notepad executable hash changed; no policy queries performed')
    process, native = w.USHORT(), w.USHORT()
    m.check(m.is_wow(handle, c.byref(process), c.byref(native)))
    result['architecture'] = {'processMachine': hex(process.value), 'nativeMachine': hex(native.value)}
    if process.value != 0 or native.value != 0xaa64:
        raise ValueError('original native ARM64 identity no longer matches')
    sdk = Path(r'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\um\winnt.h')
    sdk_text = sdk.read_text(encoding='utf-8-sig')
    enum = sdk_text.split('typedef enum _PROCESS_MITIGATION_POLICY {', 1)[1].split('}', 1)[0]
    values = [line.strip().rstrip(',') for line in enum.splitlines() if line.strip()]
    if values.index('ProcessSignaturePolicy') != 8 or values.index('ProcessExtensionPointDisablePolicy') != 6:
        raise ValueError('installed SDK policy enum differs from reviewed Microsoft definitions')
    result['sdkDefinition'] = {'path': str(sdk), 'sha256': hashlib.sha256(sdk.read_bytes()).hexdigest(), 'ProcessSignaturePolicy': 8, 'ProcessExtensionPointDisablePolicy': 6, 'bufferBytes': c.sizeof(w.DWORD)}
    query = m.api(m.K, 'GetProcessMitigationPolicy', w.BOOL, w.HANDLE, c.c_int, c.c_void_p, c.c_size_t)
    requests = [
        ('ProcessSignaturePolicy', 8, ['MicrosoftSignedOnly', 'StoreSignedOnly', 'MitigationOptIn', 'AuditMicrosoftSignedOnly', 'AuditStoreSignedOnly']),
        ('ProcessExtensionPointDisablePolicy', 6, ['DisableExtensionPoints']),
    ]
    for name, policy_id, bits in requests:
        if m.wait_process(handle, 0) != 258:
            raise ValueError('original process exited before the next policy query; stopped')
        flags = w.DWORD(0)
        c.set_last_error(0)
        returned = query(handle, policy_id, c.byref(flags), c.sizeof(flags))
        last_error = c.get_last_error()
        row = {'policy': name, 'enumValue': policy_id, 'bufferBytes': c.sizeof(flags), 'returnValue': int(returned), 'success': bool(returned), 'lastError': last_error, 'lastErrorMeaningfulOnlyOnFailure': True, 'bufferHex': bytes(flags).hex()}
        if returned:
            row.update(flags=int(flags.value), flagsHex=f'0x{flags.value:08x}', fields={field: bool(flags.value & (1 << bit)) for bit, field in enumerate(bits)}, unknownReservedMask=f'0x{flags.value & ~((1 << len(bits))-1):08x}')
        result['policies'].append(row)
        if not returned:
            raise c.WinError(last_error)
    after = m.observe(PID, handle)
    result['identityAfter'] = after
    result['targetStillRunningAfter'] = m.wait_process(handle, 0) == 258
    if after != before or not result['targetStillRunningAfter']:
        raise ValueError('process changed/exited during metadata observation; results are not a stable live identity proof')
    result['completed'] = True
except BaseException as error:
    result['completed'] = False
    result['error'] = str(error)
    result['stoppedWithoutRetry'] = True
finally:
    if handle:
        m.close(handle)
    (OUT/'observation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (OUT/'script-used.py').write_bytes(Path(__file__).read_bytes())
print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(0 if result['completed'] else 1)
