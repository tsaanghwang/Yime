#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
后台测试脚本 - 不启动GUI，只测试核心功能
"""

import sys
import io
from pathlib import Path

# 设置UTF-8输出
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 添加项目路径
sys.path.insert(0, str(Path(__file__).parent))

def test_imports():
    """测试模块导入"""
    print("=" * 60)
    print("  1. 测试模块导入")
    print("=" * 60)

    try:
        from yime.input_method import InputMethodApp
        print("✓ InputMethodApp 导入成功")
    except Exception as e:
        print(f"✗ InputMethodApp 导入失败: {e}")
        return False

    try:
        from yime.input_method.core.keyboard_listener import KeyboardListener
        print("✓ KeyboardListener 导入成功")
    except Exception as e:
        print(f"✗ KeyboardListener 导入失败: {e}")
        return False

    try:
        from yime.input_method.core.input_manager import InputManager
        print("✓ InputManager 导入成功")
    except Exception as e:
        print(f"✗ InputManager 导入失败: {e}")
        return False

    try:
        from yime.input_method.core.decoders import CompositeCandidateDecoder
        print("✓ CompositeCandidateDecoder 导入成功")
    except Exception as e:
        print(f"✗ CompositeCandidateDecoder 导入失败: {e}")
        return False

    return True


def test_pynput():
    """测试pynput"""
    print("\n" + "=" * 60)
    print("  2. 测试pynput")
    print("=" * 60)

    try:
        import pynput
        print("✓ pynput 已安装")

        from pynput import keyboard
        print("✓ keyboard 模块可用")

        # 测试创建监听器
        def on_press(key):
            pass

        listener = keyboard.Listener(on_press=on_press)
        print("✓ Listener 创建成功")

        return True
    except Exception as e:
        print(f"✗ pynput 测试失败: {e}")
        return False


def test_decoder():
    """测试解码器"""
    print("\n" + "=" * 60)
    print("  3. 测试解码器")
    print("=" * 60)

    try:
        from yime.input_method.core.decoders import CompositeCandidateDecoder
        from pathlib import Path

        app_dir = Path(__file__).parent / "yime"
        decoder = CompositeCandidateDecoder(app_dir)
        print("✓ 解码器创建成功")

        # 测试解码
        test_input = "test"
        result = decoder.decode_text(test_input)
        print(f"✓ 解码测试成功: {result[4]}")

        return True
    except Exception as e:
        print(f"✗ 解码器测试失败: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_keyboard_installation():
    """测试键盘安装状态"""
    print("\n" + "=" * 60)
    print("  4. 测试键盘安装状态")
    print("=" * 60)

    import winreg
    import os

    try:
        # 检查注册表
        layouts_root = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r'SYSTEM\CurrentControlSet\Control\Keyboard Layouts',
            0,
            winreg.KEY_READ
        )

        found = False
        i = 0
        while True:
            try:
                klid = winreg.EnumKey(layouts_root, i)
                klid_key = winreg.OpenKey(layouts_root, klid)

                try:
                    layout_text, _ = winreg.QueryValueEx(klid_key, 'Layout Text')
                    layout_file, _ = winreg.QueryValueEx(klid_key, 'Layout File')

                    if 'Yinyuan' in str(layout_text) or 'Yinyuan.dll' in str(layout_file):
                        print(f"✓ 找到音元键盘:")
                        print(f"  KLID: {klid}")
                        print(f"  Layout Text: {layout_text}")
                        print(f"  Layout File: {layout_file}")
                        found = True
                except:
                    pass

                winreg.CloseKey(klid_key)
                i += 1
            except OSError:
                break

        winreg.CloseKey(layouts_root)

        if not found:
            print("✗ 注册表中未找到音元键盘")
            return False

        # 检查DLL
        dll_path = os.path.join(os.environ['SystemRoot'], 'System32', 'Yinyuan.dll')
        if os.path.exists(dll_path):
            print(f"✓ DLL文件存在: {dll_path}")
        else:
            print(f"✗ DLL文件不存在: {dll_path}")
            return False

        return True
    except Exception as e:
        print(f"✗ 键盘安装检查失败: {e}")
        return False


def test_input_manager():
    """测试输入管理器"""
    print("\n" + "=" * 60)
    print("  5. 测试输入管理器")
    print("=" * 60)

    try:
        from yime.input_method.core.input_manager import InputManager

        # 创建回调函数
        def on_candidates_update(candidates, pinyin, code, status):
            print(f"  候选词更新: {len(candidates)} 个")

        def on_input_commit(hanzi):
            print(f"  输入提交: {hanzi}")

        # 创建输入管理器
        manager = InputManager(
            on_candidates_update=on_candidates_update,
            on_input_commit=on_input_commit,
        )
        print("✓ 输入管理器创建成功")

        # 测试按键处理
        key_info = {'key': 'a', 'ascii': ord('a'), 'time': 0}
        result = manager.process_key(key_info)
        print(f"✓ 按键处理测试: buffer={manager.get_buffer()}")

        return True
    except Exception as e:
        print(f"✗ 输入管理器测试失败: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """主测试函数"""
    print("\n" + "=" * 60)
    print("  音元输入法后台测试")
    print("=" * 60)
    print()

    results = []

    # 测试1：模块导入
    results.append(("模块导入", test_imports()))

    # 测试2：pynput
    results.append(("pynput", test_pynput()))

    # 测试3：解码器
    results.append(("解码器", test_decoder()))

    # 测试4：键盘安装
    results.append(("键盘安装", test_keyboard_installation()))

    # 测试5：输入管理器
    results.append(("输入管理器", test_input_manager()))

    # 总结
    print("\n" + "=" * 60)
    print("  测试总结")
    print("=" * 60)

    passed = 0
    failed = 0

    for name, result in results:
        status = "✓ 通过" if result else "✗ 失败"
        print(f"{name:20s} {status}")
        if result:
            passed += 1
        else:
            failed += 1

    print()
    print(f"总计: {passed} 通过, {failed} 失败")

    if failed == 0:
        print("\n✓ 所有测试通过！可以运行完整测试")
        print("\n运行命令: python test_keyboard_connection.py")
    else:
        print("\n✗ 有测试失败，需要先解决问题")
        print("\n建议:")
        print("1. 检查pynput是否安装: pip install pynput")
        print("2. 检查键盘是否安装: C:/dev/Yime-keyboard-layout/releases/msklc-package/install-amd64-manual.cmd")
        print("3. 检查数据文件是否存在")

    print("\n" + "=" * 60)


if __name__ == "__main__":
    main()
