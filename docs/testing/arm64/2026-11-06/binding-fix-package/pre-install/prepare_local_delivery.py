"""Extract and verify the frozen delivery; run the read-only native Check only."""
import hashlib
import json
import shutil
import subprocess
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

BUILD = Path('C:/dev/Yime/.wt/bindfix/.generated/package-binding-636cef68')
OUT = Path('C:/dev/Yime-deliveries/18u-binding-636cef68-20261106')
SOURCE = '636cef681ee995a21a9c45fd750f8cb4b0acb4a1'
ZIP_SHA = 'e482200ea81a8241a4780feaa07b01a53bb8b177ec62b5c2496e158a7b00b36c'

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

receipt = json.loads((BUILD / 'complete-package-receipt.json').read_text(encoding='utf-8'))
assert receipt['sourceCommit'] == SOURCE
assert receipt['version'] == '0.2.0-18u-arm64.5'
archive = Path(receipt['zip']['path'])
identity_path = Path(receipt['identity'])
identity = json.loads(identity_path.read_text(encoding='utf-8'))
assert identity['source']['commit'] == SOURCE and identity['source']['clean'] is True
assert sha(archive) == receipt['zip']['sha256'] == ZIP_SHA
assert sha(identity_path) == receipt['identityDigest']['sha256']
assert archive.stat().st_size == receipt['zip']['bytes']
assert not OUT.exists(), 'Delivery already exists; inspect rather than overwrite.'
with zipfile.ZipFile(archive) as z:
    names = [i.filename for i in z.infolist() if not i.is_dir()]
    assert len(names) == len(set(names)) == identity['fileCount'] == 1156
    assert set(names) == set(identity['files'])
    for info in z.infolist():
        path = PurePosixPath(info.filename)
        assert not path.is_absolute() and '..' not in path.parts
        assert ':' not in info.filename and '\\' not in info.filename
        assert (info.external_attr >> 16) & 0o170000 != 0o120000
    for name, row in identity['files'].items():
        data = z.read(name)
        assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256'], name
    OUT.mkdir(parents=True)
    package = OUT / 'package'
    package.mkdir()
    z.extractall(package)
shutil.copy2(archive, OUT / archive.name)
shutil.copy2(identity_path, OUT / identity_path.name)
for name, row in identity['files'].items():
    local = package / name
    assert local.stat().st_size == row['bytes'] and sha(local) == row['sha256'], name
assert sha(OUT / archive.name) == ZIP_SHA
assert sha(package / 'YimeMaintenance.exe') == receipt['maintenanceSHA256']
assert sha(package / 'maintenance-plan.json') == receipt['planSHA256']
assert sha(package / 'payload/installed-18u-product.json') == receipt['installedManifest']['sha256']
result = subprocess.run([str(package / 'YimeMaintenance.exe'), '-action', 'Check'], cwd=package, capture_output=True)
(OUT / 'native-package-check.log').write_bytes(result.stdout + result.stderr)
assert result.returncode == 0, 'Read-only native package check failed.'
launcher = '''@echo off
setlocal
title Yime 18u ARM64 .5 repair installation
if exist "%~dp0installation-output.log" (
  echo A previous installation attempt is recorded. Preserve its logs and return to Codex.
  pause
  exit /b 1
)
echo Save your documents and close Codex and Notepad before continuing.
echo If Explorer keeps the old input component loaded, restart Windows first.
echo This entry uses the standard installer and Windows UAC.
pause
cd /d "%~dp0package"
if errorlevel 1 exit /b 1
YimeMaintenance.exe -action Check > "%~dp0package-check-on-install.log" 2>&1
if errorlevel 1 (
  type "%~dp0package-check-on-install.log"
  pause
  exit /b 1
)
YimeMaintenance.exe -action Install > "%~dp0installation-output.log" 2>&1
set "YIME_BINDING_INSTALL_EXIT=%errorlevel%"
type "%~dp0installation-output.log"
echo.
echo Installer exit code: %YIME_BINDING_INSTALL_EXIT%
echo Keep this output and the Yime Setup Logs folder. Return to Codex for verification.
pause
exit /b %YIME_BINDING_INSTALL_EXIT%
'''
(OUT / 'Install-18u-ARM64.cmd').write_text(launcher, encoding='ascii', newline='\r\n')
readme = '''# ASUS 18u ARM64 焦点绑定修复包

版本：0.2.0-18u-arm64.5
固定源码：636cef681ee995a21a9c45fd750f8cb4b0acb4a1

本目录的 package 是完整安装包。已核对全部 1156 个文件，并通过原生维护程序只读 Check。
本轮尚未执行 Install，也没有完成新版记事本输入复测。

当前旧 DLL 被 Codex、资源管理器和含未保存文本的记事本加载。请先保存文档；正常重启 Windows 后，先不要打开 Codex、记事本或选择 18u 输入法。
双击本目录 Install-18u-ARM64.cmd，按 Windows 正常安装提示继续。只升级 YimeCore 18u Touch，不修改默认输入法。
入口只执行一次安装并保留 installation-output.log；若失败，不会自动重试。完整安装日志位于 C:\\Users\\tsaan\\Yime Setup Logs。
如果仍提示文件占用，保留日志，停止重试。不要结束 Explorer/System 或强制替换文件。

安装返回后，重新打开本次 Codex 对话；需核对 .5 全载荷及进程身份，再测试记事本新标签的实际绑定和中文正文提交。
原有校准文件应保持不变；自动化鼠标测试不属于真人手指/笔验收。

ZIP SHA-256：e482200ea81a8241a4780feaa07b01a53bb8b177ec62b5c2496e158a7b00b36c
'''
(OUT / 'README.zh-CN.md').write_text(readme, encoding='utf-8')
record = {
    'schema': '18u-binding-local-delivery-v1',
    'observedUTC': datetime.now(timezone.utc).isoformat(),
    'sourceCommit': SOURCE, 'version': receipt['version'], 'root': str(OUT),
    'archiveSHA256': ZIP_SHA, 'extractedFileCount': len(names),
    'extractedHashesVerified': True, 'nativeCheckExitCode': result.returncode,
    'installLaunched': False,
}
(OUT / 'local-delivery-receipt.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(record, ensure_ascii=False, indent=2))
