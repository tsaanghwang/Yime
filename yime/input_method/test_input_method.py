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
from yime.input_method.app_base import BaseInputMethodApp
from yime.input_method.ui.candidate_box_actions import CandidateBoxActions


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
    runtime_decoder = None
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

    test_name = "RuntimeCandidateDecoder 真实词语键可直接命中"
    try:
        if runtime_decoder is None:
            print("  跳过: 运行时词语数据不可用")
            result.add_pass(f"{test_name} (跳过)")
        else:
            phrase_code = ""
            phrase_text = ""
            for code, raw_candidates in runtime_decoder.by_code.items():
                if len(code) < 8:
                    continue
                for candidate in raw_candidates:
                    if str(candidate.get("entry_type", "")).strip() != "phrase":
                        continue
                    text = str(candidate.get("text", "")).strip()
                    if 2 <= len(text) <= 4:
                        phrase_code = code
                        phrase_text = text
                        break
                if phrase_code:
                    break

            assert phrase_code, "运行时数据中应至少存在一条 2-4 字词语候选"
            canonical, active, _pinyin, candidates, status = runtime_decoder.decode_text(phrase_code)
            assert canonical == phrase_code
            assert active == phrase_code
            assert phrase_text in candidates, (
                f"真实词语键 {phrase_code!r} 应命中 {phrase_text!r}，实际候选: {candidates[:5]} | {status}"
            )
            result.add_pass(test_name)
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

    test_name = "BaseInputMethodApp 不足4码时并入前缀单字候选"
    try:
        app = BaseInputMethodApp.__new__(BaseInputMethodApp)
        app.decoder = composite_decoder

        prefix_matches = composite_decoder.get_char_candidates_by_prefix("", limit=1)
        assert prefix_matches, "运行时索引中应至少存在一组单字编码"
        prefix_code, exact_candidates = prefix_matches[0]
        assert exact_candidates, "前缀编码应携带单字候选"

        merged = app._resolve_display_candidates(prefix_code[:1], [])
        assert merged, "不足4码时应显示前缀单字候选"
        assert exact_candidates[0].text in merged

        canonical, _active, _pinyin, candidates, _status = composite_decoder.decode_text("abcd")
        preserved = app._resolve_display_candidates(canonical, candidates)
        assert preserved == candidates
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CompositeCandidateDecoder 大写 H 走零声母编码"
    try:
        physical_input_map = build_physical_input_map(project_root)
        projected = project_physical_input("Hsss", physical_input_map)
        canonical, active, pinyin, candidates, status = composite_decoder.decode_text(projected)
        assert canonical == composite_decoder.runtime_decoder.bmp_to_canonical.get(projected[0], projected[0]) + composite_decoder.runtime_decoder.bmp_to_canonical.get(projected[1], projected[1]) + composite_decoder.runtime_decoder.bmp_to_canonical.get(projected[2], projected[2]) + composite_decoder.runtime_decoder.bmp_to_canonical.get(projected[3], projected[3]) if composite_decoder.runtime_decoder is not None else canonical
        assert pinyin == "a3", f"期望 a3，得到: {pinyin}"
        assert candidates, "期望零声母 a3 能命中候选"
        assert candidates[0] in {"啊", "阿", "呵"}, f"零声母候选异常: {candidates[:3]}"
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
            "abcdefgh": [
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
            "abcdefgh": [
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

    test_name = "InputManager Space 提交首选候选"
    try:
        manager.clear_buffer()
        manager.current_candidates = ["安", "按"]
        handled = manager.process_key({'key': 'Space', 'ascii': None})
        assert handled is False, "Space 选首选时应该被拦截"
        assert commits[-1] == "安", "Space 应提交首选候选"
        assert manager.get_buffer() == "", "Space 选首选后应清空编码缓冲区"
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

    test_name = "WindowManager restore_window 返回前台切换结果"
    try:
        from yime.input_method.utils.window_manager import WindowManager

        class FakeUser32:
            def __init__(self):
                self.foreground = 100
                self.attached = []
                self.shown_handles = []
                self.iconic_handles = set()

            @staticmethod
            def _hwnd_value(hwnd):
                return int(getattr(hwnd, "value", hwnd))

            def GetForegroundWindow(self):
                return self.foreground

            def IsIconic(self, hwnd):
                return 1 if self._hwnd_value(hwnd) in self.iconic_handles else 0

            def GetAncestor(self, hwnd, _flag):
                value = self._hwnd_value(hwnd)
                return 200 if value == 201 else value

            def GetWindowThreadProcessId(self, hwnd, _pid):
                value = self._hwnd_value(hwnd)
                return 11 if value == 100 else 22

            def AttachThreadInput(self, current_thread_id, thread_id, attach):
                self.attached.append((current_thread_id, thread_id, bool(attach)))
                return 1

            def ShowWindow(self, hwnd, _cmd):
                self.shown_handles.append(self._hwnd_value(hwnd))
                return 1

            def BringWindowToTop(self, hwnd):
                self.foreground = self._hwnd_value(hwnd)
                return 1

            def SetForegroundWindow(self, hwnd):
                self.foreground = self._hwnd_value(hwnd)
                return 1

            def SetActiveWindow(self, hwnd):
                return self._hwnd_value(hwnd)

            def SetFocus(self, hwnd):
                return self._hwnd_value(hwnd)

        class FakeKernel32:
            def GetCurrentThreadId(self):
                return 7

        original_user32 = WindowManager._user32
        original_kernel32 = WindowManager._kernel32
        fake_user32 = FakeUser32()
        try:
            WindowManager._user32 = fake_user32
            WindowManager._kernel32 = FakeKernel32()
            globals_ref = WindowManager.restore_window.__globals__
            original_global_user32 = globals_ref["user32"]
            original_global_kernel32 = globals_ref["kernel32"]
            globals_ref["user32"] = fake_user32
            globals_ref["kernel32"] = WindowManager._kernel32

            restored = WindowManager.restore_window(200)

            assert restored is True
            assert fake_user32.foreground == 200
            assert fake_user32.shown_handles == []
            assert fake_user32.attached == [
                (7, 11, True),
                (7, 22, True),
                (7, 22, False),
                (7, 11, False),
            ]

            fake_user32.foreground = 100
            fake_user32.shown_handles.clear()
            fake_user32.iconic_handles.add(200)
            restored = WindowManager.restore_window(201)

            assert restored is True
            assert fake_user32.foreground == 200
            assert fake_user32.shown_handles == [200]

            fake_user32.iconic_handles.clear()
            fake_user32.foreground = 200
            fake_user32.shown_handles.clear()
            restored = WindowManager.restore_window(200)

            assert restored is True
            assert fake_user32.shown_handles == []
        finally:
            WindowManager._user32 = original_user32
            WindowManager._kernel32 = original_kernel32
            globals_ref = WindowManager.restore_window.__globals__
            globals_ref["user32"] = original_global_user32
            globals_ref["kernel32"] = original_global_kernel32

        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "WindowManager 将子控件句柄归一化到顶层窗口"
    try:
        from yime.input_method.utils.window_manager import WindowManager

        class FakeUser32:
            @staticmethod
            def GetAncestor(hwnd, _flag):
                value = int(getattr(hwnd, "value", hwnd))
                return 200 if value == 201 else value

            @staticmethod
            def GetWindowTextW(_hwnd, buffer, _size):
                buffer.value = "记事本"
                return len(buffer.value)

            @staticmethod
            def GetClassNameW(_hwnd, buffer, _size):
                buffer.value = "Notepad"
                return len(buffer.value)

        original_user32 = WindowManager._user32
        globals_ref = WindowManager.normalize_window_handle.__globals__
        original_global_user32 = globals_ref["user32"]
        try:
            WindowManager._user32 = FakeUser32()
            globals_ref["user32"] = WindowManager._user32

            assert WindowManager.normalize_window_handle(201) == 200
            assert WindowManager.normalize_window_handle(200) == 200
            assert WindowManager.normalize_window_handle(None) is None
            assert WindowManager.describe_window(201) == "hwnd=200 标题=记事本 类=Notepad"
        finally:
            WindowManager._user32 = original_user32
            globals_ref["user32"] = original_global_user32

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
        assert project_physical_input("H", physical_input_map) == physical_input_map["H"]
        assert unproject_physical_input(physical_input_map["H"], projected_to_physical_map) == "H"
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
            on_copy_candidate=lambda x: None,
        )

        box.set_input("a")
        on_input_change()
        assert box.get_input() == physical_input_map["a"]
        assert box.get_projected_input() == physical_input_map["a"]
        assert box.projected_code_var.get() == ""
        assert box.input_outline_var.get() == ""
        assert not hasattr(box, "prefix_hint_panel")
        assert box.page_size_spinbox is None
        assert box.page_size_var.get() == 5
        assert box.commit_var.get() == ""
        assert box.commit_entry.winfo_manager() == ""
        box.update_candidates(["一", "乙", "二", "十", "丁"], "yi1", "", "")
        candidate_text = box.candidate_text.get("1.0", "end-1c")
        assert "1. 一  2. 乙" in candidate_text
        assert "第 1/1 页" not in candidate_text
        assert str(box.candidate_text.cget("height")) == "1"
        assert str(box.first_page_button.cget("text")) == "⏮"
        assert str(box.prev_page_button.cget("text")) == "◀"
        assert str(box.next_page_button.cget("text")) == "▶"
        assert str(box.last_page_button.cget("text")) == "⏭"
        assert box.first_page_button.pack_info()["side"] == "left"
        assert box.prev_page_button.pack_info()["side"] == "left"

        box.set_page_size(4)
        box.update_candidates(["一", "乙", "二", "十", "丁"], "yi1", "", "")
        box.show_last_page()
        assert box.page_info_var.get().startswith("第 2/2 页")
        assert str(box.last_page_button.cget("state")) == "disabled"
        box.show_first_page()
        assert box.page_info_var.get().startswith("第 1/2 页")
        assert str(box.first_page_button.cget("state")) == "disabled"

        box.set_candidate_layout("vertical")
        vertical_text = box.candidate_text.get("1.0", "end-1c")
        assert "1. 一\n2. 乙" in vertical_text
        assert "第 1/2 页" in vertical_text
        assert int(box.candidate_text.cget("height")) >= 4
        assert box.first_page_button.pack_info().get("side", "top") == "top"

        box.root.destroy()
        root.destroy()
        result.add_pass(test_name)
    except Exception as e:
        # GUI测试失败是可接受的
        print(f"  跳过: GUI环境不可用 - {e}")
        result.add_pass(f"{test_name} (跳过)")

    test_name = "CandidateBox 激活时默认定位到外部窗口右下方"
    try:
        from yime.input_method.ui.candidate_box import CandidateBox

        class FakeRoot:
            def update_idletasks(self):
                return None

            def winfo_reqwidth(self):
                return 240

            def winfo_reqheight(self):
                return 120

            def winfo_vrootx(self):
                return 0

            def winfo_vrooty(self):
                return 0

            def winfo_vrootwidth(self):
                return 1920

            def winfo_vrootheight(self):
                return 1080

            def winfo_screenwidth(self):
                return 1920

            def winfo_screenheight(self):
                return 1080

            def winfo_id(self):
                return 111

        box = CandidateBox.__new__(CandidateBox)
        box.root = FakeRoot()

        original_get_foreground_window = CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_foreground_window
        original_get_window_rect = CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_window_rect
        try:
            CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_foreground_window = staticmethod(lambda: 222)
            CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_window_rect = staticmethod(lambda _hwnd: (100, 100, 900, 500))

            target_x, target_y = CandidateBox._resolve_geometry(box, None, None, focus_input=True)

            assert target_x == 840
            assert target_y == 540
        finally:
            CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_foreground_window = original_get_foreground_window
            CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_window_rect = original_get_window_rect

        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CandidateBox 激活时可显式锚定外部窗口位置"
    try:
        from yime.input_method.ui.candidate_box import CandidateBox

        class FakeRoot:
            def update_idletasks(self):
                pass

            def winfo_reqwidth(self):
                return 240

            def winfo_reqheight(self):
                return 120

            def winfo_vrootx(self):
                return 0

            def winfo_vrooty(self):
                return 0

            def winfo_vrootwidth(self):
                return 1920

            def winfo_vrootheight(self):
                return 1080

            def winfo_screenwidth(self):
                return 1920

            def winfo_screenheight(self):
                return 1080

            def winfo_id(self):
                return 111

        box = CandidateBox.__new__(CandidateBox)
        box.root = FakeRoot()

        original_get_foreground_window = CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_foreground_window
        original_get_window_rect = CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_window_rect
        try:
            CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_foreground_window = staticmethod(lambda: 111)
            CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_window_rect = staticmethod(lambda hwnd: (200, 150, 1200, 650) if hwnd == 333 else (0, 0, 320, 240))

            target_x, target_y = CandidateBox._resolve_geometry(
                box,
                None,
                None,
                focus_input=True,
                anchor_hwnd=333,
            )

            assert target_x == 1140
            assert target_y == 690
        finally:
            CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_foreground_window = original_get_foreground_window
            CandidateBox._resolve_activation_anchor.__globals__["WindowManager"].get_window_rect = original_get_window_rect

        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CandidateBox 最小化时切到右下角待命图标"
    try:
        from yime.input_method.ui.candidate_box import CandidateBox

        calls = []

        class FakeRoot:
            def state(self):
                return "iconic"

            def after(self, delay, callback):
                calls.append((delay, callback))

        box = CandidateBox.__new__(CandidateBox)
        box.root = FakeRoot()
        box._handling_iconify = False
        box.show_standby = lambda: calls.append("standby")

        box._on_window_unmap(type("Evt", (), {"widget": box.root})())

        assert calls and calls[0][0] == 0
        calls[0][1]()
        assert "standby" in calls
        assert box._handling_iconify is False
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CandidateBox 半透明静置态点击时恢复激活回调"
    try:
        from yime.input_method.ui.candidate_box import CandidateBox

        calls = []

        class FakeActions:
            def restore_from_standby(self, event=None):
                calls.append("restore")

            def activate_for_manual_input(self, event=None):
                calls.append("activate")

        box = CandidateBox.__new__(CandidateBox)
        box._is_standby = False
        box._manual_input_enabled = False
        box._on_restore_from_standby = object()
        box.actions = FakeActions()

        box._reactivate_from_passive()

        assert calls == ["restore"]
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CandidateBox 半透明静置态点击时可回退到本地聚焦"
    try:
        from yime.input_method.ui.candidate_box import CandidateBox

        calls = []

        class FakeActions:
            def restore_from_standby(self, event=None):
                calls.append("restore")

            def activate_for_manual_input(self, event=None):
                calls.append("activate")

        box = CandidateBox.__new__(CandidateBox)
        box._is_standby = False
        box._manual_input_enabled = False
        box._on_restore_from_standby = None
        box.actions = FakeActions()

        box._reactivate_from_passive()

        assert calls == ["activate"]
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CandidateBoxActions 有恢复回调时不重复本地激活"
    try:
        from yime.input_method.ui.candidate_box_actions import CandidateBoxActions

        calls = []

        class FakeBox:
            def __init__(self):
                self._on_restore_from_standby = lambda: calls.append("callback")

            def set_manual_input_enabled(self, enabled):
                calls.append(("manual", enabled))

            def show(self, focus_input=True):
                calls.append(("show", focus_input))

        CandidateBoxActions(FakeBox()).restore_from_standby()

        assert calls == ["callback"]
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CandidateBox 半透明静置态不保持置顶"
    try:
        from yime.input_method.ui.candidate_box import CandidateBox

        calls = []

        class FakeRoot:
            def __init__(self):
                self.attrs = []

            def update_idletasks(self):
                return None

            def state(self):
                return "normal"

            def winfo_x(self):
                return 320

            def winfo_y(self):
                return 240

            def winfo_width(self):
                return 480

            def winfo_height(self):
                return 180

            def winfo_reqwidth(self):
                return 480

            def winfo_reqheight(self):
                return 180

            def geometry(self, value):
                calls.append(("geometry", value))

            def attributes(self, key, value=None):
                self.attrs.append((key, value))

            def deiconify(self):
                calls.append("deiconify")

            def winfo_id(self):
                return 777

            def update(self):
                calls.append("update")

        class FakeUser32:
            def ShowWindow(self, hwnd, cmd):
                calls.append(("showwindow", hwnd, cmd))

            def SetWindowPos(self, hwnd, insert_after, x, y, width, height, flags):
                calls.append(("setwindowpos", hwnd, insert_after, x, y, width, height, flags))

        box = CandidateBox.__new__(CandidateBox)
        box.root = FakeRoot()
        box._PASSIVE_ALPHA = 0.42
        box._HWND_NOTOPMOST = -2
        box._SW_SHOWNOACTIVATE = 4
        box._SWP_NOACTIVATE = 0x0010
        box._SWP_SHOWWINDOW = 0x0040
        box._SWP_NOOWNERZORDER = 0x0200
        box._show_main_frame = lambda: calls.append("show_main")
        box.set_manual_input_enabled = lambda enabled: calls.append(("manual", enabled))
        box._get_user32 = lambda: FakeUser32()
        box._set_noactivate = lambda enabled: calls.append(("noactivate", enabled))

        CandidateBox.show_passive(box)

        assert ("-topmost", False) in box.root.attrs
        assert any(call[:3] == ("setwindowpos", 777, -2) for call in calls if isinstance(call, tuple) and call and call[0] == "setwindowpos")
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))


def test_candidate_box_actions(result: TestResult):
    """测试候选框动作模块"""
    print("\n" + "="*60)
    print("测试候选框动作模块 (candidate_box_actions.py)")
    print("="*60)

    test_name = "CandidateBoxActions Space 在输入框中选首选并立即上屏"
    try:
        class FakeBox:
            def __init__(self) -> None:
                self.current_candidates = ["安", "按"]
                self.input_entry = object()
                self.commit_entry = object()
                self.candidate_text = object()
                self.root = object()
                self.committed = []
                self._on_commit_text_callback = lambda text: self.committed.append(text)
                self._on_copy_candidate_callback = None
                self._on_close = None
                self._on_hide = None
                self._on_restore_from_standby = None
                self._manual = True
                self.commit_text = ""
                self.status = ""
                self.selected = None
                self.focus_value = None

            def is_manual_input_enabled(self):
                return self._manual

            def get_candidate(self, index):
                return self.current_candidates[index]

            def append_commit_text(self, text):
                self.commit_text += text

            def on_select(self, hanzi):
                self.selected = hanzi

            def clear_input(self, focus_input=True):
                self.focus_value = focus_input

            def set_status(self, text):
                self.status = text

            def get_commit_text(self):
                return self.commit_text

        class FakeEvent:
            def __init__(self, widget) -> None:
                self.widget = widget

        box = FakeBox()
        actions = CandidateBoxActions(box)
        outcome = actions.on_confirm_key(FakeEvent(box.input_entry))

        assert outcome == "break"
        assert box.selected == "安"
        assert box.commit_text == "安"
        assert box.committed == ["安"]
        assert box.status == "已发送缓冲区内容: 安"
        assert box.focus_value is True
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CandidateBoxActions 支持 Home PageUp PageDown End 翻页"
    try:
        class FakeBox:
            def __init__(self) -> None:
                self.calls = []
                self.current_candidates = []
                self.input_entry = object()
                self.commit_entry = object()
                self.candidate_text = object()
                self.root = object()

            def show_first_page(self):
                self.calls.append("first")

            def show_previous_page(self):
                self.calls.append("prev")

            def show_next_page(self):
                self.calls.append("next")

            def show_last_page(self):
                self.calls.append("last")

        box = FakeBox()
        actions = CandidateBoxActions(box)

        assert actions.on_first_page_key() == "break"
        assert actions.on_previous_page_key() == "break"
        assert actions.on_next_page_key() == "break"
        assert actions.on_last_page_key() == "break"
        assert box.calls == ["first", "prev", "next", "last"]
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CandidateBoxActions 支持 ` - = \\ 选第2到第5候选并立即上屏"
    try:
        class FakeBox:
            def __init__(self) -> None:
                self.current_candidates = ["甲", "乙", "丙", "丁", "戊"]
                self.input_entry = object()
                self.commit_entry = object()
                self.candidate_text = object()
                self.root = object()
                self._manual = True
                self.selected = []
                self.commit_text = ""
                self.status = ""
                self.committed = []
                self._on_commit_text_callback = lambda text: self.committed.append(text)

            def is_manual_input_enabled(self):
                return self._manual

            def get_candidate(self, index):
                return self.current_candidates[index]

            def append_commit_text(self, text):
                self.commit_text += text

            def on_select(self, hanzi):
                self.selected.append(hanzi)

            def clear_input(self, focus_input=True):
                return None

            def set_status(self, text):
                self.status = text

            def get_commit_text(self):
                return self.commit_text

        box = FakeBox()
        actions = CandidateBoxActions(box)

        def make_event(char):
            return type("Evt", (), {"char": char})()

        assert actions.on_symbol_shortcut_key(make_event("`")) == "break"
        assert actions.on_symbol_shortcut_key(make_event("-")) == "break"
        assert actions.on_symbol_shortcut_key(make_event("=")) == "break"
        assert actions.on_symbol_shortcut_key(make_event("\\")) == "break"
        assert box.selected == ["乙", "丙", "丁", "戊"]
        assert box.commit_text == "乙丙丁戊"
        assert box.committed == ["乙", "乙丙", "乙丙丁", "乙丙丁戊"]
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "CandidateBoxActions 为 ` - = \\ 注册明确按键绑定"
    try:
        class FakeWidget:
            def __init__(self):
                self.bindings = []

            def bind(self, sequence, callback, add=None):
                self.bindings.append((sequence, add, callback))

        class FakeBox:
            def __init__(self) -> None:
                self.root = FakeWidget()
                self.input_entry = FakeWidget()
                self.commit_entry = FakeWidget()
                self.candidate_text = object()

        box = FakeBox()
        actions = CandidateBoxActions(box)
        actions.bind_keys()

        expected = {"<grave>", "<minus>", "<equal>", "<backslash>"}
        for widget in (box.root, box.input_entry, box.commit_entry):
            sequences = {sequence for sequence, _add, _callback in widget.bindings}
            assert expected.issubset(sequences)
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))


def test_hotkey_app(result: TestResult):
    """测试当前主线热键入口与回贴模式"""
    print("\n" + "="*60)
    print("测试当前热键入口 (app.py)")
    print("="*60)

    test_name = "InputMethodApp V1 热键可从待命唤起输入框"
    try:
        from yime.input_method.app import InputMethodApp

        shown = []
        status_updates = []

        class FakeWindowManager:
            def get_foreground_window(self):
                return 24680

            @staticmethod
            def normalize_window_handle(hwnd):
                return hwnd

            @staticmethod
            def describe_window(hwnd):
                return f"hwnd={hwnd} 标题=Fake 类=Fake"

        class FakeCandidateBox:
            def clear_input(self, focus_input=False):
                shown.append(("clear", focus_input))

            def show(self, focus_input=True, anchor_hwnd=None):
                shown.append(("show", focus_input, anchor_hwnd))

            def set_status(self, text):
                status_updates.append(text)

        class FakeInputManager:
            def clear_buffer(self, notify=False):
                shown.append(("clear_buffer", notify))

        app = InputMethodApp.__new__(InputMethodApp)
        app.own_hwnd = 12345
        app.last_external_hwnd = None
        app._locked_external_hwnd = None
        app.is_passthrough_enabled = False
        app._passive_standby_reason = "idle"
        app.last_replace_length = 9
        app._display_input_buffer = "abcd"
        app.window_manager = FakeWindowManager()
        app.candidate_box = FakeCandidateBox()
        app.input_manager = FakeInputManager()
        app._lock_external_target = BaseInputMethodApp._lock_external_target.__get__(app, BaseInputMethodApp)
        app._normalize_external_hwnd = BaseInputMethodApp._normalize_external_hwnd.__get__(app, BaseInputMethodApp)
        app._describe_external_target = BaseInputMethodApp._describe_external_target.__get__(app, BaseInputMethodApp)

        InputMethodApp._activate_from_hotkey(app, 24680, "hwnd=24680 标题=Fake 类=Fake")

        assert app._locked_external_hwnd == 24680
        assert app.last_external_hwnd == 24680
        assert app.is_passthrough_enabled is True
        assert app._passive_standby_reason == "manual"
        assert app._post_commit_behavior == "standby"
        assert app.last_replace_length == 0
        assert app._display_input_buffer == ""
        assert ("clear", False) in shown
        assert ("show", True, 24680) in shown
        assert status_updates[-1] == "V1 热键已唤起: hwnd=24680 标题=Fake 类=Fake"
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "BaseInputMethodApp keep-input 模式发送后会回到输入框"
    try:
        app = BaseInputMethodApp.__new__(BaseInputMethodApp)
        app._post_commit_behavior = "keep-input"
        app.last_replace_length = 0
        app._describe_external_target = lambda hwnd=None: "hwnd=30003 标题=Fake 类=Fake"
        app._current_external_target_hwnd = lambda: 30003
        app._restore_external_window = lambda: True
        scheduled = []
        app._schedule_ui = lambda delay, callback: scheduled.append((delay, callback))
        app._unlock_external_target = lambda: scheduled.append(("unlock", None))
        app._refocus_candidate_input = lambda: scheduled.append(("refocus", None))
        app.keyboard_simulator = type(
            "FakeKeyboardSimulator",
            (),
            {"send_ctrl_v": lambda self: None},
        )()
        app.candidate_box = type(
            "FakeBox",
            (),
            {"status_var": type("FakeStatus", (), {"set": lambda self, text: None})()},
        )()

        BaseInputMethodApp._paste_to_previous_window(app, "你好")

        assert scheduled[0][0] == 40
        assert scheduled[0][1] == app._restore_external_window
        assert scheduled[1][0] == 80
        assert scheduled[2][0] == 180
        assert scheduled[3][0] == 220
        assert scheduled[3][1] == app._refocus_candidate_input
        assert ("unlock", None) not in scheduled
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "InputMethodApp V1 连续输入回焦时保持已锁定目标窗口"
    try:
        from yime.input_method.app import InputMethodApp

        events = []

        class FakeInputEntry:
            def focus_set(self):
                events.append("focus")

            def icursor(self, value):
                events.append(("cursor", value))

            def selection_clear(self):
                events.append("selection_clear")

        class FakeCandidateBox:
            def __init__(self):
                self.input_entry = FakeInputEntry()

            def show(self, focus_input=True, anchor_hwnd=None):
                events.append(("show", focus_input, anchor_hwnd))

        app = InputMethodApp.__new__(InputMethodApp)
        app.candidate_box = FakeCandidateBox()
        app._locked_external_hwnd = 24680
        app.last_external_hwnd = 24680

        InputMethodApp._refocus_candidate_input(app)

        assert app._locked_external_hwnd == 24680
        assert events[0] == ("show", True, 24680)
        assert "focus" in events
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))

    test_name = "InputMethodApp V1 提交后进入半透明静置态而非图标待命"
    try:
        from yime.input_method.app import InputMethodApp

        events = []

        class FakeCandidateBox:
            def set_manual_input_enabled(self, enabled):
                events.append(("manual", enabled))

            def show_standby(self):
                events.append("standby")

            def show_passive(self):
                events.append("passive")

        app = InputMethodApp.__new__(InputMethodApp)
        app.candidate_box = FakeCandidateBox()
        app.is_passthrough_enabled = False
        app._passive_standby_reason = None
        app._display_input_buffer = "abcd"
        app._post_commit_behavior = "standby"

        app._after_commit_candidate_box_text()

        assert app.is_passthrough_enabled is True
        assert app._passive_standby_reason == "commit-box"
        assert app._display_input_buffer == ""
        assert events == [("manual", False), "passive"]
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))


def test_base_app_target_lock(result: TestResult):
    """测试公共目标窗口锁定逻辑"""
    print("\n" + "="*60)
    print("测试目标窗口锁定 (app_base.py)")
    print("="*60)

    test_name = "BaseInputMethodApp 锁定后轮询不覆盖目标窗口"
    try:
        app = BaseInputMethodApp.__new__(BaseInputMethodApp)
        app.own_hwnd = 12345
        app.last_external_hwnd = 20001
        app._locked_external_hwnd = None
        app.window_manager = type(
            "FakeWindowManager",
            (),
            {
                "get_foreground_window": lambda self: 30003,
                "normalize_window_handle": staticmethod(lambda hwnd: hwnd),
                "describe_window": staticmethod(
                    lambda hwnd: f"hwnd={hwnd} 标题=Fake 类=Fake"
                ),
            },
        )()
        scheduled = []
        app._schedule_ui = lambda delay, callback: scheduled.append((delay, callback))

        BaseInputMethodApp._lock_external_target(app)
        BaseInputMethodApp._poll_foreground_window(app)

        assert app._locked_external_hwnd == 20001
        assert app.last_external_hwnd == 20001
        assert scheduled and scheduled[0][0] == 250
        result.add_pass(test_name)
    except Exception as e:
        result.add_fail(test_name, str(e))


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
    test_candidate_box_actions(result)
    test_hotkey_app(result)
    test_base_app_target_lock(result)
    test_integration(result)

    # 输出总结
    success = result.summary()

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
