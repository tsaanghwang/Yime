"""Inert restore-control checks: Popen, process observation and imports are mocked."""
from pathlib import Path
import copy, importlib.util, json, tempfile, types
from unittest.mock import patch
root=Path(__file__).resolve().parents[2]
path=root/'.generated/armfull-tools/install-asus-18u-cb77b675.py'
spec=importlib.util.spec_from_file_location('prepared_installer',path)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
original=m.read(m.FIRST_BEFORE)
old=next(x for x in original['products'] if x['id']=='yimecore-18u')
runtime_path=str(m.INSTALL/'bin/Yime18uInstalledRuntime.exe')
by_relative={x['path']:x['sha256'] for x in old['payload']}
token={'sid':'inert-fixture-user','integrity':8192,'elevated':0,'session':2,'authenticationLuid':'inert'}
seen={101:{'pid':101,'image':runtime_path,'creationTicks':100,'token':token},102:{'pid':102,'image':str(m.INSTALL/'bin/YimeBroker18u.exe'),'creationTicks':101,'token':token},103:{'pid':103,'image':str(m.INSTALL/'bin/YimeTouchKeyboard.exe'),'creationTicks':102,'token':token}}
def fake_digest(path):
    path=Path(path)
    if path==m.FIRST_BEFORE:return m.FIRST_BEFORE_SHA
    return by_relative[path.relative_to(m.INSTALL).as_posix()]
def fake_token(row,own):
    if row['token']!=own:raise ValueError('fixture foreign token')
class ReaderLoader:
    def exec_module(self,module):module.children=lambda pid:{'bin/YimeBroker18u.exe':[102],'bin/YimeTouchKeyboard.exe':[103]}
passed=[]
for case in ('gate-fails-before-launch','explicit-flag-required','single-detached-launch','existing-family-no-launch','partial-family-refused','spawn-error-no-retry','foreign-child-token-refused'):
    before=copy.deepcopy(original);row=next(x for x in before['products'] if x['id']=='yimecore-18u');row['processes']=[]
    result={'fixture':True,'packageVerified':True,'ciVerified':True,'releasePublished':True}
    allow=True;expected_calls=1;expect_failure=False
    if case=='gate-fails-before-launch':result['releasePublished']=False;expected_calls=0;expect_failure=True
    if case=='explicit-flag-required':allow=False;expected_calls=0;expect_failure=True
    if case=='existing-family-no-launch':row['processes']=[{'pid':pid,'path':p['image']} for pid,p in seen.items()];expected_calls=0
    if case=='partial-family-refused':row['processes']=[{'pid':102,'path':seen[102]['image']}];expected_calls=0;expect_failure=True
    if case=='spawn-error-no-retry':expect_failure=True
    observations=copy.deepcopy(seen)
    if case=='foreign-child-token-refused':observations[102]['token']['sid']='foreign';expect_failure=True
    utility=types.SimpleNamespace(observe=lambda pid:copy.deepcopy(observations[pid]),same_token=fake_token)
    calls=[]
    def fake_popen(argv,**kwargs):
        calls.append((argv,kwargs))
        assert kwargs['creationflags']==m.subprocess.DETACHED_PROCESS
        assert argv[-1]==m.OLD_MANIFEST_SHA and argv[1]=='--installed-18u-run'
        if case=='spawn-error-no-retry':raise OSError('inert spawn failure')
        return types.SimpleNamespace(pid=101)
    with tempfile.TemporaryDirectory(prefix='restore-inert-',dir=root/'.generated') as temp:
        with patch.object(m,'digest',fake_digest),patch.object(m,'read',lambda p:copy.deepcopy(original)),patch.object(m.subprocess,'Popen',fake_popen),patch.object(m.importlib.util,'spec_from_file_location',lambda *a:types.SimpleNamespace(loader=ReaderLoader())),patch.object(m.importlib.util,'module_from_spec',lambda spec:types.SimpleNamespace()):
            error=None
            try:m.running_original(Path(temp),before,utility,{'token':token},result,allow)
            except Exception as e:error=e
            assert (error is not None)==expect_failure,(case,error)
            assert len(calls)==expected_calls,(case,len(calls))
    passed.append(case)
out=root/'.generated/stop-process-race-regression/restore-inert-checks.json'
out.write_text(json.dumps({'schema':'cb77-restore-inert-gates-v1','cases':passed,'passed':len(passed),'productCalls':0,'installationExecuted':False},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'inertCasesPassed':len(passed),'productCalls':0,'report':str(out)}))
