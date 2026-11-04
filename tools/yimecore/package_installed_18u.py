"""Build-only wrapper for the existing simple installer; never executes product binaries."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

import assemble_installed_18u as a

VERSION = '0.1.0-18u-test.6'
ZIP_NAME = 'YimeCore-18u-0.1.0-18u-test.6-windows-amd64.zip'
INSTALLER = ('Product.psm1', 'Setup.ps1', 'Setup.cmd')
SIGNATURE_STATUSES = {'Valid', 'UnknownError', 'NotSigned', 'HashMismatch', 'NotTrusted', 'NotSupportedFileFormat', 'Incompatible'}
README = r'''# 独立 18u 持久安装开发候选包

版本：0.1.0-18u-test.6；仅原生 Windows x64，中文 variable 模式。
这是复用 installer/simple 的独立 18u 产品，不是标准键盘版、Rime/PIME、
PR87 预览包或临时注册诊断包。保留原产品与各自数据、注册身份。

CI 仅构建与静态制包，下载、解压不代表已通过实机验收。
在已获授权的设备上，按固定交付说明执行正常卸载、安装和重启；
同一任务已有的授权不需重复确认。其他设备的安装仍需对应授权。
注意 Setup 默认 Action=Install，会请求 UAC 提权；没有参数不等于只读。
维护操作语义：
- Setup.ps1 的 -Action Check：核对包和原生宿主架构；会写安装日志，
  不是注册/激活验收。
- -Action Install：管理员持久安装独立 18u 及注册，不能当静态检查。
- -Action Uninstall：按所有权移除独立 18u，保留个人数据；不支持 ResetData。
这些操作应经仓库受检 PowerShell 入口和固定交付步骤执行。

固定安装目录：%ProgramFiles%\YimeCore 18u Touch
独立用户数据目录：%LOCALAPPDATA%\YimeCore 18u Touch
Setup 日志：%USERPROFILE%\Yime Setup Logs
CLSID：{6DFACE1F-562E-4773-A9D6-D5753A314711}
Profile：{1BD904AC-3194-4419-B70A-5574100F18B3}；语言 0804。
不要把标准版或 Rime 的安装目录、配置和数据复制进此目录。

维护顺序：先核对固定交付哈希及签名状态，再运行获准的维护操作；
Install 内部依次注销旧版、移除旧载荷、复制并注册新版。
注销 TIP 后，由独立的新进程复核 API 缺失并完成 COM 注销，避免同进程 TSF 枚举缓存误报；
任一阶段失败均保留文件，不跳过最终缺失检查。
需要独立卸载时使用 Action Uninstall，保留旧包及用户数据后再 Install。
安装日志和退出状态须明确。文件占用时取消，保存工作后正常重启，再维护；
不强杀系统或文档宿主、不放宽权限、不覆盖已加载 DLL。
日志记录完整路径、HRESULT/Win32 错误及 Restart Manager 占用查询；
拒绝访问不自动等同 ACL 错误，未查到进程也不能放行失败的文件检查。
重启沿用任务授权，Setup 本身不会自动重启。
重启后先确认仍为同一固定安装、中文输入环境和独立 18u 身份，
再按授权显式启动一次新包的已安装宿主验收，使用全新包外证据目录。
未知、残留、身份不符或验收失败时保留证据，不自动重试或重装。
Setup 不自动启动验收或开机常驻。此包不是完整日用触摸 UI，
不包含 Word/Edge 或全量物理验收结论。

包中的安装后验证入口仅供以后明确授权：Yime18uInstalledRuntime.exe
显式 installed-18u-check 模式，使用独立清单哈希和全新证据目录。
该流程使用真实已安装 TSF 实例、自有宿主、一次 Broker 编辑及独立读回；
这里描述的是实现目标，不是本次已执行或已通过的实机结果。
正常结束仅停止本轮进程，不卸载持久安装的 profile。

package-evidence.json 记录源码提交及所有其他文件的大小、SHA-256；
signatures.json 是 Windows Get-AuthenticodeSignature 对五个 PE 的只读结果。
非 PE 文件未做 Authenticode 验证，不能视为已签名。哈希不是发布者签名；
即使某项 Valid，也不意味着整个开发包或安装体验已获得认证。
包清单本身的 SHA-256 与 ZIP SHA-256 应从独立交付记录核对。

本轮不建立新的备份/恢复系统。后续回退沿用旧包重装，保留用户数据；
首次独立 18u 没有旧版时只能按获准说明卸载独立 18u，不影响标准/Rime。
安装失败需保留证据并停止，不能承诺自动回滚或重复注册。
'''


def inventory(root):
    result = {}
    for p in root.rglob('*'):
        if p.is_symlink() or (hasattr(p, 'is_junction') and p.is_junction()):
            raise ValueError('linked package member')
        if p.is_file():
            result[p.relative_to(root).as_posix()] = a.digest(p)
    return result


def signatures(path, source, package):
    doc = a.load_json(path)
    if set(doc) != {'schema', 'sourceCommit', 'files'} or doc['schema'] != 'installed-18u-signatures-v1' or doc['sourceCommit'] != source or not isinstance(doc['files'], list):
        raise ValueError('signature source/schema')
    expected = {'payload/' + name for name in a.BINARIES}
    if (package / 'payload/frontend/YimeTouchKeyboard.exe').is_file():
        expected.add('payload/frontend/YimeTouchKeyboard.exe')
    seen = set()
    for row in doc['files']:
        if not isinstance(row, dict) or set(row) != {'path', 'bytes', 'sha256', 'status', 'signerThumbprint'}:
            raise ValueError('signature entry fields')
        name = row['path']
        if not isinstance(name, str) or name not in expected or name in seen:
            raise ValueError('signature inventory')
        seen.add(name)
        if type(row['bytes']) is not int or {k: row[k] for k in ('bytes', 'sha256')} != a.digest(package / name):
            raise ValueError('signature payload mismatch')
        status, thumb = row['status'], row['signerThumbprint']
        if not isinstance(status, str) or status not in SIGNATURE_STATUSES:
            raise ValueError('signature status')
        if thumb is not None and (not isinstance(thumb, str) or not re.fullmatch('[0-9a-fA-F]{40}', thumb)):
            raise ValueError('signature thumbprint')
        if (status == 'NotSigned' and thumb is not None) or (status == 'Valid' and thumb is None):
            raise ValueError('signature claim inconsistent')
    if seen != expected:
        raise ValueError('signature inventory')
    return doc


def build(repo, native, go, data, work, signature_file, source_commit, runner=subprocess.run, frontend=None):
    repo = Path(repo).absolute()
    work = Path(work).absolute()
    for p in (work, *work.parents):
        if p.is_symlink() or (hasattr(p, 'is_junction') and p.is_junction()):
            raise ValueError('linked work directory')
    if work.exists():
        raise ValueError('fresh work directory required')
    if not re.fullmatch('[0-9a-f]{40}', source_commit):
        raise ValueError('full source commit required')
    # Inputs stay outside the fresh output; assembler checks all source locks.
    for directory in (repo, Path(native).absolute(), Path(go).absolute(), Path(data).absolute()):
        if directory == work or work in directory.parents:
            raise ValueError('work overlaps inputs')
    payload = work / 'assembled'
    package = work / 'package'
    descriptor = a.assemble(repo, native, go, data, payload, source_commit) if frontend is None else a.assemble(repo, native, go, data, payload, source_commit, frontend)
    version = VERSION if frontend is None else '0.1.0-18u-test.9'
    zip_name = ZIP_NAME if frontend is None else 'YimeCore-18u-0.1.0-18u-test.9-windows-amd64.zip'
    expected_payload = {row['path']: {k: row[k] for k in ('bytes', 'sha256')} for row in descriptor['files']}
    expected_payload['installed-18u-product.json'] = a.digest(payload / 'installed-18u-product.json')
    installer_before = {name: a.digest(repo / 'installer/simple' / name) for name in INSTALLER}
    params = work / 'build-parameters.json'
    params.write_text(json.dumps({'Product': 'yimecore-18u', 'PayloadRoot': str(payload), 'OutputRoot': str(package), 'Version': version, 'Target': 'windows-amd64'}), encoding='utf-8')
    runner([sys.executable, str(repo / 'tools/powershell/run_checked.py'), '--script', str(repo / 'installer/simple/Build-Package.ps1'), '--edition', 'ps7', '--params-file', str(params)], cwd=repo, check=True, timeout=180)
    expected = {'payload/' + name: value for name, value in expected_payload.items()}
    expected.update(installer_before)
    actual = inventory(package)
    if set(actual) != set(expected) | {'product-package.json'} or any(actual[name] != value for name, value in expected.items()):
        raise ValueError('simple package differs from exact assembled payload/installer')
    simple = a.load_json(package / 'product-package.json')
    if set(simple) != {'format', 'product', 'version', 'files', 'target', 'host_architecture', 'tsf64_architecture'} or (simple['format'], simple['product'], simple['version'], simple['target'], simple['host_architecture'], simple['tsf64_architecture']) != ('yime-simple-package-18u-1', 'yimecore-18u', version, 'windows-amd64', 'amd64', 'x64'):
        raise ValueError('simple manifest identity')
    rows = simple['files']
    if not isinstance(rows, list) or len(rows) != len(expected_payload) or any(not isinstance(r, dict) or set(r) != {'path', 'bytes', 'sha256'} for r in rows):
        raise ValueError('simple manifest inventory')
    if {r['path']: {k: r[k] for k in ('bytes', 'sha256')} for r in rows} != expected_payload:
        raise ValueError('simple manifest payload mismatch')
    sig = signatures(signature_file, source_commit, package)
    (package / 'signatures.json').write_text(json.dumps(sig, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    readme = README
    if frontend is not None:
        readme = readme.replace(VERSION, version).replace('中文 variable 模式。', '安装后检查仍为中文 variable；触控前端支持三模式和 CN/EN。')
        readme = readme.replace('此包不是完整日用触摸 UI，\n不包含 Word/Edge 或全量物理验收结论。', '本包新增 frontend/ 完整触控 UI 与 TSF 接入候选；不包含 Word/Edge 或物理验收通过结论。')
        readme = readme.replace('五个 PE', '六个 PE')
        readme += '\n安装完成后，从安装目录 frontend/Start Installed Touch Keyboard.cmd 启动。完整语义和限制见 frontend/USER_GUIDE.zh-CN.md。\n'
    (package / 'README.zh-CN.md').write_text(readme, encoding='utf-8')
    files = inventory(package)
    evidence = {'schema': 'installed-18u-package-evidence-v1', 'sourceCommit': source_commit, 'version': version, 'product': 'yimecore-18u', 'architecture': 'native-x64', 'installationExecuted': False, 'registrationExecuted': False, 'installedHostAcceptance': False, 'publisherTrust': 'not-established', 'nonPESignatureStatus': 'not-evaluated', 'files': files}
    (package / 'package-evidence.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    files['package-evidence.json'] = a.digest(package / 'package-evidence.json')
    archive = work / zip_name
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for name in sorted(files):
            if a.digest(package / name) != files[name]:
                raise ValueError('package changed before ZIP')
            z.write(package / name, name)
    with zipfile.ZipFile(archive) as z:
        if len(z.infolist()) != len(files) or set(z.namelist()) != set(files):
            raise ValueError('ZIP inventory')
        import hashlib
        for name, record in files.items():
            with z.open(name) as stream:
                if z.getinfo(name).file_size != record['bytes'] or hashlib.file_digest(stream, 'sha256').hexdigest() != record['sha256']:
                    raise ValueError('ZIP byte mismatch')
    summary = {'sourceCommit': source_commit, 'zip': zip_name, **a.digest(archive), 'packageEvidence': a.digest(package / 'package-evidence.json'), 'installedDescriptor': expected_payload['installed-18u-product.json']}
    (work / 'package-receipt.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'native', 'go', 'data', 'work', 'signatures', 'source-commit'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--frontend', help='complete matching-source installed TSF frontend; produces test.9')
    args = parser.parse_args()
    print(json.dumps(build(args.repo, args.native, args.go, args.data, args.work, args.signatures, args.source_commit, frontend=args.frontend), indent=2))

if __name__ == '__main__':
    main()
