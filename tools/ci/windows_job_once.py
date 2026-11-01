"""Bound one owned Windows process tree; no shell, retry, or background-service claim.

The root is created suspended and cannot run before assignment to a kill-on-close
Job Object. treeStopped means this job has zero active processes, NOT that Windows
system services have completed any authorized asynchronous component processing.
"""
import ctypes
import os
from pathlib import Path
import subprocess
import time


def run_once(command, cwd, stdout_path, stderr_path, timeout, backend=None):
    if not command or timeout <= 0 or not Path(command[0]).is_absolute():
        raise ValueError('absolute executable and positive deadline required')
    result = {'started': False, 'timedOut': False, 'treeStopped': False,
              'exitCode': None, 'errorCode': None}
    backend = backend or WindowsJob(command, cwd, stdout_path, stderr_path)
    try:
        backend.start_suspended_assigned()
        backend.resume()
        result['started'] = True
        deadline = time.monotonic() + timeout
        while backend.active_processes() != 0:
            if time.monotonic() >= deadline:
                result['timedOut'] = True
                backend.terminate()
                break
            time.sleep(0.05)
        stop_deadline = time.monotonic() + 30
        while backend.active_processes() != 0 and time.monotonic() < stop_deadline:
            time.sleep(0.05)
        result['treeStopped'] = backend.active_processes() == 0
        if result['treeStopped']:
            result['exitCode'] = backend.exit_code()
    except OSError as error:
        result['errorCode'] = getattr(error, 'winerror', None) or error.errno or 1
        # Fail closed: an exception never proves descendants have stopped.
    finally:
        backend.close()  # kill-on-close, including exceptions; not proof of quiescence
    return result


class WindowsJob:
    def __init__(self, command, cwd, stdout_path, stderr_path):
        if os.name != 'nt':
            raise OSError('Windows job execution unavailable')
        import msvcrt
        self.msvcrt = msvcrt
        self.command, self.cwd = command, str(Path(cwd).resolve())
        self.paths = stdout_path, stderr_path
        self.job = self.process = self.thread = None
        self.files = []
        k = self.k = ctypes.WinDLL('kernel32', use_last_error=True)
        U32, U64, SIZE, PTR = ctypes.c_uint32, ctypes.c_uint64, ctypes.c_size_t, ctypes.c_void_p
        class BASIC_LIMIT(ctypes.Structure):
            _fields_ = [('perProcessTime', ctypes.c_int64), ('perJobTime', ctypes.c_int64), ('flags', U32), ('minWorkingSet', SIZE), ('maxWorkingSet', SIZE), ('activeLimit', U32), ('affinity', SIZE), ('priority', U32), ('scheduling', U32)]
        class IO(ctypes.Structure):
            _fields_ = [(name, U64) for name in ['readOps', 'writeOps', 'otherOps', 'readBytes', 'writeBytes', 'otherBytes']]
        class EXTENDED_LIMIT(ctypes.Structure):
            _fields_ = [('basic', BASIC_LIMIT), ('io', IO), ('processMemory', SIZE), ('jobMemory', SIZE), ('peakProcess', SIZE), ('peakJob', SIZE)]
        class ACCOUNTING(ctypes.Structure):
            _fields_ = [(name, ctypes.c_int64) for name in ['user', 'kernel', 'periodUser', 'periodKernel']] + [(name, U32) for name in ['faults', 'total', 'active', 'terminated']]
        class STARTUP(ctypes.Structure):
            _fields_ = [('cb', U32), ('reserved', ctypes.c_wchar_p), ('desktop', ctypes.c_wchar_p), ('title', ctypes.c_wchar_p)] + [(name, U32) for name in ['x', 'y', 'width', 'height', 'charsX', 'charsY', 'fill', 'flags']] + [('show', ctypes.c_uint16), ('reservedSize', ctypes.c_uint16), ('reservedBytes', PTR), ('stdin', PTR), ('stdout', PTR), ('stderr', PTR)]
        class PROCESS(ctypes.Structure):
            _fields_ = [('process', PTR), ('thread', PTR), ('pid', U32), ('tid', U32)]
        self.Limit, self.Accounting, self.Startup, self.Process = EXTENDED_LIMIT, ACCOUNTING, STARTUP, PROCESS
        signatures = {
            'CreateJobObjectW': ([PTR, ctypes.c_wchar_p], PTR),
            'SetInformationJobObject': ([PTR, ctypes.c_int, PTR, U32], ctypes.c_int),
            'QueryInformationJobObject': ([PTR, ctypes.c_int, PTR, U32, PTR], ctypes.c_int),
            'CreateProcessW': ([ctypes.c_wchar_p, ctypes.c_wchar_p, PTR, PTR, ctypes.c_int, U32, PTR, ctypes.c_wchar_p, PTR, PTR], ctypes.c_int),
            'AssignProcessToJobObject': ([PTR, PTR], ctypes.c_int),
            'ResumeThread': ([PTR], U32),
            'TerminateProcess': ([PTR, U32], ctypes.c_int),
            'TerminateJobObject': ([PTR, U32], ctypes.c_int),
            'WaitForSingleObject': ([PTR, U32], U32),
            'GetExitCodeProcess': ([PTR, ctypes.POINTER(U32)], ctypes.c_int),
            'CloseHandle': ([PTR], ctypes.c_int),
        }
        for name, (args, returns) in signatures.items():
            fn = getattr(k, name); fn.argtypes = args; fn.restype = returns

    def checked(self, value):
        if not value:
            raise ctypes.WinError(ctypes.get_last_error())
        return value

    def start_suspended_assigned(self):
        self.job = self.checked(self.k.CreateJobObjectW(None, None))
        limit = self.Limit(); limit.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        self.checked(self.k.SetInformationJobObject(self.job, 9, ctypes.byref(limit), ctypes.sizeof(limit)))
        for path, mode in [(os.devnull, 'rb'), (self.paths[0], 'wb'), (self.paths[1], 'wb')]:
            self.files.append(open(path, mode))
        handles = [self.msvcrt.get_osfhandle(file.fileno()) for file in self.files]
        for handle in handles:
            os.set_handle_inheritable(handle, True)
        startup = self.Startup(); startup.cb = ctypes.sizeof(startup); startup.flags = 0x100
        startup.stdin, startup.stdout, startup.stderr = handles
        info = self.Process()
        try:
            self.checked(self.k.CreateProcessW(str(self.command[0]), ctypes.create_unicode_buffer(subprocess.list2cmdline(self.command)), None, None, True, 0x4 | 0x08000000, None, self.cwd, ctypes.byref(startup), ctypes.byref(info)))
            self.process, self.thread = info.process, info.thread
        finally:
            for handle in handles:
                os.set_handle_inheritable(handle, False)
        if not self.k.AssignProcessToJobObject(self.job, self.process):
            error = ctypes.get_last_error()
            # Suspended root has never executed or spawned descendants.
            self.k.TerminateProcess(self.process, 1)
            self.k.WaitForSingleObject(self.process, 30000)
            raise ctypes.WinError(error)

    def resume(self):
        if self.k.ResumeThread(self.thread) == 0xFFFFFFFF:
            raise ctypes.WinError(ctypes.get_last_error())

    def active_processes(self):
        info = self.Accounting()
        self.checked(self.k.QueryInformationJobObject(self.job, 1, ctypes.byref(info), ctypes.sizeof(info), None))
        return info.active

    def terminate(self):
        self.checked(self.k.TerminateJobObject(self.job, 124))

    def exit_code(self):
        value = ctypes.c_uint32()
        self.checked(self.k.GetExitCodeProcess(self.process, ctypes.byref(value)))
        return value.value

    def close(self):
        for handle in [self.job, self.thread, self.process]:
            if handle:
                self.k.CloseHandle(handle)
        for file in self.files:
            file.close()
