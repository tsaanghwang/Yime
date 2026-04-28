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
from typing import Any, Callable, Optional, cast

from .app_base import BaseInputMethodApp
from .core.decoders import project_physical_input
from .core.keyboard_listener import KeyboardListener
from .core.input_manager import InputManager
from .ui.candidate_box import CandidateBox


class InputMethodApp(BaseInputMethodApp):
    """音元输入法主应用"""

    def __init__(
        self,
        auto_paste: bool = True,
        font_family: str = "音元",
        enable_pause_toggle: bool = False,
        hotkey: str = "<ctrl>+<shift>+y",
    ) -> None:
        """
        初始化输入法应用

        Args:
            auto_paste: 是否自动粘贴到目标窗口
            font_family: 字体名称
            enable_pause_toggle: 是否启用 Ctrl+Alt+T 暂停/恢复全局监听
            hotkey: 从待命状态唤起编码框的全局快捷键
        """
        self.auto_paste = auto_paste
        self.font_family = font_family
        self.enable_pause_toggle = enable_pause_toggle
        self.hotkey = hotkey
        self.debug_ui = os.environ.get("YIME_DEBUG_UI", "").strip().lower() in {
            "1",
            "true",
            "yes",
            "on",
        }

        super().__init__(
            auto_paste=auto_paste,
            font_family=font_family,
        )

        self.last_external_layout: Optional[int] = None
        self._display_input_buffer = ""
        self._passive_standby_reason: Optional[str] = None
        self._is_closing = False
        self._after_ids: set[str] = set()
        self._ui_queue: queue.SimpleQueue[Callable[[], None]] = queue.SimpleQueue()

        self.input_manager = InputManager(
            on_candidates_update=self._dispatch_candidates_update,
            on_input_commit=self._dispatch_input_commit,
        )
        self.input_manager.set_decoder(self.decoder)

        self.keyboard_listener: Optional[KeyboardListener] = None
        self.hotkey_listener = None
        self.is_passthrough_enabled = True
        self._hotkey_mode = "unknown"

        self._setup_hotkey()

        self._enter_passive_standby(reason="idle")
        self._poll_foreground_window()
        self._pump_ui_queue()

        if self.hotkey_listener:
            self._hotkey_mode = "hotkey"
            self._set_post_commit_behavior("standby")
            self.candidate_box.set_status(
                f"V1 热键模式已就绪：按 {self.hotkey.replace('<', '').replace('>', ' ')} 唤起输入框。"
            )
        else:
            self._hotkey_mode = "click-only"
            self._set_post_commit_behavior("keep-input")
            self.candidate_box.set_status("V1 点击待命图标可进入输入；热键不可用。")

        if self.runtime_decoder_source == "sqlite":
            print("[Decoder] 运行时候选已回退到 SQLite 数据库视图 runtime_candidates")
        elif self.runtime_decoder_source == "json":
            print("[Decoder] 运行时候选来源: JSON 导出文件")

        if self.runtime_decoder_warning:
            print(f"[Decoder] 运行时编码表未启用: {self.runtime_decoder_warning}")

    def _create_candidate_box(self) -> CandidateBox:
        return CandidateBox(
            on_select=self._on_candidate_select,
            font_family=self.font_family,
            input_display_formatter=self._format_input_outline,
            projected_code_formatter=self._format_projected_code,
            on_input_change=self._on_input_change,
            on_copy_candidate=self._copy_candidate,
            on_commit_text=self._commit_candidate_box_text,
            on_restore_from_standby=self._resume_from_standby,
            on_close=self._close,
        )

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
        if not self._locked_external_hwnd and foreground and foreground != self.own_hwnd:
            self.last_external_hwnd = foreground
            layout = self.window_manager.get_window_keyboard_layout(foreground)
            if (
                layout is not None
                and layout != self.last_external_layout
            ):
                self._handle_external_layout_change(layout)
            self.last_external_layout = layout
        self._schedule_ui(250, self._poll_foreground_window)

    def _handle_external_layout_change(self, layout: int) -> None:
        """外部窗口切到其他系统输入法时，主动转入角落待命。"""
        if self.window_manager.is_english_layout(layout):
            if self._passive_standby_reason == "layout":
                self._resume_global_capture()
            return

        # 显式待命（复制/隐藏/提交后）应保持原状态，不能被布局轮询
        # 覆盖成 layout，否则一旦切回英文布局就会被意外自动恢复接管。
        if self._passive_standby_reason and self._passive_standby_reason != "layout":
            return

        self.input_manager.clear_buffer(notify=False)
        self._display_input_buffer = ""
        self.candidate_box.clear_input(focus_input=False)
        self._enter_passive_standby(reason="layout")

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

    def _setup_hotkey(self) -> None:
        """设置从待命状态唤起输入框的全局快捷键。"""
        try:
            from pynput import keyboard

            def on_activate() -> None:
                print("V1 快捷键激活：唤起候选框")
                foreground = self.window_manager.get_foreground_window()
                target_description = self._describe_external_target(foreground)
                print(f"[YIME V1] 本次锁定目标: {target_description}")
                self._enqueue_ui(
                    lambda: self._activate_from_hotkey(
                        foreground,
                        target_description,
                    )
                )

            self.hotkey_listener = keyboard.GlobalHotKeys({
                self.hotkey: on_activate,
            })
            print(f"V1 全局快捷键已设置: {self.hotkey}")
        except Exception as exc:
            self.hotkey_listener = None
            print(f"V1 设置快捷键失败: {exc}")

    def _activate_from_hotkey(
        self,
        foreground: Optional[int],
        target_description: str,
        *,
        post_commit_behavior: str = "standby",
        status_prefix: str = "V1 热键已唤起",
    ) -> None:
        """在主线程中从热键进入手动输入状态。"""
        self._lock_external_target(foreground)
        self._set_post_commit_behavior(post_commit_behavior)
        self.is_passthrough_enabled = True
        self._passive_standby_reason = "manual"
        self.last_replace_length = 0
        self._display_input_buffer = ""
        self.input_manager.clear_buffer(notify=False)
        self.candidate_box.clear_input(focus_input=False)
        self.candidate_box.show(focus_input=True)
        self.candidate_box.set_status(f"{status_prefix}: {target_description}")

    def _on_candidate_select(self, hanzi: str) -> None:
        """
        候选词选择处理

        Args:
            hanzi: 选中的汉字
        """
        self._record_candidate_selection(hanzi)

        # 主入口现在支持在待上屏区连续累积多个候选，再统一上屏到外部窗口。
        # 因此这里不再选一字就复制并退回待命，而是保留候选框继续输入。
        self.last_replace_length = 0

    def _copy_candidate(self, index: int) -> None:
        """
        复制候选词

        Args:
            index: 候选词索引
        """
        candidates = self.candidate_box.current_candidates
        if 0 <= index < len(candidates):
            hanzi = candidates[index]
            self._record_candidate_selection(hanzi)
            self._copy_text_with_status(hanzi)
            self.last_replace_length = 0
            self._display_input_buffer = ""
            self.input_manager.clear_buffer(notify=False)
            self._clear_candidate_box_state(focus_input=False)
            self._enter_passive_standby(reason="copy")
            self._restore_external_window()
            self._unlock_external_target()

    def _refocus_candidate_input(self) -> None:
        """外部编辑动作完成后，将焦点拉回编码输入框。"""
        self.candidate_box.show(focus_input=True)
        self.candidate_box.input_entry.focus_set()
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
        if self.hotkey_listener:
            self.hotkey_listener.stop()

        self.candidate_box.close()

        if target_hwnd:
            try:
                self.window_manager.restore_window(target_hwnd)
            except Exception:
                pass

    def _enter_passive_standby(self, reason: str) -> None:
        """进入待命图标并暂停全局接管，直到用户显式恢复。"""
        self.is_passthrough_enabled = True
        self._passive_standby_reason = reason
        self.candidate_box.set_manual_input_enabled(False)
        if reason == "commit-box":
            self.candidate_box.show_passive()
            return
        self.candidate_box.show_standby()

    def _resume_global_capture(self) -> None:
        """恢复全局接管，但保持当前窗口显示状态不变。"""
        self.is_passthrough_enabled = False
        self._passive_standby_reason = None

    def _resume_from_standby(self) -> None:
        """用户主动点回候选框时，进入手动输入模式，不恢复全局接管。"""
        target_description = self._describe_external_target(self.last_external_hwnd)
        self._activate_from_hotkey(
            self.last_external_hwnd,
            target_description,
            post_commit_behavior="keep-input",
        )

    def _dispatch_candidates_update(
        self,
        candidates: list[str],
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
        candidates: list[str],
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

        # 全局监听模式下，输入框显示 PUA 编码字符；投影行反查显示物理 ASCII 键。
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
                print("[UI] buffer empty; keep candidate box visible without focus")

            # 全局监听模式下清空缓冲区后也不能抢回 Entry 焦点，
            # 否则下一次按键会被误判为候选框手动输入。
            self.candidate_box.show(focus_input=False)

    def _on_input_commit(self, hanzi: str) -> None:
        """
        输入提交回调

        Args:
            hanzi: 要提交的汉字
        """
        self.candidate_box.append_commit_text(hanzi)
        self.last_replace_length = 0
        self.candidate_box.set_status(
            f"已加入缓冲区: {self.candidate_box.get_commit_text()}"
        )
        self.candidate_box.show(focus_input=False)

    def _after_commit_candidate_box_text(self) -> None:
        self._display_input_buffer = ""
        if self._should_keep_input_after_commit():
            self.candidate_box.show(focus_input=False)
            return
        self._enter_passive_standby(reason="commit-box")

    def _on_key_press(self, key_info: dict[str, Any]) -> bool:
        """
        键盘按键回调

        Returns:
            True继续传递，False拦截
        """
        try:
            if self._handle_pause_toggle(key_info):
                return False

            if self.is_passthrough_enabled:
                return True

            if self.candidate_box.is_manual_input_active():
                return True

            key = str(key_info.get("key", ""))
            if key in ("Return", "Enter", "enter"):
                buffered_text = self.candidate_box.get_commit_text().strip()
                if buffered_text and not self.input_manager.get_buffer():
                    self._commit_candidate_box_text(buffered_text)
                    return False

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

    def _handle_pause_toggle(self, key_info: dict[str, Any]) -> bool:
        """处理可选的全局监听暂停/恢复快捷键。"""
        if not self.enable_pause_toggle:
            return False

        modifiers_value = key_info.get("modifiers")
        modifiers = (
            cast(dict[str, Any], modifiers_value)
            if isinstance(modifiers_value, dict)
            else {}
        )
        if not (
            key_info.get("char") == "t"
            and modifiers.get("ctrl", False)
            and modifiers.get("alt", False)
        ):
            return False

        self.is_passthrough_enabled = not self.is_passthrough_enabled
        self.input_manager.clear_buffer(notify=True)

        if self.is_passthrough_enabled:
            self.candidate_box.show_standby()
        else:
            self.candidate_box.show()

        if self.debug_ui:
            state = "enabled" if self.is_passthrough_enabled else "disabled"
            print(f"[Input] passthrough {state}")

        return True

    def _sync_display_input_buffer(
        self,
        key_info: dict[str, Any],
        raw_text: str,
        handled: bool,
    ) -> None:
        """同步全局输入模式下输入框要显示的 PUA 编码字符。"""
        buffer_length = len(self.input_manager.get_buffer())
        if buffer_length == 0:
            self._display_input_buffer = ""
            return

        key = str(key_info.get("key", ""))
        if key in ("Backspace", "backspace") and handled is False:
            self._display_input_buffer = self._display_input_buffer[:-1]
        elif raw_text:
            projected_text = key_info.get("text", "")
            self._display_input_buffer += (
                projected_text if isinstance(projected_text, str) else raw_text
            )

        if len(self._display_input_buffer) > buffer_length:
            self._display_input_buffer = self._display_input_buffer[-buffer_length:]
        elif len(self._display_input_buffer) < buffer_length:
            self._display_input_buffer = self.input_manager.get_buffer()

    def _process_key_in_main_thread(self, key_info: dict[str, Any]) -> None:
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
        if self.hotkey_listener:
            try:
                self.hotkey_listener.start()
                print(f"V1 快捷键监听已启动: {self.hotkey}")
            except Exception as e:
                print(f"V1 快捷键监听启动失败: {e}")
                self.hotkey_listener = None

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

        print("\n当前主入口处于测试模式:")
        print("1. 平时保持右下角待命图标，不接管记事本里的英文输入")
        if self.hotkey_listener:
            print(f"2. 想输入汉字时，可按 {self.hotkey.replace('<', '').replace('>', ' ')} 或点击右下角的'音'图标")
        else:
            print("2. 想输入汉字时，点击右下角的'音'图标")
        print("3. 候选框弹出并获得焦点后，在编码框中输入")
        print("4. 选字后会回到待命图标，可继续在外部窗口编辑")

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
    parser.add_argument(
        "--enable-pause-toggle",
        action="store_true",
        help="启用 Ctrl+Alt+T 暂停/恢复全局键盘监听，便于调试外部输入行为。",
    )
    parser.add_argument(
        "--hotkey",
        default="<ctrl>+<shift>+y",
        help="从待命状态唤起输入框的快捷键。默认: Ctrl+Shift+Y",
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
    app = InputMethodApp(
        auto_paste=not args.copy_only,
        font_family=args.font_family,
        enable_pause_toggle=args.enable_pause_toggle,
        hotkey=args.hotkey,
    )
    app.run()


if __name__ == "__main__":
    main()
