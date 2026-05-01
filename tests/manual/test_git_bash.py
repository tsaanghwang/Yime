#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Git Bash 键盘响应测试

专门测试在Git Bash终端中的键盘响应
"""

import sys
import io
from pathlib import Path

# 设置UTF-8输出
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 添加项目路径
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

def test_git_bash_keyboard():
    """测试Git Bash键盘响应"""
    print("=" * 60)
    print("  Git Bash 键盘响应测试")
    print("=" * 60)
    print()

    print("问题诊断：")
    print()

    # 1. 检查pynput
    print("1. 检查pynput")
    try:
        import pynput
        from pynput import keyboard
        print("   pynput已安装")
    except ImportError:
        print("   pynput未安装")
        return

    # 2. 检查键盘监听器
    print()
    print("2. 检查键盘监听器")
    try:
        from yime.input_method.core.keyboard_listener import KeyboardListener
        print("   KeyboardListener可导入")
    except Exception as e:
        print(f"   导入失败: {e}")
        return

    # 3. 测试键盘事件
    print()
    print("3. 测试键盘事件捕获")
    print("   请在Git Bash中敲击几个键...")
    print("   (按Ctrl+C退出)")
    print()

    key_count = [0]

    def on_press(key):
        key_count[0] += 1
        try:
            key_str = str(key)
            print(f"   捕获按键 #{key_count[0]}: {key_str}")
        except:
            print(f"   捕获按键 #{key_count[0]}: [无法显示]")

    try:
        listener = keyboard.Listener(on_press=on_press)
        listener.start()
        print("   监听器已启动")
        print()

        # 等待用户输入
        import time
        for i in range(10):
            time.sleep(1)
            print(f"   等待中... {10-i}秒")

        listener.stop()

    except KeyboardInterrupt:
        print()
        print("   用户中断")
    except Exception as e:
        print(f"   错误: {e}")

    print()
    print("=" * 60)
    print("  测试结果")
    print("=" * 60)
    print()

    if key_count[0] > 0:
        print(f"成功！捕获了 {key_count[0]} 个按键")
        print()
        print("可能的问题：")
        print("1. 键盘事件被捕获，但没有触发输入处理")
        print("2. 需要检查InputManager的处理逻辑")
        print("3. 可能是线程调度问题")
    else:
        print("未捕获到任何按键")
        print()
        print("可能的原因：")
        print("1. pynput在Git Bash中可能有限制")
        print("2. Git Bash可能需要特殊权限")
        print("3. 建议在Windows PowerShell中测试")

    print()
    print("建议：")
    print("1. 在Windows PowerShell中运行测试")
    print("2. 检查是否有权限问题")
    print("3. 尝试以管理员权限运行")

if __name__ == "__main__":
    test_git_bash_keyboard()
