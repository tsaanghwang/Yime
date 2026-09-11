// Own only the suspended child; spawning descendants is prohibited. No image-name/PID lookup,
// shell, breakaway permission, or global process termination is used.
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace Yime.CandidateRegistrationChild {
    public sealed class ChildResult {
        public uint ProcessId;
        public uint ExitCode;
        public bool TimedOut;
        public bool DescendantsTerminated;
        public bool JobEmptyBeforeReturn;
    }
    public static class OwnedChild {
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        private struct StartupInfo {
            public uint Size; public string Reserved, Desktop, Title;
            public uint X, Y, XSize, YSize, XCountChars, YCountChars, FillAttribute, Flags;
            public ushort ShowWindow, Reserved2; public IntPtr Reserved2Pointer, StdInput, StdOutput, StdError;
        }
        [StructLayout(LayoutKind.Sequential)] private struct ProcessInformation { public IntPtr Process, Thread; public uint ProcessId, ThreadId; }
        [StructLayout(LayoutKind.Sequential)] private struct StartupInfoEx { public StartupInfo Startup; public IntPtr Attributes; }
        [StructLayout(LayoutKind.Sequential)] private struct BasicLimits {
            public long PerProcessTime, PerJobTime; public uint Flags;
            public UIntPtr MinimumWorkingSet, MaximumWorkingSet; public uint ActiveProcesses;
            public UIntPtr Affinity; public uint PriorityClass, SchedulingClass;
        }
        [StructLayout(LayoutKind.Sequential)] private struct IoCounters { public ulong ReadOperations, WriteOperations, OtherOperations, ReadBytes, WriteBytes, OtherBytes; }
        [StructLayout(LayoutKind.Sequential)] private struct ExtendedLimits {
            public BasicLimits Basic; public IoCounters Io;
            public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
        }
        [StructLayout(LayoutKind.Sequential)] private struct Accounting {
            public long TotalUser, TotalKernel, PeriodUser, PeriodKernel;
            public uint PageFaults, TotalProcesses, ActiveProcesses, TerminatedProcesses;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimits value, uint length);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool QueryInformationJobObject(IntPtr job, int kind, out Accounting value, uint length, IntPtr returned);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool CreateProcess(string application, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint flags, IntPtr environment, string currentDirectory, ref StartupInfoEx startup, out ProcessInformation process);
        [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool DuplicateHandle(IntPtr sourceProcess, IntPtr sourceHandle, IntPtr targetProcess, out IntPtr targetHandle, uint access, bool inherit, uint options);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returned);
        [DllImport("kernel32.dll")] private static extern void DeleteProcThreadAttributeList(IntPtr list);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetExitCodeProcess(IntPtr process, out uint code);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool TerminateJobObject(IntPtr job, uint code);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool TerminateProcess(IntPtr process, uint code);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool CloseHandle(IntPtr handle);
        private static bool Empty(IntPtr job) {
            Accounting value;
            if (!QueryInformationJobObject(job, 1, out value, (uint)Marshal.SizeOf(typeof(Accounting)), IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return value.ActiveProcesses == 0;
        }
        private static bool WaitForEmptyAfterExit(IntPtr job) {
            // A signaled process handle can precede the job accounting update.
            // Keep every lease and the restrictive job alive while observing it.
            var elapsed = System.Diagnostics.Stopwatch.StartNew();
            do {
                if (Empty(job)) return true;
                if (elapsed.ElapsedMilliseconds >= 1000) return false;
                Thread.Sleep(10);
            } while (true);
        }
        private static void Drain(IntPtr job, IntPtr process, bool assigned) {
            // An uncertain or failed termination never becomes an ordinary error
            // while a child can still mutate registration. Keep the caller and
            // its coordination/file leases alive until kernel exit is observed.
            if (assigned) {
                TerminateJobObject(job, 1460);
                while (true) {
                    try { if (Empty(job)) return; }
                    catch (Win32Exception) { /* Preserve ownership and keep waiting. */ }
                    Thread.Sleep(100);
                }
            }
            if (process != IntPtr.Zero) {
                TerminateProcess(process, 1460);
                while (WaitForSingleObject(process, 100) != 0) { }
            }
        }
        public static ChildResult Run(string path, string arguments, int timeoutMilliseconds, IntPtr coordinationHandle) {
            if (String.IsNullOrEmpty(path) || path.IndexOf('"') >= 0 || !System.IO.Path.IsPathRooted(path) || timeoutMilliseconds < 1 || timeoutMilliseconds > 600000 || coordinationHandle == IntPtr.Zero || coordinationHandle == new IntPtr(-1)) throw new ArgumentException("Literal executable, bounded timeout and retained coordinator handle required.");
            IntPtr job = IntPtr.Zero, inheritedGate = IntPtr.Zero, attributes = IntPtr.Zero, handleList = IntPtr.Zero, jobList = IntPtr.Zero;
            bool attributesReady = false; ProcessInformation process = new ProcessInformation();
            bool assigned = false, drained = false;
            try {
                job = CreateJobObject(IntPtr.Zero, null);
                if (job == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                ExtendedLimits limits = new ExtendedLimits(); limits.Basic.Flags = 0x2008; // KILL_ON_JOB_CLOSE | ACTIVE_PROCESS; no BREAKAWAY_OK.
                // Registrar/probes do not need descendants. Reject their creation
                // so every possible remaining process owns the inherited gate.
                limits.Basic.ActiveProcesses = 1;
                if (!SetInformationJobObject(job, 9, ref limits, (uint)Marshal.SizeOf(typeof(ExtendedLimits)))) throw new Win32Exception(Marshal.GetLastWin32Error());
                // Duplicate only the borrowed fixed coordinator gate, never take
                // ownership of the caller's original handle. An explicit handle
                // list excludes every unrelated handle in the elevated worker.
                IntPtr self = GetCurrentProcess();
                if (!DuplicateHandle(self, coordinationHandle, self, out inheritedGate, 0, true, 2)) throw new Win32Exception(Marshal.GetLastWin32Error());
                IntPtr attributeBytes = IntPtr.Zero;
                InitializeProcThreadAttributeList(IntPtr.Zero, 2, 0, ref attributeBytes);
                if (attributeBytes == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                attributes = Marshal.AllocHGlobal(attributeBytes);
                if (!InitializeProcThreadAttributeList(attributes, 2, 0, ref attributeBytes)) throw new Win32Exception(Marshal.GetLastWin32Error());
                attributesReady = true; handleList = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(handleList, inheritedGate);
                if (!UpdateProcThreadAttribute(attributes, 0, new IntPtr(0x00020002), handleList, new IntPtr(IntPtr.Size), IntPtr.Zero, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
                jobList = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(jobList, job);
                // JOB_LIST assigns the job atomically during CreateProcess, before
                // a worker crash could leave an uncontained suspended child.
                if (!UpdateProcThreadAttribute(attributes, 0, new IntPtr(0x0002000D), jobList, new IntPtr(IntPtr.Size), IntPtr.Zero, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
                StartupInfoEx startup = new StartupInfoEx(); startup.Startup.Size = (uint)Marshal.SizeOf(typeof(StartupInfoEx));
                startup.Startup.Flags = 1; startup.Startup.ShowWindow = 0; startup.Attributes = attributes;
                StringBuilder command = new StringBuilder("\"" + path + "\" " + arguments);
                if (!CreateProcess(path, command, IntPtr.Zero, IntPtr.Zero, true, 0x08080004, IntPtr.Zero, System.IO.Path.GetDirectoryName(path), ref startup, out process)) throw new Win32Exception(Marshal.GetLastWin32Error());
                assigned = true;
                CloseHandle(inheritedGate); inheritedGate = IntPtr.Zero;
                // The child has never run outside the job; worker death closes the
                // job and the child's inherited gate remains until its kernel exit.
                if (ResumeThread(process.Thread) == UInt32.MaxValue) throw new Win32Exception(Marshal.GetLastWin32Error());
                uint wait = WaitForSingleObject(process.Process, (uint)timeoutMilliseconds);
                bool timedOut = wait == 258;
                if (wait != 0 && !timedOut) throw new Win32Exception(Marshal.GetLastWin32Error());
                // Even a successful registrar may not leave a live descendant.
                // Terminate a timed-out job, or any descendant left after its
                // initial process exits, and confirm the entire job is empty.
                bool descendantsTerminated = !timedOut && !WaitForEmptyAfterExit(job);
                if (timedOut || descendantsTerminated) Drain(job, process.Process, true);
                drained = true;
                uint exitCode;
                if (!GetExitCodeProcess(process.Process, out exitCode)) throw new Win32Exception(Marshal.GetLastWin32Error());
                return new ChildResult { ProcessId=process.ProcessId, ExitCode=exitCode, TimedOut=timedOut, DescendantsTerminated=descendantsTerminated, JobEmptyBeforeReturn=true };
            } finally {
                if (!drained && process.Process != IntPtr.Zero) Drain(job, process.Process, assigned);
                if (process.Thread != IntPtr.Zero) CloseHandle(process.Thread);
                if (process.Process != IntPtr.Zero) CloseHandle(process.Process);
                if (job != IntPtr.Zero) CloseHandle(job);
                if (attributesReady) DeleteProcThreadAttributeList(attributes);
                if (attributes != IntPtr.Zero) Marshal.FreeHGlobal(attributes);
                if (handleList != IntPtr.Zero) Marshal.FreeHGlobal(handleList);
                if (jobList != IntPtr.Zero) Marshal.FreeHGlobal(jobList);
                if (inheritedGate != IntPtr.Zero) CloseHandle(inheritedGate);
            }
        }
    }
}
