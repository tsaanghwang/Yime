import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile
from verify_package import record, verify_zip, verify_package

repo = Path.cwd()
delivery = Path('C:/dev/Yime-deliveries/registration-fix-20260929')
package = delivery/'YimeCore-Registration-Fix-20260929'
build = repo/'.tmp/yimecore-local-product/r'
commit = '2ffee43242af9981c462aeabb0d5b26c4f99286c'
ci_id = '36503447392'
report = repo/'docs/testing/simple-maintenance/2026-09-29/registration-fix'

def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))

def write(p, value):
    with p.open('x',encoding='utf-8',newline='\n') as stream:
        json.dump(value,stream,ensure_ascii=False,indent=2)
        stream.write('\n')

ci_bytes = subprocess.check_output(['gh','run','view',ci_id,'--json','databaseId,headSha,status,conclusion,url,jobs'])
ci = json.loads(ci_bytes)
assert ci['headSha']==commit and ci['status']=='completed' and ci['conclusion']=='success', 'Source CI must pass before archive sealing'
assert all(j['conclusion']=='success' for j in ci['jobs'])
(delivery/'source-ci.json').write_bytes(ci_bytes)
assert subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()==commit
assert not read(build/'package/build/source-manifest.json')['dirty']
validation = verify_package(repo,build,package,commit)
write(delivery/'sealing-verification.json',validation)
assert validation['passed'] and read(delivery/'registration-preservation.json')['passed']
provenance = dict(schema_version='yimecore-registration-fix-delivery-v1',
    product='yimecore',version=validation['package_version'],
    source_commit=commit,source_tree=subprocess.check_output(['git','rev-parse',commit+'^{tree}'],text=True).strip(),
    installer_source_commit=commit,source_ci=dict(run_id=ci['databaseId'],url=ci['url'],head_sha=ci['headSha'],conclusion=ci['conclusion']),
    product_manifest=validation['product_manifest'],source_manifest=validation['source_manifest'],
    payload_files=65,pe_files=25,installed_acceptance=False,
    source_and_payload_mapping='See separate Evidence ZIP: payload-verification.json and core-build/package/build/source-manifest.json',
    original_unfixed_package=dict(name='Yime-Current-Readiness-20260927.zip',source_commit='0ab8631266736775bf1386f456d4a1d53e8e2eb3',sha256='45c4a0d93f8a40a4c26bebf934efb10c876f1305732c1e95a2e43547f2ddd341',unchanged=True))
write(package/'BUILD-PROVENANCE.json',provenance)
(package/'README.txt').write_text('YimeCore registration fix development package (2026-09-29)\n\n'
    'Source: '+commit+'\n'
    'Independent YimeCore package: x64 Windows runtime and x64/x86 application surfaces.\n'
    'Includes the persisted-registration query fix; the September 27 package does not.\n'
    'Installer entry: Setup.cmd (default Install); Setup.cmd -Action Uninstall removes only YimeCore.\n'
    'Use the current installer/simple/HANDOFF.md test-PC scope and verify the published SHA-256 first.\n'
    'This build has source/isolated validation, not installed-host or physical-input acceptance.\n'
    'Do not run it on the development PC under this source-delivery task.\n',encoding='utf-8',newline='\n')

def archive(root, name, report_name):
    target=delivery/name
    with zipfile.ZipFile(target,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in sorted(root.rglob('*')):
            if p.is_file(): z.write(p,root.name+'/'+p.relative_to(root).as_posix())
    result=verify_zip(target,root,root.name)
    write(delivery/report_name,result)
    return result['archive']

package_asset=archive(package,'YimeCore-Registration-Fix-20260929.zip','package-zip-verification.json')
evidence=delivery/'evidence'
evidence.mkdir()
def copy(src, dst):
    dst.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(src,dst)

for p in delivery.iterdir():
    if p.is_file() and p.suffix in ('.json','.log'):
        copy(p,evidence/p.name)
for p in build.iterdir():
    if p.is_file() and (p.suffix in ('.json','.txt','.patch') or p.name=='source-snapshot.zip'):
        copy(p,evidence/'core-build'/p.name)
for p in (build/'package/build').rglob('*'):
    if p.is_file(): copy(p,evidence/'core-build/package/build'/p.relative_to(build/'package/build'))
copy(build/'package/package-manifest.json',evidence/'core-build/package/package-manifest.json')
for arch in ('x64','x86'):
    for p in (build/f'native-{arch}').rglob('CMakeCXXCompiler.cmake'):
        copy(p,evidence/'core-build'/f'native-{arch}'/p.name)
    copy(build/f'native-{arch}/CMakeCache.txt',evidence/'core-build'/f'native-{arch}/CMakeCache.txt')
    copy(build/f'native-{arch}/Release/YimeRegistrationQueryTests.exe',evidence/'core-build'/f'native-{arch}/YimeRegistrationQueryTests.exe')
params=read(repo/'.tmp/registration-delivery/core-params.json')
admission=Path(params['SpeechAdmissionRoot'])
for p in admission.rglob('*'):
    rel=p.relative_to(admission)
    if p.is_file() and rel.parts[0] not in ('private',):
        copy(p,evidence/'speech-admission'/rel)
for p in (repo/'docs/testing/simple-maintenance/2026-09-28/current-issues').rglob('*'):
    if p.is_file(): copy(p,evidence/'original-report'/p.relative_to(repo/'docs/testing/simple-maintenance/2026-09-28/current-issues'))
for p in report.rglob('*'):
    if p.is_file(): copy(p,evidence/'source-review'/p.relative_to(report))
for p in (repo/'.tmp/registration-delivery').iterdir():
    if p.is_file(): copy(p,evidence/'delivery-tools'/p.name)
copy(package/'BUILD-PROVENANCE.json',evidence/'BUILD-PROVENANCE.json')
copy(package/'product-package.json',evidence/'product-package.json')

assets=[package_asset,
        archive(evidence,'YimeCore-Registration-Fix-20260929-Evidence.zip','evidence-zip-verification.json')]
(delivery/'SHA256SUMS.txt').write_text(''.join(a['sha256']+'  '+a['path']+'\n' for a in assets),encoding='utf-8',newline='\n')
assets.append(record(delivery/'SHA256SUMS.txt','SHA256SUMS.txt'))
write(delivery/'assets.json',dict(source_commit=commit,ci=provenance['source_ci'],assets=assets))
print(json.dumps(assets,indent=2))
