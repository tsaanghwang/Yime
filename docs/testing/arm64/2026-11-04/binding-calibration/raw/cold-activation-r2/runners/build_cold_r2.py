from pathlib import Path
import datetime, hashlib, json, subprocess

root=Path(__file__).resolve().parents[2]
out=root/'.generated/18u-cold-load-20261104-r2'
out.mkdir(exist_ok=True)
cmake=Path(r'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe')
build=out/'build'
results=[]
def run(name, command):
    r=subprocess.run([str(x) for x in command], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out/(name+'.log')).write_bytes(r.stdout)
    results.append(dict(stage=name, command=[str(x) for x in command], exitCode=r.returncode))
    print(name,r.returncode,flush=True)
    if r.returncode: raise SystemExit(r.returncode)
run('configure',[cmake,'-S',root/'YimeTextServiceExperiment','-B',build,'-G','Visual Studio 17 2022','-A','ARM64','-DYIME_TOUCH_PRODUCT=ON','-DYIME_TOUCH_REGISTERED_FORMAL_HOST=ON'])
targets=['YimeTouchFormalHostTests','YimeTouchRegisteredFormalHostTests','YimeTouchInstalledFrontendHostTests']
run('build',[cmake,'--build',build,'--config','Release','--target',*targets,'--parallel','3'])
for target in targets[:2]:
    run(target+'-module-contract',[build/'Release'/(target+'.exe'),'--module-identity-contract'])
run('ctest-cold-module',[cmake.parent/'ctest.exe','--test-dir',build,'-C','Release','-R','^Yime18uRegisteredColdModuleIdentityTests$','--output-on-failure'])
artifacts=[]
for target in targets:
    p=build/'Release'/(target+'.exe')
    artifacts.append(dict(path=str(p),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
sources=[]
for p in [root/'YimeTextServiceExperiment/tests/Formal18uHost.cpp',root/'YimeTextServiceExperiment/CMakeLists.txt']:
    sources.append(dict(path=str(p.relative_to(root)),sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
(out/'build-receipt.json').write_text(json.dumps(dict(schema='18u-cold-host-build-v1',timeUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),results=results,sources=sources,artifacts=artifacts,productActivated=False),indent=2)+'\n',encoding='utf-8')
print('PASS isolated host build and inert module identity regression',flush=True)
