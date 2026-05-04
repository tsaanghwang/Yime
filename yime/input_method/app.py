"""
音元输入法主应用

整合所有模块，提供完整的输入法功能
"""

from __future__ import annotations

import argparse
import ctypes
import os
import queue
import time
import tkinter as tk
from typing import Any, Callable, Optional, cast

from .app_base import BaseInputMethodApp
from .ui.candidate_box import CandidateBox


class InputMethodApp(BaseInputMethodApp):
    """音元输入法主应用"""

    _DEFAULT_INPUT_MODE = "hotkey"
    _DEFAULT_HOTKEY = "<ctrl>+<alt>+<insert>"
    _KNOWN_CONFLICT_HOTKEYS = {
        "<ctrl>+<shift>+y",
        "<ctrl>+<alt>+y",
        "<ctrl>+<alt>+<f10>",
    }
    _HOTKEY_WAKE_DELAY_MS = 90
    _HOTKEY_REACTIVATION_DEBOUNCE_SECONDS = 0.8

    def _format_hotkey_label(self) -> str:
        """将 pynput 风格的热键定义转换为更适合状态提示的文本。"""
        segments: list[str] = []
        for segment in self.hotkey.split("+"):
            cleaned = segment.strip().strip("<>")
            if cleaned:
                segments.append(cleaned)
        return "+".join(segments) or self.hotkey

    @classmethod
    def _has_known_hotkey_conflict(cls, hotkey: str) -> bool:
        return hotkey.strip().lower() in cls._KNOWN_CONFLICT_HOTKEYS

    def __init__(
        self,
        auto_paste: bool = True,
        font_family: str = "音元",
        enable_pause_toggle: bool = False,
        hotkey: str = _DEFAULT_HOTKEY,
    ) -> None:
        """
        初始化热键输入法模式
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

        self._passive_standby_reason: Optional[str] = None
        self._is_closing = False
        self._after_ids: set[str] = set()
        self._ui_queue: queue.SimpleQueue[Callable[[], None]] = queue.SimpleQueue()
        self._last_hotkey_activation_at = 0.0

        initial_external_hwnd = self._normalize_external_hwnd(
            self.window_manager.get_foreground_window()
        )
        if initial_external_hwnd is not None:
            self.last_external_hwnd = initial_external_hwnd
            self.last_external_layout = self.window_manager.get_window_keyboard_layout(
                initial_external_hwnd
            )

        self.hotkey_listener = None
        self._hotkey_mode = "unknown"

        self._enter_passive_standby(reason="idle")
        self._poll_foreground_window()
        self._pump_ui_queue()

        self._configure_input_mode()

        if self.runtime_decoder_source == "sqlite":
            print("[Decoder] 运行时候选已回退到 SQLite 数据库视图 runtime_candidates")
        elif self.runtime_decoder_source == "json":
            print("[Decoder] 运行时候选来源: JSON 导出文件")

        if self.runtime_decoder_warning:
            print(f"[Decoder] 运行时编码表未启用: {self.runtime_decoder_warning}")

    def _configure_input_mode(self) -> None:
        self._setup_hotkey()
        self._set_post_commit_behavior("keep-input")
        if self.hotkey_listener:
            self._hotkey_mode = "hotkey"
            if self._has_known_hotkey_conflict(self.hotkey):
                print(
                    "[YIME V1] 当前热键与已知快捷键冲突，"
                    "可能导致焦点误跳转或与码元输入冲突。建议改用 --hotkey <ctrl>+<alt>+<insert>。"
                )
            self.candidate_box.set_status(
                f"V1 热键模式已就绪：按 {self._format_hotkey_label()} 唤起输入框；再次按下可回待命。"
            )
        else:
            self._hotkey_mode = "click-only"
            self.candidate_box.set_status("V1 点击待命图标可进入输入；热键不可用。")

    def _create_candidate_box(self) -> CandidateBox:
        return CandidateBox(
            on_select=self._on_candidate_select,
            font_family=self.font_family,
            input_display_formatter=self._format_input_outline,
            projected_code_formatter=self._format_projected_code,
            manual_key_output_resolver=self._resolve_manual_key_output,
            manual_input_transformer=self._format_visible_input,
            on_input_change=self._on_input_change,
            on_copy_candidate=self._copy_candidate,
            on_commit_text=self._commit_candidate_box_text,
            on_restore_from_standby=self._resume_from_standby,
            on_toggle_standby=self._return_hotkey_session_to_standby,
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
        normalized_foreground = None
        if not self._locked_external_hwnd:
            normalized_foreground = self._normalize_external_hwnd(foreground)
        if normalized_foreground is not None:
            self.last_external_hwnd = normalized_foreground
            layout = self.window_manager.get_window_keyboard_layout(normalized_foreground)
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
                snapshot_foreground = self.window_manager.get_foreground_window()
                self._enqueue_ui(
                    lambda: self._request_hotkey_activation(snapshot_foreground)
                )

            self.hotkey_listener = keyboard.GlobalHotKeys({
                self.hotkey: on_activate,
            })
            print(f"V1 全局快捷键已设置: {self.hotkey}")
        except Exception as exc:
            self.hotkey_listener = None
            print(f"V1 设置快捷键失败: {exc}")

    def _request_hotkey_activation(
        self,
        snapshot_foreground: Optional[int],
    ) -> None:
        """在 Tk 主线程中解析热键目标，避免监听线程读到瞬时错误前台。"""
        now = time.monotonic()
        last_activation_at = getattr(self, "_last_hotkey_activation_at", 0.0)
        if now - last_activation_at < self._HOTKEY_REACTIVATION_DEBOUNCE_SECONDS:
            if getattr(self, "debug_ui", False):
                print(
                    "[YIME DEBUG] hotkey activate ignored "
                    f"delta={now - last_activation_at:.3f}s "
                    f"threshold={self._HOTKEY_REACTIVATION_DEBOUNCE_SECONDS:.3f}s"
                )
            return
        self._last_hotkey_activation_at = now

        if self._passive_standby_reason == "manual":
            self._finalize_hotkey_activation(snapshot_foreground)
            return

        if getattr(self, "debug_ui", False):
            print(
                "[YIME DEBUG] hotkey wake scheduled "
                f"delay_ms={self._HOTKEY_WAKE_DELAY_MS} snapshot={snapshot_foreground}"
            )
        self._schedule_ui(
            self._HOTKEY_WAKE_DELAY_MS,
            lambda: self._finalize_hotkey_activation(snapshot_foreground),
        )

    def _finalize_hotkey_activation(
        self,
        snapshot_foreground: Optional[int],
    ) -> None:
        """在组合键释放后执行真正的热键会话切换。"""
        current_foreground = self.window_manager.get_foreground_window()
        foreground = self._resolve_hotkey_target(current_foreground)
        if foreground is None and snapshot_foreground != current_foreground:
            foreground = self._resolve_hotkey_target(snapshot_foreground)
        target_description = self._describe_external_target(foreground)
        print(f"[YIME V1] 本次锁定目标: {target_description}")
        if getattr(self, "debug_ui", False):
            print(
                "[YIME DEBUG] hotkey activate "
                f"snapshot={snapshot_foreground} foreground={current_foreground} "
                f"resolved={foreground} last_external={self.last_external_hwnd} "
                f"locked={self._locked_external_hwnd}"
            )
        self._toggle_hotkey_session(
            foreground,
            target_description,
        )

    def _resolve_hotkey_target(self, foreground: Optional[int]) -> Optional[int]:
        """热键唤起时优先取当前外部前台，取不到时回退到上次外部目标。"""
        normalized_foreground = self._normalize_external_hwnd(foreground)
        resolved = normalized_foreground
        if resolved is None:
            resolved = self._normalize_external_hwnd(self.last_external_hwnd)
        if getattr(self, "debug_ui", False):
            print(
                "[YIME DEBUG] resolve hotkey target "
                f"foreground={foreground} normalized={normalized_foreground} "
                f"last_external={self.last_external_hwnd} resolved={resolved}"
            )
        return resolved

    def _activate_from_hotkey(
        self,
        foreground: Optional[int],
        target_description: str,
        *,
        post_commit_behavior: str = "keep-input",
        status_prefix: str = "V1 热键已唤起",
        prefer_pointer_position: bool = False,
        force_recompute: bool = True,
    ) -> None:
        """在主线程中从热键进入手动输入状态。"""
        locked_target = self._lock_external_target(foreground)
        if getattr(self, "debug_ui", False):
            print(
                "[YIME DEBUG] activate manual input "
                f"requested={foreground} locked={locked_target} "
                f"status='{target_description}' post_commit={post_commit_behavior}"
            )
        self._set_post_commit_behavior(post_commit_behavior)
        self._passive_standby_reason = "manual"
        self.last_replace_length = 0
        self.candidate_box.clear_input(focus_input=False)
        pointer_x: Optional[int] = None
        pointer_y: Optional[int] = None
        if prefer_pointer_position:
            try:
                pointer_x, pointer_y = self.candidate_box.get_pointer_position()
            except Exception:
                pointer_x = None
                pointer_y = None

        if getattr(self, "debug_ui", False):
            print(
                "[YIME DEBUG] activate position "
                f"pointer=({pointer_x},{pointer_y}) anchor={foreground} prefer_pointer={prefer_pointer_position}"
            )

        if prefer_pointer_position and pointer_x is not None and pointer_y is not None:
            self.candidate_box.show(
                pointer_x,
                pointer_y + 20,
                focus_input=True,
                anchor_hwnd=foreground,
                force_recompute=force_recompute,
            )
        else:
            self.candidate_box.show(focus_input=True, anchor_hwnd=foreground, force_recompute=force_recompute)
        self.candidate_box.set_status(f"{status_prefix}: {target_description}")

    def _toggle_hotkey_session(
        self,
        foreground: Optional[int],
        target_description: str,
    ) -> None:
        """热键模式下再次按热键可在连续输入与待命之间切换。"""
        if self._passive_standby_reason == "manual":
            self._return_hotkey_session_to_standby()
            return
        self._activate_from_hotkey(foreground, target_description)

    def _return_hotkey_session_to_standby(self) -> None:
        """显式结束当前热键输入会话并回到待命。"""
        self.last_replace_length = 0
        self.candidate_box.clear_input(focus_input=False)
        self.candidate_box.clear_commit_text()
        self._enter_passive_standby(reason="idle")
        self._restore_external_window()
        self._unlock_external_target()
        self.candidate_box.set_status(
            f"V1 已回待命：按 {self._format_hotkey_label()} 可再次唤起输入框。"
        )

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
        if getattr(self, "keyboard_listener", None):
            self.keyboard_listener.stop()
        if getattr(self, "hotkey_listener", None):
            self.hotkey_listener.stop()

        self.candidate_box.close()

        if target_hwnd:
            try:
                self.window_manager.restore_window(target_hwnd)
            except Exception:
                pass

    def _enter_passive_standby(self, reason: str) -> None:
        """进入待命图标并暂停全局接管，直到用户显式恢复。"""
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
        current_foreground = self.window_manager.get_foreground_window()
        target_hwnd = self._resolve_hotkey_target(current_foreground)
        target_description = self._describe_external_target(target_hwnd)
        if getattr(self, "debug_ui", False):
            print(
                "[YIME DEBUG] resume from standby "
                f"foreground={current_foreground} resolved={target_hwnd} "
                f"last_external={self.last_external_hwnd} locked={self._locked_external_hwnd}"
            )
        self._activate_from_hotkey(
            target_hwnd,
            target_description,
            post_commit_behavior="keep-input",
            force_recompute=False,
        )

    def run(self) -> None:
        """运行应用"""
        if self.hotkey_listener:
            try:
                self.hotkey_listener.start()
                print(f"V1 快捷键监听已启动: {self.hotkey}")
            except Exception as e:
                print(f"V1 快捷键监听启动失败: {e}")
                self.hotkey_listener = None

        print("\n当前主入口处于测试模式:")
        print("1. 平时保持右下角待命图标，不接管记事本里的英文输入")
        if self.hotkey_listener:
            print(f"2. 想输入汉字时，可按 {self._format_hotkey_label()} 或点击右下角的'音'图标")
        else:
            print("2. 想输入汉字时，点击右下角的'音'图标")
        print("3. 候选框弹出并获得焦点后，在编码框中输入")
        print("4. 选字后会回到待命图标，可继续在外部窗口编辑")

        # 运行候选框
        self.candidate_box.run()


def parse_args() -> argparse.Namespace:
    """解析命令行参数"""
    default_hotkey = InputMethodApp._DEFAULT_HOTKEY
    parser = argparse.ArgumentParser(description="音元输入法 Windows 候选框")
    parser.add_argument(
        "--input-mode",
        choices=["hotkey", "global-listener"],
        default="hotkey",
        help="输入模式。默认 hotkey；global-listener 为实验性独立入口。",
    )
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
        default=default_hotkey,
        help="从待命状态唤起输入框的快捷键。默认: Ctrl+Alt+Insert；避开 VS Code 与码元输入冲突。",
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

    if args.input_mode == "global-listener":
        from .app_global import GlobalListenerApp
        app = GlobalListenerApp(
            auto_paste=not args.copy_only,
            font_family=args.font_family,
            enable_pause_toggle=args.enable_pause_toggle,
        )
    else:
        app = InputMethodApp(
            auto_paste=not args.copy_only,
            font_family=args.font_family,
            enable_pause_toggle=args.enable_pause_toggle,
            hotkey=args.hotkey,
        )
    app.run()


if __name__ == "__main__":
    main()
