using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace Yime.Maintenance {
    public sealed class ApplicationUse {
        public int Pid;
        public long StartFileTime;
        public string Name;
        public uint Type;
    }
    public static class ResourceUse {
        [StructLayout(LayoutKind.Sequential)] struct UniqueProcess {
            public int Pid;
            public System.Runtime.InteropServices.ComTypes.FILETIME Start;
        }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct ProcessInfo {
            public UniqueProcess Process;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string Service;
            public uint Type, Status, Session;
            [MarshalAs(UnmanagedType.Bool)] public bool Restartable;
        }
        [DllImport("rstrtmgr.dll", CharSet=CharSet.Unicode)] static extern int RmStartSession(out uint handle, int flags, StringBuilder key);
        [DllImport("rstrtmgr.dll")] static extern int RmEndSession(uint handle);
        [DllImport("rstrtmgr.dll", CharSet=CharSet.Unicode)] static extern int RmRegisterResources(uint handle, uint count, string[] files, uint apps, IntPtr processes, uint services, IntPtr names);
        [DllImport("rstrtmgr.dll")] static extern int RmGetList(uint handle, out uint needed, ref uint count, [In, Out] ProcessInfo[] list, ref uint reason);
        // No RmShutdown/RmRestart or process termination: users close their apps.
        public static ApplicationUse[] Applications(string[] paths) {
            if(paths.Length == 0) return new ApplicationUse[0];
            uint session;
            int code = RmStartSession(out session, 0, new StringBuilder(33));
            if(code != 0) throw new Win32Exception(code, "Restart Manager session failed");
            try {
                code = RmRegisterResources(session, (uint)paths.Length, paths, 0, IntPtr.Zero, 0, IntPtr.Zero);
                if(code != 0) throw new Win32Exception(code, "Resource registration failed");
                uint count=0, needed=0, reason=0;
                ProcessInfo[] list=null;
                for(int attempt=0; attempt<4; attempt++) {
                    code=RmGetList(session, out needed, ref count, list, ref reason);
                    if(code == 0) {
                        var result=new List<ApplicationUse>();
                        for(int i=0; i<count; i++) result.Add(new ApplicationUse {
                            Pid=list[i].Process.Pid, Name=list[i].Name, Type=list[i].Type,
                            StartFileTime=((long)(uint)list[i].Process.Start.dwHighDateTime << 32) | (uint)list[i].Process.Start.dwLowDateTime
                        });
                        // A reboot-only resource cannot be declared clear from an empty list.
                        if(reason != 0 && result.Count == 0) throw new InvalidOperationException("Windows reports a resource requiring a later session; cancel maintenance.");
                        return result.ToArray();
                    }
                    if(code != 234) throw new Win32Exception(code, "Resource application query failed");
                    count=needed; list=new ProcessInfo[count];
                }
                throw new IOException("Application list changed repeatedly; check again.");
            } finally { RmEndSession(session); }
        }
        // Open existing bytes without writing, truncating, renaming or marking deletion.
        // Exclusive write admission also detects mapped private-font files.
        public static int Probe(string path) {
            try { using(var stream=new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None)) {} return 0; }
            catch(IOException e) { return e.HResult & 0xffff; }
            catch(UnauthorizedAccessException e) { return e.HResult & 0xffff; }
        }
    }
}
