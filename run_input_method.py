#!/usr/bin/env python
"""
启动音元输入法

使用方法:
    python run_input_method.py [选项]

选项:
    --copy-only       只复制候选字到剪贴板，不自动回贴
    --font-family     指定字体名称（默认: YinYuan Regular）
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
