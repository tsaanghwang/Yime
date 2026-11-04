"""Upload a source-frozen draft while CI runs; publish only after exact-source CI."""
import argparse,hashlib,json,re,subprocess,sys,zipfile
from datetime import datetime,timezone
from pathlib import Path
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('source')
parser.add_argument('--stage',choices=['draft','publish'],required=True)
args=parser.parse_args()
source=args.source
assert re.fullmatch('[0-9a-f]{40}',source)
short=source[:8]
repo='tsaanghwang/Yime'
tag='test-arm64-18u-wait-'+short+'-20261104'
build=root/('.generated/asus-18u-wait-repair-'+short)
out=root/('.generated/18u-wait-repair-release-'+short)
out.mkdir(exist_ok=True)
assert not (out/'delivery-receipt.json').exists(),'Already published; read receipt instead of rerunning'
def read(path):return json.loads(Path(path).read_text(encoding='utf-8'))
def sha(path):
    with Path(path).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
receipt=read(build/'complete-package-receipt.json')
assert receipt['sourceCommit']==source and receipt['version']=='0.2.0-18u-arm64.4'
identity_path=Path(receipt['identity'])
identity=read(identity_path)
assert identity['source']['commit']==source and identity['source']['clean'] is True
assert identity['product']=='yimecore-18u' and identity['target']=='windows-arm64'
archive=build/'complete'/receipt['zip']['name']
assert identity['zip']==receipt['zip'] and sha(archive)==receipt['zip']['sha256'] and archive.stat().st_size==receipt['zip']['bytes']
with zipfile.ZipFile(archive) as z:
    names=[i.filename for i in z.infolist() if not i.is_dir()]
    assert len(names)==len(set(names))==identity['fileCount'] and set(names)==set(identity['files'])
    for name,row in identity['files'].items():
        data=z.read(name)
        assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],name
build_asset=out/('native-build-'+short+'.json')
build_asset.write_bytes((build/'build-receipt.json').read_bytes())
assets=[(p,sha(p),p.stat().st_size) for p in (archive,identity_path,build_asset)]
ci=None
if args.stage=='publish':
    ci_path=root/('.generated/armfull-tools/ci-'+short+'.json')
    ci=read(ci_path)
    assert ci['headSha']==source and ci['passed'] is True
    assert ci['counts']['success']>=19 and ci['counts']['expectedManualOnlySkipped']==3 and ci['counts']['failed']==0 and ci['counts']['pending']==0
    assert {'Build','ARM64 complete input contracts'}.issubset({w['name'] for w in ci['workflows']})
    assert all(w['headSha']==source and w['status']=='completed' and w['conclusion']=='success' and w['attempt']==1 for w in ci['workflows'])
    allowed={'one-shot-18u-language-prepare','one-shot-18u-registration-probe','one-shot-18u-language-inventory'}
    assert len({c['id'] for c in ci['checks']})==len(ci['checks'])
    assert all(c['headSha']==source and c['status']=='completed' and (c['conclusion']=='success' or (c['conclusion']=='skipped' and c['name'] in allowed)) for c in ci['checks'])
    assert {c['name'] for c in ci['checks'] if c['conclusion']=='skipped'}==allowed
    assert sum(c['conclusion']=='skipped' for c in ci['checks'])==3
    assert sum(c['conclusion']=='success' for c in ci['checks'])==ci['counts']['success']
    asset=out/('source-ci-'+short+'.json');asset.write_bytes(ci_path.read_bytes())
    assets.append((asset,sha(asset),asset.stat().st_size))
notes=out/('release-notes-'+args.stage+'.md')
ci_text=('Exact-source CI completed: '+str(ci['counts']['success'])+' successful checks, 3 existing manual-only skips, no failures. See the attached CI receipt for workflows and direct URLs.') if ci else 'DRAFT: exact-source CI has not yet been confirmed by this draft step. Installation is not authorized by this draft.'
notes.write_text('''18u ARM64 development package 0.2.0-18u-arm64.4.

Frozen source: `'''+source+'''`.

Strengthens installer shutdown verification by requiring the held original process handle to become signaled before protected payload replacement. A private native ARM64 fixture demonstrated that exit code 37 can be observable while the process handle still returns WAIT_TIMEOUT; an exit-code observation alone does not prove completion. The cb77b675/.3 running-upgrade attempt stopped processes but then encountered sharing violation 32 on the Broker file before payload copying. The specific cause or owner of that historical sharing violation has not been determined. This .4 change closes the demonstrated wait-completion gap; it does not claim that the historical sharing violation has been causally explained or that an installed upgrade has passed. Previous failed attempts and packages remain preserved.

Includes the c9676d17 per-display ruler calibration and cold TIP loading validation. The ASUS 57.5 mm observation can be saved for normal startup at 3840 x 2400 / 250%, reducing only blank outer margins to fit the board. Key geometry and Windows scaling are unchanged; the user must still remeasure the ruler and complete real finger input in the application body.

'''+ci_text+'''

Local native ARM64 build and complete archive validation passed. Installed/software/physical acceptance of this .4 package is pending at publication. Run YimeMaintenance.exe -action Install from an ordinary user parent; the installer handles UAC. Only YimeCore 18u Touch is updated. Standard YimeCore and Rime/PIME retain separate fixed deliveries and the default input method is preserved. x64/x86/ARM64EC host compatibility is unverified. Development binaries are not trusted-signed public releases.

Assets:
'''+''.join(f'- `{p.name}`: SHA256 `{h}`, {n} bytes\n' for p,h,n in assets),encoding='utf-8')
def run(*values,check=True):
    p=subprocess.run([sys.executable,'-B','-X','utf8',str(root/'.generated/armfull-tools/gh_repo.py'),*values],capture_output=True,text=True,encoding='utf-8')
    if check and p.returncode:raise RuntimeError(p.stderr)
    return p
def remote(allow_missing=False):
    p=run('release','view',tag,'--repo',repo,'--json','assets,isDraft,isPrerelease,url,tagName,targetCommitish',check=False)
    if p.returncode:
        if allow_missing and ('release not found' in p.stderr.lower() or 'HTTP 404' in p.stderr):return None
        raise RuntimeError(p.stderr)
    return json.loads(p.stdout)
current=remote(True)
if current is None:
    assert args.stage=='draft','Publish must follow a separately reviewed draft upload'
    run('release','create',tag,'--repo',repo,'--target',source,'--draft','--prerelease','--title','ARM64 18u .4: process wait completion and display calibration','--notes-file',str(notes))
else:
    assert current['targetCommitish']==source and current['isDraft'] is True
for path,digest,size in assets:
    current=remote()
    assert current['targetCommitish']==source and current['isDraft'] is True
    existing=next((a for a in current['assets'] if a['name']==path.name),None)
    if existing is None:
        print('Uploading '+path.name,flush=True)
        run('release','upload',tag,str(path),'--repo',repo)
        existing=next(a for a in remote()['assets'] if a['name']==path.name)
    assert existing['digest']=='sha256:'+digest and existing['size']==size and existing['state']=='uploaded',path.name
    print('Verified remote SHA256 and size: '+path.name,flush=True)
def validate_assets(current):
    expected={p.name:(digest,size) for p,digest,size in assets}
    assert len(expected)==len(assets)
    actual=current['assets']
    assert len(actual)==len({a['name'] for a in actual})==len(expected)
    assert {a['name'] for a in actual}==set(expected),'Unexpected or missing draft assets'
    for row in actual:
        digest,size=expected[row['name']]
        assert row['digest']=='sha256:'+digest and row['size']==size and row['state']=='uploaded',row['name']
validate_assets(remote())
if args.stage=='publish':
    run('release','edit',tag,'--repo',repo,'--draft=false','--prerelease','--latest=false','--notes-file',str(notes))
current=remote()
assert current['targetCommitish']==source and current['isDraft']==(args.stage=='draft')
validate_assets(current)
record={'source':source,'stage':args.stage,'verifiedAtUTC':datetime.now(timezone.utc).isoformat(),'url':current['url'],'draft':current['isDraft'],'prerelease':current['isPrerelease'],'ciCounts':ci['counts'] if ci else None,'assets':[{'name':a['name'],'size':a['size'],'digest':a['digest'],'url':a['url'],'state':a['state']} for a in current['assets']]}
(out/('delivery-receipt.json' if args.stage=='publish' else 'draft-receipt.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(record,ensure_ascii=False,indent=2),flush=True)
