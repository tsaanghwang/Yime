from pathlib import Path
import datetime, hashlib, json, shutil, subprocess

root=Path(__file__).resolve().parents[2]
src=root/'.generated/18u-cold-load-20261104-r2'
raw=root/'docs/testing/arm64/2026-11-04/binding-calibration/raw'
dest=raw/'cold-activation-r2'
git=r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe'
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
prior=raw/'cold-activation'
prior_inventory=json.loads((prior/'sha256-inventory.json').read_text())
for row in prior_inventory['files']:assert digest(prior/row['path'])==row['sha256']
build=json.loads((src/'build-receipt.json').read_text())
assert all(x['exitCode']==0 for x in build['results'])
for row in build['sources']:assert digest(root/row['path'])==row['sha256']
dest.mkdir(parents=True,exist_ok=False)
copies=[]
for name in ['build-receipt.json','build.log','configure.log','ctest-cold-module.log','YimeTouchFormalHostTests-module-contract.log','YimeTouchRegisteredFormalHostTests-module-contract.log']:
    copies.append((src/name,Path('logs')/name))
for name in ['build_cold_r2.py','archive_cold_r2.py']:
    copies.append((root/'.generated/touch-cold-tools'/name,Path('runners')/name))
for name in ['tests/Formal18uHost.cpp','CMakeLists.txt']:
    copies.append((root/'YimeTextServiceExperiment'/name,Path('source/YimeTextServiceExperiment')/name))
copies.extend([(src/'build/CMakeCache.txt',Path('build/CMakeCache.txt')),(src/'build/Testing/Temporary/LastTest.log',Path('build/LastTest.log'))])
for source,target in copies:
    target=dest/target;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target);assert digest(source)==digest(target)
p=subprocess.run([git,'diff','--no-index','--',str(prior/'source/YimeTextServiceExperiment/tests/Formal18uHost.cpp'),str(root/'YimeTextServiceExperiment/tests/Formal18uHost.cpp')],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
assert p.returncode==1 and not p.stderr,p.stderr
(dest/'source/r1-to-r2.patch').write_bytes(p.stdout)
summary=dict(schema='18u-cold-activation-r2-archive-v1',archivedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),
    sourceBaseCommit=subprocess.check_output([git,'rev-parse','HEAD'],cwd=root,text=True).strip(),
    reason='TF_TMAE_NOACTIVATETIP suppresses activation only within ActivateEx; Windows may asynchronously activate the selected TIP after this thread gains focus. A second warm-module rejection after context/focus setup would reject a valid Windows cold load.',
    officialContract='https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfthreadmgrex-activateex',
    change='The initial requireColdModule remains mandatory before ThreadMgr creation. The later observation records expectedDLLLoaded instead of rejecting. Explicit ActivateProfile and active profile/provider/vtable file identity checks are unchanged. No registered-path LoadLibrary was added.',
    validation=dict(arm64HostBuildTargets=3,directModuleContract='PASS',registeredModuleContract='PASS',registeredColdModuleCTest='PASS',initialWarmModuleRejectedByInertContract=True,installedActivationRun=False),
    previousLiveEvidence=dict(path='../cold-activation',inventorySHA256=digest(prior/'sha256-inventory.json'),all29MembersUnchanged=True,installedProductSourceCommit='46dd58967266edcab3f0d3bb131015d81dc4b951',scope='r1 only: old installed DLL + newly built r1 test host, one activation-only PASS; not rerun or relabelled as r2 live acceptance'),
    limits=['No installed product call or UI operation in r2.','No new package, Notepad, document-input, or physical acceptance claim.','The asynchronous Windows-load branch is allowed by the official API contract; no new live run was performed to force it.'],
    excluded=['exe','dll','pdb','dictionaries'],inventorySelfExcluded=True)
(dest/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
entries=[dict(path=p.relative_to(dest).as_posix(),bytes=p.stat().st_size,sha256=digest(p)) for p in sorted(dest.rglob('*')) if p.is_file()]
(dest/'sha256-inventory.json').write_text(json.dumps(dict(schema='sha256-file-inventory-v1',selfExcluded=True,count=len(entries),files=entries),indent=2)+'\n',encoding='utf-8')
for row in entries:assert digest(dest/row['path'])==row['sha256']
print(json.dumps(dict(directory=str(dest),filesIncludingInventory=len(entries)+1,hashedMembers=len(entries),inventorySHA256=digest(dest/'sha256-inventory.json'),trackedWritesComplete=True)))
