#!/usr/bin/env python
"""
启动音元输入法 - 改进版（带快捷键）

使用方法:
    python run_input_method_v2.py [选项]

选项:
    --copy-only       只复制候选字到剪贴板，不自动回贴
    --font-family     指定字体名称（默认: Noto Sans）
    --hotkey          指定快捷键（默认: Ctrl+Shift+Y）
"""

import sys
import subprocess
from pathlib import Path

# 确保项目根目录在路径中
project_root = Path(__file__).resolve().parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

if __name__ == "__main__":
    # 获取Python解释器路径
    python_exe = sys.executable

    # 构建命令
    cmd = [python_exe, "-m", "yime.input_method.app_hotkey"] + sys.argv[1:]

    # 运行
    subprocess.run(cmd)
