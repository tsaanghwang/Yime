// Shared native-token helper for unpackaged, same-SID maintenance only.
// Callers must reject packaged ancestry BEFORE invoking Start. No ShellExecute,
// Explorer automation, alternate credentials, or elevated fallback is used.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;

namespace YimeCore.LocalMaintenance {
    public sealed class TokenEvidence {
        public string Sid;
        public bool Elevated;
        public int Integrity;
        public int Session;
        public bool AppContainer;
        public int TokenType;
    }

    // Diagnostic snapshot only; never used as authorization or live-state proof.
    public sealed class LaunchAttempt {
        public string Stage;
        public uint TokenAccess;
        public int LogonFlags;
        public TokenEvidence SourceToken;
        public TokenEvidence DuplicatedToken;
        public TokenEvidence ChildToken;
    }

    public static class StandardUserLauncher {
        public const string InitiatorEnvironment = "YIMECORE_MAINTENANCE_INITIATOR";
        // CreateProcessWithTokenW needs these additional rights on its token
        // HANDLE in real de-elevation implementations; 0x000b was insufficient.
        // See Chromium base/win/elevation_util.cc, RunDeElevated. Only the access
        // mask is adopted: we never obtain an Explorer token or enable privileges.
        public const uint PrimaryLaunchAccess = 0x0001 | 0x0002 | 0x0008 | 0x0080 | 0x0100;
        public static LaunchAttempt LastLaunchAttempt { get; private set; }
        public static bool HasRequiredPrimaryLaunchAccess(uint access) {
            return (access & PrimaryLaunchAccess) == PrimaryLaunchAccess;
        }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        struct StartupInfo {
            public int cb;
            public string reserved, desktop, title;
            public int x, y, xSize, ySize, xChars, yChars, fill, flags;
            public short show, reservedBytes;
            public IntPtr reservedPointer, stdin, stdout, stderr;
        }
        [StructLayout(LayoutKind.Sequential)]
        struct ProcessInfo { public IntPtr process, thread; public int pid, tid; }
        [DllImport("advapi32.dll", SetLastError=true)]
        static extern bool GetTokenInformation(IntPtr token, int type, IntPtr data, int bytes, out int returned);
        [DllImport("advapi32.dll", SetLastError=true)]
        static extern bool OpenProcessToken(IntPtr process, int access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError=true)]
        static extern bool DuplicateTokenEx(IntPtr token, uint access, IntPtr attributes, int level, int type, out IntPtr duplicate);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern bool CreateProcessWithTokenW(IntPtr token, int logonFlags, string application,
            StringBuilder command, int creationFlags, IntPtr environment, string directory,
            ref StartupInfo startup, out ProcessInfo process);
        [DllImport("advapi32.dll")]
        static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
        [DllImport("advapi32.dll")]
        static extern IntPtr GetSidSubAuthority(IntPtr sid, uint index);
        [DllImport("userenv.dll", SetLastError=true)]
        static extern bool CreateEnvironmentBlock(out IntPtr environment, IntPtr token, bool inherit);
        [DllImport("userenv.dll")]
        static extern bool DestroyEnvironmentBlock(IntPtr environment);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern IntPtr OpenProcess(int access, bool inherit, int pid);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool GetProcessTimes(IntPtr process, out long created, out long exited, out long kernel, out long user);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder image, ref int length);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
        static extern int GetPackageFullName(IntPtr process, ref uint length, IntPtr name);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool TerminateProcess(IntPtr process, uint exitCode);
        [DllImport("kernel32.dll")]
        static extern bool CloseHandle(IntPtr handle);

        static IntPtr Information(IntPtr token, int type) {
            int bytes;
            GetTokenInformation(token, type, IntPtr.Zero, 0, out bytes);
            if (bytes <= 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetTokenInformation size");
            IntPtr buffer = Marshal.AllocHGlobal(bytes);
            if (!GetTokenInformation(token, type, buffer, bytes, out bytes)) {
                int error = Marshal.GetLastWin32Error(); Marshal.FreeHGlobal(buffer);
                throw new Win32Exception(error, "GetTokenInformation");
            }
            return buffer;
        }
        static int TokenInt(IntPtr token, int type) {
            IntPtr info = Information(token, type);
            try { return Marshal.ReadInt32(info); } finally { Marshal.FreeHGlobal(info); }
        }
        static TokenEvidence Inspect(IntPtr token) {
            TokenEvidence evidence = new TokenEvidence();
            using (WindowsIdentity identity = new WindowsIdentity(token)) { evidence.Sid = identity.User.Value; }
            evidence.Elevated = TokenInt(token, 20) != 0;
            evidence.Session = TokenInt(token, 12);
            evidence.AppContainer = TokenInt(token, 29) != 0;
            evidence.TokenType = TokenInt(token, 8);
            IntPtr info = Information(token, 25);
            try {
                IntPtr sid = Marshal.ReadIntPtr(info);
                byte count = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
                if (count == 0) throw new InvalidOperationException("Integrity SID has no RID");
                evidence.Integrity = Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(count - 1)));
            } finally { Marshal.FreeHGlobal(info); }
            return evidence;
        }
        public static TokenEvidence InspectProcess(int pid) {
            IntPtr process = OpenProcess(0x1000, false, pid);
            if (process == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess token inspection");
            try { return InspectProcessHandle(process); } finally { CloseHandle(process); }
        }
        static TokenEvidence InspectProcessHandle(IntPtr process) {
            IntPtr token;
            if (!OpenProcessToken(process, 8, out token)) throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcessToken");
            try { return Inspect(token); } finally { CloseHandle(token); }
        }
        public static bool IsExpectedStandardToken(TokenEvidence evidence, string sid, int session) {
            return evidence != null && evidence.Sid == sid && !evidence.Elevated &&
                evidence.Integrity >= 0x2000 && evidence.Integrity < 0x3000 &&
                evidence.Session == session && !evidence.AppContainer;
        }
        static void RequireStandard(IntPtr token, string sid, int session) {
            if (!IsExpectedStandardPrimaryToken(Inspect(token), sid, session))
                throw new InvalidOperationException("Expected same-SID, same-session, medium-integrity, non-elevated PRIMARY token");
        }
        public static bool IsExpectedStandardPrimaryToken(TokenEvidence evidence, string sid, int session) {
            return IsExpectedStandardToken(evidence,sid,session) && evidence.TokenType == 1;
        }
        public static bool TryParseInitiatorReference(string reference, out int pid, out long created) {
            pid=0; created=0;
            if (String.IsNullOrEmpty(reference)) return false;
            string[] parts=reference.Split(':');
            return parts.Length == 2 &&
                Int32.TryParse(parts[0],NumberStyles.None,CultureInfo.InvariantCulture,out pid) && pid > 0 &&
                Int64.TryParse(parts[1],NumberStyles.None,CultureInfo.InvariantCulture,out created) && created > 0;
        }
        public static string CaptureInitiatorReference(string targetSid) {
            // Called by the native, non-elevated PowerShell before UAC. That
            // process must remain alive and wait for its elevated worker.
            using (Process process=Process.GetCurrentProcess()) {
                using (WindowsIdentity current=WindowsIdentity.GetCurrent()) {
                    RequireStandard(current.Token,targetSid,process.SessionId);
                }
                return process.Id.ToString(CultureInfo.InvariantCulture)+":"+
                    process.StartTime.ToFileTimeUtc().ToString(CultureInfo.InvariantCulture);
            }
        }
        static IntPtr OpenInitiatorPrimaryToken(string targetSid, int session) {
            int pid; long expectedCreated;
            if (!TryParseInitiatorReference(Environment.GetEnvironmentVariable(InitiatorEnvironment),out pid,out expectedCreated))
                throw new InvalidOperationException("No live standard-user maintenance initiator. Start from a non-administrator, Explorer-launched Windows PowerShell and let maintenance request UAC.");
            // Only the explicitly retained maintenance process, never Explorer
            // or a process selected by name. PID reuse is rejected by FILETIME.
            IntPtr process=OpenProcess(0x101000,false,pid); // query limited + synchronize
            if (process == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"Open maintenance initiator");
            IntPtr token=IntPtr.Zero;
            try {
                long created,exited,kernel,user;
                if (!GetProcessTimes(process,out created,out exited,out kernel,out user))
                    throw new Win32Exception(Marshal.GetLastWin32Error(),"Read maintenance initiator creation time");
                if (created != expectedCreated || WaitForSingleObject(process,0) != 258)
                    throw new InvalidOperationException("Maintenance initiator exited or its PID was reused");
                StringBuilder image=new StringBuilder(32768); int length=image.Capacity;
                if (!QueryFullProcessImageName(process,0,image,ref length))
                    throw new Win32Exception(Marshal.GetLastWin32Error(),"Read maintenance initiator image");
                string expected=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell\\v1.0\\powershell.exe");
                if (!String.Equals(image.ToString(),expected,StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Initiator must be native Windows PowerShell, not another application");
                uint packageLength=0;
                if (GetPackageFullName(process,ref packageLength,IntPtr.Zero) != 15700)
                    throw new InvalidOperationException("Packaged maintenance initiator rejected");
                if (!OpenProcessToken(process,0x000a,out token)) // query + duplicate
                    throw new Win32Exception(Marshal.GetLastWin32Error(),"Open maintenance initiator primary token");
                RequireStandard(token,targetSid,session);
                IntPtr result=token; token=IntPtr.Zero; return result;
            } finally {
                if(token != IntPtr.Zero) CloseHandle(token);
                CloseHandle(process);
            }
        }
        public static TokenEvidence ValidateLaunchToken(string targetSid) {
            using (WindowsIdentity current = WindowsIdentity.GetCurrent()) {
                int session = Process.GetCurrentProcess().SessionId;
                TokenEvidence caller = Inspect(current.Token);
                if (caller.Sid != targetSid || caller.AppContainer) throw new InvalidOperationException("Invalid maintenance caller token");
                if (!caller.Elevated) { RequireStandard(current.Token,targetSid,session); return caller; }
                IntPtr initiator=OpenInitiatorPrimaryToken(targetSid,session);
                try { return Inspect(initiator); } finally { CloseHandle(initiator); }
            }
        }
        public static Process Start(string executable, string arguments, string directory, string targetSid) {
            LaunchAttempt attempt=new LaunchAttempt();
            attempt.Stage="validate-caller";
            LastLaunchAttempt=attempt;
            if (!System.IO.Path.IsPathRooted(executable) || !System.IO.Path.IsPathRooted(directory) ||
                executable.IndexOf('"') >= 0) throw new ArgumentException("Explicit executable and directory required");
            using (WindowsIdentity current = WindowsIdentity.GetCurrent()) {
                int session = Process.GetCurrentProcess().SessionId;
                if (current.User.Value != targetSid) throw new InvalidOperationException("Initiating SID mismatch");
                TokenEvidence caller = Inspect(current.Token);
                if (caller.AppContainer) throw new InvalidOperationException("Packaged token is not a maintenance launcher");
                if (!caller.Elevated) {
                    RequireStandard(current.Token, targetSid, session);
                    attempt.SourceToken=caller;
                    attempt.Stage="create-current-user-process";
                    ProcessStartInfo start = new ProcessStartInfo(executable, arguments);
                    start.WorkingDirectory=directory; start.UseShellExecute=false;
                    start.CreateNoWindow=true; start.WindowStyle=ProcessWindowStyle.Hidden;
                    Process child = Process.Start(start);
                        try {
                            attempt.ChildToken=InspectProcessHandle(child.Handle);
                            if (!IsExpectedStandardPrimaryToken(attempt.ChildToken, targetSid, session))
                                throw new InvalidOperationException("Child token did not remain standard");
                            attempt.Stage="started-current-user-process";
                            return child;
                        } catch {
                            if (!child.HasExited) child.Kill();
                            child.Dispose();
                            throw;
                        }
                }
                IntPtr initiator = IntPtr.Zero, primary = IntPtr.Zero, environment = IntPtr.Zero;
                ProcessInfo created = new ProcessInfo();
                Process retained = null;
                bool resumed = false;
                try {
                    // TokenLinkedToken can be identification-only (1346 in the
                    // actual native acceptance). Never use it as launch authority.
                    attempt.Stage="open-initiator-primary";
                    initiator=OpenInitiatorPrimaryToken(targetSid,session);
                    attempt.SourceToken=Inspect(initiator);
                    attempt.Stage="duplicate-primary";
                    attempt.TokenAccess=PrimaryLaunchAccess;
                    if (!DuplicateTokenEx(initiator, PrimaryLaunchAccess, IntPtr.Zero, 2, 1, out primary))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Duplicate maintenance initiator primary token");
                    RequireStandard(primary,targetSid,session);
                    attempt.DuplicatedToken=Inspect(primary);
                    attempt.Stage="create-user-environment";
                    if (!CreateEnvironmentBlock(out environment, primary, false))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Create user environment");
                    StartupInfo startup = new StartupInfo();
                    startup.cb=Marshal.SizeOf(typeof(StartupInfo)); startup.flags=1; startup.show=0;
                    StringBuilder command = new StringBuilder("\"" + executable + "\" " + arguments);
                    if (command.Length >= 1024) throw new ArgumentException("Runtime command exceeds token-launch limit");
                    // Create suspended so token validation occurs before user code.
                    attempt.Stage="create-process-with-token";
                    attempt.LogonFlags=1;
                    if (!CreateProcessWithTokenW(primary, 1, executable, command, 0x08000404,
                            environment, directory, ref startup, out created))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Create standard-user runtime; no elevated fallback");
                    attempt.Stage="validate-suspended-child";
                    attempt.ChildToken=InspectProcessHandle(created.process);
                    if (!IsExpectedStandardPrimaryToken(attempt.ChildToken, targetSid, session))
                        throw new InvalidOperationException("New runtime token did not match initiating standard user");
                    // Retain the real child handle before it can exit/reuse a PID.
                    retained=Process.GetProcessById(created.pid);
                    IntPtr retainedHandle=retained.Handle;
                    attempt.Stage="resume-standard-child";
                    if (ResumeThread(created.thread) == 0xffffffff)
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Resume standard-user runtime");
                    resumed=true;
                    attempt.Stage="started-standard-child";
                    return retained;
                } finally {
                    if (created.process != IntPtr.Zero && !resumed) TerminateProcess(created.process, 1);
                    if (retained != null && !resumed) retained.Dispose();
                    if (created.thread != IntPtr.Zero) CloseHandle(created.thread);
                    if (created.process != IntPtr.Zero) CloseHandle(created.process);
                    if (environment != IntPtr.Zero) DestroyEnvironmentBlock(environment);
                    if (primary != IntPtr.Zero) CloseHandle(primary);
                    if (initiator != IntPtr.Zero) CloseHandle(initiator);
                }
            }
        }
    }
}
