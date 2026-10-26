import ctypes
from ctypes import wintypes
import datetime
import hashlib
import json
from pathlib import Path
import struct

root = Path(r'C:\dev\Yime\.tmp\arm64-notepad-live-20261026')
kernel = ctypes.WinDLL('kernel32', use_last_error=True)
kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel.OpenProcess.restype = wintypes.HANDLE
kernel.CloseHandle.argtypes = [wintypes.HANDLE]
kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
kernel.IsWow64Process2.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.USHORT), ctypes.POINTER(wintypes.USHORT)]
kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4

def inspect(pid):
    handle = kernel.OpenProcess(0x1000, False, pid)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        buffer = ctypes.create_unicode_buffer(32768)
        length = wintypes.DWORD(len(buffer))
        if not kernel.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(length)):
            raise ctypes.WinError(ctypes.get_last_error())
        process_machine, native_machine = wintypes.USHORT(), wintypes.USHORT()
        if not kernel.IsWow64Process2(handle, ctypes.byref(process_machine), ctypes.byref(native_machine)):
            raise ctypes.WinError(ctypes.get_last_error())
        times = [wintypes.FILETIME() for _ in range(4)]
        if not kernel.GetProcessTimes(handle, *(ctypes.byref(item) for item in times)):
            raise ctypes.WinError(ctypes.get_last_error())
        image = Path(buffer.value)
        with image.open('rb') as stream:
            header = stream.read(64)
            assert header[:2] == b'MZ'
            stream.seek(struct.unpack_from('<I', header, 0x3c)[0])
            pe = stream.read(6)
            assert pe[:4] == b'PE\x00\x00'
            machine = struct.unpack_from('<H', pe, 4)[0]
        created = (times[0].dwHighDateTime << 32) | times[0].dwLowDateTime
        return {'pid': pid, 'image': str(image), 'image_sha256': hashlib.file_digest(image.open('rb'), 'sha256').hexdigest(),
                'pe_machine': hex(machine), 'process_machine': hex(process_machine.value),
                'native_machine': hex(native_machine.value), 'creation_filetime': created,
                'creation_time_utc': (datetime.datetime(1601, 1, 1, tzinfo=datetime.timezone.utc) + datetime.timedelta(microseconds=created // 10)).isoformat()}
    finally:
        kernel.CloseHandle(handle)

result = {'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'method': 'Read-only PROCESS_QUERY_LIMITED_INFORMATION, IsWow64Process2 and PE headers; no input injection or process mutation.',
          'notepad': inspect(29208), 'focus_loss_foreground_process_postcheck': inspect(6864)}
path = root / 'host-identity.json'
with path.open('x', encoding='utf-8', newline='\n') as output:
    json.dump(result, output, ensure_ascii=False, indent=2)
    output.write('\n')
print(json.dumps(result, ensure_ascii=False, indent=2))
