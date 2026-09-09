using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace Yime.CandidateCoordinator {
    // This is a cooperative cross-process lifetime gate, not caller authentication.
    // No Wait/Release operation changes the semaphore count. The kernel removes
    // its name only after the parent and every delegated worker close their handles.
    public sealed class LifetimeGate : IDisposable {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern SafeWaitHandle CreateSemaphoreW(IntPtr security, int initial, int maximum, string name);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern SafeWaitHandle OpenSemaphoreW(uint access, bool inherit, string name);
        [DllImport("kernel32.dll", SetLastError=true)] static extern SafeWaitHandle OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(SafeWaitHandle process, out long created, out long exited, out long kernel, out long user);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(SafeWaitHandle handle, uint milliseconds);
        [DllImport("kernel32.dll")] static extern int GetCurrentProcessId();
        [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(SafeWaitHandle process, uint access, out SafeWaitHandle token);
        SafeWaitHandle gate, delegation, parent;
        bool closed;
        public int ParentPid { get; private set; }
        public long ParentCreationFileTime { get; private set; }
        public string TargetUserSid { get; private set; }
        public string DelegationToken { get; private set; }
        public bool IsWorker { get; private set; }
        public bool Closed { get { return closed; } }
        public IntPtr BorrowGateHandle() { if(closed || gate==null || gate.IsInvalid) throw new ObjectDisposedException("LifetimeGate"); return gate.DangerousGetHandle(); }
        static string ScopeName(string scope) {
            if (scope != "product" && !Regex.IsMatch(scope ?? "", "^fixture-[0-9a-f]{32}$")) throw new ArgumentException("Unsupported coordinator scope.");
            return "Global\\Yime.RimePime.CandidateMaintenance.v1." + scope;
        }
        static SafeWaitHandle CreateUnique(string name) {
            SafeWaitHandle h = CreateSemaphoreW(IntPtr.Zero, 0, 1, name);
            int error = Marshal.GetLastWin32Error();
            if (h.IsInvalid) { h.Dispose(); throw new Win32Exception(error, "Cannot create candidate lifetime gate."); }
            if (error == 183) { h.Dispose(); throw new InvalidOperationException("Candidate maintenance or a delegated worker is already active."); }
            return h;
        }
        static SafeWaitHandle OpenRequired(string name) {
            SafeWaitHandle h = OpenSemaphoreW(0x00100000, false, name);
            if (h.IsInvalid) { int error=Marshal.GetLastWin32Error(); h.Dispose(); throw new Win32Exception(error, "Candidate delegation is no longer active."); }
            return h;
        }
        static SafeWaitHandle OpenIdentity(int pid) {
            SafeWaitHandle p = OpenProcess(0x00101000, false, pid);
            if (p.IsInvalid) { int error=Marshal.GetLastWin32Error(); p.Dispose(); throw new Win32Exception(error, "Cannot pin candidate parent."); }
            return p;
        }
        static long Creation(SafeWaitHandle process) {
            long created,exited,kernel,user;
            if (!GetProcessTimes(process,out created,out exited,out kernel,out user)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return created;
        }
        static string Sid(SafeWaitHandle process) {
            SafeWaitHandle token;
            if (!OpenProcessToken(process,8,out token)) throw new Win32Exception(Marshal.GetLastWin32Error());
            using(token) using(WindowsIdentity identity = new WindowsIdentity(token.DangerousGetHandle())) return identity.User.Value;
        }
        public static LifetimeGate OpenParent(string scope) {
            LifetimeGate result = new LifetimeGate();
            try {
                string name=ScopeName(scope);
                result.gate=CreateUnique(name);
                result.ParentPid=GetCurrentProcessId();
                result.parent=OpenIdentity(result.ParentPid);
                result.ParentCreationFileTime=Creation(result.parent);
                result.TargetUserSid=Sid(result.parent);
                result.DelegationToken=Guid.NewGuid().ToString("N");
                result.delegation=CreateUnique(name+".Delegate."+result.DelegationToken);
                return result;
            } catch { result.Dispose(); throw; }
        }
        public static LifetimeGate JoinWorker(string scope,int parentPid,long creation,string sid,string token) {
            if(parentPid<=0 || creation<=0 || !Regex.IsMatch(token ?? "","^[0-9a-f]{32}$") || string.IsNullOrEmpty(sid)) throw new ArgumentException("Invalid coordinator delegation.");
            LifetimeGate result=new LifetimeGate();
            try {
                string name=ScopeName(scope);
                // Pin both named objects before checking liveness. If the parent
                // dies after this point, these handles continue to exclude others.
                result.gate=OpenRequired(name);
                result.delegation=OpenRequired(name+".Delegate."+token);
                result.parent=OpenIdentity(parentPid);
                if(WaitForSingleObject(result.parent,0)!=258 || Creation(result.parent)!=creation || Sid(result.parent)!=sid) throw new InvalidOperationException("Candidate parent identity/liveness differs from delegation.");
                using(SafeWaitHandle self=OpenIdentity(GetCurrentProcessId())) if(Sid(self)!=sid) throw new InvalidOperationException("Candidate worker SID differs from parent.");
                result.ParentPid=parentPid;result.ParentCreationFileTime=creation;result.TargetUserSid=sid;result.DelegationToken=token;result.IsWorker=true;
                return result;
            } catch { result.Dispose(); throw; }
        }
        public void Dispose() {
            if(closed)return;closed=true;
            if(parent!=null)parent.Dispose();
            if(delegation!=null)delegation.Dispose();
            if(gate!=null)gate.Dispose();
        }
    }
}
