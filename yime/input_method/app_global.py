"""
全局监听模式专属应用 (Experimental Global Listener App)
"""

import os
from typing import Any, Callable, Optional, cast

from .app_base import BaseInputMethodApp
from .core.decoders import project_physical_input
from .core.keyboard_listener import KeyboardListener
from .core.input_manager import InputManager
from .ui.candidate_box import CandidateBox

class GlobalListenerApp(BaseInputMethodApp):
    """
    独立全局监听模式应用
    
    直接监听全局键盘（无需快捷键唤醒），
    当输入合法音元编码时，自动拦截键盘事件并显示候选框。
    """

    def __init__(
        self,
        auto_paste: bool = True,
        font_family: str = "音元",
        enable_pause_toggle: bool = False,
    ) -> None:
        self.auto_paste = auto_paste
        self.font_family = font_family
        self.enable_pause_toggle = enable_pause_toggle
        self.is_passthrough_enabled = False
        
        self.debug_ui = os.environ.get("YIME_DEBUG_UI", "").strip().lower() in {
            "1", "true", "yes", "on",
        }

        super().__init__(
            auto_paste=auto_paste,
            font_family=font_family,
        )

        self._display_input_buffer = ""
        
        # 专属部件：输入管理器和全局键盘钩子
        self.input_manager = InputManager(
            on_candidates_update=self._on_candidates_update_from_manager,
            on_input_commit=self._on_input_commit_from_manager,
        )
        self.input_manager.set_decoder(self.decoder)
        self.keyboard_listener: Optional[KeyboardListener] = None

        self._set_post_commit_behavior("standby")

    def _on_candidates_update_from_manager(self, candidates: list[str], _kanji: str, code: str, comment: str) -> None:
        self.candidate_box.update_candidates(
            candidates, code, comment, 
            status=f"输入中 ({self._display_input_buffer})"
        )

    def _on_input_commit_from_manager(self, hanzi: str) -> None:
        self._commit_candidate_box_text(hanzi)
        self.input_manager.clear_buffer(notify=False)
        self._display_input_buffer = ""

    def run(self) -> None:
        """运行应用"""
        try:
            self.keyboard_listener = KeyboardListener(
                on_key_press=self._on_key_press,
            )
            self.keyboard_listener.start()
            if self.keyboard_listener.is_active():
                print("实验性全局监听已启动")
            else:
                print("实验性全局监听未启用")
        except Exception as e:
            print(f"启动实验性全局监听失败: {e}")
            print("当前会话将保持待命窗口，不接管外部键盘")

        print("\n当前主入口处于测试模式:")
        print("1. 当前为实验性全局监听模式，默认接管外部键盘输入")
        print("2. 不启用热键会话；请直接在外部窗口输入编码")
        print("3. 当前模式与热键模式分离，便于独立排查全局监听问题")

        self.candidate_box.set_status("实验性全局监听模式已就绪：直接监听外部键盘输入")
        self.candidate_box.run()

    def _on_key_press(self, key_info: dict[str, Any]) -> bool:
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
                x, y = getattr(self.candidate_box, "get_pointer_position", lambda: (0, 0))()
                self._schedule_ui(0, lambda: self.candidate_box.show(x, y + 20, focus_input=False))

            return handled
        except Exception as e:
            print(f"处理键盘事件出错: {e}")
        return True

    def _handle_pause_toggle(self, key_info: dict[str, Any]) -> bool:
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
            self._schedule_ui(0, lambda: self.candidate_box.show_standby())
        else:
            self._schedule_ui(0, lambda: self.candidate_box.show())

        if getattr(self, "debug_ui", False):
            state = "enabled" if self.is_passthrough_enabled else "disabled"
            print(f"[Input] passthrough {state}")

        return True

    def _sync_display_input_buffer(
        self,
        key_info: dict[str, Any],
        raw_text: str,
        handled: bool,
    ) -> None:
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
