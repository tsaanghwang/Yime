# Read-only diagnostics for a failed native maintenance launch. This helper does
# not duplicate tokens, enable privileges, launch processes or touch registration.
function Get-YimeCoreExceptionEvidence([Exception]$Exception) {
    $chain=[Collections.Generic.List[object]]::new()
    for($current=$Exception;$null -ne $current;$current=$current.InnerException) {
        $nativeCode=$null;$nativeMessage=$null
        if($current -is [ComponentModel.Win32Exception]) {
            $nativeCode=$current.NativeErrorCode
            $nativeMessage=([ComponentModel.Win32Exception]::new($nativeCode)).Message
        }
        $chain.Add([ordered]@{type=$current.GetType().FullName;message=$current.Message;
            hresult=$current.HResult;native_error_code=$nativeCode;native_error_message=$nativeMessage})
    }
    return $chain.ToArray()
}

function Get-YimeCoreLaunchTokenDiagnostics {
    if(-not ('YimeCore.ReadOnlyTokenDiagnostics.Snapshot' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
namespace YimeCore.ReadOnlyTokenDiagnostics {
    public sealed class TokenFacts {
        public string Sid;
        public int TokenType;
        public string TokenTypeName;
        public int? ImpersonationLevel;
        public int ElevationType;
        public bool Elevated;
        public int Session;
        public bool AppContainer;
    }
    public sealed class Snapshot {
        public TokenFacts Caller;
        public TokenFacts Linked;
        [DllImport("advapi32.dll", SetLastError=true)]
        static extern bool GetTokenInformation(IntPtr token, int type, IntPtr data, int bytes, out int returned);
        [DllImport("kernel32.dll")]
        static extern bool CloseHandle(IntPtr handle);
        static IntPtr Information(IntPtr token, int type) {
            int bytes;
            GetTokenInformation(token,type,IntPtr.Zero,0,out bytes);
            if(bytes <= 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr buffer=Marshal.AllocHGlobal(bytes);
            if(!GetTokenInformation(token,type,buffer,bytes,out bytes)) {
                int code=Marshal.GetLastWin32Error(); Marshal.FreeHGlobal(buffer);
                throw new Win32Exception(code);
            }
            return buffer;
        }
        static int Value(IntPtr token,int type) {
            IntPtr data=Information(token,type);
            try {return Marshal.ReadInt32(data);} finally {Marshal.FreeHGlobal(data);}
        }
        static TokenFacts Inspect(IntPtr token) {
            TokenFacts facts=new TokenFacts();
            using(WindowsIdentity identity=new WindowsIdentity(token)) {facts.Sid=identity.User.Value;}
            facts.TokenType=Value(token,8);
            facts.TokenTypeName=facts.TokenType == 1 ? "Primary" : "Impersonation";
            // TokenImpersonationLevel is not a valid query for primary tokens.
            if(facts.TokenType == 2) facts.ImpersonationLevel=Value(token,9);
            facts.ElevationType=Value(token,18);
            facts.Elevated=Value(token,20)!=0;
            facts.Session=Value(token,12);
            facts.AppContainer=Value(token,29)!=0;
            return facts;
        }
        public static Snapshot Capture() {
            using(WindowsIdentity identity=WindowsIdentity.GetCurrent()) {
                Snapshot result=new Snapshot();
                result.Caller=Inspect(identity.Token);
                // Query only the current elevated caller's own linked token.
                if(result.Caller.Elevated && result.Caller.ElevationType == 2) {
                    IntPtr info=Information(identity.Token,19);
                    IntPtr linked;
                    try {linked=Marshal.ReadIntPtr(info);} finally {Marshal.FreeHGlobal(info);}
                    try {result.Linked=Inspect(linked);} finally {CloseHandle(linked);}
                }
                return result;
            }
        }
    }
}
'@
    }
    [YimeCore.ReadOnlyTokenDiagnostics.Snapshot]::Capture()
}
