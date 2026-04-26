"""
音元输入法主应用

整合所有模块，提供完整的输入法功能
"""

from __future__ import annotations

import argparse
import ctypes
import os
import queue
import tkinter as tk
from pathlib import Path
from typing import Callable, Optional

from .core.decoders import (
    CompositeCandidateDecoder,
    build_code_display,
    build_input_outline,
    build_input_visual_map,
    build_physical_input_map,
    project_physical_input,
)
from .core.keyboard_listener import KeyboardListener
from .core.input_manager import InputManager
from .ui.candidate_box import CandidateBox
from .utils.clipboard import ClipboardManager
from .utils.keyboard_simulator import KeyboardSimulator
from .utils.window_manager import WindowManager


class InputMethodApp:
    """音元输入法主应用"""

    def __init__(
        self,
        auto_paste: bool = True,
        font_family: str = "音元",
    ) -> None:
        """
        初始化输入法应用

        Args:
            auto_paste: 是否自动粘贴到目标窗口
            font_family: 字体名称
        """
        self.auto_paste = auto_paste
        self.font_family = font_family
        self.debug_ui = os.environ.get("YIME_DEBUG_UI", "").strip().lower() in {
            "1",
            "true",
            "yes",
            "on",
        }

        # 初始化各模块
        app_dir = Path(__file__).resolve().parent.parent
        self.decoder = CompositeCandidateDecoder(app_dir)
        self.input_visual_map = build_input_visual_map(app_dir.parent)
        self.physical_input_map = build_physical_input_map(app_dir.parent)
        self.runtime_decoder_warning = self.decoder.get_runtime_warning()
        self.runtime_decoder_source = self.decoder.get_runtime_source()
        self.clipboard = ClipboardManager()
        self.keyboard_simulator = KeyboardSimulator()
        self.window_manager = WindowManager()

        # 创建候选框，显式注入回调
        self.candidate_box = CandidateBox(
            on_select=self._on_candidate_select,
            font_family=font_family,
            input_display_formatter=self._format_input_outline,
            on_input_change=self._on_input_change,
            on_decode_from_clipboard=self._decode_from_clipboard,
            on_copy_candidate=self._copy_candidate,
            on_commit_text=self._commit_candidate_box_text,
            on_hide=self._hide_candidate_box,
            on_close=self._close,
        )

        # 状态变量
        self.own_hwnd = self.candidate_box.root.winfo_id()
        self.last_external_hwnd: Optional[int] = None
        self.last_replace_length = 0
        self._display_input_buffer = ""
        self._is_closing = False
        self._after_ids: set[str] = set()
        self._ui_queue: queue.SimpleQueue[Callable[[], None]] = queue.SimpleQueue()

        # 创建输入管理器
        self.input_manager = InputManager(
            on_candidates_update=self._dispatch_candidates_update,
            on_input_commit=self._dispatch_input_commit,
        )
        self.input_manager.set_decoder(self.decoder)

        # 创建键盘监听器
        self.keyboard_listener: Optional[KeyboardListener] = None
        self.is_paused = False  # 是否处于系统输入法切换时的暂停测试模式
        self.is_paused = False  # 是否处于系统输入法切换时的暂停测试模式

        # 启动后默认显示待命图标
        self.candidate_box.show_standby()

        # 启动窗口焦点轮询
        self._poll_foreground_window()
        self._pump_ui_queue()

        # 设置关闭处理
        self.candidate_box.root.protocol("WM_DELETE_WINDOW", self._close)

        if self.runtime_decoder_source == "sqlite":
            print("[Decoder] 运行时候选已回退到 SQLite 数据库视图 runtime_candidates")
        elif self.runtime_decoder_source == "json":
            print("[Decoder] 运行时候选来源: JSON 导出文件")

        if self.runtime_decoder_warning:
            print(f"[Decoder] 运行时编码表未启用: {self.runtime_decoder_warning}")

    def _format_input_outline(self, text: str) -> str:
        return build_input_outline(text, self.input_visual_map)

    def _format_visible_input(self, text: str) -> str:
        if not text:
            return ""
        if all(ord(char) < 128 for char in text):
            return text
        return build_input_outline(text, self.input_visual_map)

    def _schedule_ui(self, delay_ms: int, callback: Callable[[], None]) -> Optional[str]:
        """通过统一入口调度 Tk 回调，便于关闭时统一取消。"""
        if self._is_closing:
            return None

        try:
            if not self.candidate_box.root.winfo_exists():
                return None
        except tk.TclError:
            return None

        after_id: Optional[str] = None

        def wrapped() -> None:
            if after_id is not None:
                self._after_ids.discard(after_id)
            if self._is_closing:
                return
            try:
                if self.candidate_box.root.winfo_exists():
                    callback()
            except tk.TclError:
                return

        after_id = self.candidate_box.root.after(delay_ms, wrapped)
        self._after_ids.add(after_id)
        return after_id

    def _cancel_scheduled_callbacks(self) -> None:
        """取消所有尚未执行的 Tk after 任务。"""
        for after_id in list(self._after_ids):
            try:
                self.candidate_box.root.after_cancel(after_id)
            except tk.TclError:
                pass
            finally:
                self._after_ids.discard(after_id)

    def _poll_foreground_window(self) -> None:
        """轮询前台窗口"""
        if self._is_closing:
            return
        foreground = self.window_manager.get_foreground_window()
        if foreground and foreground != self.own_hwnd:
            self.last_external_hwnd = foreground
        self._schedule_ui(250, self._poll_foreground_window)

    def _pump_ui_queue(self) -> None:
        """在 Tk 主线程中执行由后台线程提交的 UI 任务。"""
        if self._is_closing:
            return

        while True:
            try:
                callback = self._ui_queue.get_nowait()
            except queue.Empty:
                break

            try:
                callback()
            except tk.TclError:
                pass
            except Exception as exc:
                print(f"UI任务执行出错: {exc}")

        self._schedule_ui(16, self._pump_ui_queue)

    def _enqueue_ui(self, callback: Callable[[], None]) -> None:
        """允许任意线程提交 UI 更新，由主线程统一处理。"""
        if self._is_closing:
            return
        self._ui_queue.put(callback)

    def _on_input_change(self, event: Optional[object] = None) -> None:
        """输入变化处理"""
        display_input = self.candidate_box.get_input()
        projected_input = self.candidate_box.get_projected_input()
        if projected_input == display_input:
            projected_input = project_physical_input(display_input, self.physical_input_map)
            self.candidate_box.set_projected_input(projected_input)

        input_text = projected_input
        if not input_text:
            self.candidate_box.update_candidates(
                [],
                "",
                "",
                '连续输入时自动取最近 4 码。请先复制编码，再点"读取剪贴板"。',
            )
            return

        # 解码
        canonical_code, active_code, pinyin, candidates, status = (
            self.decoder.decode_text(input_text)
        )

        # 记录替换长度
        self.last_replace_length = min(4, len(input_text))

        # 更新显示
        code_display = build_code_display(input_text, canonical_code, active_code)

        self.candidate_box.update_candidates(
            candidates, pinyin, code_display, status
        )

    def _decode_from_clipboard(self) -> None:
        """从剪贴板读取并解码"""
        captured = self.clipboard.paste()
        if not captured:
            self.candidate_box.status_var.set("剪贴板没有可读取文本。")
            return

        self.candidate_box.set_input(
            self._format_visible_input(captured),
            projected_text=captured,
        )
        self.candidate_box.input_entry.focus_set()
        self._on_input_change()

    def _on_candidate_select(self, hanzi: str) -> None:
        """
        候选词选择处理

        Args:
            hanzi: 选中的汉字
        """
        # 复制到剪贴板
        self.clipboard.copy(hanzi)
        self.candidate_box.status_var.set(f"已复制: {hanzi}")

        # 手工候选框选字时先加入待上屏文本，不立刻回贴。
        self.candidate_box._clear_input(focus_input=True)

    def _copy_candidate(self, index: int) -> None:
        """
        复制候选词

        Args:
            index: 候选词索引
        """
        candidates = self.candidate_box.current_candidates
        if 0 <= index < len(candidates):
            hanzi = candidates[index]
            self.clipboard.copy(hanzi)
            self.candidate_box.status_var.set(f"已复制: {hanzi}")

    def _paste_to_previous_window(self, hanzi: str) -> None:
        """
        粘贴到上一个窗口

        Args:
            hanzi: 要粘贴的汉字
        """
        if not self.last_external_hwnd:
            self.candidate_box.status_var.set(
                f"已复制: {hanzi}，未找到上一个窗口"
            )
            return

        # 恢复目标窗口
        self.window_manager.restore_window(self.last_external_hwnd)

        # 如果需要替换已输入的码元
        if self.last_replace_length > 0:
            self._schedule_ui(
                80,
                lambda: self.keyboard_simulator.send_backspace(
                    self.last_replace_length
                ),
            )
            self._schedule_ui(170, self.keyboard_simulator.send_ctrl_v)
            self._schedule_ui(
                280,
                lambda: self.candidate_box.status_var.set(
                    f"已替换前一个窗口中的 {self.last_replace_length} 个编码字符: {hanzi}"
                ),
            )
            self._schedule_ui(360, self._refocus_candidate_input)
            return

        # 直接粘贴
        self._schedule_ui(80, self.keyboard_simulator.send_ctrl_v)
        self._schedule_ui(
            180,
            lambda: self.candidate_box.status_var.set(
                f"已回贴到前一个窗口: {hanzi}"
            ),
        )
        self._schedule_ui(240, self._refocus_candidate_input)

    def _refocus_candidate_input(self) -> None:
        """外部编辑动作完成后，将焦点拉回编码输入框。"""
        self.candidate_box.show(focus_input=True)
        self.candidate_box.input_entry.icursor(tk.END)
        self.candidate_box.input_entry.selection_clear()

    def _close(self) -> None:
        """关闭应用"""
        if self._is_closing:
            return

        target_hwnd = None
        if self.last_external_hwnd and self.last_external_hwnd != self.own_hwnd:
            target_hwnd = self.last_external_hwnd

        self._is_closing = True
        self._cancel_scheduled_callbacks()

        # 停止键盘监听
        if self.keyboard_listener:
            self.keyboard_listener.stop()

        self.candidate_box._close()

        if target_hwnd:
            try:
                self.window_manager.restore_window(target_hwnd)
            except Exception:
                pass

    def _hide_candidate_box(self) -> None:
        """将候选框缩到待命图标并清空当前组合，但保持全局监听继续运行。"""
        self.last_replace_length = 0
        self._display_input_buffer = ""
        self.input_manager.clear_buffer(notify=False)
        self.candidate_box._clear_input(focus_input=False)
        self.candidate_box.clear_commit_text()

        self.candidate_box.show_standby()

        if self.last_external_hwnd and self.last_external_hwnd != self.own_hwnd:
            try:
                self.window_manager.restore_window(self.last_external_hwnd)
            except Exception:
                pass

    def _dispatch_candidates_update(
        self,
        candidates: list,
        pinyin: str,
        code: str,
        status: str,
    ) -> None:
        """确保候选框更新在 Tk 主线程执行。"""
        self._enqueue_ui(
            lambda: self._on_candidates_update(candidates, pinyin, code, status)
        )

    def _dispatch_input_commit(self, hanzi: str) -> None:
        """确保提交逻辑在 Tk 主线程执行。"""
        self._enqueue_ui(lambda: self._on_input_commit(hanzi))

    def _on_candidates_update(
        self,
        candidates: list,
        pinyin: str,
        code: str,
        status: str,
    ) -> None:
        """
        候选词更新回调

        Args:
            candidates: 候选词列表
            pinyin: 拼音
            code: 编码
            status: 状态消息
        """
        buffer_text = self.input_manager.get_buffer()

        # 全局监听模式下，输入框显示物理键；投影行显示 PUA 编码字符。
        display_text = self._display_input_buffer if buffer_text else ""
        if (
            self.candidate_box.get_input() != display_text
            or self.candidate_box.get_projected_input() != buffer_text
        ):
            self.candidate_box.set_input(display_text, projected_text=buffer_text)

        # 更新候选框显示
        self.candidate_box.update_candidates(candidates, pinyin, code, status)

        # 只要仍在组合输入，就保持编辑框可见；候选为空也应允许继续编辑。
        if buffer_text:
            # 获取光标位置并显示
            try:
                x, y = self.candidate_box.get_pointer_position()
                if self.debug_ui:
                    print(
                        f"[UI] update buffer='{buffer_text}' candidates={len(candidates)} pos=({x},{y + 20}) status={status}"
                    )
                self.candidate_box.show(x, y + 20, focus_input=False)
            except Exception as exc:
                if self.debug_ui:
                    print(f"[UI] cursor position fallback: {exc}")
                try:
                    x, y = self.window_manager.get_cursor_position()
                    self.candidate_box.show(x, y + 20, focus_input=False)
                except Exception:
                    self.candidate_box.show(focus_input=False)
        else:
            if self.debug_ui:
                print("[UI] keep tracking candidate box even if buffer is empty for debugging")

            # 全局监听模式下清空缓冲区后也不能抢回 Entry 焦点，
            # 否则下一次按键会被误判为候选框手动输入。
            self.candidate_box.show(focus_input=False)

    def _on_input_commit(self, hanzi: str) -> None:
        """
        输入提交回调

        Args:
            hanzi: 要提交的汉字
        """
        # 复制到剪贴板
        self.clipboard.copy(hanzi)

        # 自动粘贴到目标窗口
        if (
            self.auto_paste
            and self.last_external_hwnd
            and self.last_external_hwnd != self.own_hwnd
        ):
            self._paste_to_previous_window(hanzi)

    def _commit_candidate_box_text(self, text: str) -> None:
        """将候选框里累积的汉字整段上屏到外部编辑区。"""
        self.clipboard.copy(text)

        if (
            self.last_external_hwnd
            and self.last_external_hwnd != self.own_hwnd
        ):
            self.last_replace_length = 0
            self._schedule_ui(50, lambda: self._paste_to_previous_window(text))

        self.candidate_box.clear_commit_text()
        self._display_input_buffer = ""
        self.candidate_box._clear_input(focus_input=False)

    def _on_key_press(self, key_info: dict) -> bool:
        """
        键盘按键回调

        Returns:
            True继续传递，False拦截
        """
        try:
            # === 测试模式切换逻辑 ===
            if key_info.get("char") == "t" and key_info.get("modifiers", {}).get("ctrl", False) and key_info.get("modifiers", {}).get("alt", False):
                self.is_paused = not self.is_paused
                self.input_manager.clear_buffer(notify=True)

                # 同步更新UI界面状态
                if self.is_paused:
                    self.candidate_box.show_standby()
                else:
                    # 如果要唤醒时直接展示主面板，可以调用 show()，或者先展示空内容的面板
                    self.candidate_box.show()

                print(f"[TEST MODE] Paused={self.is_paused}")
                return False  # 拦截切换快捷键

            if self.is_paused:
                return True
            # ========================

            if self.candidate_box.is_manual_input_active():
                return True

            buffer_was_empty = not bool(self.input_manager.get_buffer())

            # 让 InputManager 决定是否拦截
            projected_key_info = dict(key_info)
            raw_text = ""
            text = projected_key_info.get("text", "")
            if isinstance(text, str) and len(text) == 1 and text >= " ":
                raw_text = text
                projected_text = project_physical_input(text, self.physical_input_map)
                if projected_text != text:
                    projected_key_info["text"] = projected_text
                    projected_key_info["ascii"] = None

            handled = self.input_manager.process_key(projected_key_info)
            self._sync_display_input_buffer(projected_key_info, raw_text, handled)

            # 如果是从空缓存变为有缓存（开始输入），还原悬浮框大小
            if buffer_was_empty and self.input_manager.get_buffer() and not self.candidate_box.root.state() == "withdrawn":
                x, y = self.candidate_box.get_pointer_position()
                self._enqueue_ui(lambda: self.candidate_box.show(x, y + 20, focus_input=False))

            return handled
        except Exception as e:
            print(f"处理键盘事件出错: {e}")
        return True

    def _sync_display_input_buffer(
        self,
        key_info: dict,
        raw_text: str,
        handled: bool,
    ) -> None:
        """同步全局输入模式下输入框要显示的原始键盘字符。"""
        buffer_length = len(self.input_manager.get_buffer())
        if buffer_length == 0:
            self._display_input_buffer = ""
            return

        key = str(key_info.get("key", ""))
        if key in ("Backspace", "backspace") and handled is False:
            self._display_input_buffer = self._display_input_buffer[:-1]
        elif raw_text:
            self._display_input_buffer += raw_text

        if len(self._display_input_buffer) > buffer_length:
            self._display_input_buffer = self._display_input_buffer[-buffer_length:]
        elif len(self._display_input_buffer) < buffer_length:
            self._display_input_buffer = self.input_manager.get_buffer()

    def _process_key_in_main_thread(self, key_info: dict) -> None:
        """
        在主线程中处理键盘事件

        Args:
            key_info: 按键信息
        """
        try:
            self.input_manager.process_key(key_info)
        except Exception as e:
            print(f"处理键盘事件出错: {e}")

    def run(self) -> None:
        """运行应用"""
        # 启动键盘监听
        try:
            self.keyboard_listener = KeyboardListener(
                on_key_press=self._on_key_press,
            )
            self.keyboard_listener.start()
            if self.keyboard_listener.is_active():
                print("键盘监听已启动，按ESC退出")
            else:
                print("键盘监听未启用，将使用手动输入模式")
        except Exception as e:
            print(f"启动键盘监听失败: {e}")
            print("将使用手动输入模式")

        # 运行候选框
        self.candidate_box.run()


def parse_args() -> argparse.Namespace:
    """解析命令行参数"""
    parser = argparse.ArgumentParser(description="音元输入法 Windows 候选框")
    parser.add_argument(
        "--copy-only",
        action="store_true",
        help="只复制候选字到剪贴板，不自动回贴到上一个窗口。",
    )
    parser.add_argument(
        "--font-family",
        default="音元",
        help="输入框字体名。默认: 音元",
    )
    return parser.parse_args()


def main() -> None:
    """主函数"""
    if ctypes.sizeof(ctypes.c_void_p) == 0:
        raise SystemExit("Windows API 初始化失败")

    try:
        # 启用高 DPI 支持，解决 Tkinter 在高分屏下渲染模糊的问题
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        pass

    args = parse_args()
    app = InputMethodApp(auto_paste=not args.copy_only, font_family=args.font_family)
    app.run()


if __name__ == "__main__":
    main()
