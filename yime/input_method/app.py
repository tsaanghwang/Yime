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

    @staticmethod
    def _normalize_trigger_mode(mode: str, *, option_name: str) -> frozenset[str]:
        normalized = mode.strip().lower()
        if normalized == "both":
            return frozenset({"hotkey", "mouse"})
        if normalized in {"hotkey", "mouse"}:
            return frozenset({normalized})
        raise ValueError(
            f"{option_name} 必须是 hotkey、mouse 或 both，收到: {mode!r}"
        )

    def _is_hotkey_wake_enabled(self) -> bool:
        return "hotkey" in getattr(
            self,
            "wake_triggers",
            frozenset({"hotkey", "mouse"}),
        )

    def _is_mouse_wake_enabled(self) -> bool:
        return "mouse" in getattr(
            self,
            "wake_triggers",
            frozenset({"hotkey", "mouse"}),
        )

    def _is_hotkey_standby_enabled(self) -> bool:
        return "hotkey" in getattr(
            self,
            "standby_triggers",
            frozenset({"hotkey", "mouse"}),
        )

    def _is_mouse_standby_enabled(self) -> bool:
        return "mouse" in getattr(
            self,
            "standby_triggers",
            frozenset({"hotkey", "mouse"}),
        )

    def _should_listen_for_hotkey(self) -> bool:
        return self._is_hotkey_wake_enabled() or self._is_hotkey_standby_enabled()

    def _wake_trigger_hint(self) -> str:
        hints: list[str] = []
        if self._is_hotkey_wake_enabled() and getattr(self, "hotkey_listener", True):
            hints.append(f"按 {self._format_hotkey_label()}")
        if self._is_mouse_wake_enabled():
            hints.append("点击右下角的'音'图标")
        return " 或 ".join(hints) if hints else "当前未配置唤醒方式"

    def _standby_trigger_hint(self) -> str:
        hints: list[str] = []
        if self._is_hotkey_standby_enabled() and getattr(self, "hotkey_listener", True):
            hints.append(f"再次按 {self._format_hotkey_label()}")
        if self._is_mouse_standby_enabled():
            hints.append("右键候选框")
        return " 或 ".join(hints) if hints else "当前未配置休眠方式"

    def _is_wake_enabled_for_source(self, trigger_source: str) -> bool:
        return (
            self._is_hotkey_wake_enabled()
            if trigger_source == "hotkey"
            else self._is_mouse_wake_enabled()
        )

    def _is_standby_enabled_for_source(self, trigger_source: str) -> bool:
        return (
            self._is_hotkey_standby_enabled()
            if trigger_source == "hotkey"
            else self._is_mouse_standby_enabled()
        )

    @staticmethod
    def _activation_status_prefix(trigger_source: str) -> str:
        return "V1 鼠标已唤起" if trigger_source == "mouse" else "V1 热键已唤起"

    def _remember_manual_session_context(
        self,
        trigger_source: str,
        target_hwnd: Optional[int],
    ) -> None:
        self._manual_session_trigger = trigger_source
        self._last_manual_session_trigger = trigger_source
        try:
            normalized_target = self._normalize_external_hwnd(target_hwnd)
        except Exception:
            normalized_target = target_hwnd
        if normalized_target is not None:
            self._last_manual_target_hwnd = normalized_target

    def _current_manual_target_hwnd(self) -> Optional[int]:
        try:
            target_hwnd = self._current_external_target_hwnd()
        except Exception:
            target_hwnd = getattr(self, "_locked_external_hwnd", None) or getattr(
                self,
                "last_external_hwnd",
                None,
            )
        if target_hwnd is not None:
            return target_hwnd
        remembered_target = getattr(self, "_last_manual_target_hwnd", None)
        try:
            return self._normalize_external_hwnd(remembered_target)
        except Exception:
            return remembered_target

    def __init__(
        self,
        auto_paste: bool = True,
        font_family: str = "音元",
        enable_pause_toggle: bool = False,
        hotkey: str = _DEFAULT_HOTKEY,
        wake_trigger: str = "both",
        standby_trigger: str = "both",
    ) -> None:
        """
        初始化热键输入法模式
        """
        self.auto_paste = auto_paste
        self.font_family = font_family
        self.enable_pause_toggle = enable_pause_toggle
        self.hotkey = hotkey
        self.input_mode = self._DEFAULT_INPUT_MODE
        self.wake_triggers = self._normalize_trigger_mode(
            wake_trigger,
            option_name="wake_trigger",
        )
        self.standby_triggers = self._normalize_trigger_mode(
            standby_trigger,
            option_name="standby_trigger",
        )
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
        self._manual_session_trigger: Optional[str] = None
        self._last_manual_session_trigger: Optional[str] = None
        self._last_manual_target_hwnd: Optional[int] = None
        self._last_external_caret_rect: Optional[tuple[int, int, int, int]] = None

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

    def _is_global_listener_mode(self) -> bool:
        return getattr(self, "input_mode", self._DEFAULT_INPUT_MODE) == "global-listener"

    def _configure_input_mode(self) -> None:
        default_triggers = frozenset({"hotkey", "mouse"})
        wake_triggers = getattr(self, "wake_triggers", default_triggers)
        standby_triggers = getattr(self, "standby_triggers", default_triggers)
        if self._is_global_listener_mode():
            self._set_post_commit_behavior("standby")
            self._resume_global_capture()
            self._hotkey_mode = "disabled"
            self._emit_feedback(
                "输入模式",
                "实验性全局监听模式已就绪：直接监听外部键盘输入；不启用热键会话。"
            )
            return

        if self._should_listen_for_hotkey():
            self._setup_hotkey()
        else:
            self.hotkey_listener = None
        self._set_post_commit_behavior("keep-input")
        if self.hotkey_listener:
            self._hotkey_mode = "hotkey"
            if self._has_known_hotkey_conflict(self.hotkey):
                print(
                    "[YIME V1] 当前热键与已知快捷键冲突，"
                    "可能导致焦点误跳转或与码元输入冲突。建议改用 --hotkey <ctrl>+<alt>+<insert>。"
                )
            if wake_triggers == default_triggers and standby_triggers == default_triggers:
                self._emit_feedback(
                    "输入模式",
                    f"V1 热键模式已就绪：按 {self._format_hotkey_label()} 唤起输入框；再次按下可回待命。"
                )
            else:
                self._emit_feedback(
                    "输入模式",
                    "V1 已就绪："
                    f"唤起可通过{self._wake_trigger_hint()}；"
                    f"休眠可通过{self._standby_trigger_hint()}。"
                )
        else:
            self._hotkey_mode = "click-only"
            if wake_triggers == frozenset({"mouse"}) and standby_triggers == frozenset({"mouse"}):
                self._emit_feedback("输入模式", "V1 点击待命图标可进入输入；热键不可用。")
            else:
                self._emit_feedback(
                    "输入模式",
                    "V1 已就绪："
                    f"唤起可通过{self._wake_trigger_hint()}；"
                    f"休眠可通过{self._standby_trigger_hint()}。"
                )

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
            on_add_input_to_user_lexicon=self._add_current_input_to_user_lexicon,
            on_delete_input_from_user_lexicon=self._delete_current_input_from_user_lexicon,
            on_feedback=self._emit_feedback,
            on_restore_from_standby=self._resume_from_standby,
            on_toggle_standby=self._return_mouse_session_to_standby,
            on_close=self._close,
            enable_mouse_wake=self._is_mouse_wake_enabled(),
            enable_mouse_standby=self._is_mouse_standby_enabled(),
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
        if not getattr(self, "_locked_external_hwnd", None):
            normalized_foreground = self._normalize_external_hwnd(foreground)
        if normalized_foreground is not None:
            self.last_external_hwnd = normalized_foreground
            caret_rect = self.window_manager.get_input_anchor_rect(normalized_foreground)
            if caret_rect is not None:
                self._last_external_caret_rect = caret_rect
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
        if (
            self._passive_standby_reason != "manual"
            and not self._is_hotkey_wake_enabled()
        ):
            if getattr(self, "debug_ui", False):
                print(
                    "[YIME DEBUG] hotkey wake ignored "
                    "because hotkey wake is disabled in standby"
                )
            return

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
        status_prefix: Optional[str] = None,
        prefer_pointer_position: bool = False,
        force_recompute: bool = True,
        trigger_source: str = "hotkey",
    ) -> None:
        """在主线程中进入手动输入状态。"""
        locked_target = self._lock_external_target(foreground)
        effective_target = locked_target or self._current_manual_target_hwnd()
        self._remember_manual_session_context(trigger_source, effective_target)
        if status_prefix is None:
            status_prefix = self._activation_status_prefix(trigger_source)
        if getattr(self, "debug_ui", False):
            print(
                "[YIME DEBUG] activate manual input "
                f"requested={foreground} locked={locked_target} trigger={trigger_source} "
                f"status='{target_description}' post_commit={post_commit_behavior}"
            )
        self._set_post_commit_behavior(post_commit_behavior)
        self.is_passthrough_enabled = True
        self._passive_standby_reason = "manual"
        self.last_replace_length = 0
        self._display_input_buffer = ""
        if getattr(self, "input_manager", None):
            self.input_manager.clear_buffer(notify=False)
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

        anchor_rect = getattr(self, "_last_external_caret_rect", None) if trigger_source == "mouse" else None

        if prefer_pointer_position and pointer_x is not None and pointer_y is not None:
            self.candidate_box.show(
                pointer_x,
                pointer_y + 20,
                focus_input=True,
                anchor_hwnd=effective_target,
                force_recompute=force_recompute,
            )
        else:
            try:
                self.candidate_box.show(
                    focus_input=True,
                    anchor_hwnd=effective_target,
                    force_recompute=force_recompute,
                    anchor_rect=anchor_rect,
                )
            except TypeError:
                self.candidate_box.show(
                    focus_input=True,
                    anchor_hwnd=effective_target,
                    force_recompute=force_recompute,
                )
        self._emit_feedback("会话", f"{status_prefix}: {target_description}")

    def _toggle_hotkey_session(
        self,
        foreground: Optional[int],
        target_description: str,
        *,
        trigger_source: str = "hotkey",
    ) -> None:
        """手动会话可由热键或鼠标在输入与待命之间切换。"""
        if self._passive_standby_reason == "manual":
            if self._is_standby_enabled_for_source(trigger_source):
                self._return_hotkey_session_to_standby(trigger_source=trigger_source)
            return
        if self._is_wake_enabled_for_source(trigger_source):
            self._activate_from_hotkey(
                foreground,
                target_description,
                trigger_source=trigger_source,
            )

    def _return_hotkey_session_to_standby(self, *, trigger_source: str = "hotkey") -> None:
        """显式结束当前手动输入会话并回到待命。"""
        self._remember_manual_session_context(
            getattr(self, "_manual_session_trigger", trigger_source),
            self._current_manual_target_hwnd(),
        )
        self.last_replace_length = 0
        self._display_input_buffer = ""
        if getattr(self, "input_manager", None):
            self.input_manager.clear_buffer(notify=False)
        self.candidate_box.clear_input(focus_input=False)
        self.candidate_box.clear_commit_text()
        self._enter_passive_standby(reason="idle")
        self._restore_external_window()
        self._unlock_external_target()
        if self._is_hotkey_wake_enabled() and getattr(self, "hotkey_listener", True):
            self._emit_feedback(
                "会话",
                f"V1 已回待命：按 {self._format_hotkey_label()} 可再次唤起输入框。"
            )
        elif self._is_mouse_wake_enabled():
            self._emit_feedback("会话", "V1 已回待命：点击右下角的'音'图标可再次唤起输入框。")
        else:
            self._emit_feedback("会话", "V1 已回待命。")

    def _return_mouse_session_to_standby(self) -> None:
        try:
            self._return_hotkey_session_to_standby(trigger_source="mouse")
        except TypeError:
            self._return_hotkey_session_to_standby()

    def _on_candidate_select(self, hanzi: str) -> None:
        """
        候选词选择处理

        Args:
            hanzi: 选中的汉字
        """
        persisted_freq = self._record_candidate_selection(hanzi)
        if persisted_freq > 0:
            self._emit_feedback(
                "调序",
                f"调序已记录：{hanzi}（累计 {persisted_freq} 次）。如需追查请用 diagnose_candidate_order.py。",
            )

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
        anchor_hwnd = self._current_manual_target_hwnd()
        try:
            self.candidate_box.show(
                focus_input=True,
                anchor_hwnd=anchor_hwnd,
                force_recompute=False,
            )
        except TypeError:
            self.candidate_box.show(focus_input=True, anchor_hwnd=anchor_hwnd)
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
        if getattr(self, "_manual_session_trigger", None):
            self._remember_manual_session_context(
                self._manual_session_trigger,
                self._current_manual_target_hwnd(),
            )
        self._manual_session_trigger = None
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

    def _after_commit_candidate_box_text(self) -> None:
        self._display_input_buffer = ""
        self._enter_passive_standby(reason="commit-box")

    def _resume_from_standby(self) -> None:
        """用户主动点回候选框时，进入手动输入模式，不恢复全局接管。"""
        current_foreground = self.window_manager.get_foreground_window()
        target_hwnd = self._resolve_hotkey_target(current_foreground)
        target_description = self._describe_external_target(target_hwnd)
        try:
            self._activate_from_hotkey(
                target_hwnd,
                    target_description,
                post_commit_behavior="keep-input",
                status_prefix=self._activation_status_prefix("mouse"),
                force_recompute=True,
                trigger_source="mouse",
            )
        except TypeError:
            self._activate_from_hotkey(
                target_hwnd,
                target_description,
                post_commit_behavior="keep-input",
                status_prefix=self._activation_status_prefix("mouse"),
                force_recompute=True,
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
        print(f"2. 想输入汉字时，可通过 {self._wake_trigger_hint()}")
        print("3. 候选框弹出并获得焦点后，在编码框中输入")
        print(f"4. 想休眠时，可通过 {self._standby_trigger_hint()}")

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
    parser.add_argument(
        "--wake-trigger",
        choices=["hotkey", "mouse", "both"],
        default="both",
        help="唤醒方式：hotkey 仅组合键，mouse 仅鼠标，both 两者都可。默认: both",
    )
    parser.add_argument(
        "--standby-trigger",
        choices=["hotkey", "mouse", "both"],
        default="both",
        help="休眠方式：hotkey 仅组合键，mouse 仅鼠标，both 两者都可。默认: both",
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
            wake_trigger=args.wake_trigger,
            standby_trigger=args.standby_trigger,
        )
    app.run()


if __name__ == "__main__":
    main()
