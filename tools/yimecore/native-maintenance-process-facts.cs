// Additional read-only handle observations; no process launch/termination APIs.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

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
        private readonly bool ownsHandle;
        private readonly Process source;
        private readonly SafeProcessHandle sourceHandle;
        private readonly long referenceCreation;
        private ProcessPin(IntPtr handle, int pid) { this.handle=handle; this.pid=pid; ownsHandle=true; }
        private ProcessPin(Process source) {
            if (source == null || source.GetType() != typeof(Process)) throw new ArgumentException("Original exact Process instance required.");
            this.source=source;sourceHandle=source.SafeHandle;
            try {
                bool referenceHeld=false;
                try {
                    if (sourceHandle.IsClosed || sourceHandle.IsInvalid) throw new InvalidOperationException("Original Process handle is closed.");
                    sourceHandle.DangerousAddRef(ref referenceHeld);
                    IntPtr original=sourceHandle.DangerousGetHandle();
                    if (original == IntPtr.Zero || original == new IntPtr(-1)) throw new InvalidOperationException("Invalid original Process handle.");
                    // Duplicate THIS kernel object, with only query/synchronize
                    // rights. No PID lookup or handle-reopening fallback.
                    IntPtr current=GetCurrentProcess();
                    if (!DuplicateHandle(current,original,current,out handle,0x00101000,false,0)) throw new Win32Exception(Marshal.GetLastWin32Error());
                    ownsHandle=true;
                } finally { if (referenceHeld) sourceHandle.DangerousRelease(); }
                // Do not retain DangerousAddRef for the lease interval: doing
                // so can hide caller Dispose from SafeHandle.IsClosed.
                uint originalPid=GetProcessId(handle);
                if (originalPid == 0 || originalPid > Int32.MaxValue) throw new Win32Exception(Marshal.GetLastWin32Error());
                pid=(int)originalPid;
                referenceCreation=Capture().CreationFileTime;
                Capture();
            } catch { Dispose();throw; }
        }
        [StructLayout(LayoutKind.Sequential)] private struct FileTime { public uint Low, High; }
        // NTSTATUS and KPRIORITY each occupy a pointer-aligned slot in PBI.
        [StructLayout(LayoutKind.Sequential)] private struct BasicInfo {
            public IntPtr ExitStatus, Peb, Affinity, BasePriority, ProcessId, ParentId;
        }
        [DllImport("kernel32.dll", SetLastError=true)] private static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool DuplicateHandle(IntPtr sourceProcess, IntPtr sourceHandle, IntPtr targetProcess, out IntPtr targetHandle, uint access, bool inherit, uint options);
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
        // Bind the supplied reference and a private duplicate of its original
        // SafeHandle. Never replace it by opening the same numeric PID again.
        public static ProcessPin OpenReference(Process source) { return new ProcessPin(source); }
        private void RequireAssociation() {
            if (source == null) return;
            if (sourceHandle.IsClosed || sourceHandle.IsInvalid || source.Id != pid || !Object.ReferenceEquals(source.SafeHandle,sourceHandle))
                throw new InvalidOperationException("Original Process reference association changed.");
        }
        private void RequireLive() {
            if (handle == IntPtr.Zero) throw new ObjectDisposedException("ProcessPin");
            uint result=WaitForSingleObject(handle,0);
            if (result == 0xffffffff) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (result != 0x102) throw new InvalidOperationException("Pinned process exited or has unknown wait state.");
        }
        public ProcessObservation Capture() {
            RequireLive();
            RequireAssociation();
            if (GetProcessId(handle) != (uint)pid) throw new InvalidOperationException("Pinned PID mismatch.");
            FileTime creation, exit, kernel, user;
            if (!GetProcessTimes(handle,out creation,out exit,out kernel,out user)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (exit.Low != 0 || exit.High != 0) throw new InvalidOperationException("Pinned process terminated during capture.");
            long observedCreation=((long)creation.High << 32) | creation.Low;
            if (observedCreation <= 0 || (referenceCreation != 0 && observedCreation != referenceCreation) ||
                (source != null && source.StartTime.ToUniversalTime().ToFileTimeUtc() != observedCreation))
                throw new InvalidOperationException("Original Process creation identity changed.");
            var image=new StringBuilder(32768); int length=image.Capacity;
            if (!QueryFullProcessImageName(handle,0,image,ref length)) throw new Win32Exception(Marshal.GetLastWin32Error());
            BasicInfo basic; int returned; int size=Marshal.SizeOf(typeof(BasicInfo));
            int status=NtQueryInformationProcess(handle,0,out basic,size,out returned);
            if (status != 0 || returned != size || basic.ProcessId.ToInt64() != pid || basic.ParentId.ToInt64() <= 0 || basic.ParentId.ToInt64() > Int32.MaxValue)
                throw new InvalidOperationException("Native parent/process identity unavailable.");
            ushort processMachine, nativeMachine;
            if (!IsWow64Process2(handle,out processMachine,out nativeMachine)) throw new Win32Exception(Marshal.GetLastWin32Error());
            RequireAssociation();
            RequireLive();
            return new ProcessObservation {Pid=pid,ParentPid=(int)basic.ParentId.ToInt64(),CreationFileTime=observedCreation,
                Image=image.ToString(),ProcessMachine=processMachine,NativeMachine=nativeMachine};
        }
        public void Dispose() {
            IntPtr old=handle;handle=IntPtr.Zero;
            if (ownsHandle && old != IntPtr.Zero) CloseHandle(old);
        }
    }
}
