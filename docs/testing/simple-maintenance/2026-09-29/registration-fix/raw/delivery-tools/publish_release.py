import hashlib
import json
from pathlib import Path
import subprocess

root=Path('C:/dev/Yime-deliveries/registration-fix-20260929')
commit='2ffee43242af9981c462aeabb0d5b26c4f99286c'
tag='test-yimecore-registration-20260929-2ffee432'
assets=json.loads((root/'assets.json').read_text(encoding='utf-8'))
ci=json.loads(subprocess.check_output(['gh','run','view','36503447392','--json','status,conclusion,headSha,url']))
assert ci['headSha']==commit and ci['conclusion']=='success' and ci['status']=='completed'
for row in assets['assets']:
    p=root/row['path']
    assert p.stat().st_size==row['bytes'] and hashlib.file_digest(p.open('rb'),'sha256').hexdigest()==row['sha256']
notes=root/'release-notes.md'
notes.write_text('# YimeCore 注册查询修复开发测试包\n\n'
    '仅影响 YimeCore；独立完整包包含 x64 运行时及 x64/x86 应用支持。\n\n'
    f'源码及安装器提交：`{commit}`；[全部 CI 通过]({ci["url"]})。\n\n'
    '注册预检查询当前架构的精确持久化 profile，保留真实重复注册拒绝，并增加注册步骤诊断。'
    '本地与 CI 的两架构查询回归均通过；完整构建、65 文件清单、25 PE 架构、PS5 包检查及 ZIP 逐成员核验通过。\n\n'
    '这是新包，尚无本包的实机安装/输入验收。2026-09-27 原发布包未变更，也不包含本修复。'
    '开发机安装保持不变；后续测试 PC 范围由目标分支 installer/simple/HANDOFF.md 指定。\n\n'
    '下载完整 ZIP 并核对 SHA256SUMS；GitHub 自动 Source code ZIP 不是安装包。Evidence ZIP 保留源码快照、构建、准入及验证证据。\n',
    encoding='utf-8',newline='\n')
command=['gh','release','create',tag,'--target',commit,'--title','YimeCore registration fix 2026-09-29','--prerelease','--latest=false','--notes-file',str(notes)]
command += [str(root/r['path']) for r in assets['assets']]
subprocess.run(command,check=True)
remote_bytes=subprocess.check_output(['gh','api',f'repos/tsaanghwang/Yime/releases/tags/{tag}'])
(root/'release-remote.json').write_bytes(remote_bytes)
remote=json.loads(remote_bytes)
assert remote['tag_name']==tag and remote['prerelease'] and not remote['draft']
actual={a['name']:a for a in remote['assets']}
assert set(actual)=={a['path'] for a in assets['assets']}
rows=[]
for expected in assets['assets']:
    received=actual[expected['path']]
    assert received['state']=='uploaded' and received['size']==expected['bytes']
    assert received['digest']=='sha256:'+expected['sha256'], received
    rows.append(dict(**expected,url=received['browser_download_url'],remote_asset_id=received['id'],remote_digest=received['digest'],passed=True))
result=dict(passed=True,source_commit=commit,ci=ci,release_url=remote['html_url'],tag=tag,assets=rows,
    original_release_modified=False,installed_acceptance=False)
(root/'publication-verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,indent=2))
