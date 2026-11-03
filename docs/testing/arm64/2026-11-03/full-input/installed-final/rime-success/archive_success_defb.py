"""Archive existing successful installation and read-only observation evidence."""
import hashlib
import json
from pathlib import Path
import shutil

repo=Path(__file__).resolve().parents[2]
source=repo/'.generated/complete-input-install/final-defbf9f8-rime'
live_source=repo/'.generated/rime-live-preparation/final-defbf9f8-success/live-process-identity.json'
out=repo/'docs/testing/arm64/2026-11-03/full-input/installed-final/rime-success'
if out.exists():raise ValueError('preserve an existing success archive')
result=json.loads((source/'setup-result.json').read_text(encoding='utf-8'))
after=json.loads((source/'after.json').read_text(encoding='utf-8-sig'))
installed=next(row for row in after['products'] if row['id']=='rime-pime')
live=json.loads(live_source.read_text(encoding='utf-8'))
if result['exitCode']!=0 or not live['passed'] or result['source']!=live['sourceCommit']:
    raise ValueError('successful matching evidence required')
if len(installed['payload'])!=366 or not all(row['match'] for row in installed['payload']):
    raise ValueError('installed payload snapshot mismatch')
log=(source/'setup-output.log').read_text(encoding='utf-8')
observations=[]
for arch in ('x86','arm64'):
    chunks=[text for text in log.split('schema_version=')[1:] if '\narchitecture='+arch+'\n' in '\n'+text]
    if len(chunks)!=1:raise ValueError('missing unique recorded registration result')
    fields=dict(line.split('=',1) for line in chunks[0].splitlines() if '=' in line)
    expected={'service_profiles_registered_count':'1','exact_profile_registered_count':'1',
        'profile_description_matches':'true','profile_enabled_for_current_user':'true',
        'categories_registered_count':'6','expected_categories_registered_count':'6','category_set_exact':'true',
        'profile_query_hresult':'0x0','description_query_hresult':'0x0','enabled_query_hresult':'0x0','category_query_hresult':'0x0',
        'mutation_performed':'false'}
    if any(fields.get(key)!=value for key,value in expected.items()):raise ValueError('registration result did not pass')
    observations.append({'architecture':arch,'command':'verify-present','source':'setup-output.log','passed':True,**expected})
admin_log=Path('C:/Users/tsaan/Yime Setup Logs/978e6797ed7b45b482abd83e621792ec.admin.log')
admin_text=admin_log.read_text(encoding='utf-8-sig')
if 'f4a0147ed0fc63540dda0b6b18b088996830d7d7d65496288baaebf4aebb307b' not in admin_text:
    raise ValueError('administrator transcript does not identify the final plan')
out.mkdir(parents=True)
for path in source.iterdir():
    if path.is_file():shutil.copyfile(path,out/path.name)
shutil.copyfile(admin_log,out/'setup-admin.log')
shutil.copyfile(live_source,out/'live-process-identity.json')
shutil.copyfile(Path(__file__).with_name('observe_success_defb.py'),out/'observe_success_defb.py')
shutil.copyfile(Path(__file__),out/'archive_success_defb.py')
utility=Path(live['processUtility']['path'])
if hashlib.sha256(utility.read_bytes()).hexdigest()!=live['processUtility']['sha256']:
    raise ValueError('observed utility source changed before archival')
shutil.copyfile(utility,out/'process-utility-source.py')
summary={'schema':'yime-rime-installed-success-summary-v1',
    'sourceCommit':result['source'],'version':installed['version'],'installRoot':installed['root'],
    'archiveSHA256':result['archiveSHA256'],'deliveryURL':result['deliveryURL'],
    'installationExitCode':0,'installationCompletedUTC':result['completedUTC'],
    'dataResetRequested':result['resetData'],'installedPayloadSnapshotCount':366,'installedPayloadSnapshotMismatches':0,
    'registrationObservedByOriginalOrdinaryParent':observations,
    'bothRegistrationProbesPassedBeforeRuntimeLaunch':True,
    'liveObservationUTC':live['capturedAtUTC'],'watchdogPID':live['watchdogPID'],'workerPIDs':live['workerPIDs'],
    'allObservedRuntimeImagesNativeARM64':True,'allObservedRuntimeImagesMatchDeliveredPackage':True,
    'allObservedRuntimeTokensOrdinaryMediumIntegrity':True,'sameUserSessionAndLogon':True,
    'backendPIDs':live['backendPIDs'],'backendAbsenceAcceptedAsLazyBeforeActivation':not live['backendPIDs'],
    'liveDocumentInputExecuted':False,'physicalTouchOrPenAcceptance':False,
    'registrationProbesRepeatedByObserver':False,'processesStartedOrStoppedByObserver':False,
    'previousFailureEvidencePreserved':True,
    'scope':'Successful installation, exact package/registration convergence and live ordinary native Launcher identity. No host profile activation, live document input or physical acceptance is claimed.'}
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(out/'README.md').write_text('''# Rime ARM64 安装成功及只读运行身份

`defbf9f805b52146bd79048620058f48c6c29f23` 包在本地 2026-11-04 00:46:42 安装成功，退出码为 0。原普通父进程先完成 x86、ARM64 两个 `verify-present`，profile 数目、描述、用户启用及六项类别全部正确，然后才启动 Launcher。

安装后快照记录 366 个 payload，全部哈希匹配。00:54:38 的独立只读观察确认启动 PID 39884 与其直接子 PID 38684 仍存活，路径及创建时间与快照一致；两者均原生 ARM64、TokenElevation=0、Medium 完整性 8192，属于同一用户、会话及登录令牌，镜像 SHA 与交付包一致。38684 的 worker 角色依据父子关系和 Launcher 源码推定，未读取其命令行。

尚未观察到按需启动的 `server.exe`；当前未激活 Rime 宿主，此项不作失败判断。没有执行真实文档输入、当前宿主 profile 激活或手指/笔验收，不能把安装和进程验证称为输入验收。

`setup-output.log` 是原普通父进程的双架构验证及启动原始输出；`setup-admin.log` 是本次提升阶段记录；`live-process-identity.json` 记录独立 Win32 令牌、进程架构、创建时间和镜像哈希。观察器没有重复注册探针、启动/停止产品或运行 UI。脚本副本仅保存采集时实现，原执行位置在 `.generated/rime-live-preparation/`；导入的 18u 工具仅调用只读 observe/token 函数，未调用其运行入口。

前两次失败目录保持原样。此处记录最终成功结果，不改写此前失败，也不把第二次即时 TSF 枚举差异的内部原因标为已经确定。
''',encoding='utf-8')
inventory={p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in out.iterdir() if p.is_file()}
(out/'evidence-inventory.json').write_text(json.dumps({'schema':'yime-installed-evidence-inventory-v1','files':inventory},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'archive':str(out),'files':len(inventory),'summary':summary},ensure_ascii=False,indent=2))
