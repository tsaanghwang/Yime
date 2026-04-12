#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
字体支持测试

测试系统中哪些字体支持私用区字符
"""

import sys
import io
import tkinter as tk
from tkinter import font as tkfont

# 设置UTF-8输出
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

print("=" * 60)
print("  字体支持测试")
print("=" * 60)
print()

# 测试字符
test_chars = ['\uE4F1', '\uE4E9', '\uE4EA', '\uE4EB']
test_str = ''.join(test_chars)

print("测试私用区字符:")
print(f"  {test_str}")
print(f"  Unicode: U+E4F1, U+E4E9, U+E4EA, U+E4EB")
print()

# 创建tkinter窗口测试字体
root = tk.Tk()
root.withdraw()

# 获取所有字体
all_fonts = tkfont.families()

print("检查字体支持:")
print()

# 重点检查的字体
important_fonts = [
    'Noto Sans',
    'Noto Sans CJK SC',
    'Noto Sans CJK TC',
    'Noto Sans CJK JP',
    'Noto Sans CJK KR',
    'Microsoft YaHei',
    'SimSun',
    'Consolas',
    'Courier New',
]

print("重点字体:")
for font_name in important_fonts:
    if font_name in all_fonts:
        try:
            # 创建Label测试
            label = tk.Label(root, text=test_str, font=(font_name, 12))
            label.pack()
            root.update()
            print(f"  {font_name}: 可用")
            label.destroy()
        except:
            print(f"  {font_name}: 错误")
    else:
        print(f"  {font_name}: 未安装")

print()

# 检查Noto Sans变体
print("Noto Sans变体:")
noto_fonts = [f for f in all_fonts if 'Noto' in f and 'Sans' in f]
for font_name in sorted(noto_fonts)[:10]:
    print(f"  {font_name}")

print()

# 检查CJK字体
print("CJK字体:")
cjk_fonts = [f for f in all_fonts if 'CJK' in f or 'Chinese' in f]
for font_name in sorted(cjk_fonts)[:10]:
    print(f"  {font_name}")

print()

root.destroy()

print("=" * 60)
print("  解决方案")
print("=" * 60)
print()

print("如果显示占位符，可能的原因:")
print()
print("1. 字体不支持私用区字符")
print("   - 需要使用支持PUA的字体")
print("   - Noto Sans应该支持")
print()
print("2. 字体未正确安装")
print("   - 重新安装Noto Sans")
print("   - 确保安装了所有变体")
print()
print("3. 应用未使用正确字体")
print("   - 检查应用字体设置")
print("   - 确保选择Noto Sans")
print()
print("4. 字体缓存问题")
print("   - 重启应用")
print("   - 或重启系统")
print()

print("=" * 60)
print("  IDE问题分析")
print("=" * 60)
print()

print("IDE编辑区无显示，光标不动:")
print()
print("可能原因:")
print("1. IDE不支持IME输入")
print("   - 某些IDE对输入法支持有限")
print("   - 需要特殊配置")
print()
print("2. 输入法未正确激活")
print("   - 确保切换到音元键盘")
print("   - Win+Space选择")
print()
print("3. IDE输入模式问题")
print("   - 检查IDE输入设置")
print("   - 可能需要切换输入模式")
print()
print("4. 焦点问题")
print("   - 确保焦点在编辑区")
print("   - 点击编辑区获得焦点")
print()

print("预览区正常显示:")
print("  说明字符本身没问题")
print("  问题在于编辑区的输入处理")
print()
