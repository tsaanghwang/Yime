"""Read-only preparation for the fixed MSI test.6 baseline; never launches payloads.

Exit 0 means baseline verification completed, NOT physical/app-input readiness.
Only the explicitly supplied, new report file is written.
"""
import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import sys

HOST = 'WIN-JTKUT7KBVN7'
SOURCE = '5367accdb6f18bb298f2282df67d4cc6d342aa5e'
DESCRIPTOR_SHA256 = '096920dfaf62178fbbf3bd049a0057237dbe360ad04bed9364f947d315392880'
CLSID = '{6DFACE1F-562E-4773-A9D6-D5753A314711}'
PROFILE = '{1BD904AC-3194-4419-B70A-5574100F18B3}'
VERSION = '0.1.0-18u-test.6'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def regular(path):
    for component in (path, *path.parents):
        if component.is_symlink() or (hasattr(component, 'is_junction') and component.is_junction()):
            raise ValueError('linked path refused: ' + str(component))
    if not path.is_file():
        raise ValueError('missing regular file: ' + str(path))
    return path


def verify_payload(root):
    descriptor = regular(root / 'installed-18u-product.json')
    if digest(descriptor) != DESCRIPTOR_SHA256:
        raise ValueError('descriptor differs from fixed test.6 delivery')
    manifest = json.loads(descriptor.read_text(encoding='utf-8'))
    if (manifest['sourceCommit'] != SOURCE or manifest['product'] != 'yimecore-18u'
            or manifest['architecture'] != 'native-x64'
            or manifest['identity'] != {'clsid': CLSID, 'profile': PROFILE}):
        raise ValueError('fixed product identity mismatch')
    marker = json.loads(regular(root / '.yime-product.json').read_text(encoding='utf-8-sig'))
    if any(marker.get(k) != v for k, v in {
        'format': 'yime-simple-install-1', 'product': 'yimecore-18u',
        'target': 'windows-amd64', 'version': VERSION,
    }.items()):
        raise ValueError('installed marker mismatch')
    seen = set()
    for entry in manifest['files']:
        name = entry['path']
        relative = PurePosixPath(name)
        if (relative.is_absolute() or '..' in relative.parts or ':' in name
                or '\\' in name or name.casefold() in seen):
            raise ValueError('invalid or duplicate member path')
        seen.add(name.casefold())
        member = regular(root / relative)
        if member.stat().st_size != entry['bytes'] or digest(member) != entry['sha256']:
            raise ValueError('payload mismatch: ' + name)
    if len(seen) != 15:
        raise ValueError('fixed test.6 member count mismatch')
    return {'version': VERSION, 'sourceCommit': SOURCE,
            'descriptorSHA256': DESCRIPTOR_SHA256, 'verifiedMembers': 15,
            'descriptorAlsoVerified': True, 'markerMatches': True,
            'scope': 'descriptor-listed payload only; maintenance resources and extra files not certified'}


def observe_windows(root):
    import winreg
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.IsWow64Process2.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ushort), ctypes.POINTER(ctypes.c_ushort)]
    kernel.IsWow64Process2.restype = ctypes.c_int
    process, native = ctypes.c_ushort(), ctypes.c_ushort()
    if not kernel.IsWow64Process2(kernel.GetCurrentProcess(), ctypes.byref(process), ctypes.byref(native)):
        raise ctypes.WinError(ctypes.get_last_error())
    if process.value != 0 or native.value != 0x8664:
        raise ValueError('requires native x64 process on x64 Windows')
    access = winreg.KEY_READ | winreg.KEY_WOW64_64KEY
    com = 'SOFTWARE\\Classes\\CLSID\\' + CLSID + '\\InprocServer32'
    tip = 'SOFTWARE\\Microsoft\\CTF\\TIP\\' + CLSID
    profile_key = tip + '\\LanguageProfile\\0x00000804\\' + PROFILE
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, com, 0, access) as key:
        dll, _ = winreg.QueryValueEx(key, '')
    if os.path.normcase(os.path.abspath(dll)) != os.path.normcase(str(root / 'x64/YimeTextService18u.dll')):
        raise ValueError('COM path differs from selected installation')
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, profile_key, 0, access):
        pass
    user = ctypes.WinDLL('user32', use_last_error=True)
    user.GetSystemMetrics.argtypes = [ctypes.c_int]
    user.GetSystemMetrics.restype = ctypes.c_int
    metrics = {name: user.GetSystemMetrics(index) for name, index in {
        'processVisibleWidth': 0, 'processVisibleHeight': 1, 'monitorCount': 80,
        'digitizerFlags': 94, 'maximumTouches': 95, 'convertibleSlateMode': 0x2003,
    }.items()}
    if metrics['processVisibleWidth'] <= 0 or metrics['processVisibleHeight'] <= 0:
        raise ValueError('interactive display metrics unavailable')
    return {'nativeArchitecture': 'AMD64', 'windowsVersion': platform.version(),
            'comPathMatches': True, 'profileRegistryKeyPresent': True,
            'registrationScope': 'read-only HKLM view; not live TSF activation or category verification',
            'displayMetrics': metrics,
            'displayScope': 'process-visible dimensions, not physical pixels or ruler calibration',
            'touchReported': bool(metrics['digitizerFlags'] & 3),
            'penReported': bool(metrics['digitizerFlags'] & 12),
            'digitizerReadyReported': bool(metrics['digitizerFlags'] & 128)}


def assess(root, host, observe):
    report = {'schema': 'msi-18u-test6-preparation-v1',
              'recordedAtUTC': datetime.now(timezone.utc).isoformat(), 'host': host,
              'installRoot': str(root), 'baselineVerified': False,
              'physicalAcceptancePerformed': False, 'appInputPerformed': False,
              'installedHostRetested': False, 'systemMutationPerformed': False,
              'readyForInstalledTouchAppTest': False,
              'blockers': ['test.6 has no packaged touch frontend',
                           'ordinary-application installed input entry is not delivered by test.6'],
              'manualChecks': ['current pen charge and response', 'screen posture and ruler calibration',
                               'new frontend package identity and ordinary-app TSF route']}
    try:
        if host.upper() != HOST:
            raise ValueError('wrong host: this preparation is scoped to ' + HOST)
        report['payload'] = verify_payload(root)
        report['environment'] = observe(root)
        report['baselineVerified'] = True
        if not report['environment'].get('digitizerReadyReported'):
            report['blockers'].append('Windows does not currently report digitizer ready')
    except (OSError, ValueError, KeyError, TypeError) as error:
        report['error'] = str(error)
    return report


def write_report(path, root, report):
    # No overwrites and no evidence inside the installation, including linked aliases.
    if path.resolve().is_relative_to(root.resolve()):
        raise ValueError('report must be outside installation')
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='new report file in an existing directory')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('Windows only; portable unit tests use injected observations')
    root = args.install_root.absolute()
    if args.output.exists() or args.output.resolve().is_relative_to(root.resolve()):
        parser.error('use a new output file outside installation')
    report = assess(root, platform.node(), observe_windows)
    try:
        write_report(args.output, root, report)
    except (OSError, ValueError) as error:
        print('Report not written: ' + str(error), file=sys.stderr)
        return 2
    print(json.dumps({'baselineVerified': report['baselineVerified'],
                      'readyForInstalledTouchAppTest': False,
                      'report': str(args.output.absolute())}, ensure_ascii=False))
    return 0 if report['baselineVerified'] else 2


if __name__ == '__main__':
    sys.exit(main())
