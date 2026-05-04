#!/usr/bin/env python
"""
启动音元输入法

当前主入口为测试模式：
1. 默认以热键模式启动，保持右下角待命图标，不抢外部窗口的英文输入焦点。
2. 想输入汉字时，可按热键或点击右下角“音”图标。
3. 候选框弹出并获得输入焦点后，在编码框中输入。
4. 若显式传入 --input-mode global-listener，则改为实验性独立全局监听入口。

使用方法:
    python run_input_method.py [选项]

选项:
    --input-mode      输入模式。默认 hotkey；global-listener 为实验性独立入口
    --copy-only       只复制候选字到剪贴板，不自动回贴
    --font-family     指定字体名称（默认: 音元）
    --hotkey          从待命状态唤起输入框的快捷键（默认: Ctrl+Alt+Insert，避开 VS Code 与码元输入冲突）
    --wake-trigger    唤醒方式：hotkey、mouse、both（默认: both）
    --standby-trigger 休眠方式：hotkey、mouse、both（默认: both）
"""

import sys
from pathlib import Path

# 确保项目根目录在路径中
project_root = Path(__file__).resolve().parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

# 使用模块方式运行
if __name__ == "__main__":
    import subprocess

    # 获取Python解释器路径
    python_exe = sys.executable

    # 构建命令
    cmd = [python_exe, "-m", "yime.input_method.app"] + sys.argv[1:]

    # 运行
    subprocess.run(cmd)
