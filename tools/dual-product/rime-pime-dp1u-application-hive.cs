// Private application-hive primitive. No predefined registry root or product path is used.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Yime.Dp1UApplicationHive {
    public sealed class ValueInput {
        public readonly string Name, Kind;
        private readonly byte[] data;
        public ValueInput(string name,string kind,byte[] bytes) { Name=name;Kind=kind;data=bytes==null?null:(byte[])bytes.Clone(); }
        internal byte[] Copy() { return data==null?null:(byte[])data.Clone(); }
    }
    public sealed class ValueMetadata {
        public readonly string Name, Kind, Sha256;
        public readonly int Bytes;
        internal ValueMetadata(ValueRecord row) { Name=row.Name;Kind=row.Kind;Bytes=row.Data.Length;Sha256=Native.Hash(row.Data); }
    }
    public sealed class ValueExport {
        public readonly string Name, Kind;
        public readonly byte[] RawBytes;
        internal ValueExport(ValueRecord row) { Name=row.Name;Kind=row.Kind;RawBytes=(byte[])row.Data.Clone(); }
    }
    internal sealed class ValueRecord {
        internal readonly string Name,Kind;
        internal readonly uint Type;
        internal readonly byte[] Data;
        internal ValueRecord(string name,string kind,uint type,byte[] data) { Name=name;Kind=kind;Type=type;Data=(byte[])data.Clone(); }
        internal bool Equal(ValueRecord other) {
            if(other==null || Name!=other.Name || Kind!=other.Kind || Type!=other.Type || Data.Length!=other.Data.Length)return false;
            for(int i=0;i<Data.Length;i++)if(Data[i]!=other.Data[i])return false;
            return true;
        }
    }
    public sealed class HiveSnapshot {
        internal readonly HiveContext Owner;
        internal readonly ValueRecord[] Records;
        internal HiveSnapshot(HiveContext owner,ValueRecord[] records) { Owner=owner;Records=records; }
        public ValueMetadata[] Metadata() { var rows=new ValueMetadata[Records.Length];for(int i=0;i<rows.Length;i++)rows[i]=new ValueMetadata(Records[i]);return rows; }
    }
    public sealed class FileIdentity {
        public readonly string FileId,Sha256;
        public readonly long Bytes;
        internal FileIdentity(string id,long bytes,string hash) { FileId=id;Bytes=bytes;Sha256=hash; }
    }
    public sealed class HiveContext : IDisposable {
        internal static readonly string[] Names={"machine-com-server-x86","machine-com-server-native","machine-profile-icon-index","machine-product-root","target-profile-enabled","target-profile-metadata"};
        internal static readonly string[] Kinds={"String","String","DWord","ExpandString","DWord","MultiString"};
        private readonly List<SafeFileHandle> directories=new List<SafeFileHandle>();
        private readonly List<string> directoryPaths=new List<string>(),directoryIds=new List<string>();
        private SafeRegistryHandle hive;
        private string fileId;
        private bool disposed;
        public readonly string Path;
        private HiveContext(string path) { Path=path; }
        public static HiveContext Open(string path) { return OpenCore(path,null); }
        public static HiveContext Reopen(string path,string id,long bytes,string sha256) {
            if(!Native.ValidId(id) || bytes<0 || !Native.ValidHash(sha256))throw new InvalidOperationException("Invalid expected hive identity.");
            return OpenCore(path,new FileIdentity(id,bytes,sha256));
        }
        private static HiveContext OpenCore(string path,FileIdentity expected) {
            Native.Canonical(path);var result=new HiveContext(path);
            try {
                var parents=new Stack<string>();
                for(string cursor=System.IO.Path.GetDirectoryName(path);cursor!=null;cursor=System.IO.Path.GetDirectoryName(cursor))parents.Push(cursor);
                while(parents.Count>0) {
                    string parent=parents.Pop();var handle=Native.OpenDirectory(parent);
                    try { string id=Native.Verify(handle,parent,true);Native.NoStreams(parent);result.directories.Add(handle);result.directoryPaths.Add(parent);result.directoryIds.Add(id);handle=null; }
                    finally { if(handle!=null)handle.Dispose(); }
                }
                if(expected==null)Native.RequireAbsent(path);
                else {
                    var before=Native.Inspect(path);
                    if(before.FileId!=expected.FileId || before.Bytes!=expected.Bytes || before.Sha256!=expected.Sha256)throw new InvalidOperationException("Existing hive identity/size/hash mismatch.");
                }
                // There is no CREATE_NEW disposition. This is NOT an atomic hostile-same-SID creation boundary.
                int error=Native.RegLoadAppKeyW(path,out result.hive,0x2001fu,1,0);
                Native.Check(error,"RegLoadAppKeyW");
                result.fileId=Native.InspectId(path);
                if(expected!=null && result.fileId!=expected.FileId)throw new InvalidOperationException("Hive file identity changed while loading.");
                result.Validate();
                // New hives must actually be empty. An already-existing raced-in hive cannot be adopted as a blank one.
                if(expected==null) {
                    uint subkeys,values;Native.Check(Native.RegQueryInfoKeyW(result.hive,null,IntPtr.Zero,IntPtr.Zero,out subkeys,IntPtr.Zero,IntPtr.Zero,out values,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero),"RegQueryInfoKeyW");
                    if(subkeys!=0 || values!=0)throw new InvalidOperationException("New application hive is not empty.");
                }
                return result;
            } catch { result.Dispose();throw; }
        }
        public void Validate() {
            if(disposed || hive==null || hive.IsClosed || hive.IsInvalid)throw new InvalidOperationException("Application hive context is closed.");
            for(int i=0;i<directories.Count;i++) {
                if(Native.Verify(directories[i],directoryPaths[i],true)!=directoryIds[i])throw new InvalidOperationException("Ancestor identity changed.");
                Native.NoStreams(directoryPaths[i]);
            }
            if(Native.InspectId(Path)!=fileId)throw new InvalidOperationException("Application hive path identity changed.");
        }
        private ValueRecord Read(string name) {
            for(int attempt=0;attempt<4;attempt++) {
                uint type=0,size=0;int error=Native.RegQueryValueExW(hive,name,IntPtr.Zero,out type,null,ref size);
                if(error==2)return new ValueRecord(name,"Absent",0,new byte[0]);
                if(error!=0 && error!=234)Native.Check(error,"RegQueryValueExW size");
                if(size>65536)throw new InvalidOperationException("Application hive value exceeds byte limit.");
                byte[] data=new byte[size];uint actual=size,actualType=0;
                error=Native.RegQueryValueExW(hive,name,IntPtr.Zero,out actualType,data,ref actual);
                if(error==234 || error==2)continue;
                Native.Check(error,"RegQueryValueExW bytes");
                if(actual>size || actualType!=type)continue;
                if(actual!=data.Length)Array.Resize(ref data,(int)actual);
                string kind=Native.Kind(type);Native.ValidateBytes(kind,data);
                return new ValueRecord(name,kind,type,data);
            }
            throw new InvalidOperationException("Application hive value changed while reading.");
        }
        public HiveSnapshot Capture() {
            Validate();var rows=new ValueRecord[Names.Length];
            for(int i=0;i<rows.Length;i++)rows[i]=Read(Names[i]);
            // Two bounded observations detect ordinary changes; they do not prove quiescence.
            for(int i=0;i<rows.Length;i++)if(!rows[i].Equal(Read(Names[i])))throw new InvalidOperationException("Application hive values changed during capture.");
            Validate();return new HiveSnapshot(this,rows);
        }
        private void RequireSnapshot(HiveSnapshot snapshot) { Validate();if(snapshot==null || !Object.ReferenceEquals(snapshot.Owner,this))throw new InvalidOperationException("Original same-context snapshot required."); }
        // Explicit fixture-only raw export. A retained snapshot may describe an earlier state;
        // this does not observe current values or authorize a write. Never share its byte arrays.
        public ValueExport[] ExportValues(HiveSnapshot snapshot) {
            RequireSnapshot(snapshot);var rows=new ValueExport[Names.Length];
            for(int i=0;i<rows.Length;i++)rows[i]=new ValueExport(snapshot.Records[i]);
            Validate();return rows;
        }
        public void RequireCurrent(HiveSnapshot snapshot) {
            RequireSnapshot(snapshot);var current=Capture();
            for(int i=0;i<Names.Length;i++)if(!snapshot.Records[i].Equal(current.Records[i]))throw new InvalidOperationException("Expected-before snapshot conflict.");
        }
        public HiveSnapshot PrepareValues(ValueInput[] values) {
            Validate();if(values==null || values.Length!=Names.Length)throw new InvalidOperationException("Exactly six fixed values are required.");
            var records=new ValueRecord[Names.Length];var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach(var value in values) {
                if(value==null || !seen.Add(value.Name))throw new InvalidOperationException("Invalid or duplicate value.");
                int index=Array.IndexOf(Names,value.Name);
                if(index<0 || (value.Kind!="Absent" && value.Kind!=Kinds[index]))throw new InvalidOperationException("Fixed value name/type allowlist mismatch.");
                byte[] bytes=value.Copy();Native.ValidateBytes(value.Kind,bytes);
                records[index]=new ValueRecord(value.Name,value.Kind,Native.Type(value.Kind),bytes);
            }
            return new HiveSnapshot(this,records);
        }
        // Called only by the source-owned module loop; no public callback or arbitrary root/name argument.
        public void WriteIndex(HiveSnapshot wanted,int index) {
            RequireSnapshot(wanted);if(index<0 || index>=Names.Length)throw new InvalidOperationException("Invalid fixed value index.");
            var row=wanted.Records[index];int error;
            if(row.Kind=="Absent") { error=Native.RegDeleteValueW(hive,row.Name);if(error==2)error=0; }
            else error=Native.RegSetValueExW(hive,row.Name,0,row.Type,row.Data,(uint)row.Data.Length);
            Native.Check(error,"Application hive typed write");
        }
        public void Flush() { Validate();Native.Check(Native.RegFlushKey(hive),"RegFlushKey"); }
        public void Dispose() {
            if(disposed)return;disposed=true;
            try { if(hive!=null)hive.Dispose(); }
            finally { for(int i=directories.Count-1;i>=0;i--)directories[i].Dispose();directories.Clear(); }
        }
        public FileIdentity CloseAndInspect() {
            Validate();Flush();
            // Keep directory leases across unload and the exact-file observation.
            hive.Dispose();hive=null;
            try { var result=Native.Inspect(Path);if(result.FileId!=fileId)throw new InvalidOperationException("Closed hive identity changed.");return result; }
            finally { Dispose(); }
        }
    }
    public static class Native {
        [StructLayout(LayoutKind.Sequential)] private struct Info { public uint Attributes;public System.Runtime.InteropServices.ComTypes.FILETIME Creation,Access,Write;public uint Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow; }
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] private struct StreamInfo { public long Size;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=296)]public string Name; }
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] internal static extern int RegLoadAppKeyW(string path,out SafeRegistryHandle key,uint access,uint options,uint reserved);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] internal static extern int RegQueryValueExW(SafeRegistryHandle key,string name,IntPtr reserved,out uint type,[Out]byte[] data,ref uint bytes);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] internal static extern int RegSetValueExW(SafeRegistryHandle key,string name,uint reserved,uint type,byte[] data,uint bytes);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] internal static extern int RegDeleteValueW(SafeRegistryHandle key,string name);
        [DllImport("advapi32.dll")] internal static extern int RegFlushKey(SafeRegistryHandle key);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] internal static extern int RegQueryInfoKeyW(SafeRegistryHandle key,StringBuilder cls,IntPtr clsLength,IntPtr reserved,out uint subkeys,IntPtr maxSubkey,IntPtr maxClass,out uint values,IntPtr maxValue,IntPtr maxData,IntPtr security,IntPtr lastWrite);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern SafeFileHandle CreateFileW(string name,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool GetFileInformationByHandle(SafeFileHandle file,out Info info);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern uint GetFinalPathNameByHandleW(SafeFileHandle file,StringBuilder name,uint length,uint flags);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern IntPtr FindFirstStreamW(string path,int level,out StreamInfo data,uint flags);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool FindNextStreamW(IntPtr find,out StreamInfo data);
        [DllImport("kernel32.dll")] private static extern bool FindClose(IntPtr find);
        internal static void Check(int error,string operation) { if(error!=0)throw new Win32Exception(error,operation+": "+new Win32Exception(error).Message); }
        internal static string Hash(byte[] bytes) { using(var hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-","").ToLowerInvariant(); }
        internal static bool ValidId(string value) { return value!=null && System.Text.RegularExpressions.Regex.IsMatch(value,"\\A[0-9a-f]{8}:[0-9a-f]{16}\\z"); }
        internal static bool ValidHash(string value) { return value!=null && System.Text.RegularExpressions.Regex.IsMatch(value,"\\A[0-9a-f]{64}\\z"); }
        internal static string Kind(uint type) { switch(type) { case 1:return "String";case 2:return "ExpandString";case 4:return "DWord";case 7:return "MultiString";default:throw new InvalidOperationException("Unsupported native registry value type."); } }
        internal static uint Type(string kind) { switch(kind) { case "Absent":return 0;case "String":return 1;case "ExpandString":return 2;case "DWord":return 4;case "MultiString":return 7;default:throw new InvalidOperationException("Unsupported registry value kind."); } }
        internal static void ValidateBytes(string kind,byte[] bytes) {
            Type(kind);if(bytes==null || bytes.Length>65536 || (kind=="Absent" && bytes.Length!=0) || (kind=="DWord" && bytes.Length!=4) || ((kind=="String" || kind=="ExpandString" || kind=="MultiString") && bytes.Length%2!=0))throw new InvalidOperationException("Invalid typed raw byte length.");
            // Win32 may append a terminator to malformed input. Reject it before any write;
            // never normalize bytes or claim it can be restored byte-for-byte by this adapter.
            if(bytes.Length>0 && (kind=="String" || kind=="ExpandString" || kind=="MultiString")) {
                int required=kind=="MultiString"?4:2;
                if(bytes.Length<required)throw new InvalidOperationException("Missing registry string terminator.");
                for(int i=bytes.Length-required;i<bytes.Length;i++)if(bytes[i]!=0)throw new InvalidOperationException("Missing registry string terminator.");
            }
        }
        public static void Canonical(string path) {
            if(path==null || path.Length<3 || path[0]<'A' || path[0]>'Z' || path[1]!=':' || path[2]!='\\' || path.Substring(2).Contains(":"))throw new InvalidOperationException("Canonical local path required.");
            if(!String.Equals(System.IO.Path.GetFullPath(path),path,StringComparison.Ordinal))throw new InvalidOperationException("Noncanonical path.");
            if(path.Length==3)return;
            foreach(string part in path.Substring(3).Split('\\')) {
                if(part.Length==0 || part=="." || part==".." || part!=part.Trim() || part.EndsWith(".") || part.IndexOfAny(new char[]{'/','~','*','?','"','<','>','|'})>=0 || System.Text.RegularExpressions.Regex.IsMatch(part,"\\A(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\\.|\\z)"))throw new InvalidOperationException("Ambiguous path.");
                foreach(char c in part)if(c<32)throw new InvalidOperationException("Control character in path.");
            }
        }
        private static SafeFileHandle OpenFile(string path,uint access,uint share) {
            var result=CreateFileW(path,access,share,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
            if(result.IsInvalid){int error=Marshal.GetLastWin32Error();result.Dispose();throw new Win32Exception(error);}return result;
        }
        internal static SafeFileHandle OpenDirectory(string path) { return OpenFile(path,0x81,1); }
        internal static string Verify(SafeFileHandle handle,string path,bool directory) {
            Info info;if(handle.IsClosed || handle.IsInvalid)throw new InvalidOperationException("Closed file handle.");
            if(!GetFileInformationByHandle(handle,out info))throw new Win32Exception(Marshal.GetLastWin32Error());
            if((info.Attributes&0x400)!=0 || ((info.Attributes&0x10)!=0)!=directory || (!directory && (info.Links!=1 || (info.Attributes&1)!=0)))throw new InvalidOperationException("Indirect, hardlinked, readonly or wrong-type path.");
            var text=new StringBuilder(32768);uint count=GetFinalPathNameByHandleW(handle,text,(uint)text.Capacity,0);
            if(count==0 || count>=text.Capacity || !String.Equals(text.ToString(),@"\\?\"+path,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Native final path mismatch.");
            return info.Volume.ToString("x8")+":"+info.IndexHigh.ToString("x8")+info.IndexLow.ToString("x8");
        }
        internal static void NoStreams(string path) {
            StreamInfo info;IntPtr find=FindFirstStreamW(path,0,out info,0);
            if(find==new IntPtr(-1)){int error=Marshal.GetLastWin32Error();if(error==38)return;throw new Win32Exception(error);}
            try { do { if(info.Name!="::$DATA")throw new InvalidOperationException("Named stream rejected."); }while(FindNextStreamW(find,out info));int error=Marshal.GetLastWin32Error();if(error!=38)throw new Win32Exception(error); }
            finally { FindClose(find); }
        }
        internal static void RequireAbsent(string path) {
            var probe=CreateFileW(path,0x80,7,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
            if(!probe.IsInvalid){probe.Dispose();throw new InvalidOperationException("New hive path already exists.");}
            int error=Marshal.GetLastWin32Error();probe.Dispose();if(error!=2)throw new Win32Exception(error,"Cannot prove new hive path absent.");
        }
        internal static string InspectId(string path) { using(var handle=OpenFile(path,0x80,7)){string id=Verify(handle,path,false);NoStreams(path);return id;} }
        public static FileIdentity Inspect(string path) {
            Canonical(path);using(var handle=OpenFile(path,0x81,1))using(var stream=new FileStream(handle,FileAccess.Read)) {
                string id=Verify(handle,path,false);NoStreams(path);long bytes=stream.Length;string hash;
                using(var sha=SHA256.Create())hash=BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();
                if(stream.Length!=bytes || Verify(handle,path,false)!=id)throw new InvalidOperationException("Hive file changed during observation.");
                return new FileIdentity(id,bytes,hash);
            }
        }
    }
}
