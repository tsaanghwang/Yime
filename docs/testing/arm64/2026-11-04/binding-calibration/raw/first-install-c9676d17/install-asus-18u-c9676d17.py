"""Reviewable one-attempt upgrade. Default mode is read-only preflight.

Only --install invokes the fixed native maintenance helper. It never closes a
document app, changes the default input method, resets data, or retries a failed
installation. The native installer owns stopping/replacing only its 18u product.
"""
from pathlib import Path, PurePosixPath
import argparse, datetime, hashlib, importlib.util, json, os, shutil, subprocess, sys

ROOT=Path(__file__).resolve().parents[2]
SOURCE='c9676d17e7ac396aba294980bc183c2bb4b08fca'
OLD_SOURCE='46dd58967266edcab3f0d3bb131015d81dc4b951'
VERSION='0.2.0-18u-arm64.2'
PACKAGE=ROOT/'.generated/asus-18u-repair-c9676d17/simple/package'
COMPLETE=ROOT/'.generated/asus-18u-repair-c9676d17/complete'
ZIP_NAME='yime-yimecore-18u-windows-arm64-c9676d17e7ac.zip'
ZIP_SHA='3f31f089a8526c369521003242ec092e54eaa9ec621b43e29a9826dd85c2d01f'
ZIP_BYTES=219928196
IDENTITY_NAME=ZIP_NAME.removesuffix('.zip')+'.identity.json'
IDENTITY_SHA='058f2f0aee9e4e1c806c23c28d4bb6d51b44fa460a18517b31907a8c5539e62b'
PLAN_SHA='b66195a6cd4220532ecafad112ff64f134d7835f006296416b70a1cdd00a64a2'
HELPER_SHA='cc5adb0000318acd2d9cf2af745386a9bb25d700d30112da038b30b2ac25b494'
MANIFEST_SHA='af790b803c45c935843c2821bd3f42c075499ac6aafd26f3e48cec5ba74c5e77'
OLD_MANIFEST_SHA='afd950556cfc70afbdb8d62d8e7514c08173cb9f0b60146d3a7243680ab932fd'
RELEASE_TAG='test-arm64-18u-calibration-c9676d17-20261104'
RELEASE_URL='https://github.com/tsaanghwang/Yime/releases/tag/'+RELEASE_TAG
DELIVERY=ROOT/'.generated/18u-repair-release-c9676d17/delivery-receipt.json'
CI=ROOT/'.generated/armfull-tools/ci-c9676d17.json'
INSTALL=Path(r'C:\Program Files\YimeCore 18u Touch')
TOOLS=ROOT/'.generated/armfull-tools'
UTILITY=ROOT/'.generated/touch-full-tools/run_installed_frontend_checkpoints.py'
PINNED={
 '.generated/armfull-tools/capture-installed.ps1':'c75b66779a9db0990a8fb88864fdc2683debf734e7139225943688910fd5c2c1',
 '.generated/armfull-tools/run_checked_local.py':'2965e0ba391380d79b42df0ace657210d3d2624085c675fed926b7c3c98a14d5',
 'tools/powershell/run_checked.py':'09ed4b1cc4e6c05b90019bd69f12a0cb68b9ac825dc8f47dfcbfcff4a3d6d261',
 'installer/simple/Product.psm1':'a0b3c82b2e3d539f18b3dacbd9f65025b0541d667a2edd9bdc4fb9ed40dc1c22',
 '.generated/armfull-tools/query-asus-18u-locks.ps1':'70742862887a68973592a252bf991db1ed4a6888cb86a79bbd495e38991c60dd',
 '.generated/touch-full-tools/run_installed_frontend_checkpoints.py':'a97d8fcc7a9e85ed9f4ecd6166dabe4c03cd05ece756fa79666618633cf0a349',
}
class GateError(RuntimeError):pass
def need(value, message):
    if not value:raise GateError(message)
def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    return h.hexdigest()
def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def save(path,value):Path(path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def checked(report,script,stage):
    params=report/(stage+'-params.json');save(params,{'Report':str(report/(stage+'.json'))})
    command=[sys.executable,str(TOOLS/'run_checked_local.py'),'--edition','ps7','--script',str(TOOLS/script),'--params-file',str(params)]
    with (report/(stage+'-capture.log')).open('wb') as log:
        code=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT).returncode
    need(code==0,stage+' checked PowerShell failed; inspect raw capture log')
    return read(report/(stage+'.json'))
def load_observer():
    for path,expected in PINNED.items():need(digest(ROOT/path)==expected,'Local observation helper changed: '+path)
    spec=importlib.util.spec_from_file_location('only_read_identity',UTILITY)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    # Only observe()/Win32 query APIs are used; never this module's run()/stop/controller.
    return module
def verify_ci():
    ci=read(CI)
    need(ci['repository']=='tsaanghwang/Yime' and ci['headSha']==SOURCE and ci['passed'] is True,'CI source identity mismatch')
    need(ci['counts']=={'success':21,'expectedManualOnlySkipped':3,'failed':0,'pending':0},'Unexpected CI totals')
    expected={'18u async route contracts','Touch terminal prototype','ARM64 complete input contracts','Build'}
    need(len(ci['workflows'])==4 and {x['name'] for x in ci['workflows']}==expected,'Incomplete CI workflows')
    need(all(x['headSha']==SOURCE and x['status']=='completed' and x['conclusion']=='success' for x in ci['workflows']),'CI workflow not successful')
    skips={'one-shot-18u-language-prepare','one-shot-18u-registration-probe','one-shot-18u-language-inventory'}
    need(len(ci['checks'])==24 and len({x['id'] for x in ci['checks']})==24,'CI check count/identity mismatch')
    need(all(x['headSha']==SOURCE and x['status']=='completed' and (x['conclusion']=='success' or (x['conclusion']=='skipped' and x['name'] in skips)) for x in ci['checks']),'Unexpected CI failure/skip')
    need({x['name'] for x in ci['checks'] if x['conclusion']=='skipped'}==skips,'Historical skip set changed')
    return ci
def verify_release():
    delivery=read(DELIVERY)
    need(delivery['source']==SOURCE and delivery['draft'] is False and delivery['prerelease'] is True and delivery['url']==RELEASE_URL,'Exact release is not published')
    expected={ZIP_NAME:(ZIP_BYTES,ZIP_SHA),IDENTITY_NAME:(219346,IDENTITY_SHA)}
    for name,(size,sha) in expected.items():
        rows=[x for x in delivery['assets'] if x['name']==name]
        need(len(rows)==1,'Release asset missing/ambiguous: '+name)
        row=rows[0]
        need(row['state']=='uploaded' and row['size']==size and row['digest']=='sha256:'+sha and row['url']=='https://github.com/tsaanghwang/Yime/releases/download/'+RELEASE_TAG+'/'+name,'Release asset identity mismatch: '+name)
    return delivery
def verify_package():
    need(digest(COMPLETE/IDENTITY_NAME)==IDENTITY_SHA,'Package identity changed')
    identity=read(COMPLETE/IDENTITY_NAME)
    need(identity['source']['commit']==SOURCE and identity['source']['clean'] is True and identity['deliveryState']=='source-frozen' and identity['product']=='yimecore-18u' and identity['target']=='windows-arm64','Package source/product mismatch')
    need(identity['zip']=={'bytes':ZIP_BYTES,'name':ZIP_NAME,'sha256':ZIP_SHA},'ZIP receipt mismatch')
    need((COMPLETE/ZIP_NAME).stat().st_size==ZIP_BYTES and digest(COMPLETE/ZIP_NAME)==ZIP_SHA,'Local ZIP mismatch')
    files=identity['files'];actual=set()
    for p in PACKAGE.rglob('*'):
        need(not p.is_symlink() and not p.is_junction(),'Package reparse entry: '+str(p))
        if p.is_file():actual.add(p.relative_to(PACKAGE).as_posix())
    need(len(files)==1156 and actual==set(files),'Package member inventory changed')
    for name,row in files.items():
        rel=PurePosixPath(name);need(not rel.is_absolute() and '..' not in rel.parts and '\\' not in name and ':' not in name,'Unsafe member')
        p=PACKAGE/name;need(p.stat().st_size==row['bytes'] and digest(p)==row['sha256'],'Package bytes changed: '+name)
    need(digest(PACKAGE/'YimeMaintenance.exe')==HELPER_SHA and digest(PACKAGE/'maintenance-plan.json')==PLAN_SHA,'Native helper/plan changed')
    manifest=read(PACKAGE/'product-package.json')
    need(manifest['product']=='yimecore-18u' and manifest['version']==VERSION and manifest['target']=='windows-arm64' and len(manifest['files'])==20,'Payload contract changed')
    need(digest(PACKAGE/'payload/installed-18u-product.json')==MANIFEST_SHA,'New installed manifest changed')
    return manifest
def products(snapshot):
    rows={x['id']:x for x in snapshot['products']}
    need(set(rows)=={'yimecore','rime-pime','yimecore-18u'},'Three-product snapshot incomplete')
    for key,row in rows.items():
        need(row['exists'] and row['payload'] and all(x['exists'] and x['match'] for x in row['payload']),'Installed payload mismatch: '+key)
    return rows
def extra_identity(snapshot,observer):
    result={}
    for row in snapshot['products']:
        folder=Path(row['root']);meta={}
        for p in [folder/'.yime-product.json',*(folder/'.setup').rglob('*')]:
            if p.is_file():meta[p.relative_to(folder).as_posix()]=digest(p)
        live=[observer.observe(int(x['pid'])) for x in row['processes']]
        result[row['id']]={'metadataSHA256':meta,'liveProcesses':sorted(live,key=lambda x:x['pid'])}
    return result
def old_product(snapshot):
    row=products(snapshot)['yimecore-18u']
    need(row['root'].casefold()==str(INSTALL).casefold() and row['version']=='0.2.0-18u-arm64.1','This orchestrator only upgrades the installed .1 product')
    need(digest(INSTALL/'installed-18u-product.json')==OLD_MANIFEST_SHA and read(INSTALL/'installed-18u-product.json')['sourceCommit']==OLD_SOURCE,'Old 46dd product manifest changed')
def compare_after(before,after,bextra,aextra,manifest,observer):
    old,new=products(before),products(after)
    need(before['defaultInputOverride']==after['defaultInputOverride'],'Default input override changed')
    for key in ('yimecore','rime-pime'):
        need(old[key]==new[key] and bextra[key]==aextra[key],'Unrelated product changed: '+key)
    changed=new['yimecore-18u'];need(changed['version']==VERSION,'New installed version mismatch')
    need(digest(INSTALL/'installed-18u-product.json')==MANIFEST_SHA,'New installed source manifest mismatch')
    want={x['path']:x['sha256'] for x in manifest['files']}
    need({x['path']:x['sha256'] for x in changed['payload']}==want,'New installed 20-file payload mismatch')
    need(changed['registrations']==old['yimecore-18u']['registrations'],'18u COM path/views changed unexpectedly')
    processes=aextra['yimecore-18u']['liveProcesses']
    runtime=[x for x in processes if x['image'].casefold()==str(INSTALL/'bin/Yime18uInstalledRuntime.exe').casefold()]
    need(len(runtime)==1,'Expected one ordinary installed runtime')
    current=runtime[0]
    need(current['token']['elevated']==0 and current['token']['integrity']==8192 and current['token']['sid']==observer['token']['sid'] and current['token']['session']==observer['token']['session'],'Installed runtime token mismatch')
    for p in processes:
        need(p['token']['elevated']==0 and p['token']['sid']==observer['token']['sid'],'Unexpected elevated/foreign 18u process')
    return current
def main():
    parser=argparse.ArgumentParser(description=__doc__);group=parser.add_mutually_exclusive_group()
    group.add_argument('--preflight',action='store_true');group.add_argument('--install',action='store_true')
    args=parser.parse_args()
    report=(ROOT/'.generated/complete-input-install/asus-18u-c9676d17') if args.install else (ROOT/'.generated/asus-18u-preflight-c9676d17'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    report.mkdir(parents=True,exist_ok=False) # Never replace the first attempt or its failure.
    result={'schema':'asus-18u-upgrade-attempt-v1','sourceCommit':SOURCE,'version':VERSION,'mode':'install' if args.install else 'preflight','startedUTC':now(),'package':str(PACKAGE),'archiveSHA256':ZIP_SHA,'releaseURL':RELEASE_URL,'installCalled':False,'resetData':False,'otherProductsRequested':False,'automaticRetry':False,'report':str(report)}
    before=None;before_extra=None;observer=None;manifest=None;exitcode=1
    try:
        utility=load_observer();observer=utility.observe(os.getpid());result['ordinaryParent']=observer
        need(observer['token']['elevated']==0 and observer['token']['integrity']==8192,'Must run from the ordinary Medium user, not an administrator')
        manifest=verify_package();result['packageVerified']=True
        ci=verify_ci();shutil.copyfile(CI,report/'ci-receipt.json');result['ciVerified']=True
        if DELIVERY.exists():
            try:verify_release();result['releasePublished']=True;shutil.copyfile(DELIVERY,report/'delivery-receipt.json')
            except Exception as e:result['releasePublished']=False;result['releaseGateError']=str(e)
        else:result['releasePublished']=False
        before=checked(report,'capture-installed.ps1','before');old_product(before)
        before_extra=extra_identity(before,utility);save(report/'before-extra.json',before_extra)
        locks=checked(report,'query-asus-18u-locks.ps1','dll-users');result['dllUsers']=locks['users']
        result['prerequisites']=[]
        if locks['users']:result['prerequisites'].append('The listed application(s) still use the old 18u DLL. Save and close them explicitly before upgrade; this script never closes them.')
        if not result['releasePublished']:result['prerequisites'].append('The exact source/ZIP/identity release must be published and its delivery receipt verified.')
        if not args.install:
            result['readyForInstall']=not result['prerequisites']
        else:
            need(result['releasePublished'],'Exact published release gate is not satisfied')
            need(not locks['users'],'Installed 18u DLL is in use; no installation started')
            # Revalidate the exact bound entry immediately before the only mutation call.
            need(digest(PACKAGE/'YimeMaintenance.exe')==HELPER_SHA and digest(PACKAGE/'maintenance-plan.json')==PLAN_SHA,'Maintenance entry changed after preflight')
            result['installCalled']=True;result['installStartedUTC']=now()
            with (report/'setup-output.log').open('wb') as log:
                process=subprocess.Popen([str(PACKAGE/'YimeMaintenance.exe'),'-action','Install'],cwd=PACKAGE,stdout=log,stderr=subprocess.STDOUT)
                result['maintenancePID']=process.pid
                result['installerExitCode']=process.wait() # Never kill an elevated child or silently retry.
            result['installCompletedUTC']=now()
            need(result['installerExitCode']==0,'Native installer failed; first failure and raw output preserved')
        exitcode=0
    except BaseException as e:
        result['firstFailure']=repr(e);exitcode=result.get('installerExitCode',1) or 1
    finally:
        if before is not None:
            try:
                after=checked(report,'capture-installed.ps1','after');after_extra=extra_identity(after,utility);save(report/'after-extra.json',after_extra)
                if result['installCalled']:
                    # Also report isolation on a failed/partial 18u install without
                    # requiring the changed 18u payload to be internally complete.
                    old_rows={x['id']:x for x in before['products']};new_rows={x['id']:x for x in after['products']}
                    isolation=before['defaultInputOverride']==after['defaultInputOverride'] and all(old_rows.get(key)==new_rows.get(key) and before_extra.get(key)==after_extra.get(key) for key in ('yimecore','rime-pime'))
                    result['unrelatedProductsAndDefaultUnchanged']=isolation
                    need(isolation,'Unrelated products or default input changed during installation')
                if result['installCalled'] and result.get('installerExitCode')==0:
                    runtime=compare_after(before,after,before_extra,after_extra,manifest,observer)
                    result.update(runtimePID=runtime['pid'],runtimeCreationTicks=runtime['creationTicks'],runtimeImage=runtime['image'],runtimeToken=runtime['token'],runtimeSHA256=digest(runtime['image']),only18uChanged=True,postInstallVerified=True)
                elif not result['installCalled']:
                    need(products(before)==products(after) and before['defaultInputOverride']==after['defaultInputOverride'] and before_extra==after_extra,'Read-only preflight observed concurrent product/default changes')
                    result['readOnlySnapshotsStable']=True
            except BaseException as e:
                result.setdefault('firstFailure',repr(e));result['afterValidationError']=repr(e);exitcode=1
        result['completedUTC']=now();result['exitCode']=exitcode
        save(report/'install-result.json',result)
        print(json.dumps(result,ensure_ascii=False,indent=2),flush=True)
    return exitcode
if __name__=='__main__':raise SystemExit(main())
