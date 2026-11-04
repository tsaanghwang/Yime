import hashlib,json,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=root/'.generated/18u-repair-release-c9676d17'
result=json.loads((root/'.generated/complete-input-install/asus-18u-c9676d17/install-result.json').read_text(encoding='utf-8'))
assert result['installerExitCode']==1 and result['unrelatedProductsAndDefaultUnchanged'] is True
tag='test-arm64-18u-calibration-c9676d17-20261104'
source='c9676d17e7ac396aba294980bc183c2bb4b08fca'
notes=out/'release-notes-after-install-failure.md'
notes.write_text('''Installation update, 2026-11-04: the one attempted upgrade from the running 18u .1 installation failed before unregistering or copying files. Setup queried GetOwnerSid for an old Broker process snapshot after Runtime shutdown had already ended Broker; CIM returned 0x80041002 (NotFound). The old .1 files remain intact; its background processes stopped. Standard YimeCore, Rime/PIME and the default input override were unchanged. No calibration was saved and no physical acceptance passed. The first failure is preserved in the branch evidence. A separate .3 installer correction is being prepared; do not infer successful upgrade from this package's source CI. Existing assets remain byte-for-byte unchanged.

---

'''+(out/'release-notes.md').read_text(encoding='utf-8'),encoding='utf-8')
def run(*args):
    r=subprocess.run([sys.executable,'-B','-X','utf8',str(root/'.generated/armfull-tools/gh_repo.py'),*args],capture_output=True,text=True,encoding='utf-8')
    if r.returncode:raise RuntimeError(r.stderr)
    return r.stdout
current=json.loads(run('release','view',tag,'--repo','tsaanghwang/Yime','--json','targetCommitish,isDraft'))
assert current['targetCommitish']==source and current['isDraft'] is False
run('release','edit',tag,'--repo','tsaanghwang/Yime','--notes-file',str(notes))
current=json.loads(run('release','view',tag,'--repo','tsaanghwang/Yime','--json','body,targetCommitish,isDraft,url'))
assert current['body'].replace('\r\n','\n').rstrip()==notes.read_text(encoding='utf-8').rstrip()
receipt={'source':source,'url':current['url'],'notesSHA256':hashlib.sha256(notes.read_bytes()).hexdigest(),'assetsChanged':False,'installationOutcome':'failed before unregister/copy','bodyReadbackMatched':True}
(out/'failure-note-update-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
print(json.dumps(receipt,indent=2))
