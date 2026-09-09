// Compiled with the pinned exact-removal source into a private namespace.
// Process-interruption protocol for owned fixtures; not a power-loss guarantee.
namespace Yime.Dp1UExactRemoval {
    using System.Text.RegularExpressions;
    public sealed class TransactionStore : IDisposable {
        private readonly Dictionary<string,SafeFileHandle> directories=new Dictionary<string,SafeFileHandle>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string,string> directoryIds=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string,FileStream> records=new Dictionary<string,FileStream>(StringComparer.Ordinal);
        private FileStream mutex;
        public readonly string Root;
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool MoveFileExW(string from,string to,uint flags);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern SafeFileHandle CreateFileW(string path,uint access,uint share,IntPtr security,uint mode,uint flags,IntPtr template);
        private static readonly byte[] Magic=Encoding.ASCII.GetBytes("YDP1UTX1");
        public TransactionStore(string root,bool create) {
            Native.CanonicalPath(root);Root=root;
            try {
                PinDirectory(root);
                mutex=new FileStream(System.IO.Path.Combine(root,"transaction.lock"),create?FileMode.CreateNew:FileMode.Open,FileAccess.ReadWrite,FileShare.None);
                Native.Verify(mutex.SafeFileHandle,System.IO.Path.Combine(root,"transaction.lock"),false);
                Native.RejectNamedStreams(System.IO.Path.Combine(root,"transaction.lock"));
                if(mutex.Length!=0)throw new InvalidOperationException("Transaction lock is not empty.");
                mutex.Flush(true);Validate();
            } catch {Dispose();throw;}
        }
        public string PinDirectory(string path) {
            Native.CanonicalPath(path);
            var stack=new Stack<string>();
            for(string p=path;p!=null;p=System.IO.Path.GetDirectoryName(p))stack.Push(p);
            while(stack.Count>0) {
                string p=stack.Pop();if(directories.ContainsKey(p))continue;
                // Permit metadata writes needed for same-directory record rename,
                // while denying DELETE so the directory object cannot be replaced.
                var h=CreateFileW(p,0x81,3,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
                if(h.IsInvalid){int error=Marshal.GetLastWin32Error();h.Dispose();throw new Win32Exception(error);}
                try{string id=Native.Verify(h,p,true);Native.RejectNamedStreams(p);directories.Add(p,h);directoryIds.Add(p,id);h=null;}
                finally{if(h!=null)h.Dispose();}
            }
            return directoryIds[path];
        }
        public void Validate() {
            if(mutex==null)throw new InvalidOperationException("Closed transaction store.");
            foreach(var pair in directories) {
                if(Native.Verify(pair.Value,pair.Key,true)!=directoryIds[pair.Key])throw new InvalidOperationException("Transaction directory changed.");
                Native.RejectNamedStreams(pair.Key);
            }
            var entries=Directory.GetFileSystemEntries(Root);
            if(entries.Length>128)throw new InvalidOperationException("Too many transaction records.");
            foreach(string p in entries) {
                string n=System.IO.Path.GetFileName(p);
                if(n!="transaction.lock" && n!="prepared.bin" && n!="commit.bin" && n!="terminal.bin" &&
                   !Regex.IsMatch(n,"\\A(?:prepared|commit|terminal)\\.bin\\.pending-[0-9a-f]{32}\\z"))
                    throw new InvalidOperationException("Unlisted transaction member.");
                if((File.GetAttributes(p)&FileAttributes.Directory)!=0)throw new InvalidOperationException("Transaction member is a directory.");
            }
        }
        private string PathFor(string name) {
            if(name!="prepared.bin" && name!="commit.bin" && name!="terminal.bin")throw new InvalidOperationException("Unknown transaction record.");
            return System.IO.Path.Combine(Root,name);
        }
        public bool Has(string name) {
            Validate();int error;string status=Native.ClosedLeafStatus(PathFor(name),out error);
            if(status=="removed")return false;
            if(status!="path-present")throw new InvalidOperationException("Transaction record inaccessible: "+error);
            return true;
        }
        public byte[] Read(string name) {
            Validate();string path=PathFor(name);FileStream stream;
            if(!records.TryGetValue(name,out stream)) {
                var h=Native.OpenFile(path,false);
                try{stream=new FileStream(h,FileAccess.Read);h=null;records.Add(name,stream);}
                catch{if(stream!=null)stream.Dispose();throw;}finally{if(h!=null)h.Dispose();}
            }
            if(stream.Length<44 || stream.Length>1048620)throw new InvalidOperationException("Invalid transaction record length.");
            Native.Verify(stream.SafeFileHandle,path,false);Native.RejectNamedStreams(path);
            stream.Position=0;var all=new byte[(int)stream.Length];int pos=0;
            while(pos<all.Length){int n=stream.Read(all,pos,all.Length-pos);if(n==0)throw new EndOfStreamException();pos+=n;}
            for(int i=0;i<8;i++)if(all[i]!=Magic[i])throw new InvalidOperationException("Transaction record magic mismatch.");
            int length=BitConverter.ToInt32(all,8);
            if(length<1 || length!=all.Length-44)throw new InvalidOperationException("Torn transaction record.");
            var payload=new byte[length];Array.Copy(all,44,payload,0,length);
            byte[] hash;using(var sha=SHA256.Create())hash=sha.ComputeHash(payload);
            for(int i=0;i<32;i++)if(hash[i]!=all[12+i])throw new InvalidOperationException("Transaction record digest mismatch.");
            return payload;
        }
        public string Publish(string name,byte[] payload) {
            Validate();if(payload==null || payload.Length<1 || payload.Length>1048576)throw new InvalidOperationException("Transaction payload exceeds limit.");
            string path=PathFor(name),temp=path+".pending-"+Guid.NewGuid().ToString("N");
            byte[] hash;using(var sha=SHA256.Create())hash=sha.ComputeHash(payload);
            using(var stream=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None,4096,FileOptions.WriteThrough)) {
                Native.Verify(stream.SafeFileHandle,temp,false);Native.RejectNamedStreams(temp);
                stream.Write(Magic,0,8);var length=BitConverter.GetBytes(payload.Length);stream.Write(length,0,4);
                stream.Write(hash,0,32);stream.Write(payload,0,payload.Length);stream.Flush(true);
            }
            // No replace. An orphan pending file is retained and never a decision.
            if(!MoveFileExW(temp,path,8))throw new Win32Exception(Marshal.GetLastWin32Error());
            byte[] actual=Read(name);
            if(actual.Length!=payload.Length)throw new InvalidOperationException("Published record changed.");
            for(int i=0;i<payload.Length;i++)if(actual[i]!=payload[i])throw new InvalidOperationException("Published record changed.");
            return BitConverter.ToString(hash).Replace("-","").ToLowerInvariant();
        }
        public string LeafStatus(string path) {
            Native.CanonicalPath(path);Validate();int error;string status=Native.ClosedLeafStatus(path,out error);
            if(status!="removed" && status!="path-present")throw new InvalidOperationException("Payload pending or inaccessible: "+error);
            return status;
        }
        public void Dispose() {
            foreach(var s in records.Values)s.Dispose();records.Clear();
            if(mutex!=null){mutex.Dispose();mutex=null;}
            foreach(var h in directories.Values)h.Dispose();directories.Clear();directoryIds.Clear();
        }
    }
    // Same strict syntax rules as receipt-v2: no duplicate/case-duplicate keys,
    // comments, trailing content or permissive PS5/PS7 parser extensions.
    public sealed class TransactionJson {
        readonly string s;int p;TransactionJson(string text){s=text;}
        void Fail(){throw new FormatException("Invalid transaction JSON at "+p);}
        void Ws(){while(p<s.Length && (s[p]==' '||s[p]=='\r'||s[p]=='\n'||s[p]=='\t'))p++;}
        bool Take(char c){Ws();if(p<s.Length && s[p]==c){p++;return true;}return false;}
        string Str(){
            if(!Take('"'))Fail();var b=new StringBuilder();
            while(p<s.Length){char c=s[p++];if(c=='"')return b.ToString();if(c<32)Fail();
                if(c=='\\'){if(p==s.Length)Fail();c=s[p++];switch(c){
                    case '"':case '\\':case '/':break;
                    case 'b':c='\b';break;case 'f':c='\f';break;case 'n':c='\n';break;case 'r':c='\r';break;case 't':c='\t';break;
                    case 'u':if(p+4>s.Length||!Regex.IsMatch(s.Substring(p,4),"\\A[0-9a-fA-F]{4}\\z"))Fail();c=(char)Convert.ToInt32(s.Substring(p,4),16);p+=4;break;
                    default:Fail();break;}}
                b.Append(c);}
            Fail();return null;
        }
        void Value(int depth){
            if(depth>32)Fail();Ws();if(p==s.Length)Fail();
            if(Take('{')){var keys=new HashSet<string>(StringComparer.OrdinalIgnoreCase);if(Take('}'))return;
                do{string key=Str();if(!keys.Add(key)||!Take(':'))Fail();Value(depth+1);if(Take('}'))return;}while(Take(','));Fail();}
            else if(Take('[')){if(Take(']'))return;do{Value(depth+1);if(Take(']'))return;}while(Take(','));Fail();}
            else if(s[p]=='"'){Str();}
            else{var m=Regex.Match(s.Substring(p),"\\A(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)");if(!m.Success)Fail();p+=m.Length;}
        }
        public static void Check(string text){var v=new TransactionJson(text);v.Value(0);v.Ws();if(v.p!=text.Length)v.Fail();}
    }
}
