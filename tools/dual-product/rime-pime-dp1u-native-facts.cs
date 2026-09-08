// Read-only Win32 primitives for the DP1-U native observation adapter.
// No launch, mutation, elevation, or product-code entry points.
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Yime.Dp1UNative {
    public sealed class ProcessLease : IDisposable {
        internal IntPtr Handle;
        public int Pid;
        public string Image;
        public string Sid;
        public long CreationFileTime;
        public int PackageQuery;
        public bool Elevated;
        public void Dispose() { if (Handle != IntPtr.Zero) { Facts.CloseHandle(Handle); Handle = IntPtr.Zero; } }
    }
    public static class Facts {
        [StructLayout(LayoutKind.Sequential)] private struct FileTime { public uint Low, High; }
        [StructLayout(LayoutKind.Sequential)] private struct SystemInfo {
            public ushort Architecture, Reserved; public uint PageSize;
            public IntPtr MinimumAddress, MaximumAddress, ProcessorMask;
            public uint ProcessorCount, ProcessorType, AllocationGranularity;
            public ushort ProcessorLevel, ProcessorRevision;
        }
        [StructLayout(LayoutKind.Sequential)] private struct FileInfo {
            public uint Attributes; public FileTime Creation, Access, Write;
            public uint VolumeSerial, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", SetLastError=true)] private static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll")] internal static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder image, ref int size);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetProcessTimes(IntPtr process, out FileTime creation, out FileTime exit, out FileTime kernel, out FileTime user);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] private static extern int GetPackageFullName(IntPtr process, ref uint size, IntPtr name);
        [DllImport("advapi32.dll", SetLastError=true)] private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError=true)] private static extern bool GetTokenInformation(IntPtr token, int kind, out int value, int size, out int required);
        [DllImport("kernel32.dll")] private static extern void GetNativeSystemInfo(out SystemInfo info);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInfo info);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path, uint size, uint flags);
        public static string Architecture() {
            SystemInfo info; GetNativeSystemInfo(out info);
            return info.Architecture == 9 ? "x64" : info.Architecture == 12 ? "arm64" : "unsupported";
        }
        public static ProcessLease OpenProcessFacts(int pid) {
            var result = new ProcessLease(); result.Pid = pid;
            result.Handle = OpenProcess(0x1000, false, pid);
            if (result.Handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr token = IntPtr.Zero;
            try {
                var image = new StringBuilder(32768); int length = image.Capacity;
                if (!QueryFullProcessImageName(result.Handle, 0, image, ref length)) throw new Win32Exception(Marshal.GetLastWin32Error());
                result.Image = image.ToString();
                FileTime creation, exit, kernel, user;
                if (!GetProcessTimes(result.Handle, out creation, out exit, out kernel, out user)) throw new Win32Exception(Marshal.GetLastWin32Error());
                if (exit.Low != 0 || exit.High != 0) throw new InvalidOperationException("Ancestry process already exited.");
                result.CreationFileTime = ((long)creation.High << 32) | creation.Low;
                uint packageLength = 0;
                result.PackageQuery = GetPackageFullName(result.Handle, ref packageLength, IntPtr.Zero);
                if (!OpenProcessToken(result.Handle, 8, out token)) throw new Win32Exception(Marshal.GetLastWin32Error());
                using (var identity = new WindowsIdentity(token)) result.Sid = identity.User.Value;
                int elevated, required;
                if (!GetTokenInformation(token, 20, out elevated, sizeof(int), out required)) throw new Win32Exception(Marshal.GetLastWin32Error());
                result.Elevated = elevated != 0;
                return result;
            } catch { result.Dispose(); throw; }
            finally { if (token != IntPtr.Zero) CloseHandle(token); }
        }
        public static string VerifyFileHandle(FileStream stream, string expectedPath) {
            FileInfo info;
            if (!GetFileInformationByHandle(stream.SafeFileHandle, out info)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if ((info.Attributes & 0x400) != 0 || info.Links != 1) throw new InvalidOperationException("Indirect or multiply-linked artifact rejected.");
            var path = new StringBuilder(32768);
            uint length = GetFinalPathNameByHandle(stream.SafeFileHandle, path, (uint)path.Capacity, 0);
            if (length == 0 || length >= path.Capacity) throw new Win32Exception(Marshal.GetLastWin32Error());
            string final = path.ToString();
            if (!String.Equals(final, @"\\?\" + expectedPath, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Artifact final path differs from approved path.");
            return info.VolumeSerial.ToString("x8") + ":" + info.IndexHigh.ToString("x8") + info.IndexLow.ToString("x8");
        }
    }
}
