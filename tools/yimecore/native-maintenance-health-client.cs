using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace Yime.MaintenanceHealth {
    public sealed class Reply {
        public string Role;
        public string PipeName;
        public int ProcessId;
        public long CreationFileTime;
        public bool HealthServiceResponsive;
        public bool NonceVerified;
        public bool PipeServerIdentityBound;
    }

    public static class Client {
        const int BudgetMilliseconds = 1000;
        const uint StillRunning = 258;
        static int outstandingIo;
        public static int OutstandingIo { get { return Interlocked.CompareExchange(ref outstandingIo, 0, 0); } }
        [DllImport("kernel32.dll", SetLastError=true)] static extern SafeFileHandle OpenProcess(uint access, bool inherit, uint pid);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(SafeFileHandle process, out long creation, out long exit, out long kernel, out long user);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(SafeFileHandle handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out uint pid);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool CancelIoEx(SafePipeHandle file, IntPtr overlapped);

        static int Remaining(Stopwatch clock) {
            long remaining = BudgetMilliseconds - clock.ElapsedMilliseconds;
            if (remaining <= 0) throw new TimeoutException("Health pair protocol deadline exceeded");
            return (int)remaining;
        }
        static void CheckProcess(SafeFileHandle process, long expected) {
            if (WaitForSingleObject(process, 0) != StillRunning) throw new InvalidOperationException("Observed health process is no longer alive");
            long creation, exit, kernel, user;
            if (!GetProcessTimes(process, out creation, out exit, out kernel, out user)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (creation != expected) throw new InvalidOperationException("Health process creation identity differs");
        }
        static void CheckServerPid(NamedPipeClientStream pipe, int pid) {
            uint server;
            if (!GetNamedPipeServerProcessId(pipe.SafePipeHandle, out server)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (server != (uint)pid) throw new InvalidOperationException("Health pipe belongs to another process");
        }
        static void CheckServer(NamedPipeClientStream pipe, SafeFileHandle process, int pid, long creation) {
            CheckServerPid(pipe, pid);
            CheckProcess(process, creation);
        }
        static uint U32(byte[] b, int offset) {
            return (uint)b[offset] | ((uint)b[offset+1] << 8) | ((uint)b[offset+2] << 16) | ((uint)b[offset+3] << 24);
        }
        static ulong U64(byte[] b, int offset) { return U32(b, offset) | ((ulong)U32(b, offset+4) << 32); }
        static void Put32(byte[] b, int offset, uint value) { for (int i=0; i<4; i++) b[offset+i]=(byte)(value >> (8*i)); }
        static bool Equal(byte[] a, int ao, byte[] b, int bo, int count) {
            int difference=0; for(int i=0; i<count; i++) difference |= a[ao+i] ^ b[bo+i]; return difference == 0;
        }
        static byte[] Request(uint role) {
            byte[] request=new byte[48];
            Buffer.BlockCopy(Encoding.ASCII.GetBytes("YIMEH01\0"), 0, request, 0, 8);
            Put32(request, 8, role);
            byte[] nonce=new byte[32];
            using (RandomNumberGenerator rng=RandomNumberGenerator.Create()) {
                rng.GetBytes(nonce); bool nonzero=false;
                foreach(byte value in nonce) nonzero |= value != 0;
                if (!nonzero) throw new InvalidOperationException("Fresh health nonce is all zero");
            }
            Buffer.BlockCopy(nonce, 0, request, 16, 32);
            return request;
        }
        sealed class Exchange : IDisposable {
            public readonly NamedPipeClientStream Pipe;
            Task pending;
            public Exchange(string name) {
                Pipe=new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous, TokenImpersonationLevel.Identification);
            }
            public void Await(Task task, Stopwatch clock) {
                if (pending != null) throw new InvalidOperationException("Overlapping health IO rejected");
                pending=task; Interlocked.Increment(ref outstandingIo);
                try {
                    if (!task.Wait(Remaining(clock))) throw new TimeoutException("Health pair protocol deadline exceeded");
                    task.GetAwaiter().GetResult();
                } finally {
                    if (task.IsCompleted) { pending=null; Interlocked.Decrement(ref outstandingIo); }
                }
            }
            public void Dispose() {
                try {
                    // The protocol deadline forbids further IO. Close/cancel then
                    // drain the already issued async operation before returning.
                    // OS cancellation cleanup is not a hard real-time guarantee.
                    if (pending != null && !pending.IsCompleted && Pipe.IsConnected) CancelIoEx(Pipe.SafePipeHandle, IntPtr.Zero);
                } finally {
                    try { Pipe.Dispose(); }
                    finally {
                        if (pending != null) {
                            try { pending.GetAwaiter().GetResult(); } catch { }
                            finally { pending=null; Interlocked.Decrement(ref outstandingIo); }
                        }
                    }
                }
            }
        }
        static Reply Probe(string name, uint role, int pid, long creation, int brokerPid, long brokerCreation, Stopwatch clock) {
            using (Exchange exchange=new Exchange(name)) {
                exchange.Pipe.Connect(Remaining(clock));
                CheckServerPid(exchange.Pipe, pid);
                using (SafeFileHandle process=OpenProcess(0x00101000, false, (uint)pid)) {
                    if (process.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                    CheckServer(exchange.Pipe, process, pid, creation);
                    byte[] request=Request(role);
                    Remaining(clock);
                    exchange.Await(exchange.Pipe.WriteAsync(request, 0, request.Length), clock);
                    byte[] response=new byte[80]; int filled=0;
                    while (filled < response.Length) {
                        Remaining(clock);
                        Task<int> read=exchange.Pipe.ReadAsync(response, filled, response.Length-filled);
                        exchange.Await(read, clock);
                        int count=read.GetAwaiter().GetResult();
                        if (count == 0) throw new InvalidDataException("Short health response");
                        filled+=count;
                    }
                    byte[] trailing=new byte[1];
                    Remaining(clock);
                    Task<int> eof=exchange.Pipe.ReadAsync(trailing, 0, 1);
                    exchange.Await(eof, clock);
                    if (eof.GetAwaiter().GetResult() != 0) throw new InvalidDataException("Extra health response bytes");
                    CheckServer(exchange.Pipe, process, pid, creation);
                    Remaining(clock);
                    if (!Equal(response,0,Encoding.ASCII.GetBytes("YIMER01\0"),0,8) || U32(response,8)!=role || U32(response,12)!=1 ||
                        !Equal(response,16,request,16,32) || U32(response,48)!=(uint)pid || U32(response,52)!=(uint)brokerPid ||
                        U64(response,56)!=(ulong)creation || U64(response,64)!=(ulong)brokerCreation || U64(response,72)!=0)
                        throw new InvalidDataException("Health response does not bind the serving process and fresh nonce");
                    return new Reply {Role=role==1?"broker":"runtime", PipeName=@"\\.\pipe\"+name, ProcessId=pid, CreationFileTime=creation,
                        HealthServiceResponsive=true, NonceVerified=true, PipeServerIdentityBound=true};
                }
            }
        }
        public static Reply[] ProbePair(string brokerPipe, int runtimePid, long runtimeCreation, int brokerPid, long brokerCreation) {
            if (brokerPipe==null || brokerPipe.Length-9+18>128 || !Regex.IsMatch(brokerPipe,@"\A\\\\\.\\pipe\\[A-Za-z0-9][A-Za-z0-9._-]*\z"))
                throw new ArgumentException("Canonical bounded local broker pipe required");
            if (runtimePid<=0 || brokerPid<=0 || runtimeCreation<=0 || brokerCreation<=0) throw new ArgumentException("Positive observed process identities required");
            Stopwatch clock=Stopwatch.StartNew();
            string leaf=brokerPipe.Substring(9);
            Reply broker=Probe(leaf+".health-v1",1,brokerPid,brokerCreation,0,0,clock);
            Reply runtime=Probe(leaf+".runtime-health-v1",2,runtimePid,runtimeCreation,brokerPid,brokerCreation,clock);
            return new Reply[] { broker, runtime };
        }
    }
}
