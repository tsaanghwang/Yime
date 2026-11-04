import hashlib,json,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=root/'.generated/18u-race-repair-release-cb77b675'
result=json.loads((root/'.generated/complete-input-install/asus-18u-cb77b675/install-result.json').read_text(encoding='utf-8'))
assert result['installerExitCode']==1 and result['unrelatedProductsAndDefaultUnchanged'] is True and result['runningUpgradeBaselineVerified'] is True
tag='test-arm64-18u-upgrade-cb77b675-20261104'
source='cb77b675ff6964c7b069294222200a5060316bd2'
notes=out/'release-notes-after-install-failure.md'
notes.write_text('''Installation update, 2026-11-04: one running-upgrade attempt restored and verified the intact old .1 Runtime/Broker/GUI before invoking this package. The corrected process-stop stage passed. The next exclusive ReadWrite file check failed for old YimeBroker18u.exe with sharing violation 32; Restart Manager reported zero users. This does not identify the historical holder. No unregister/copy occurred: the old .1 payload remains intact, its processes stopped, and standard YimeCore/Rime/PIME/default input override were unchanged. No calibration was saved and no physical acceptance passed. The failed attempt is preserved. Further work is checking the process-exit waiting boundary; this package is not a passed running-upgrade delivery. Existing assets remain unchanged.

---

'''+(out/'release-notes-publish.md').read_text(encoding='utf-8'),encoding='utf-8')
def run(*args):
    r=subprocess.run([sys.executable,'-B','-X','utf8',str(root/'.generated/armfull-tools/gh_repo.py'),*args],capture_output=True,text=True,encoding='utf-8')
    if r.returncode:raise RuntimeError(r.stderr)
    return r.stdout
current=json.loads(run('release','view',tag,'--repo','tsaanghwang/Yime','--json','targetCommitish,isDraft'))
assert current['targetCommitish']==source and current['isDraft'] is False
run('release','edit',tag,'--repo','tsaanghwang/Yime','--notes-file',str(notes))
current=json.loads(run('release','view',tag,'--repo','tsaanghwang/Yime','--json','body,targetCommitish,isDraft,url'))
assert current['body'].replace('\r\n','\n').rstrip()==notes.read_text(encoding='utf-8').rstrip()
receipt={'source':source,'url':current['url'],'notesSHA256':hashlib.sha256(notes.read_bytes()).hexdigest(),'assetsChanged':False,'installationOutcome':'failed at file-sharing gate before unregister/copy','bodyReadbackMatched':True}
(out/'failure-note-update-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
print(json.dumps(receipt,indent=2))
