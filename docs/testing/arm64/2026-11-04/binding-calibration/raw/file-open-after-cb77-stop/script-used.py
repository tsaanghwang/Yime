"""One read-only, non-sharing file-open observation; never write or install."""
import ctypes as c,hashlib,importlib.util,json,os
from ctypes import wintypes as w
from datetime import datetime,timezone
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=root/'.generated/18u-file-open-after-cb77-stop'
out.mkdir(exist_ok=False)
spec=importlib.util.spec_from_file_location('identity_reader',root/'.generated/touch-full-tools/run_installed_frontend_checkpoints.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
own=m.observe(os.getpid())
folder=Path(r'C:\Program Files\YimeCore 18u Touch')
anchor='afd950556cfc70afbdb8d62d8e7514c08173cb9f0b60146d3a7243680ab932fd'
assert m.digest(folder/'installed-18u-product.json')==anchor
create=m.api(m.K,'CreateFileW',w.HANDLE,w.LPCWSTR,w.DWORD,w.DWORD,c.c_void_p,w.DWORD,w.DWORD,w.HANDLE)
rows=[]
for name in ('Yime18uInstalledRuntime.exe','YimeBroker18u.exe','YimeTouchKeyboard.exe'):
    path=folder/'bin'/name
    digest=m.digest(path)
    c.set_last_error(0)
    handle=create(str(path),0x80000000,0,None,3,0x80,None)
    error=c.get_last_error()
    ok=handle != c.c_void_p(-1).value
    if ok:m.close(handle)
    rows.append({'path':str(path),'sha256':digest,'desiredAccess':'GENERIC_READ','shareMode':0,'creationDisposition':'OPEN_EXISTING','success':ok,'win32Error':0 if ok else error,'writeRequested':False})
record={'schema':'one-shot-read-only-exclusive-file-open-v1','observedUTC':datetime.now(timezone.utc).isoformat(),'observer':own,'oldManifestSHA256':anchor,'results':rows,'limitations':'These are exclusive READ opens after the failed installer exited. They are not elevated ReadWrite replacement probes and cannot identify the historical holder or prove the earlier failure cause.','operationRetries':0,'installedMutation':False}
(out/'observation.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(out/'script-used.py').write_bytes(Path(__file__).read_bytes())
print(json.dumps(record,ensure_ascii=False,indent=2))
