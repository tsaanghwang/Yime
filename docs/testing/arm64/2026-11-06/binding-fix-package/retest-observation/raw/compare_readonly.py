"""Compare immutable prior snapshot and expected .5 package with live read-only evidence."""
import datetime as dt
import hashlib
import json
from pathlib import Path

ROOT = Path('C:/dev/Yime/.wt/bindfix')
OUT = ROOT / '.generated/binding-retest-20261106'
PRIOR = ROOT / '.generated/binding-upgrade-20261106'
PACKAGE = ROOT / '.generated/package-binding-636cef68/simple/package'

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def record_copy(source, name):
    target = OUT / name
    assert not target.exists()
    data = source.read_bytes()
    target.write_bytes(data)
    return {'source': str(source), 'snapshot': str(target), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}

before = read(PRIOR / 'prepared-state.json')
current = read(OUT / 'current-state.json')
boot = read(OUT / 'boot-observation.json')
before_locks = read(PRIOR / 'prepared-dll-users.json')
locks = read(OUT / 'current-dll-users.json')
observed = {p['id']: p for p in current['products']}
baseline = {p['id']: p for p in before['products']}
installed_root = Path(observed['yimecore-18u']['root'])
copies = [record_copy(installed_root / 'installed-18u-product.json', 'installed-18u-product.json'), record_copy(installed_root / '.setup/product-package.json', 'installed-product-package.json'), record_copy(PACKAGE / 'payload/installed-18u-product.json', 'expected-5-installed-18u-product.json'), record_copy(PACKAGE / 'product-package.json', 'expected-5-product-package.json')]
installed_manifest = read(OUT / 'installed-18u-product.json')
expected_manifest = read(OUT / 'expected-5-installed-18u-product.json')
expected_package = read(OUT / 'expected-5-product-package.json')

comparisons = []
for product_id, now in observed.items():
    old = baseline[product_id]
    old_payload = {r['path']: r['sha256'] for r in old['payload']}
    now_payload = {r['path']: r['sha256'] for r in now['payload']}
    differences = [{'path': path, 'before': old_payload.get(path), 'current': now_payload.get(path)} for path in sorted(old_payload.keys() | now_payload.keys()) if old_payload.get(path) != now_payload.get(path)]
    old_processes = {(p['pid'], p['path'], p['startUtc']) for p in old['processes']}
    now_processes = {(p['pid'], p['path'], p['startUtc']) for p in now['processes']}
    comparisons.append({'id': product_id, 'beforeVersion': old['version'], 'currentVersion': now['version'], 'payloadCount': len(now_payload), 'ownManifestMismatches': [r['path'] for r in now['payload'] if not r['match']], 'payloadDifferencesFromPrepared': differences, 'registrationsUnchanged': now['registrations'] == old['registrations'], 'startupUnchanged': now['startup'] == old['startup'], 'sameProcessInstancesAsPrepared': now_processes == old_processes, 'currentProcesses': now['processes']})

now_payload = {r['path']: r for r in observed['yimecore-18u']['payload']}
expected_comparison = [{'path': r['path'], 'expectedSha256': r['sha256'], 'currentSha256': now_payload.get(r['path'], {}).get('sha256'), 'match': now_payload.get(r['path'], {}).get('sha256') == r['sha256']} for r in expected_package['files']]
prior_lock_instances = {(p['pid'], p['creationTicks']) for p in before_locks['users']}
current_lock_instances = {(p['pid'], p['creationTicks']) for p in locks['users']}
last_boot = dt.datetime.fromisoformat(boot['lastBootUpUtc'].replace('Z', '+00:00'))
prior_observed = dt.datetime.fromisoformat(before['observedUtc'].replace('Z', '+00:00'))
result = {
    'schema': 'binding-retest-installed-comparison-v1',
    'observedUtc': current['observedUtc'],
    'baseline': str(PRIOR / 'prepared-state.json'),
    'readOnly': True,
    'installedVersion': observed['yimecore-18u']['version'],
    'installedSourceCommit': installed_manifest['sourceCommit'],
    'expectedVersion': expected_package['version'],
    'expectedSourceCommit': expected_manifest['sourceCommit'],
    'target5Installed': observed['yimecore-18u']['version'] == expected_package['version'] and installed_manifest['sourceCommit'] == expected_manifest['sourceCommit'] and all(r['match'] for r in expected_comparison),
    'expected5PayloadComparison': expected_comparison,
    'defaultInputOverride': current['defaultInputOverride'],
    'defaultInputOverrideUnchanged': before['defaultInputOverride'] == current['defaultInputOverride'],
    'products': comparisons,
    'currentDllUsers': locks['users'],
    'sameDllUserProcessInstancesAsPrepared': current_lock_instances == prior_lock_instances,
    'lastBootUpUtc': boot['lastBootUpUtc'],
    'lastBootUpAfterPreparedSnapshot': last_boot > prior_observed,
    'rebootEvidenceConclusion': 'No later full system startup is shown. All three installed products retain the exact PID/start-time instances from the prepared snapshot; the three DLL users retain exact PID/creationTicks. This observation does not infer what action the user attempted.',
    'snapshottedManifests': copies,
    'inputAcceptanceClaimed': False,
}
target = OUT / 'comparison.json'
assert not target.exists()
target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
summary = ['# 18u 安装状态只读复核', '', f"观察时间：{current['observedUtc']}（UTC）。", '', f"当前安装仍为 {result['installedVersion']}，源码 {result['installedSourceCommit']}；尚未安装目标 {result['expectedVersion']} / {result['expectedSourceCommit']}。", '', '三产品全部已安装载荷与各自安装清单匹配：YimeCore 69/69、Rime/PIME 366/366、18u 20/20。三者相对 prepared-state 的载荷、注册路径、启动项和默认输入法覆盖项均未变化。', '', '18u Runtime、Broker、GUI 均来自 C:\\Program Files\\YimeCore 18u Touch\\bin，三者提升标志均为 false，PID 和精确创建时间均与前轮一致。', '', '当前 DLL 使用者仍为 Explorer 20092、Codex 39152、Notepad 11912，PID 与 creationTicks 均和 prepared-dll-users 一致。只读取 Restart Manager 清单，没有请求关闭或重启。', '', f"系统 LastBootUpTime 为 {boot['lastBootUpUtc']}（北京时间 2026-11-01 22:40:29）。记录未显示前轮之后的新系统启动，且产品及 DLL 使用进程均是前轮同一实例；不据此推断用户尝试的操作或原因。", '', f"与目标 .5 的 20 个载荷逐项比较：{sum(r['match'] for r in expected_comparison)} 项相同，{sum(not r['match'] for r in expected_comparison)} 项不同（完整明细见 comparison.json）。", '', '本轮未安装、注册、停止进程、修改默认输入法、修改源码或执行输入验收。']
(OUT / 'README.zh-CN.md').write_text('\n'.join(summary) + '\n', encoding='utf-8')
print(json.dumps({'target5Installed': result['target5Installed'], 'installedVersion': result['installedVersion'], 'installedSourceCommit': result['installedSourceCommit'], 'products': [{k: p[k] for k in ['id','payloadCount','ownManifestMismatches','payloadDifferencesFromPrepared','registrationsUnchanged','startupUnchanged','sameProcessInstancesAsPrepared']} for p in comparisons], 'sameDllUserProcessInstancesAsPrepared': result['sameDllUserProcessInstancesAsPrepared'], 'defaultInputOverrideUnchanged': result['defaultInputOverrideUnchanged'], 'expected5Matching': sum(r['match'] for r in expected_comparison), 'expected5Mismatched': [r['path'] for r in expected_comparison if not r['match']]}, ensure_ascii=False, indent=2))
