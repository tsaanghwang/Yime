"""Reviewable one-attempt upgrade. Default mode is read-only preflight.

Only --install invokes the fixed native maintenance helper. The additional
--restore-original-runtime flag permits one validated .1 runtime launch first.
All new package/CI/publication gates must pass before that launch. It never closes a
document app, changes the default input method, resets data, or retries a failed
installation. The native installer owns stopping/replacing only its 18u product.
"""
from pathlib import Path, PurePosixPath
import argparse, datetime, hashlib, importlib.util, json, os, shutil, subprocess, sys, time

ROOT=Path(__file__).resolve().parents[2]
SOURCE='cb77b675ff6964c7b069294222200a5060316bd2'
OLD_SOURCE='46dd58967266edcab3f0d3bb131015d81dc4b951'
VERSION='0.2.0-18u-arm64.3'
PACKAGE=ROOT/'.generated/asus-18u-race-repair-cb77b675/simple/package'
COMPLETE=ROOT/'.generated/asus-18u-race-repair-cb77b675/complete'
ZIP_NAME='yime-yimecore-18u-windows-arm64-cb77b675ff69.zip'
ZIP_SHA='e38b82c8b492cb93595dbca66c14fbda6019e48e131d8869477997f1bc474997'
ZIP_BYTES=219928908
IDENTITY_NAME=ZIP_NAME.removesuffix('.zip')+'.identity.json'
IDENTITY_SHA='0a0792016bdc75edaac038061b836e4b54e91eb166584c9ccb4e6962e6c689f3'
IDENTITY_BYTES=219346
PLAN_SHA='d0b23559a03b1ad5d01df9142a8aaef1ce892f088551b7993bc5895a1d57021c'
HELPER_SHA='4605c735b7962f1946cc6a2fdf706256e555c54830de7ba445f43d5ad6a459cd'
MANIFEST_SHA='0ff013204ca450b45d8ac24ba4dac8eee9e2cfbc2ff0d158f78d65482d634bad'
OLD_MANIFEST_SHA='afd950556cfc70afbdb8d62d8e7514c08173cb9f0b60146d3a7243680ab932fd'
RELEASE_TAG='test-arm64-18u-upgrade-cb77b675-20261104'
RELEASE_URL='https://github.com/tsaanghwang/Yime/releases/tag/'+RELEASE_TAG
DELIVERY=ROOT/'.generated/18u-race-repair-release-cb77b675/delivery-receipt.json'
CI=ROOT/'.generated/armfull-tools/ci-cb77b675.json'
INSTALL=Path(r'C:\Program Files\YimeCore 18u Touch')
TOOLS=ROOT/'.generated/armfull-tools'
UTILITY=ROOT/'.generated/touch-full-tools/run_installed_frontend_checkpoints.py'
FAMILY_READER=ROOT/'.generated/asus-18u-prepared-c9676d17/capture_installed_frontend_identity.py'
FIRST_BEFORE=ROOT/'.generated/complete-input-install/asus-18u-c9676d17/before.json'
FIRST_BEFORE_SHA='81f70be3701615c2fa7dd3946fe267de9ff38e396958a518b77f30d7170dcbb5'
PINNED={
 '.generated/armfull-tools/capture-installed.ps1':'c75b66779a9db0990a8fb88864fdc2683debf734e7139225943688910fd5c2c1',
 '.generated/armfull-tools/run_checked_local.py':'2965e0ba391380d79b42df0ace657210d3d2624085c675fed926b7c3c98a14d5',
 'tools/powershell/run_checked.py':'09ed4b1cc4e6c05b90019bd69f12a0cb68b9ac825dc8f47dfcbfcff4a3d6d261',
 'installer/simple/Product.psm1':'a0b3c82b2e3d539f18b3dacbd9f65025b0541d667a2edd9bdc4fb9ed40dc1c22',
 '.generated/armfull-tools/query-asus-18u-locks.ps1':'70742862887a68973592a252bf991db1ed4a6888cb86a79bbd495e38991c60dd',
 '.generated/touch-full-tools/run_installed_frontend_checkpoints.py':'a97d8fcc7a9e85ed9f4ecd6166dabe4c03cd05ece756fa79666618633cf0a349',
 '.generated/asus-18u-prepared-c9676d17/capture_installed_frontend_identity.py':'38283c254f5b3cc51ad91b422497e7628c0cb48d1b23b0fe3d46ec576b381c37',
 '.generated/asus-18u-prepared-c9676d17/run_installed_frontend_checkpoints.py':'a97d8fcc7a9e85ed9f4ecd6166dabe4c03cd05ece756fa79666618633cf0a349',
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
    need(ci['counts']=={'success':19,'expectedManualOnlySkipped':3,'failed':0,'pending':0},'Unexpected CI totals')
    expected={'ARM64 complete input contracts','Build'}
    need(len(ci['workflows'])==2 and {x['name'] for x in ci['workflows']}==expected,'Incomplete CI workflows')
    need(all(x['headSha']==SOURCE and x['event']=='push' and x['attempt']==1 and x['status']=='completed' and x['conclusion']=='success' for x in ci['workflows']),'CI workflow not successful')
    skips={'one-shot-18u-language-prepare','one-shot-18u-registration-probe','one-shot-18u-language-inventory'}
    need(len(ci['checks'])==22 and len({x['id'] for x in ci['checks']})==22,'CI check count/identity mismatch')
    need(all(x['headSha']==SOURCE and x['status']=='completed' and (x['conclusion']=='success' or (x['conclusion']=='skipped' and x['name'] in skips)) for x in ci['checks']),'Unexpected CI failure/skip')
    need({x['name'] for x in ci['checks'] if x['conclusion']=='skipped'}==skips,'Historical skip set changed')
    return ci
def verify_release():
    delivery=read(DELIVERY)
    need(delivery['source']==SOURCE and delivery['draft'] is False and delivery['prerelease'] is True and delivery['url']==RELEASE_URL,'Exact release is not published')
    expected={ZIP_NAME:(ZIP_BYTES,ZIP_SHA),IDENTITY_NAME:(IDENTITY_BYTES,IDENTITY_SHA)}
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

def unrelated_unchanged(before,after,bextra,aextra):
    old={x['id']:x for x in before['products']};new={x['id']:x for x in after['products']}
    return before['defaultInputOverride']==after['defaultInputOverride'] and all(old.get(key)==new.get(key) and bextra.get(key)==aextra.get(key) for key in ('yimecore','rime-pime'))

def running_original(report,before,utility,observer,result,allow_restore):
    # Gates precede any explicit restoration. This function never installs,
    # retries a launch, or stops an application/runtime to obtain a clean state.
    need(result.get('packageVerified') and result.get('ciVerified') and result.get('releasePublished'),'Restore requires the verified new package, CI and published release')
    need(digest(FIRST_BEFORE)==FIRST_BEFORE_SHA,'First failed attempt before snapshot changed')
    original=products(read(FIRST_BEFORE))['yimecore-18u'];current=products(before)['yimecore-18u']
    need({k:v for k,v in current.items() if k!='processes'}=={k:v for k,v in original.items() if k!='processes'},'Old product payload/registration/startup no longer matches the preserved first attempt')
    argv=[str(INSTALL/'bin/Yime18uInstalledRuntime.exe'),'--installed-18u-run','--install-root',str(INSTALL),'--manifest-sha256',OLD_MANIFEST_SHA]
    need(original['startup']=={'result':0,'value':subprocess.list2cmdline(argv)},'Original startup differs from the exact checked argument vector')
    need(digest(INSTALL/'bin/Yime18uInstalledRuntime.exe')==next(x['sha256'] for x in original['payload'] if x['path']=='bin/Yime18uInstalledRuntime.exe'),'Original runtime changed')
    runtimes=[x for x in current['processes'] if x['path'].casefold()==argv[0].casefold()]
    result['runtimeRestoration']={'requested':allow_restore,'launched':False,'firstBeforeSHA256':FIRST_BEFORE_SHA,'arguments':argv,'creationFlags':subprocess.DETACHED_PROCESS}
    if not current['processes']:
        need(allow_restore,'Old runtime is stopped; explicit --restore-original-runtime is required for this running-upgrade reproduction')
        result['runtimeRestoreAttempted']=True
        save(report/'install-result.json',result)
        with (report/'original-runtime-restore.log').open('wb') as log:
            process=subprocess.Popen(argv,cwd=INSTALL,stdin=subprocess.DEVNULL,stdout=log,stderr=log,creationflags=subprocess.DETACHED_PROCESS)
        result['runtimeRestoration'].update(launched=True,pid=process.pid)
        runtime_pid=process.pid
        save(report/'install-result.json',result)
    else:
        need(len(current['processes'])==3 and len(runtimes)==1,'Existing old runtime family is partial/ambiguous; no second runtime will be started')
        runtime_pid=int(runtimes[0]['pid'])
    spec=importlib.util.spec_from_file_location('read_only_runtime_children',FAMILY_READER)
    reader=importlib.util.module_from_spec(spec);spec.loader.exec_module(reader)
    runtime=utility.observe(runtime_pid);utility.same_token(runtime,observer['token'])
    need(runtime['image'].casefold()==argv[0].casefold(),'Runtime PID path differs')
    deadline=time.monotonic()+120
    while True:
        children=reader.children(runtime_pid)
        need(not any(len(pids)>1 for pids in children.values()),'Ambiguous normal runtime children')
        need(utility.observe(runtime_pid)==runtime,'Original runtime identity changed/exited while observing its children')
        if all(len(pids)==1 for pids in children.values()):break
        need(time.monotonic()<deadline,'Normal Broker/GUI did not appear; no launch retry is permitted')
        time.sleep(.25) # Bounded read-only readiness observation, not an installation retry.
    rows=[dict(relative='bin/Yime18uInstalledRuntime.exe',**runtime)]
    for relative,pids in children.items():
        seen=utility.observe(pids[0]);utility.same_token(seen,observer['token'])
        need(seen['image'].casefold()==str(INSTALL/relative).casefold() and seen['creationTicks']>=runtime['creationTicks'],'Child process path/creation identity mismatch')
        rows.append(dict(relative=relative,**seen))
    hashes={x['path']:x['sha256'] for x in original['payload']}
    for row in rows:need(digest(row['image'])==hashes[row['relative']],'Running old product image changed')
    result['runtimeRestoration']['verifiedFamily']=rows
    save(report/'original-runtime-family.json',result['runtimeRestoration'])
    return rows
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
    parser.add_argument('--restore-original-runtime',action='store_true',help='With --install only: permit one checked old .1 runtime launch before capturing the running-upgrade baseline')
    args=parser.parse_args()
    if args.restore_original_runtime and not args.install:parser.error('--restore-original-runtime requires --install and its complete gates')
    report=(ROOT/'.generated/complete-input-install/asus-18u-cb77b675') if args.install else (ROOT/'.generated/asus-18u-preflight-cb77b675'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
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
        before=checked(report,'capture-installed.ps1','initial');old_product(before)
        before_extra=extra_identity(before,utility);save(report/'initial-extra.json',before_extra)
        locks=checked(report,'query-asus-18u-locks.ps1','dll-users');result['dllUsers']=locks['users']
        result['prerequisites']=[]
        if locks['users']:result['prerequisites'].append('The listed application(s) still use the old 18u DLL. Save and close them explicitly before upgrade; this script never closes them.')
        if not result['releasePublished']:result['prerequisites'].append('The exact source/ZIP/identity release must be published and its delivery receipt verified.')
        if not args.install:
            result['readyForInstall']=not result['prerequisites']
        else:
            need(result['releasePublished'],'Exact published release gate is not satisfied')
            need(not locks['users'],'Installed 18u DLL is in use; no installation started')
            family=running_original(report,before,utility,observer,result,args.restore_original_runtime)
            running=checked(report,'capture-installed.ps1','before');old_product(running)
            running_extra=extra_identity(running,utility);save(report/'before-extra.json',running_extra)
            need(unrelated_unchanged(before,running,before_extra,running_extra),'Other products/default changed before installation')
            wanted=sorted([{k:v for k,v in row.items() if k!='relative'} for row in family],key=lambda x:x['pid'])
            need(running_extra['yimecore-18u']['liveProcesses']==wanted,'Original runtime family changed before running-upgrade snapshot')
            before=running;before_extra=running_extra
            result['runningUpgradeBaselineVerified']=True
            final_locks=checked(report,'query-asus-18u-locks.ps1','before-install-dll-users')
            need(not final_locks['users'],'An application loaded the old DLL during runtime restoration; installation was not started')
            # Revalidate the exact bound entry immediately before the sole install.
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
                if result['installCalled'] or result.get('runtimeRestoreAttempted'):
                    # Also report isolation on a failed/partial 18u install without
                    # requiring the changed 18u payload to be internally complete.
                    isolation=unrelated_unchanged(before,after,before_extra,after_extra)
                    result['unrelatedProductsAndDefaultUnchanged']=isolation
                    need(isolation,'Unrelated products or default input changed during installation')
                if result['installCalled'] and result.get('installerExitCode')==0:
                    runtime=compare_after(before,after,before_extra,after_extra,manifest,observer)
                    result.update(runtimePID=runtime['pid'],runtimeCreationTicks=runtime['creationTicks'],runtimeImage=runtime['image'],runtimeToken=runtime['token'],runtimeSHA256=digest(runtime['image']),only18uChanged=True,postInstallVerified=True)
                elif result.get('runtimeRestoreAttempted'):
                    old_product(after)
                    result['oldPayloadIntactAfterRestoreAttempt']=True
                    result['noAutomaticRuntimeRetryOrRollback']=True
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
