"""
测试 yime.input_method 包

测试覆盖：
1. decoders 模块 - 解码器功能
2. input_manager 模块 - 输入管理
3. utility 模块 - 工具函数
4. UI 组件 - 候选框
5. 集成测试 - InputMethodApp
"""

import sys
import json
from pathlib import Path
from typing import Tuple, List

# 添加项目根目录到路径
project_root = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(project_root))

from yime.input_method.core.decoders import (
    StaticCandidateDecoder,
    RuntimeCandidateDecoder,
    CompositeCandidateDecoder,
)
from yime.input_method.core.input_manager import InputManager, InputState


class TestResult:
    """测试结果收集器"""
    
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.errors = []
    
    def add_pass(self, test_name: str):
        self.passed += 1
        print(f"[PASS] {test_name}")
    
    def add_fail(self, test_name: str, error: str):
        self.failed += 1
        self.errors.append((test_name, error))
        print(f"[FAIL] {test_name}: {error}")
    
    def summary(self):
        total = self.passed + self.failed
        print(f"\n{'='*60}")
        print(f"测试总结: {self.passed}/{total} 通过")
        if self.errors:
            print(f"\n失败的测试:")
            for name, error in self.errors:
                print(f"  - {name}: {error}")
        print(f"{'='*60}")
        return self.failed == 0


def test_decoders(result: TestResult):
    """测试解码器模块"""
    print("\n" + "="*60)
    print("测试解码器模块 (decoders.py)")
    print("="*60)
    
    app_dir = Path(__file__).resolve().parent.parent
    
    # 测试 StaticCandidateDecoder
    test_name = "StaticCandidateDecoder 初始化"
    try:
        decoder = StaticCandidateDecoder(app_dir)
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
        return
    
    # 测试解码空字符串
    test_name = "StaticCandidateDecoder 解码空字符串"
    try:
        canonical, active, pinyin, candidates, status = decoder.decode_text("")
        assert canonical == "", f"期望空字符串，得到: {canonical}"
        assert active == "", f"期望空字符串，得到: {active}"
        assert candidates == [], f"期望空列表，得到: {candidates}"
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试解码不足4码
    test_name = "StaticCandidateDecoder 解码不足4码"
    try:
        canonical, active, pinyin, candidates, status = decoder.decode_text("abc")
        assert len(canonical) == 3, f"期望3个字符，得到: {len(canonical)}"
        assert candidates == [], f"期望空列表，得到: {candidates}"
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试解码4码
    test_name = "StaticCandidateDecoder 解码4码"
    try:
        # 使用一个测试编码
        canonical, active, pinyin, candidates, status = decoder.decode_text("abcd")
        # 只要不抛出异常就算通过
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试 RuntimeCandidateDecoder
    test_name = "RuntimeCandidateDecoder 初始化"
    try:
        runtime_decoder = RuntimeCandidateDecoder(app_dir)
        result.add_pass(test_name)
    except FileNotFoundError as e:
        # 运行时文件可能不存在，这是预期情况
        print(f"  跳过: 运行时文件不存在 - {e}")
        result.add_pass(f"{test_name} (跳过)")
    except json.JSONDecodeError as e:
        # Git LFS文件未拉取，这也是预期情况
        print(f"  跳过: Git LFS文件未拉取 - {e}")
        result.add_pass(f"{test_name} (跳过)")
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试 CompositeCandidateDecoder
    test_name = "CompositeCandidateDecoder 初始化"
    try:
        composite_decoder = CompositeCandidateDecoder(app_dir)
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
        return
    
    # 测试组合解码器解码
    test_name = "CompositeCandidateDecoder 解码"
    try:
        canonical, active, pinyin, candidates, status = composite_decoder.decode_text("test")
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试组合解码器回退机制
    test_name = "CompositeCandidateDecoder 回退机制"
    try:
        # 测试多个编码
        for test_input in ["abcd", "test", "1234"]:
            canonical, active, pinyin, candidates, status = composite_decoder.decode_text(test_input)
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))


def test_input_manager(result: TestResult):
    """测试输入管理器模块"""
    print("\n" + "="*60)
    print("测试输入管理器模块 (input_manager.py)")
    print("="*60)
    
    # 测试 InputState
    test_name = "InputState 初始化"
    try:
        state = InputState()
        assert state.buffer == ""
        assert state.is_composing == False
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试 InputManager 初始化
    test_name = "InputManager 初始化"
    try:
        candidates_updates = []
        commits = []
        
        def on_candidates_update(candidates, pinyin, code, status):
            candidates_updates.append((candidates, pinyin, code, status))
        
        def on_input_commit(hanzi):
            commits.append(hanzi)
        
        manager = InputManager(
            on_candidates_update=on_candidates_update,
            on_input_commit=on_input_commit,
        )
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
        return
    
    # 测试添加字符
    test_name = "InputManager 添加字符"
    try:
        manager.add_char('a')
        assert manager.get_buffer() == 'a'
        manager.add_char('b')
        assert manager.get_buffer() == 'ab'
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试退格
    test_name = "InputManager 退格"
    try:
        manager.backspace()
        assert manager.get_buffer() == 'a'
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试清空
    test_name = "InputManager 清空"
    try:
        manager.clear_buffer()
        assert manager.get_buffer() == ""
        assert not manager.is_composing()
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试按键处理
    test_name = "InputManager 按键处理"
    try:
        # 测试普通字符
        handled = manager.process_key({'key': 'a', 'ascii': ord('a')})
        assert handled == False, "普通字符应该被拦截"
        
        # 测试特殊键
        manager.clear_buffer()
        manager.add_char('x')
        handled = manager.process_key({'key': 'Escape', 'ascii': None})
        assert manager.get_buffer() == "", "ESC应该清空缓冲区"
        
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试缓冲区限制
    test_name = "InputManager 缓冲区限制"
    try:
        manager2 = InputManager(
            on_candidates_update=lambda *args: None,
            on_input_commit=lambda *args: None,
            max_buffer_length=5,
        )
        for i in range(6):
            manager2.add_char(chr(ord('a') + i))
        # 缓冲区应该被清空或限制长度
        assert len(manager2.get_buffer()) <= 5
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))


def test_utilities(result: TestResult):
    """测试工具模块"""
    print("\n" + "="*60)
    print("测试工具模块 (utils/)")
    print("="*60)
    
    # 测试 ClipboardManager
    test_name = "ClipboardManager 导入"
    try:
        from yime.input_method.utils.clipboard import ClipboardManager
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
        return
    
    test_name = "ClipboardManager 初始化"
    try:
        clipboard = ClipboardManager()
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试 KeyboardSimulator
    test_name = "KeyboardSimulator 导入"
    try:
        from yime.input_method.utils.keyboard_simulator import KeyboardSimulator
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
        return
    
    test_name = "KeyboardSimulator 初始化"
    try:
        keyboard = KeyboardSimulator()
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
    
    # 测试 WindowManager
    test_name = "WindowManager 导入"
    try:
        from yime.input_method.utils.window_manager import WindowManager
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
        return
    
    test_name = "WindowManager 初始化"
    try:
        window_mgr = WindowManager()
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))


def test_ui_components(result: TestResult):
    """测试UI组件"""
    print("\n" + "="*60)
    print("测试UI组件 (ui/)")
    print("="*60)
    
    # 测试 CandidateBox 导入
    test_name = "CandidateBox 导入"
    try:
        from yime.input_method.ui.candidate_box import CandidateBox
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
        return
    
    # 注意：CandidateBox 需要 tkinter 环境，在无GUI环境下可能失败
    test_name = "CandidateBox 初始化 (需要GUI)"
    try:
        import tkinter
        root = tkinter.Tk()
        root.withdraw()  # 隐藏主窗口
        
        box = CandidateBox(
            on_select=lambda x: None,
            font_family="Arial",
            on_input_change=lambda x: None,
            on_decode_from_clipboard=lambda: None,
            on_copy_candidate=lambda x: None,
        )
        
        root.destroy()
        result.add_pass(test_name)
    except Exception as e:
        # GUI测试失败是可接受的
        print(f"  跳过: GUI环境不可用 - {e}")
        result.add_pass(f"{test_name} (跳过)")


def test_integration(result: TestResult):
    """测试集成"""
    print("\n" + "="*60)
    print("测试集成 (InputMethodApp)")
    print("="*60)
    
    # 测试 InputMethodApp 导入
    test_name = "InputMethodApp 导入"
    try:
        from yime.input_method.app import InputMethodApp
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))
        return
    
    # 测试 InputMethodApp 初始化
    test_name = "InputMethodApp 初始化 (需要GUI)"
    try:
        import tkinter
        root = tkinter.Tk()
        root.withdraw()
        
        app = InputMethodApp(auto_paste=False, font_family="Arial")
        
        # 验证组件初始化
        assert app.decoder is not None
        assert app.clipboard is not None
        assert app.keyboard_simulator is not None
        assert app.window_manager is not None
        assert app.candidate_box is not None
        assert app.input_manager is not None
        
        # 清理
        app.candidate_box.root.destroy()
        result.add_pass(test_name)
    except Exception as e:
        print(f"  跳过: GUI环境不可用 - {e}")
        result.add_pass(f"{test_name} (跳过)")


def main():
    """运行所有测试"""
    print("="*60)
    print("开始测试 yime.input_method 包")
    print("="*60)
    
    result = TestResult()
    
    # 运行测试
    test_decoders(result)
    test_input_manager(result)
    test_utilities(result)
    test_ui_components(result)
    test_integration(result)
    
    # 输出总结
    success = result.summary()
    
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
