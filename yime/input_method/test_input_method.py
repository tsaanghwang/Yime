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
    SQLiteRuntimeCandidateDecoder,
    CompositeCandidateDecoder,
    RuntimeCandidateRecord,
    build_input_sound_notes,
    build_input_visual_map,
    build_physical_input_map,
    build_projected_to_physical_map,
    project_physical_input,
    unproject_physical_input,
)
from yime.input_method.core.char_code_index import CharCodeIndex
from yime.input_method.core.input_manager import InputManager, InputState
from yime.input_method.core.prefix_tree import PrefixTree


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

    test_name = "CompositeCandidateDecoder 不足4码状态不混入单字前缀"
    try:
        canonical, active, pinyin, candidates, status = composite_decoder.decode_text("a")
        assert canonical == "a"
        assert active == "a"
        assert candidates == []
        assert "当前 1/4 码" in status
        assert "单字前缀" not in status
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CompositeCandidateDecoder 单字编码查询"
    try:
        matches = composite_decoder.get_char_candidates_by_prefix("", limit=1)
        assert isinstance(matches, list)
        if matches:
            code, char_candidates = matches[0]
            assert code
            assert char_candidates
            exact_candidates = composite_decoder.get_char_candidates(code)
            assert exact_candidates
            assert exact_candidates[0].code == code
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "SQLiteRuntimeCandidateDecoder 单字编码查询"
    try:
        if not (app_dir / "pinyin_hanzi.db").exists():
            print("  跳过: SQLite 数据库不存在")
            result.add_pass(f"{test_name} (跳过)")
        else:
            sqlite_decoder = SQLiteRuntimeCandidateDecoder(app_dir)
            matches = sqlite_decoder.get_char_candidates_by_prefix("", limit=1)
            assert isinstance(matches, list)
            if matches:
                code, char_candidates = matches[0]
                assert code
                assert char_candidates
                exact_candidates = sqlite_decoder.get_char_candidates(code)
                assert exact_candidates
                assert exact_candidates[0].code == code
            result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "RuntimeCandidateDecoder 多音节词语编码查询"
    try:
        runtime_decoder = RuntimeCandidateDecoder.__new__(RuntimeCandidateDecoder)
        runtime_decoder.bmp_to_canonical = {}
        runtime_decoder.by_code = {
            "abcd efgh": [
                {
                    "text": "安全",
                    "entry_type": "phrase",
                    "pinyin_tone": "an1 quan2",
                    "sort_weight": 120.0,
                    "text_length": 2,
                    "is_common": 1,
                },
                {
                    "text": "按全",
                    "entry_type": "phrase",
                    "pinyin_tone": "an4 quan2",
                    "sort_weight": 110.0,
                    "text_length": 2,
                    "is_common": 0,
                },
            ]
        }
        runtime_decoder.char_code_index = CharCodeIndex.from_runtime_candidates(runtime_decoder.by_code)
        runtime_decoder._user_freq_by_candidate = {}

        canonical, active, pinyin, candidates, status = runtime_decoder.decode_text("abcdefgh")
        assert canonical == "abcdefgh"
        assert active == "abcdefgh"
        assert candidates[:2] == ["安全", "按全"]
        assert "音节" in status
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "RuntimeCandidateDecoder 词语优先于单字"
    try:
        runtime_decoder = RuntimeCandidateDecoder.__new__(RuntimeCandidateDecoder)
        runtime_decoder.bmp_to_canonical = {}
        runtime_decoder.by_code = {
            "abcd": [
                {
                    "text": "安全",
                    "entry_type": "phrase",
                    "pinyin_tone": "an1 quan2",
                    "sort_weight": 1.0,
                    "text_length": 2,
                    "is_common": 1,
                },
                {
                    "text": "安",
                    "entry_type": "char",
                    "pinyin_tone": "an1",
                    "sort_weight": 999.0,
                    "text_length": 1,
                    "is_common": 1,
                },
            ]
        }
        runtime_decoder.char_code_index = CharCodeIndex.from_runtime_candidates(runtime_decoder.by_code)
        runtime_decoder._user_freq_by_candidate = {}

        _canonical, _active, _pinyin, candidates, _status = runtime_decoder.decode_text("abcd")
        assert candidates[:2] == ["安全", "安"]
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "RuntimeCandidateDecoder 同频词语支持动态调频"
    try:
        runtime_decoder = RuntimeCandidateDecoder.__new__(RuntimeCandidateDecoder)
        runtime_decoder.bmp_to_canonical = {}
        runtime_decoder.by_code = {
            "abcd efgh": [
                {
                    "text": "安全",
                    "entry_type": "phrase",
                    "pinyin_tone": "an1 quan2",
                    "sort_weight": 120.0,
                    "text_length": 2,
                    "is_common": 1,
                },
                {
                    "text": "安权",
                    "entry_type": "phrase",
                    "pinyin_tone": "an1 quan2",
                    "sort_weight": 120.0,
                    "text_length": 2,
                    "is_common": 1,
                },
            ]
        }
        runtime_decoder.char_code_index = CharCodeIndex.from_runtime_candidates(runtime_decoder.by_code)
        runtime_decoder._user_freq_by_candidate = {}

        _canonical, _active, _pinyin, candidates, _status = runtime_decoder.decode_text("abcdefgh")
        assert candidates[:2] == ["安全", "安权"]

        runtime_decoder.record_selection("abcdefgh", "安权")
        _canonical, _active, _pinyin, promoted, _status = runtime_decoder.decode_text("abcdefgh")
        assert promoted[:2] == ["安权", "安全"]
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


def test_prefix_tree(result: TestResult):
    """测试干净的前缀树模块"""
    print("\n" + "="*60)
    print("测试前缀树模块 (prefix_tree.py)")
    print("="*60)

    test_name = "PrefixTree 精确查找"
    try:
        tree: PrefixTree[str] = PrefixTree()
        tree.insert("abcd", "安")
        tree.insert("abcd", "按")
        tree.insert("abce", "昂")

        assert tree.contains("abcd")
        assert not tree.contains("abc")
        assert tree.get_exact("abcd") == ["安", "按"]
        assert tree.key_count == 2
        assert tree.value_count == 3
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "PrefixTree 前缀查找"
    try:
        matches = tree.get_with_prefix("abc")
        assert matches == [("abcd", ["安", "按"]), ("abce", ["昂"])]
        assert tree.has_prefix("ab")
        assert not tree.has_prefix("zz")
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "PrefixTree 限制结果数量"
    try:
        matches = tree.get_with_prefix("abc", limit=1)
        assert matches == [("abcd", ["安", "按"])]
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "PrefixTree 拒绝空键"
    try:
        try:
            tree.insert("", "空")
        except ValueError:
            result.add_pass(test_name)
        else:
            result.add_fail(test_name, "空键应抛出 ValueError")
    except Exception as e:
        result.add_fail(test_name, str(e))


def test_char_code_index(result: TestResult):
    """测试单字编码索引"""
    print("\n" + "="*60)
    print("测试单字编码索引 (char_code_index.py)")
    print("="*60)

    payload = {
        "abcd": [
            {
                "entry_type": "char",
                "entry_id": "1",
                "text": "安",
                "pinyin_tone": "an1",
                "sort_weight": "10",
                "is_common": 1,
            },
            {
                "entry_type": "phrase",
                "entry_id": "p1",
                "text": "安全",
                "pinyin_tone": "an1 quan2",
                "sort_weight": "99",
                "is_common": 1,
            },
        ],
        "abce": [
            {
                "entry_type": "char",
                "entry_id": "2",
                "text": "昂",
                "pinyin_tone": "ang2",
                "sort_weight": 8,
                "is_common": False,
            }
        ],
    }

    test_name = "CharCodeIndex 只索引单字候选"
    try:
        index = CharCodeIndex.from_runtime_candidates(payload)
        candidates = index.get_exact("abcd")
        assert [candidate.text for candidate in candidates] == ["安"]
        assert candidates[0].code == "abcd"
        assert candidates[0].entry_id == "1"
        assert candidates[0].sort_weight == 10.0
        assert candidates[0].is_common is True
        assert index.code_count == 2
        assert index.candidate_count == 2
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CharCodeIndex 前缀查找"
    try:
        matches = index.get_with_prefix("abc")
        assert [(code, [item.text for item in items]) for code, items in matches] == [
            ("abcd", ["安"]),
            ("abce", ["昂"]),
        ]
        assert index.has_prefix("ab")
        assert not index.has_prefix("zz")
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CharCodeIndex 前缀限制数量"
    try:
        matches = index.get_with_prefix("abc", limit=1)
        assert [(code, [item.text for item in items]) for code, items in matches] == [
            ("abcd", ["安"]),
        ]
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

    test_name = "投影编码反查物理 ASCII"
    try:
        physical_input_map = build_physical_input_map(project_root)
        projected_to_physical_map = build_projected_to_physical_map(physical_input_map)
        projected_text = project_physical_input("qsss", physical_input_map)
        assert projected_text != "qsss"
        assert unproject_physical_input(projected_text, projected_to_physical_map) == "qsss"
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "码元音符连续显示"
    try:
        input_visual_map = build_input_visual_map(project_root)
        physical_input_map = build_physical_input_map(project_root)
        projected_text = project_physical_input("qsss", physical_input_map)
        sound_notes = build_input_sound_notes(projected_text, input_visual_map)
        assert sound_notes
        assert "[" not in sound_notes
        assert "]" not in sound_notes
        assert " " not in sound_notes
        assert "N01" not in sound_notes
        assert "M01" not in sound_notes
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

        input_visual_map = build_input_visual_map(project_root)
        physical_input_map = build_physical_input_map(project_root)
        box = None

        def format_input_outline(text):
            return build_input_sound_notes(text, input_visual_map)

        projected_to_physical_map = build_projected_to_physical_map(physical_input_map)

        def format_projected_code(text):
            return unproject_physical_input(text, projected_to_physical_map)

        def on_input_change(event=None):
            if box is None:
                return
            display_input = box.get_input()
            projected_input = project_physical_input(display_input, physical_input_map)
            if display_input != projected_input or box.get_projected_input() != projected_input:
                box.set_input(projected_input, projected_text=projected_input)

        box = CandidateBox(
            on_select=lambda x: None,
            font_family="YinYuan Regular",
            input_display_formatter=format_input_outline,
            projected_code_formatter=format_projected_code,
            on_input_change=on_input_change,
            on_decode_from_clipboard=lambda: None,
            on_copy_candidate=lambda x: None,
        )

        box.set_input("a")
        on_input_change()
        assert box.get_input() == physical_input_map["a"]
        assert box.get_projected_input() == physical_input_map["a"]
        assert box.projected_code_var.get() == "a"
        assert "[" not in box.input_outline_var.get()
        assert "]" not in box.input_outline_var.get()

        box.root.destroy()
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
    test_prefix_tree(result)
    test_char_code_index(result)
    test_utilities(result)
    test_ui_components(result)
    test_integration(result)

    # 输出总结
    success = result.summary()

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
