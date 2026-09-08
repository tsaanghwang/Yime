// Additional read-only handle observations; no process launch/termination APIs.
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace Yime.MaintenanceProcesses {
    public sealed class ProcessObservation {
        public int Pid { get; internal set; }
        public int ParentPid { get; internal set; }
        public long CreationFileTime { get; internal set; }
        public string Image { get; internal set; }
        public ushort ProcessMachine { get; internal set; }
        public ushort NativeMachine { get; internal set; }
    }
    public sealed class ProcessPin : IDisposable {
        private IntPtr handle;
        private readonly int pid;
        private ProcessPin(IntPtr handle, int pid) { this.handle=handle; this.pid=pid; }
        [StructLayout(LayoutKind.Sequential)] private struct FileTime { public uint Low, High; }
        // NTSTATUS and KPRIORITY each occupy a pointer-aligned slot in PBI.
        [StructLayout(LayoutKind.Sequential)] private struct BasicInfo {
            public IntPtr ExitStatus, Peb, Affinity, BasePriority, ProcessId, ParentId;
        }
        [DllImport("kernel32.dll", SetLastError=true)] private static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern uint GetProcessId(IntPtr process);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetProcessTimes(IntPtr process, out FileTime creation, out FileTime exit, out FileTime kernel, out FileTime user);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder image, ref int size);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool IsWow64Process2(IntPtr process, out ushort processMachine, out ushort nativeMachine);
        [DllImport("ntdll.dll")] private static extern int NtQueryInformationProcess(IntPtr process, int infoClass, out BasicInfo info, int length, out int returned);
        public static ProcessPin Open(int pid) {
            if (pid <= 0) throw new ArgumentOutOfRangeException("pid");
            IntPtr handle=OpenProcess(0x00101000, false, pid); // SYNCHRONIZE | QUERY_LIMITED_INFORMATION
            if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            var result=new ProcessPin(handle,pid);
            try { result.Capture(); return result; } catch { result.Dispose(); throw; }
        }
        private void RequireLive() {
            if (handle == IntPtr.Zero) throw new ObjectDisposedException("ProcessPin");
            uint result=WaitForSingleObject(handle,0);
            if (result == 0xffffffff) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (result != 0x102) throw new InvalidOperationException("Pinned process exited or has unknown wait state.");
        }
        public ProcessObservation Capture() {
            RequireLive();
            if (GetProcessId(handle) != (uint)pid) throw new InvalidOperationException("Pinned PID mismatch.");
            FileTime creation, exit, kernel, user;
            if (!GetProcessTimes(handle,out creation,out exit,out kernel,out user)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (exit.Low != 0 || exit.High != 0) throw new InvalidOperationException("Pinned process terminated during capture.");
            var image=new StringBuilder(32768); int length=image.Capacity;
            if (!QueryFullProcessImageName(handle,0,image,ref length)) throw new Win32Exception(Marshal.GetLastWin32Error());
            BasicInfo basic; int returned; int size=Marshal.SizeOf(typeof(BasicInfo));
            int status=NtQueryInformationProcess(handle,0,out basic,size,out returned);
            if (status != 0 || returned != size || basic.ProcessId.ToInt64() != pid || basic.ParentId.ToInt64() <= 0 || basic.ParentId.ToInt64() > Int32.MaxValue)
                throw new InvalidOperationException("Native parent/process identity unavailable.");
            ushort processMachine, nativeMachine;
            if (!IsWow64Process2(handle,out processMachine,out nativeMachine)) throw new Win32Exception(Marshal.GetLastWin32Error());
            RequireLive();
            return new ProcessObservation {Pid=pid,ParentPid=(int)basic.ParentId.ToInt64(),CreationFileTime=((long)creation.High << 32) | creation.Low,
                Image=image.ToString(),ProcessMachine=processMachine,NativeMachine=nativeMachine};
        }
        public void Dispose() { if (handle != IntPtr.Zero) { CloseHandle(handle); handle=IntPtr.Zero; } }
    }
}
