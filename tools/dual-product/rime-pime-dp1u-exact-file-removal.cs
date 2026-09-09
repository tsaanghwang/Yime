// Source-owned, handle-bound regular-file deletion. No path-based delete fallback.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Yime.Dp1UExactRemoval {
    public sealed class ExpectedFile {
        public readonly string Path, Sha256, FileId;
        public readonly long Bytes;
        public ExpectedFile(string path, long bytes, string sha256, string fileId) {
            Path = path; Bytes = bytes; Sha256 = sha256; FileId = fileId;
        }
    }
    public sealed class FileObservation {
        public readonly string FileId, Sha256;
        public readonly long Bytes;
        internal FileObservation(string id, long bytes, string hash) { FileId=id; Bytes=bytes; Sha256=hash; }
    }
    public sealed class LeafOutcome {
        public readonly string Path, Status;
        public readonly bool MarkedForDeletion, Removed;
        public readonly int ErrorCode;
        internal LeafOutcome(string path, string status, bool marked, bool removed, int error) {
            Path=path; Status=status; MarkedForDeletion=marked; Removed=removed; ErrorCode=error;
        }
    }
    public sealed class RemovalContext : IDisposable {
        private sealed class DirectoryPin {
            internal readonly string Path, Id;
            internal readonly SafeFileHandle Handle;
            internal DirectoryPin(string path, SafeFileHandle handle, string id) { Path=path; Handle=handle; Id=id; }
        }
        private sealed class LeafPin {
            internal readonly string Path;
            internal readonly ExpectedFile Expected;
            internal readonly FileStream Stream;
            internal LeafPin(string path, ExpectedFile expected, FileStream stream) { Path=path; Expected=expected; Stream=stream; }
        }
        private readonly List<DirectoryPin> directories = new List<DirectoryPin>();
        private readonly List<LeafPin> leaves = new List<LeafPin>();
        private bool disposed, consumed;
        public readonly string Root;
        public int Count { get { return leaves.Count; } }
        private RemovalContext(string root) { Root=root; }
        public static RemovalContext Open(string root, ExpectedFile[] expected) {
            Native.CanonicalPath(root);
            if(expected==null || expected.Length==0 || expected.Length>4096) throw new InvalidOperationException("Expected file set is empty or too large.");
            var context=new RemovalContext(root);
            try {
                var pinned=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                context.PinParents(root,pinned);
                var paths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach(var item in expected) {
                    if(item==null) throw new InvalidOperationException("Missing expected file.");
                    Native.RelativePath(item.Path);
                    if(!paths.Add(item.Path) || item.Bytes<0 || !Native.IsHash(item.Sha256) || !Native.IsId(item.FileId))
                        throw new InvalidOperationException("Invalid or duplicate expected file identity.");
                    string path=System.IO.Path.Combine(root,item.Path);
                    Native.CanonicalPath(path);
                    if(!path.StartsWith(root+"\\",StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Leaf escapes root.");
                    context.PinParents(System.IO.Path.GetDirectoryName(path),pinned);
                    var handle=Native.OpenFile(path,true);
                    FileStream stream=null;
                    try {
                        stream=new FileStream(handle,FileAccess.Read);
                        var leaf=new LeafPin(path,item,stream);
                        context.ValidateLeaf(leaf);
                        context.leaves.Add(leaf); stream=null; handle=null;
                    } finally { if(stream!=null)stream.Dispose(); if(handle!=null)handle.Dispose(); }
                }
                context.ValidateAll();
                return context;
            } catch { context.Dispose(); throw; }
        }
        private void PinParents(string path, HashSet<string> pinned) {
            var pending=new Stack<string>();
            for(string cursor=path;cursor!=null;cursor=System.IO.Path.GetDirectoryName(cursor))
                if(!pinned.Contains(cursor))pending.Push(cursor);
            while(pending.Count>0) {
                string next=pending.Pop(); var handle=Native.OpenDirectory(next);
                try {
                    string id=Native.Verify(handle,next,true);
                    Native.RejectNamedStreams(next);
                    directories.Add(new DirectoryPin(next,handle,id));pinned.Add(next);handle=null;
                } finally { if(handle!=null)handle.Dispose(); }
            }
        }
        private void RequireActive() {
            if(disposed || consumed) throw new InvalidOperationException("Removal context is disposed or already consumed.");
        }
        private void ValidateLeaf(LeafPin leaf) {
            var record=Native.Observe(leaf.Stream,leaf.Path);
            if(record.FileId!=leaf.Expected.FileId || record.Bytes!=leaf.Expected.Bytes || record.Sha256!=leaf.Expected.Sha256)
                throw new InvalidOperationException("Approved leaf identity/size/hash mismatch: "+leaf.Expected.Path);
        }
        public void ValidateAll() {
            RequireActive();
            foreach(var directory in directories) {
                if(Native.Verify(directory.Handle,directory.Path,true)!=directory.Id) throw new InvalidOperationException("Directory identity changed.");
                Native.RejectNamedStreams(directory.Path);
            }
            foreach(var leaf in leaves)ValidateLeaf(leaf);
        }
        public LeafOutcome[] Remove() {
            ValidateAll(); // Entire set is rechecked before the first mutation.
            consumed=true;
            var outcomes=new List<LeafOutcome>();
            try {
                foreach(var leaf in leaves) {
                    bool marked=false;int error=0;
                    try {
                        // Use the same open object; no reopen by path between validation and deletion.
                        ValidateLeaf(leaf);
                        Native.MarkDelete(leaf.Stream.SafeFileHandle);marked=true;
                    } catch(Win32Exception ex) { error=ex.NativeErrorCode; }
                    catch { error=-1; }
                    finally { leaf.Stream.Dispose(); }
                    int statusError=0;
                    string status=marked ? Native.ClosedLeafStatus(leaf.Path,out statusError) : "preserved-error";
                    if(!marked)statusError=error;
                    outcomes.Add(new LeafOutcome(leaf.Expected.Path,status,marked,status=="removed",statusError));
                    if(!marked || status!="removed") break; // Preserve all later members on an incomplete operation.
                }
                for(int i=outcomes.Count;i<leaves.Count;i++)outcomes.Add(new LeafOutcome(leaves[i].Expected.Path,"not-attempted",false,false,0));
                return outcomes.ToArray();
            } finally { Dispose(); }
        }
        public void Dispose() {
            if(disposed)return;
            disposed=true;
            foreach(var leaf in leaves)leaf.Stream.Dispose();
            for(int i=directories.Count-1;i>=0;i--)directories[i].Handle.Dispose();
        }
    }
    public static class Native {
        [StructLayout(LayoutKind.Sequential)] private struct Time { public uint Low,High; }
        [StructLayout(LayoutKind.Sequential)] private struct Info {
            public uint Attributes;public Time Creation,Access,Write;
            public uint Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;
        }
        [StructLayout(LayoutKind.Sequential)] private struct Disposition { public byte DeleteFile; }
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] private struct StreamData {
            public long Size;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=296)] public string Name;
        }
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern SafeFileHandle CreateFileW(string name,uint access,uint share,IntPtr security,uint mode,uint flags,IntPtr template);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool GetFileInformationByHandle(SafeFileHandle handle,out Info info);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle,StringBuilder path,uint size,uint flags);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool SetFileInformationByHandle(SafeFileHandle handle,int kind,ref Disposition value,uint size);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern IntPtr FindFirstStreamW(string path,int level,out StreamData data,uint flags);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool FindNextStreamW(IntPtr find,out StreamData data);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool FindClose(IntPtr find);
        public static bool IsHash(string text) { return text!=null && System.Text.RegularExpressions.Regex.IsMatch(text,"\\A[0-9a-f]{64}\\z"); }
        public static bool IsId(string text) { return text!=null && System.Text.RegularExpressions.Regex.IsMatch(text,"\\A[0-9a-f]{8}:[0-9a-f]{16}\\z"); }
        public static void RelativePath(string path) {
            if(String.IsNullOrEmpty(path) || path.StartsWith("\\") || path.Contains(":")) throw new InvalidOperationException("Invalid relative leaf path.");
            CheckParts(path);
        }
        private static void CheckParts(string path) {
            if(path.IndexOfAny(new char[]{'/','\0','\r','\n','\t','"','<','>','|','?','*','~'})>=0)throw new InvalidOperationException("Ambiguous path.");
            foreach(string part in path.Split('\\')) {
                if(part.Length==0 || part=="." || part==".." || part!=part.Trim() || part.EndsWith(".") ||
                    System.Text.RegularExpressions.Regex.IsMatch(part,"\\A(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\\.|\\z)"))
                    throw new InvalidOperationException("Ambiguous path component.");
                foreach(char c in part)if(c<32)throw new InvalidOperationException("Control character in path.");
            }
        }
        public static void CanonicalPath(string path) {
            if(path==null || path.Length<3 || path[0]<'A' || path[0]>'Z' || path[1]!=':' || path[2]!='\\' || path.Substring(2).Contains(":"))
                throw new InvalidOperationException("Canonical local drive path required.");
            if(path.Length>3)CheckParts(path.Substring(3));
            if(!String.Equals(System.IO.Path.GetFullPath(path),path,StringComparison.Ordinal))throw new InvalidOperationException("Noncanonical full path.");
        }
        internal static SafeFileHandle OpenDirectory(string path) {
            // LIST_DIRECTORY is required for the sharing lease to reject directory rename.
            var handle=CreateFileW(path,0x81,1,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
            if(handle.IsInvalid){int error=Marshal.GetLastWin32Error();handle.Dispose();throw new Win32Exception(error);}
            return handle;
        }
        internal static SafeFileHandle OpenFile(string path,bool deletion) {
            var handle=CreateFileW(path,deletion ? 0x10081u : 0x81u,1,IntPtr.Zero,3,0x00200000,IntPtr.Zero);
            if(handle.IsInvalid){int error=Marshal.GetLastWin32Error();handle.Dispose();throw new Win32Exception(error);}
            return handle;
        }
        internal static string Verify(SafeFileHandle handle,string expected,bool directory) {
            if(handle==null || handle.IsClosed || handle.IsInvalid)throw new InvalidOperationException("Closed native handle.");
            Info info;if(!GetFileInformationByHandle(handle,out info))throw new Win32Exception(Marshal.GetLastWin32Error());
            if((info.Attributes&0x400)!=0 || ((info.Attributes&0x10)!=0)!=directory)throw new InvalidOperationException("Indirect or wrong-type path.");
            if(!directory && (info.Links!=1 || (info.Attributes&1)!=0))throw new InvalidOperationException("Hardlinked or read-only file rejected.");
            var text=new StringBuilder(32768);uint count=GetFinalPathNameByHandleW(handle,text,(uint)text.Capacity,0);
            if(count==0 || count>=text.Capacity)throw new Win32Exception(Marshal.GetLastWin32Error());
            if(!String.Equals(text.ToString(),@"\\?\"+expected,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Final path differs from approved path.");
            return info.Volume.ToString("x8")+":"+info.IndexHigh.ToString("x8")+info.IndexLow.ToString("x8");
        }
        internal static void RejectNamedStreams(string path) {
            StreamData data;IntPtr find=FindFirstStreamW(path,0,out data,0);
            if(find==new IntPtr(-1)){int error=Marshal.GetLastWin32Error();if(error==38)return;throw new Win32Exception(error);}
            try {
                do { if(data.Name!="::$DATA")throw new InvalidOperationException("Named stream rejected."); } while(FindNextStreamW(find,out data));
                int error=Marshal.GetLastWin32Error();if(error!=38)throw new Win32Exception(error);
            } finally { FindClose(find); }
        }
        internal static FileObservation Observe(FileStream stream,string path) {
            string id=Verify(stream.SafeFileHandle,path,false);RejectNamedStreams(path);
            long length=stream.Length;stream.Position=0;string hash;
            using(var sha=SHA256.Create())hash=BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();
            if(stream.Length!=length || Verify(stream.SafeFileHandle,path,false)!=id)throw new InvalidOperationException("File changed during observation.");
            return new FileObservation(id,length,hash);
        }
        public static FileObservation Inspect(string path) {
            CanonicalPath(path);
            using(var handle=OpenFile(path,false))using(var stream=new FileStream(handle,FileAccess.Read))return Observe(stream,path);
        }
        internal static void MarkDelete(SafeFileHandle handle) {
            var disposition=new Disposition{DeleteFile=1};
            if(!SetFileInformationByHandle(handle,4,ref disposition,1))throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        internal static string ClosedLeafStatus(string path,out int error) {
            // Parents remain pinned. Missing path is distinguished from sharing/access denial.
            var probe=CreateFileW(path,0x80,7,IntPtr.Zero,3,0x00200000,IntPtr.Zero);
            if(probe.IsInvalid) {
                error=Marshal.GetLastWin32Error();probe.Dispose();
                if(error==2)return "removed";
                if(error==5 || error==32 || error==303)return "pending-or-inaccessible";
                return "unknown";
            }
            probe.Dispose();error=0;return "path-present";
        }
    }
}
