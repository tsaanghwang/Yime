"""Build the complete isolated CN134 Chinese desktop portable package (18u)."""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess

from touch_keyboard_resources import ROOT, LOCK, NAMES, digest, generated, verify

ASSETS = (
    'prototypes/touch-terminal/data/physical-layout.json',
    'prototypes/touch-terminal/encoding/manual_key_layout.resolved.json',
    'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json',
    'go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf',
    'internal_data/yime_syllable_decomposition.tsv',
)
PROFILE = 'prototypes/touch-terminal/desktop/profiles/'
LAUNCHERS = {
    'Start Keyboard.cmd': '',
    'Start Main Area.cmd': '',
    'Start Preview.cmd': ' --preview',
    'Start Touch Screen Keyboard.cmd': ' --touch-ui --theme dark --key-sound click',
    'Start Touch Screen Preview.cmd': ' --preview --touch-ui --theme dark --key-sound click',
    'Start English Only.cmd': ' --english-only',
    'Start Full Keyboard.cmd': ' --profile '+PROFILE+'full-size.json',
    'Start Left Area.cmd': ' --numeric-zones left --remove-gutters',
    'Start Right Area.cmd': ' --numeric-zones right --remove-gutters',
    # Frozen candidates retain their existing English-only behavior.
    'Start 17u Main Area.cmd': ' --english-only --profile '+PROFILE+'main-17u.json',
    'Start 23u Keyboard.cmd': ' --english-only --profile '+PROFILE+'full-23u.json',
}


def stage_resources(output, data):
    verify(data)
    for name in ASSETS:
        dest = output / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, dest)
    shutil.copytree(ROOT / PROFILE, output / PROFILE)
    (output / 'data').mkdir()
    for name in NAMES:
        shutil.copyfile(data / name, output / 'data' / name)
    shutil.copyfile(LOCK, output / 'resources.lock.json')
    shutil.copyfile(ROOT / 'prototypes/touch-terminal/desktop/USER_GUIDE.zh-CN.md', output / 'USER_GUIDE.zh-CN.md')
    for name, args in LAUNCHERS.items():
        body = '@echo off\r\nstart "" /d "%~dp0" "%~dp0YimeTouchKeyboard.exe"'+args+'\r\n'
        (output/name).write_bytes(body.encode('ascii'))
    (output/'Check Package.cmd').write_bytes(b'@echo off\r\n"%~dp0YimeTouchKeyboard.exe" --check-package --data-report "%~dp0package-check.json"\r\nif errorlevel 1 (echo Package check FAILED) else (echo Package check PASSED - see package-check.json)\r\npause\r\n')
    (output/'README.txt').write_text('''音元桌面触摸键盘：18u 完整中文便携实验包

完整解压后双击 Start Keyboard.cmd（或 YimeTouchKeyboard.exe）。
主区为 18u / 100 键 / 342.90 mm。先在目标文本区放置光标，
再点键盘“绑定目标”。组合只在键盘内显示，明确确认后才发送。
先阅读 USER_GUIDE.zh-CN.md。无需源码、Go、Python、网络或已安装输入法。

Start Preview.cmd：只写窗口内文本，不向宿主发送。
Start Touch Screen Keyboard.cmd / Start Touch Screen Preview.cmd：新增触屏试用视图。
18u宽，主体84键纵向为原设计80%，加18个等宽同高控制键，共102键；设置、帮助、
编辑和退出替换原功能行；顶部文字和翻页区随盘面校准尺寸调整。不会自动改变宿主窗口尺寸。
省略 --touch-ui 仍是原完整100键视图。两种视图的测试记录不能互相继承。
Start English Only.cmd：保留旧版英文输入路径。
Start Full Keyboard.cmd：原 24.75u 全盘；Left/Right 保留一侧数字区。
17u / 23u 为冻结候选，仍为旧英文路径，不开展另一条开发或验收路线。
未实施“缩短 1 毫米”。

Check Package.cmd：检查资源及三模式中文内存选词，生成 package-check.json。
该检查不打开键盘窗口、不向应用发送输入；失败时不得沿用旧报告。
程序启动时核对编译绑定的 resources.json 及所有资源 SHA-256。
资源缺失/修改/混包时失败，请完整解压同一包到新目录。
不要手工编辑包内 profile、字体或词典；可用命令行调整屏幕毫米和标尺校准。
manifest.json 记录源码、架构、资源与文件身份；SHA-256 不是数字签名。

完整词典每次启动生成独立临时索引，正常关闭后清理。没有用户词库、学习
迁移或已安装产品回退。字体仅在本进程私有加载，不安装到系统。
首次加载需等待，不要连续重复启动。最小化后点任务栏恢复；Ctrl+Alt+K 切换最小化/恢复。

失焦、最小化、帮助或发送结果不明后停止，核对正文后重新绑定；不自动重放。
SendInput 不能原子绑定窗口，发送计数不是宿主接受结论。
手指、触控笔、真实应用与 ARM64 原生验收均须另行观察。
ARM64 包仅交叉构建。未修改已安装输入法、默认输入法或用户数据。
''', encoding='utf-8', newline='\n')


def build(output: Path, arch: str, data: Path):
    output = generated(output)
    if output == ROOT/'.generated' or output.exists() and any(output.iterdir()):
        raise ValueError('Choose a new empty package directory under .generated/; existing packages are preserved')
    verify(data)
    output.mkdir(parents=True, exist_ok=True)
    stage_resources(output, data)
    git = ['git', '-c', 'core.fsmonitor=false']
    head = subprocess.check_output(git+['rev-parse','HEAD'], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(git+['status','--porcelain'], cwd=ROOT, text=True).strip())
    if os.environ.get('GITHUB_ACTIONS') == 'true' and dirty:
        raise ValueError('CI package requires a clean source checkout')
    resources = {'schemaVersion': 1, 'scope': 'isolated-cn134-portable-resources',
                 'sourceCommit': head, 'sourceChanges': dirty, 'architecture': 'windows-'+arch,
                 'files': {p.relative_to(output).as_posix(): digest(p) for p in sorted(output.rglob('*')) if p.is_file()}}
    resource_file = output/'resources.json'
    resource_file.write_text(json.dumps(resources, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\n')
    env = dict(os.environ, GOOS='windows', GOARCH=arch, CGO_ENABLED='0')
    exe = output/'YimeTouchKeyboard.exe'
    subprocess.run(['go','build','-trimpath',f'-ldflags=-H=windowsgui -X main.portableResourcesSHA256={digest(resource_file)}',
                    '-o',str(exe),'./cmd/yime-touch-keyboard'], cwd=ROOT/'go-backend', env=env, check=True)
    manifest = {'schemaVersion': 2, 'scope': 'uninstalled-desktop-touch-keyboard-chinese-experiment',
                'architecture': 'windows-'+arch, 'sourceCommit': head, 'sourceChanges': dirty,
                'goVersion': subprocess.check_output(['go','version'],text=True).strip(),
                'developmentBaseline': 'main-18u', 'defaultLauncher': 'Start Keyboard.cmd',
                'defaultMode': 'chinese-host-explicit-target-binding', 'defaultProfile': PROFILE+'main-only.json',
                'unitMM': 19.05, 'mainWidthU': 18, 'mainWidthMM': 342.9, 'mainKeyCount': 100,
                'touchScreenView': {'version': 'touch-screen-v2', 'flag': '--touch-ui',
                    'mainWidthU': 18, 'boardHeightU': 5.7, 'bodyKeyHeightScale': 0.8,
                    'controlHeightU': 0.8, 'controlWidthU': 1, 'controlCount': 18,
                    'reservedControlCount': 3, 'keyCount': 102,
                    'bodyKeycapStyle': {'version': 'raised-rectangular-v1',
                                       'scope': 'single-rectangle-body-keys', 'hitGeometryChanged': False,
                                       'horizontalInsetU': 0.04, 'verticalInsetU': 0.03,
                                       'depthU': 0.025, 'bevelU': 0.012, 'extraLegendInsetU': 0.05},
                    'headerSizing': {'policy': 'calibrated-board-units', 'statusHeightU': 0.30,
                                     'candidateHeightU': 0.8, 'pagerWidthU': 1, 'pagerHeightU': 0.8,
                                     'marginU': 0.04, 'minimumPixels': {'status': 32, 'row': 1, 'pager': 1, 'margin': 6}},
                    'hardwareAcceptance': False},
                'main17Status': 'frozen-optional-candidate', 'full23Status': 'frozen-optional-candidate',
                'resourceArchiveSHA256': json.loads(LOCK.read_text())['archiveSHA256'],
                'portableResourcesSHA256': digest(resource_file), 'completeChineseResources': True,
                'hardwareAcceptance': False, 'installedProductAcceptance': False,
                'arm64NativeAcceptance': False,
                'files': {p.relative_to(output).as_posix(): digest(p) for p in sorted(output.rglob('*')) if p.is_file()}}
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        manifest['ci'] = {'runURL': f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
                          'event': os.environ.get('GITHUB_EVENT_NAME'),
                          'attempt': os.environ.get('GITHUB_RUN_ATTEMPT'),
                          'checkoutCommit': head}
    (output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(output)
    print('Executable SHA-256:',digest(exe))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir',type=Path,default=ROOT/'.generated/touch-keyboard-desktop')
    parser.add_argument('--arch',choices=['amd64','arm64'],default='amd64')
    parser.add_argument('--data-dir',type=Path,default=ROOT/'.generated/touch-keyboard-resources')
    args=parser.parse_args()
    build(args.output_dir,args.arch,args.data_dir)
