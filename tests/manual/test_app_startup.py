"""
测试输入法应用启动和基本功能
"""

import sys
import time
from pathlib import Path

# 添加项目根目录到路径
project_root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(project_root))

def test_app_initialization():
    """测试应用初始化"""
    print("="*60)
    print("测试应用初始化")
    print("="*60)

    try:
        from yime.input_method import InputMethodApp
        print("[PASS] 导入 InputMethodApp")
    except Exception as e:
        print(f"[FAIL] 导入失败: {e}")
        return False

    try:
        # 创建应用实例（不启动GUI）
        app = InputMethodApp(auto_paste=False, font_family="Arial")
        print("[PASS] 创建应用实例")

        # 检查组件
        checks = [
            ("解码器", app.decoder is not None),
            ("剪贴板管理器", app.clipboard is not None),
            ("键盘模拟器", app.keyboard_simulator is not None),
            ("窗口管理器", app.window_manager is not None),
            ("候选框", app.candidate_box is not None),
            ("输入管理器", app.input_manager is not None),
        ]

        all_passed = True
        for name, check in checks:
            if check:
                print(f"[PASS] {name}已初始化")
            else:
                print(f"[FAIL] {name}未初始化")
                all_passed = False

        # 清理
        try:
            app.candidate_box.root.destroy()
            print("[PASS] 清理资源")
        except:
            pass

        return all_passed

    except Exception as e:
        print(f"[FAIL] 初始化失败: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_decoder_functionality():
    """测试解码器功能"""
    print("\n" + "="*60)
    print("测试解码器功能")
    print("="*60)

    try:
        from yime.input_method.core.decoders import CompositeCandidateDecoder

        app_dir = Path(__file__).resolve().parent / "yime"
        decoder = CompositeCandidateDecoder(app_dir)

        # 测试解码
        test_cases = [
            ("", "空输入"),
            ("a", "单字符"),
            ("abcd", "四字符"),
        ]

        for test_input, desc in test_cases:
            try:
                result = decoder.decode_text(test_input)
                print(f"[PASS] 解码测试: {desc}")
            except Exception as e:
                print(f"[FAIL] 解码测试 {desc}: {e}")
                return False

        return True

    except Exception as e:
        print(f"[FAIL] 解码器测试失败: {e}")
        return False


def test_input_manager():
    """测试输入管理器"""
    print("\n" + "="*60)
    print("测试输入管理器")
    print("="*60)

    try:
        from yime.input_method.core.input_manager import InputManager

        updates = []
        commits = []

        def on_update(*args):
            updates.append(args)

        def on_commit(*args):
            commits.append(args)

        manager = InputManager(
            on_candidates_update=on_update,
            on_input_commit=on_commit,
        )

        # 测试输入
        manager.add_char('a')
        if manager.get_buffer() == 'a':
            print("[PASS] 添加字符")
        else:
            print("[FAIL] 添加字符")
            return False

        # 测试退格
        manager.backspace()
        if manager.get_buffer() == '':
            print("[PASS] 退格")
        else:
            print("[FAIL] 退格")
            return False

        return True

    except Exception as e:
        print(f"[FAIL] 输入管理器测试失败: {e}")
        return False


def main():
    """运行所有测试"""
    print("开始测试输入法应用\n")

    results = []

    # 测试初始化
    results.append(("应用初始化", test_app_initialization()))

    # 测试解码器
    results.append(("解码器功能", test_decoder_functionality()))

    # 测试输入管理器
    results.append(("输入管理器", test_input_manager()))

    # 总结
    print("\n" + "="*60)
    print("测试总结")
    print("="*60)

    passed = sum(1 for _, r in results if r)
    total = len(results)

    for name, result in results:
        status = "[PASS]" if result else "[FAIL]"
        print(f"{status} {name}")

    print(f"\n通过: {passed}/{total}")

    if passed == total:
        print("\n所有测试通过！应用可以正常启动。")
        return 0
    else:
        print("\n部分测试失败，请检查错误信息。")
        return 1


if __name__ == "__main__":
    sys.exit(main())
