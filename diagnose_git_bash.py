#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Git Bash 键盘响应诊断

诊断为什么Git Bash终端没有响应
"""

import sys
import io

# 设置UTF-8输出
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

print("=" * 60)
print("  Git Bash 键盘响应诊断")
print("=" * 60)
print()

print("问题分析：")
print()
print("1. pynput是全局键盘监听")
print("   - 监听所有应用的键盘输入")
print("   - 不区分是哪个终端")
print()
print("2. Git Bash终端没有响应的可能原因：")
print("   a) 键盘事件被捕获，但没有触发候选框")
print("   b) 候选框被其他窗口遮挡")
print("   c) 输入法状态不正确")
print("   d) 线程调度问题")
print()

print("诊断步骤：")
print()
print("步骤1：检查键盘事件是否被捕获")
print("  运行: python test_git_bash.py")
print("  在Git Bash中敲击键盘，观察是否捕获")
print()

print("步骤2：检查候选框是否显示")
print("  - 候选框可能被Git Bash窗口遮挡")
print("  - 尝试移动Git Bash窗口")
print("  - 查看是否有候选框在其他位置")
print()

print("步骤3：检查输入法状态")
print("  - Win + Space 切换到音元键盘")
print("  - 确认输入法图标显示音元")
print()

print("步骤4：检查线程问题")
print("  - 查看是否有错误信息")
print("  - 检查是否有'main thread'错误")
print()

print("=" * 60)
print("  快速测试")
print("=" * 60)
print()

print("请选择测试方式：")
print()
print("1. 简单测试 - 只捕获键盘事件")
print("   python test_git_bash.py")
print()
print("2. 完整测试 - 启动候选框")
print("   python test_keyboard_connection.py")
print()
print("3. 后台测试 - 不启动GUI")
print("   python test_backend.py")
print()

print("=" * 60)
print("  可能的解决方案")
print("=" * 60)
print()

print("方案1：在Windows PowerShell中测试")
print("  - PowerShell可能有更好的兼容性")
print("  - 切换到PowerShell选项卡")
print("  - 运行测试")
print()

print("方案2：检查候选框位置")
print("  - 候选框可能显示在屏幕外")
print("  - 或被其他窗口遮挡")
print("  - 尝试最小化其他窗口")
print()

print("方案3：检查输入法切换")
print("  - 确保已切换到音元键盘")
print("  - Win + Space 选择音元")
print("  - 观察输入法图标")
print()

print("方案4：检查权限")
print("  - 以管理员权限运行")
print("  - 右键 → 以管理员身份运行")
print()

print("=" * 60)
print("  当前建议")
print("=" * 60)
print()

print("立即执行：")
print()
print("1. 在Git Bash中运行：")
print("   python test_git_bash.py")
print()
print("2. 敲击几个键，观察是否捕获")
print()
print("3. 如果捕获成功，说明pynput工作正常")
print("   问题在于候选框显示或输入处理")
print()
print("4. 如果没有捕获，说明pynput有问题")
print("   尝试在PowerShell中测试")
print()
