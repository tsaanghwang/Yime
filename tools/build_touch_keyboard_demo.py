"""Build an isolated-development-only x64 own-TSF demo, never an IME installer."""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

from build_touch_keyboard_desktop import stage_resources, LAUNCHERS
from touch_keyboard_resources import ROOT, digest, generated, verify

HOST = 'YimeTouchBridgeDemoHost.exe'
SCOPE = 'isolated-own-tsf-demo-development-only'


def validate_host(path):
    path = Path(path).resolve(strict=True)
    if not path.is_relative_to((ROOT / '.generated').resolve()):
        raise ValueError('host must be under .generated; CI must build it from this checkout')
    raw = path.read_bytes()
    if len(raw) < 64 or raw[:2] != b'MZ':
        raise ValueError('invalid host PE')
    offset = struct.unpack_from('<I', raw, 60)[0]
    if offset + 6 > len(raw) or raw[offset:offset+4] != b'PE\0\0' or struct.unpack_from('<H', raw, offset+4)[0] != 0x8664:
        raise ValueError('native x64 host PE required')
    return path


def inventory(output):
    return {p.relative_to(output).as_posix(): digest(p) for p in sorted(output.rglob('*')) if p.is_file()}


def build(output, data, host):
    host = validate_host(host)
    output = generated(output)
    if output == ROOT / '.generated' or output.exists() and any(output.iterdir()):
        raise ValueError('new empty .generated demo package required')
    verify(data)  # Existing complete locked experimental dictionaries, never fixtures.
    output.mkdir(parents=True, exist_ok=True)
    stage_resources(output, data)
    for name in LAUNCHERS:
        (output / name).unlink()
    shutil.copyfile(host, output / HOST)
    (output / 'Start Isolated TSF Demo.cmd').write_bytes(b'@echo off\r\n"%~dp0YimeTouchKeyboard.exe" --own-tsf-demo --touch-ui\r\n')
    (output / 'README.txt').write_text('''18u 自有 TSF 宿主开发演示 — 仅隔离 Windows x64 开发环境

不是安装包，不注册输入法，不向 Word/Edge 或其他应用输入。
当前禁止在用户日常桌面执行：TSF ActivateEx 抑制标志不保证后续不会激活已安装 TIP。
Start Isolated TSF Demo.cmd 是显式启动入口；裸运行 EXE 不得回退到 SendInput。
请完整解压到新目录，不能覆盖原 PR87 或 a837 包；不得继承其验收。
使用本包真实完整专用词典，当前只接 CN/variable；未支持操作拒绝，不自动回退。
正文只来自自有 TSF context 独立读回；失焦/最小化后需明确重新绑定，未知提交不重放。
关闭仅回收本演示子宿主；无安装、默认输入法、用户词库或参数修改。
SHA-256 仅身份校验，不是数字签名。physicalAcceptance/installedProductAcceptance 均为 false。
USER_GUIDE 与本说明一致；不包含旧外部目标绑定/SendInput 启动说明。
''', encoding='utf-8')
    (output / 'USER_GUIDE.zh-CN.md').write_text((output / 'README.txt').read_text(encoding='utf-8'), encoding='utf-8')
    git = ['git', '-c', 'core.fsmonitor=false']
    head = subprocess.check_output(git + ['rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(git + ['status', '--porcelain'], cwd=ROOT, text=True).strip())
    if os.environ.get('GITHUB_ACTIONS') == 'true' and dirty:
        raise ValueError('CI demo requires clean source checkout')
    resources = dict(schemaVersion=1, scope='isolated-cn134-portable-resources', sourceCommit=head,
                     sourceChanges=dirty, architecture='windows-amd64', files=inventory(output))
    (output / 'resources.json').write_text(json.dumps(resources, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    bound = digest(output / 'resources.json')
    subprocess.run(['go', 'build', '-trimpath', '-ldflags=-H=windowsgui -X main.portableResourcesSHA256='+bound+' -X main.ownTSFDemoPackage=1',
                    '-o', str(output / 'YimeTouchKeyboard.exe'), './cmd/yime-touch-keyboard'],
                   cwd=ROOT/'go-backend', env=dict(os.environ, GOOS='windows', GOARCH='amd64', CGO_ENABLED='0'), check=True)
    manifest = dict(schemaVersion=1, scope=SCOPE, sourceCommit=head, sourceChanges=dirty,
                    architecture='windows-amd64', portableResourcesSHA256=bound, nativeHostSHA256=digest(output/HOST),
                    defaultLauncher='Start Isolated TSF Demo.cmd', completeChineseResources=True,
                    mode='variable', inputLanguage='chinese', physicalAcceptance=False, installedProductAcceptance=False,
                    userDesktopExecutionApproved=False, files=inventory(output))
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        manifest['ci'] = dict(runID=os.environ['GITHUB_RUN_ID'], checkoutCommit=head)
    (output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(output)


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output-dir',type=Path,default=ROOT/'.generated/touch-keyboard-own-tsf-demo')
    p.add_argument('--data-dir',type=Path,default=ROOT/'.generated/touch-keyboard-resources')
    p.add_argument('--host',type=Path,required=True)
    a=p.parse_args(); build(a.output_dir,a.data_dir,a.host)
