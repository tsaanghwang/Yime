"""Stage completed .4 evidence and documentation candidates under .generated only.

Never installs, starts a process, or writes tracked files. Reads only completed
evidence plus the one receipt-identified product calibration JSON. Invoke after
the single installer and any requested calibration controller
have returned; unfinished receipts are rejected. Root reviews/copies candidates.
"""
from pathlib import Path
import argparse,datetime,difflib,hashlib,json,re,shutil

ROOT=Path(__file__).resolve().parents[2]
SOURCE='6cea24bc665a4ded31e083a42bebd5d2d039832d'
VERSION='0.2.0-18u-arm64.4'
PREFIX=ROOT/'.generated/asus-18u-wait-repair-6cea24bc'
RELEASE=ROOT/'.generated/18u-wait-repair-release-6cea24bc'
CI=ROOT/'.generated/armfull-tools/ci-6cea24bc.json'
ATTEMPT=ROOT/'.generated/complete-input-install/asus-18u-6cea24bc'
CALIBRATION=ROOT/'.generated/asus-18u-installed-6cea24bc-run'
PREPARED=ROOT/'.generated/asus-18u-prepared-6cea24bc'
BASE=Path('docs/testing/arm64/2026-11-04/binding-calibration')
RAW=BASE/'raw/final-6cea24bc'
URL='https://github.com/tsaanghwang/Yime/releases/tag/test-arm64-18u-wait-6cea24bc-20261104'
ZIP='yime-yimecore-18u-windows-arm64-6cea24bc665a.zip'
ZIP_SHA='432db184c1a9fcb7a981522f08f5aa3bb6e933169e2e7961e51afb2f614d10be'
IDENTITY_SHA='5df7ab584b57c42153f4efdf4ba9b772f0c5a8e731bb45b01fb526886c94394d'
MANIFEST_SHA='572f66e68ad91effbdc994c6fbe1ca71a705d7ee4c5194b10d41447480ad83f3'
PLAN_SHA='b8dfe0c0822ee24c22ffb8aa9700bfcc77a7b2ae08c8b05a26b2188a1bc1ea62'
SUFFIXES={'.json','.jsonl','.log','.txt','.py','.ps1','.psm1','.cmd','.md','.patch','.yml','.yaml'}
DOCS=[Path('installer/simple/HANDOFF.md'),BASE/'README.md',Path('docs/testing/arm64/2026-11-03/full-input/README.md'),Path('docs/testing/arm64/2026-11-03/full-input/INSTALLED-RESULT.md'),Path('docs/testing/arm64/2026-11-03/full-input/FINAL-DELIVERY.md'),Path('docs/project/ARM64_COMPLETE_INPUT_INSTALL_2026-11-03.md')]
def need(value,message):
    if not value:raise RuntimeError(message)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def save(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def completed_inputs(args):
    package=read(PREFIX/'complete-package-receipt.json');build=read(PREFIX/'build-receipt.json')
    need(package['sourceCommit']==SOURCE and package['version']==VERSION and package['payloadCount']==20,'Wrong complete package')
    need(package['zip']=={'name':ZIP,'bytes':219929065,'sha256':ZIP_SHA} and package['installedManifestSHA256']==MANIFEST_SHA and package['planSHA256']==PLAN_SHA,'Complete package identity mismatch')
    identity_path=PREFIX/'complete'/ZIP.replace('.zip','.identity.json')
    need(sha(identity_path)==IDENTITY_SHA,'Complete identity changed')
    identity=read(identity_path)
    need(identity['source']['commit']==SOURCE and identity['source']['clean'] is True and len(identity['files'])==1156,'Unfrozen package identity')
    need(build['sourceCommit']==SOURCE and build['sourceCleanBefore'] is True and build['sourceCleanAfter'] is True and all(x['exitCode']==0 for x in build['builds']),'Build receipt not successful/frozen')
    ci=read(CI);delivery=read(RELEASE/'delivery-receipt.json')
    need(ci['headSha']==SOURCE and ci['passed'] is True and ci['counts']=={'success':19,'expectedManualOnlySkipped':3,'failed':0,'pending':0},'CI not final/successful')
    need(len(ci['workflows'])==2 and all(x['headSha']==SOURCE and x['status']=='completed' and x['conclusion']=='success' for x in ci['workflows']),'Incomplete final CI workflows')
    need(delivery['source']==SOURCE and delivery['draft'] is False and delivery['prerelease'] is True and delivery['url']==URL,'Release is not the exact published delivery')
    asset=[x for x in delivery['assets'] if x['name']==ZIP]
    need(len(asset)==1 and asset[0]['digest']=='sha256:'+ZIP_SHA and asset[0]['size']==219929065 and asset[0]['state']=='uploaded','Published ZIP mismatch')
    install=read(ATTEMPT/'install-result.json')
    need(install['sourceCommit']==SOURCE and install['version']==VERSION and install['mode']=='install' and install.get('completedUTC') and type(install.get('exitCode')) is int,'Install attempt is unfinished or has a different identity')
    if install['installCalled']:
        need(type(install.get('installerExitCode')) is int and install.get('installCompletedUTC'),'Installer is still active')
        need(args.admin_log is not None,'Supply this completed attempt exact --admin-log')
    admin=None
    if args.admin_log:
        admin=args.admin_log.resolve();logs=Path(r'C:\Users\tsaan\Yime Setup Logs')
        need(admin.parent==logs and re.fullmatch(r'[0-9a-f]{32}\.admin\.log',admin.name),'Unexpected administrator log path')
        text=admin.read_text(encoding='utf-8-sig')
        need(PLAN_SHA in text and 'Action: Install;' in text,'Administrator log does not belong to the .4 plan')
    after=read(ATTEMPT/'after.json');rows={x['id']:x for x in after['products']}
    need(set(rows)=={'yimecore','rime-pime','yimecore-18u'},'Completed after snapshot is missing products')
    current=rows['yimecore-18u'];matches=sum(x['exists'] and x['match'] for x in current['payload'])
    success=install.get('exitCode')==0 and install.get('installerExitCode')==0 and install.get('postInstallVerified') is True and install.get('only18uChanged') is True and install.get('unrelatedProductsAndDefaultUnchanged') is True and current['version']==VERSION and matches==20 and len(current['payload'])==20
    calibration=None
    if CALIBRATION.exists():
        need((CALIBRATION/'receipt.json').is_file(),'Calibration controller directory exists but its final receipt is unfinished')
        calibration=read(CALIBRATION/'receipt.json')
        need(calibration.get('sourceCommit')==SOURCE and calibration.get('manifestSHA256')==MANIFEST_SHA and calibration.get('packageVersion')==VERSION and type(calibration.get('ok')) is bool,'Calibration receipt identity/final state differs')
        need(calibration.get('installerReceiptSHA256')==sha(ATTEMPT/'install-result.json'),'Calibration belongs to a different install result')
        config=Path(calibration['calibration']['path'])
        need(config.parent==Path(r'C:\Users\tsaan\AppData\Local\YimeCore 18u Touch\display-calibration') and re.fullmatch(r'[0-9a-f]{64}\.json',config.name),'Calibration file is outside the explicit product settings scope')
        need(sha(config)==calibration['calibration']['sha256'] and read(config)==calibration['calibration']['measurement'],'Saved calibration bytes no longer match the completed receipt')
        need(calibration.get('checkpointReceiptSHA256')==sha(CALIBRATION/'checkpoints/receipt.json'),'Checkpoint receipt changed')
    elif success:need(bool(args.calibration_not_run),'Successful install awaits requested calibration results; or explicitly record --calibration-not-run REASON')
    full_checks=bool(calibration and calibration.get('ok') is True and calibration.get('runRequested') is True and calibration.get('calibrationExitCode')==0 and calibration.get('checkpointsControllerExitCode')==0 and calibration.get('checkpoints')==18 and calibration.get('testJobEmptyBeforeRestore') is True and len(calibration.get('restoredProcesses',[]))==3 and not calibration.get('restorationObservationError'))
    return package,build,ci,delivery,identity,install,after,calibration,admin,success,full_checks,matches
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--admin-log',type=Path,help='Exact completed .4 administrator transcript, never a directory scan')
    parser.add_argument('--calibration-not-run',default='',help='Explicit reason when installation passed but requested software/calibration run was not performed')
    parser.add_argument('--output',type=Path,default=ROOT/'.generated/asus-18u-final-evidence-6cea24bc')
    args=parser.parse_args();out=args.output.resolve()
    need(out.is_relative_to(ROOT/'.generated') and out!=ROOT/'.generated','Output must stay strictly within this worktree .generated')
    need(not out.exists(),'Evidence candidate output already exists; never overwrite a prior result')
    values=completed_inputs(args) # Refuse active operations before writing a candidate tree.
    package,build,ci,delivery,identity,install,after,calibration,admin,success,full_checks,matches=values
    need(not (ROOT/RAW).exists(),'Final tracked archive already exists; review it instead of overwriting')
    staged=out/'candidate-tree';raw=staged/RAW;raw.mkdir(parents=True)
    members=[]
    def copy(source,relative,kind='original-receipt-or-log'):
        source=Path(source);need(source.is_file() and not source.is_symlink() and not source.is_junction(),'Not a plain evidence file: '+str(source))
        need(source.suffix.lower() in SUFFIXES and source.stat().st_size<=64*1024*1024,'Unexpected binary/large evidence file: '+str(source))
        before=sha(source);destination=raw/relative;destination.parent.mkdir(parents=True,exist_ok=True)
        need(not destination.exists(),'Duplicate evidence destination: '+str(destination));shutil.copyfile(source,destination)
        need(sha(destination)==before and sha(source)==before,'Source changed during archive; operation may still be active: '+str(source))
        origin=source.relative_to(ROOT).as_posix() if source.is_relative_to(ROOT) else str(source)
        members.append({'path':destination.relative_to(raw).as_posix(),'source':origin,'kind':kind,'bytes':destination.stat().st_size,'sha256':before})
    # Metadata only. Native/compiler output directories and package ZIPs are not copied.
    for p in sorted(PREFIX.iterdir()):
        if p.is_file() and p.suffix.lower() in SUFFIXES:copy(p,'build-artifacts/'+p.name)
    for p in sorted((PREFIX/'complete').iterdir()):
        if p.is_file() and p.suffix.lower() in SUFFIXES:copy(p,'package/'+p.name)
    for name in ('product-package.json','maintenance-plan.json','Setup.ps1','Product.psm1','Setup.cmd'):
        copy(PREFIX/'simple/package'/name,'package/source-snapshots/'+name,'fixed-package-maintenance-source-or-plan')
    for p in sorted(RELEASE.rglob('*')):
        if p.is_file() and p.suffix.lower() in SUFFIXES:copy(p,'release/'+p.relative_to(RELEASE).as_posix())
    copy(CI,'ci/source-ci.json')
    for p in sorted(ATTEMPT.rglob('*')):
        if p.is_file():copy(p,'install/'+p.relative_to(ATTEMPT).as_posix())
    if admin:copy(admin,'install/admin/'+admin.name)
    if calibration:
        for p in sorted(CALIBRATION.rglob('*')):
            if p.is_file():copy(p,'calibration-checks/'+p.relative_to(CALIBRATION).as_posix())
        config=Path(calibration['calibration']['path'])
        copy(config,'calibration-settings/'+config.name,'explicitly-authorized-product-display-setting-not-a-user-lexicon')
        need(members[-1]['sha256']==calibration['calibration']['sha256'],'Calibration setting changed after receipt validation')
    for p in sorted(PREPARED.iterdir()):
        if p.is_file() and p.suffix.lower() in SUFFIXES:copy(p,'calibration-prepared/'+p.name,'prepared-controller-not-an-execution-result')
    for name in ('install-asus-18u-6cea24bc.py','install-asus-18u-6cea24bc.audit.json','bind-installer-6cea24bc.py','build-asus-18u-wait-repair.py','package-asus-18u-wait-repair.py','publish-asus-18u-wait-repair.py','prepare-final-18u-6cea-evidence.py'):
        p=ROOT/'.generated/armfull-tools'/name
        if p.is_file():copy(p,'runners/'+name,'runner-source-snapshot')
    current=next(x for x in after['products'] if x['id']=='yimecore-18u')
    observed=datetime.datetime.fromisoformat(install['completedUTC']).astimezone(datetime.timezone(datetime.timedelta(hours=8)))
    stamp=observed.strftime('%Y-%m-%d')
    install_stamp=observed.strftime('%Y-%m-%d %H:%M（UTC+08）')
    state='安装成功' if success else '升级未通过'
    if full_checks:checks='随后已依据 100 mm 参考线实测 57.5 mm 保存校准，已安装前端的软件检查 18/18 通过，测试 Job 已清空并重新核验恢复后的三个普通用户进程。'
    elif calibration:checks='校准/已安装前端检查已有本轮结果，但未满足完整成功条件；检查数为 '+str(calibration.get('checkpoints',0))+'/18，停止原因与恢复状态见原始 receipt。'
    else:checks='本轮校准与已安装前端检查未执行。'+(('原因：'+args.calibration_not_run+'。') if args.calibration_not_run else '')
    protection='其他两产品及默认输入覆盖值保持未变。' if install.get('unrelatedProductsAndDefaultUnchanged') is True else '其他产品/默认项的保护结果尚未完整确认，必须读取原始快照。'
    installed='结束快照为 `'+current['version']+'`，'+str(matches)+'/'+str(len(current['payload']))+' 项载荷匹配。'
    limits='软件校准保存与受控 TSF 检查不代表实体尺复测、真实记事本正文或真人手指输入通过；这些仍须单独记录。历史 `.2`/`.3` 首失败保留，未据 `.4` 的结果追认 `.3` 的锁来源。'
    short='ASUS 18u `.4` '+state+'。'+installed+protection+checks
    summary={'schema':'asus-18u-final-record-v1','sourceCommit':SOURCE,'version':VERSION,'installVerified':success,'installedVersionObserved':current['version'],'matchedPayloads':matches,'payloadCount':len(current['payload']),'calibratedFrontend18CheckpointsPassed':full_checks,'calibrationExecuted':bool(calibration and calibration.get('runRequested')),'physicalAcceptanceClaimed':False,'historicalBrokerSharingViolationCauseProven':False,'installCompletedUTC':install['completedUTC'],'publishedRelease':URL,'archivePath':RAW.as_posix(),'statusText':short,'limits':limits}
    save(raw/'summary.json',summary)
    members.append({'path':'summary.json','source':'derived from completed receipts only','kind':'scope-and-result-summary','bytes':(raw/'summary.json').stat().st_size,'sha256':sha(raw/'summary.json')})
    save(raw/'manifest.json',{'schema':'yime-byte-exact-evidence-manifest-v1','sourceCommit':SOURCE,'bytePreservationRule':'binding-calibration/.gitattributes raw/** -text !eol -whitespace','members':members})
    # Generate reviewable complete-document candidates; never write the targets.
    link='[本轮记录](../../docs/testing/arm64/2026-11-04/binding-calibration/README.md)'
    body=f'**{stamp}：{short}** 当前固定源码 `{SOURCE}`，版本 `{VERSION}`；{limits} 继续读取{link}，不重复旧失败安装命令。\n\n'
    section=f'## `.4` 固定交付与本轮结果\n\n{stamp}：{short}\n\n安装结束时间为 {install_stamp}；校准与 18 项软件检查发生在安装之后。固定源码 `{SOURCE}`，版本 `{VERSION}`。两条 CI 工作流成功，19 项成功、3 项既有手动检查跳过。完整包 1,156 项成员，ZIP 为 219,929,065 字节、SHA-256 `{ZIP_SHA}`；[固定 `.4` 交付]({URL})。安装、来源、发布与校准检查原始回执见 `raw/final-6cea24bc/`。\n\n{limits}\n\n'
    doc_plan=[]
    for target in DOCS:
        original=(ROOT/target).read_text(encoding='utf-8-sig');candidate=original
        if target==Path('installer/simple/HANDOFF.md'):
            need('## 当前任务\n\n' in original,'HANDOFF anchor changed');candidate=original.replace('## 当前任务\n\n','## 当前任务\n\n'+body,1)
        elif target==BASE/'README.md':
            need('## 后续单次检查' in original and '## `.4` 固定交付与本轮结果' not in original,'README result section already exists or anchor changed');candidate=original.replace('## 后续单次检查',section+'## 后续单次检查',1)
        elif target.name=='INSTALLED-RESULT.md':
            need('## 当前结果（2026-11-04）' in original,'Installed result anchor changed')
            note=f'## 当前 18u 更新（{stamp}）\n\n{short} {limits} 当前结果及固定包见[量尺与绑定记录](../../2026-11-04/binding-calibration/README.md)。下方保留首次三产品安装时的历史状态。\n\n## 三产品首次安装结果（历史，升级前）'
            candidate=original.replace('## 当前结果（2026-11-04）',note,1)
        else:
            first,sep,rest=original.partition('\n\n');need(bool(sep),'Document heading anchor missing')
            relative='../testing/arm64/2026-11-04/binding-calibration/README.md' if target.parts[1]=='project' else '../../2026-11-04/binding-calibration/README.md'
            note=f'**最新状态（{stamp}）：{short}** 固定 `.4` 来源与实际结果见[本轮记录]({relative})。{limits}\n\n以下保留本次更新之前的实施、安装或交付记录，不作为旧包重装指令。\n\n'
            candidate=first+'\n\n'+note+rest
            if target.name=='FINAL-DELIVERY.md':candidate=candidate.replace('## 46dd 阶段记录：18u 当前包、Rime 历史候选','## 46dd 阶段记录：18u 首次安装包、Rime 历史候选',1)
        destination=staged/target;destination.parent.mkdir(parents=True,exist_ok=True);destination.write_text(candidate,encoding='utf-8')
        diff=''.join(difflib.unified_diff(original.splitlines(keepends=True),candidate.splitlines(keepends=True),fromfile=target.as_posix(),tofile=target.as_posix()))
        patch=out/'review-diffs'/(target.as_posix().replace('/','__')+'.patch');patch.parent.mkdir(parents=True,exist_ok=True);patch.write_text(diff,encoding='utf-8')
        doc_plan.append({'target':target.as_posix(),'originalSHA256':sha(ROOT/target),'candidate':str(destination),'candidateSHA256':sha(destination),'reviewDiff':str(patch)})
    inventory_target=BASE/'evidence-inventory.json';inventory=read(ROOT/inventory_target)
    existing={x['path'] for x in inventory['files']}
    for p in sorted(raw.rglob('*')):
        if not p.is_file():continue
        relative=(Path('raw/final-6cea24bc')/p.relative_to(raw)).as_posix();need(relative not in existing,'Inventory already contains final archive')
        inventory['files'].append({'source':'candidate archive from completed .4 receipts','path':relative,'sha256':sha(p)})
    save(staged/inventory_target,inventory)
    doc_plan.append({'target':inventory_target.as_posix(),'originalSHA256':sha(ROOT/inventory_target),'candidate':str(staged/inventory_target),'candidateSHA256':sha(staged/inventory_target)})
    for row in members:need(sha(raw/row['path'])==row['sha256'],'Final staged member changed')
    save(out/'review-plan.json',{'schema':'generated-only-final-evidence-and-doc-candidates-v1','sourceCommit':SOURCE,'trackedFilesWritten':False,'productCalls':0,'archiveTarget':RAW.as_posix(),'archiveCandidate':str(raw),'archiveMembers':len(members),'manifestSHA256':sha(raw/'manifest.json'),'documentationCandidates':doc_plan,'applicationInstructions':'Review actual-result wording and all diffs; require every originalSHA256 still matches before copying. Copy the fresh archive only if its tracked target does not exist. No apply action is implemented by this generator.'})
    print(json.dumps({'output':str(out),'archiveMembers':len(members),'manifestSHA256':sha(raw/'manifest.json'),'documentationCandidates':len(doc_plan),'installVerified':success,'softwareCheckpointsPassed':full_checks,'trackedFilesWritten':False},ensure_ascii=False))
if __name__=='__main__':main()
