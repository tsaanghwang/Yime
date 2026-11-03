import datetime
import importlib.util
import json
import os
from pathlib import Path
import sys

root=Path(__file__).absolute().parents[2]
spec=importlib.util.spec_from_file_location('controller',Path(__file__).with_name('run_installed_frontend_checkpoints.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
observed=m.observe(os.getpid())
def info(text):
    p=Path(text)
    s=p.stat()
    return {'path':str(p),'absolute':str(p.absolute()),'resolved':str(p.resolve(strict=True)),
      'sha256':m.digest(p),'statDevice':s.st_dev,'statInode':s.st_ino,
      'ancestors':[{'path':str(a),'reparsePoint':bool(getattr(a.lstat(),'st_file_attributes',0)&1024),
                    'reparseTag':getattr(a.lstat(),'st_reparse_tag',None),'isSymlink':a.is_symlink()} for a in (p,*p.parents)]}
out={'observedUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'observation':observed,
     'sysExecutable':info(sys.executable),'processImage':info(observed['image']),
     'pathObjectEqual':Path(sys.executable)==Path(observed['image']),
     'sameFile':os.path.samefile(sys.executable,observed['image']),
     'processChanges':False,'hostStarted':False,'inputReplayed':False}
folder=root/'.generated/18u-host-diagnostics';folder.mkdir(exist_ok=True)
path=folder/'controller-image-ordinary.json'
if path.exists():raise ValueError('fresh evidence required')
path.write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8')
print(json.dumps(out,indent=2))
