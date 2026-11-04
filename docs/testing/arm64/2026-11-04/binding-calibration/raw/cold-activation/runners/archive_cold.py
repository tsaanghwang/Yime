from pathlib import Path
import datetime, hashlib, json, shutil, subprocess

root=Path(__file__).resolve().parents[2]
src=root/'.generated/18u-cold-load-20261104'
dest=root/'docs/testing/arm64/2026-11-04/binding-calibration/raw/cold-activation'
git=r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe'
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
build=json.loads((src/'build-receipt.json').read_text())
for row in build['sources']:
    assert digest(root/row['path'])==row['sha256'],row['path']
live=json.loads((src/'activation-once/result.json').read_text(encoding='utf-8'))
assert live['exitCode']==0 and live['testProcessExited'] and live['protectedProcessesUnchanged'] and live['installedDLLUnchanged']
dest.mkdir(parents=True,exist_ok=False)
copies=[]
for name in ['build-receipt.json','build.log','configure.log','ctest-cold-module.log','YimeTouchFormalHostTests-module-contract.log','YimeTouchRegisteredFormalHostTests-module-contract.log']:
    copies.append((src/name,Path('logs')/name))
for name in ['input.json','stdout.jsonl','stderr.jsonl','result.json']:
    copies.append((src/'activation-once'/name,Path('activation-once')/name))
for name in ['build_cold.py','run_activation_once.py','archive_cold.py']:
    copies.append((root/'.generated/touch-cold-tools'/name,Path('runners')/name))
copies.append((root/'.generated/touch-full-tools/run_installed_frontend_checkpoints.py',Path('runners/read-identity-utility-snapshot.py')))
for name in ['tests/Formal18uHost.cpp','tests/InstalledFrontendHost.cpp','tests/FormalInputSequence.h','tests/ActionFailureObservation.h','DedicatedTouchService.h','YimeTextServiceIds.h','TouchProductIdentity.h.in','CMakeLists.txt']:
    copies.append((root/'YimeTextServiceExperiment'/name,Path('source/YimeTextServiceExperiment')/name))
copies.extend([(root/'tools/yimecore/18u-touch-product-arm64.json',Path('source/18u-touch-product-arm64.json')),
               (src/'build/TouchProductIdentity.h',Path('build/TouchProductIdentity.h')),
               (src/'build/CMakeCache.txt',Path('build/CMakeCache.txt')),
               (src/'build/Testing/Temporary/LastTest.log',Path('build/LastTest.log')),
               (src/'build/YimeTouchRegisteredFormalHostTests.vcxproj',Path('build/YimeTouchRegisteredFormalHostTests.vcxproj'))])
for source,target in copies:
    assert source.suffix.lower() not in ('.exe','.dll','.pdb')
    target=dest/target;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    assert digest(source)==digest(target)
base=subprocess.check_output([git,'rev-parse','HEAD'],cwd=root,text=True).strip()
patch=subprocess.check_output([git,'diff','--','YimeTextServiceExperiment/tests/Formal18uHost.cpp','YimeTextServiceExperiment/CMakeLists.txt'],cwd=root)
(dest/'source/host-change.patch').write_bytes(patch)
summary=dict(schema='18u-cold-activation-archive-v1',archivedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),
    sourceBaseCommit=base,hostSourceState='working-tree test change; exact source SHA in logs/build-receipt.json and source snapshots',
    installedProductSourceCommit='46dd58967266edcab3f0d3bb131015d81dc4b951',installedDLL=live['installedDLL'],newHostTest=live['testHost'],
    scope='Old installed 46dd DLL with newly built ARM64 test host. One process-scoped cold activation only. This is not a new product package or new-package acceptance.',
    outcome=dict(activationHResult=0,deactivationHResult=0,processExitCode=0,preloadedByHost=False,profileProviderAndDLLIdentityVerified=True,ownDocumentsEmpty=True,textActions=0,protectedProcessesUnchanged=True),
    validation=dict(directHostModuleContract='PASS',registeredHostModuleContract='PASS',registeredColdModuleCTest='PASS',nativeHostBuildTargets=3,independentSourceReview='validation agent: no blocker; reference ownership and existing stdin/stdout protocol checked'),
    limits=['Does not establish packaged Notepad activation or binding.','No physical finger input or document text acceptance.','No registration/install/default changes; no other process stopped.','Existing runtime adapter may connect to its existing Broker; no new Broker or GUI launched.'],
    stderr='TransportCancelled on teardown; original stderr retained.',
    runners='Snapshots are provenance only. Do not run automatically; the read-identity utility snapshot also contains an unrelated full frontend controller entry point that was never invoked here.',
    archiveExcludes=['executables','DLLs','PDBs','dictionaries'],inventorySelfExcluded=True)
(dest/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
entries=[dict(path=p.relative_to(dest).as_posix(),bytes=p.stat().st_size,sha256=digest(p)) for p in sorted(dest.rglob('*')) if p.is_file()]
(dest/'sha256-inventory.json').write_text(json.dumps(dict(schema='sha256-file-inventory-v1',self='sha256-inventory.json',selfExcluded=True,count=len(entries),files=entries),indent=2)+'\n',encoding='utf-8')
for row in entries:assert digest(dest/row['path'])==row['sha256']
print(json.dumps(dict(directory=str(dest),filesIncludingInventory=len(entries)+1,hashedMembers=len(entries),inventorySHA256=digest(dest/'sha256-inventory.json'),trackedWritesComplete=True)))
