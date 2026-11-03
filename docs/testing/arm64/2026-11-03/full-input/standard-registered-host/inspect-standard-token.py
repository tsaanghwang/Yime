import ctypes as c
from ctypes import wintypes as w
import json
from pathlib import Path
root=Path(__file__).parent/'standard-installed-startup'
status=json.loads((root/'runtime-status-after.json').read_text(encoding='utf-8-sig'))
k=c.WinDLL('kernel32',use_last_error=True);a=c.WinDLL('advapi32',use_last_error=True)
k.OpenProcess.argtypes=[w.DWORD,w.BOOL,w.DWORD];k.OpenProcess.restype=w.HANDLE
k.CloseHandle.argtypes=[w.HANDLE]
k.QueryFullProcessImageNameW.argtypes=[w.HANDLE,w.DWORD,w.LPWSTR,c.POINTER(w.DWORD)]
a.OpenProcessToken.argtypes=[w.HANDLE,w.DWORD,c.POINTER(w.HANDLE)]
a.GetTokenInformation.argtypes=[w.HANDLE,c.c_int,c.c_void_p,w.DWORD,c.POINTER(w.DWORD)]
a.GetSidSubAuthorityCount.argtypes=[c.c_void_p];a.GetSidSubAuthorityCount.restype=c.POINTER(c.c_ubyte)
a.GetSidSubAuthority.argtypes=[c.c_void_p,w.DWORD];a.GetSidSubAuthority.restype=c.POINTER(w.DWORD)
out=[]
for name in ('runtime_pid','broker_pid','toolbar_pid'):
    pid=status[name];r={'role':name,'pid':pid};out.append(r)
    h=k.OpenProcess(0x1000,False,pid);t=w.HANDLE()
    if not h:r['open_error']=c.get_last_error();continue
    try:
        n=w.DWORD(32768);b=c.create_unicode_buffer(n.value)
        if k.QueryFullProcessImageNameW(h,0,b,c.byref(n)):r['image']=b.value
        else:r['image_error']=c.get_last_error()
        if not a.OpenProcessToken(h,8,c.byref(t)):r['token_error']=c.get_last_error();continue
        e=w.DWORD();n=w.DWORD()
        if not a.GetTokenInformation(t,20,c.byref(e),c.sizeof(e),c.byref(n)):raise c.WinError(c.get_last_error())
        r['elevated']=bool(e.value)
        a.GetTokenInformation(t,25,None,0,c.byref(n));buf=c.create_string_buffer(n.value)
        if not a.GetTokenInformation(t,25,buf,n,c.byref(n)):raise c.WinError(c.get_last_error())
        sid=c.cast(buf,c.POINTER(c.c_void_p)).contents.value
        count=a.GetSidSubAuthorityCount(sid).contents.value
        r['integrity_rid']=a.GetSidSubAuthority(sid,count-1).contents.value
    finally:
        if t:k.CloseHandle(t)
        k.CloseHandle(h)
(root/'live-token-query.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print(json.dumps(out,indent=2))
