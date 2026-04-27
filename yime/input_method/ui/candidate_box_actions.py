from __future__ import annotations

import tkinter as tk
from typing import TYPE_CHECKING, Optional

if TYPE_CHECKING:
    from .candidate_box import CandidateBox


class CandidateBoxActions:
    """Event and command handlers for CandidateBox."""

    def __init__(self, box: CandidateBox) -> None:
        self.box = box

    def bind_keys(self) -> None:
        for index in range(1, 10):
            self.box.root.bind(
                str(index),
                lambda event, value=index: self.on_digit_shortcut(event, value),
            )

        self.box.root.bind("<Return>", self.on_confirm_key)
        self.box.input_entry.bind("<Return>", self.on_confirm_key)
        self.box.commit_entry.bind("<Return>", self.on_confirm_key)
        self.box.root.bind("<space>", self.on_confirm_key)
        self.box.input_entry.bind("<space>", self.on_confirm_key)
        self.box.commit_entry.bind("<space>", self.on_confirm_key)

        self.box.root.bind("<Escape>", lambda event: self.box.clear_input())
        self.box.root.bind("<Control-q>", lambda event: self.request_close())
        self.box.root.bind("<Control-v>", self.on_ctrl_v)
        self.box.input_entry.bind("<Control-v>", self.on_ctrl_v)
        self.box.commit_entry.bind("<Control-v>", self.on_ctrl_v)
        self.box.root.bind("<Control-Shift-C>", self.on_copy_input_shortcut)
        self.box.input_entry.bind("<Control-Shift-C>", self.on_copy_input_shortcut)
        self.box.commit_entry.bind("<Control-Shift-C>", self.on_copy_input_shortcut)
        self.box.root.bind("<Prior>", self.on_previous_page_key)
        self.box.root.bind("<Next>", self.on_next_page_key)
        self.box.root.bind("<FocusIn>", self.on_window_focus_in)
        self.box.input_entry.bind("<Prior>", self.on_previous_page_key)
        self.box.input_entry.bind("<Next>", self.on_next_page_key)
        self.box.commit_entry.bind("<Prior>", self.on_previous_page_key)
        self.box.commit_entry.bind("<Next>", self.on_next_page_key)

    def on_window_focus_in(self, event: object) -> None:
        widget = getattr(event, "widget", None)
        if (
            widget == self.box.root
            and not self.box.is_standby()
            and self.box.is_manual_input_enabled()
        ):
            self.box.focus_input_cursor()

    def on_input_change(self, event: Optional[tk.Event] = None) -> None:
        self.box.set_projected_input(self.box.get_input())
        if self.box._on_input_change_callback:
            self.box._on_input_change_callback(event)

    def activate_for_manual_input(self, event: Optional[tk.Event] = None) -> None:
        self.box.set_manual_input_enabled(True)
        self.box.show(focus_input=True)

    def restore_from_standby(self, event: Optional[tk.Event] = None) -> None:
        if self.box._on_restore_from_standby:
            self.box._on_restore_from_standby()
        self.box.set_manual_input_enabled(True)
        self.box.show(focus_input=True)

    def on_ctrl_v(self, event: Optional[tk.Event] = None) -> str:
        self.paste_code_from_clipboard()
        return "break"

    def on_copy_input_shortcut(self, event: Optional[tk.Event] = None) -> str:
        self.box.copy_input_text()
        return "break"

    def on_confirm_key(self, event: Optional[tk.Event] = None) -> str:
        if self.should_allow_native_edit_key(event):
            return ""
        if self.box.current_candidates:
            self.select_candidate_by_index(0)
        else:
            self.commit_output_text()
        return "break"

    def on_digit_shortcut(self, event: Optional[tk.Event], value: int) -> str:
        if self.should_allow_native_edit_key(event):
            return ""
        self.select_candidate_by_index(value - 1)
        return "break"

    def on_previous_page_key(self, event: Optional[tk.Event] = None) -> str:
        self.box.show_previous_page()
        return "break"

    def on_next_page_key(self, event: Optional[tk.Event] = None) -> str:
        self.box.show_next_page()
        return "break"

    def on_page_size_change(self, event: Optional[tk.Event] = None) -> None:
        try:
            page_size = int(self.box.page_size_var.get())
        except (tk.TclError, ValueError):
            return
        self.box.set_page_size(page_size)

    def should_allow_native_edit_key(self, event: Optional[tk.Event]) -> bool:
        if not event:
            return False
        widget = getattr(event, "widget", None)
        return widget in {
            self.box.input_entry,
            self.box.commit_entry,
            self.box.page_size_spinbox,
        }

    def on_commit_backspace(self, event: Optional[tk.Event] = None) -> str:
        selection = self.box.commit_entry.selection_present()
        if self.box.commit_var.get() or selection:
            return ""
        self.box.remove_last_commit_char()
        return "break"

    def decode_from_clipboard(self) -> None:
        if self.box._on_decode_from_clipboard_callback:
            self.box._on_decode_from_clipboard_callback()

    def paste_code_from_clipboard(self) -> None:
        self.box.show(focus_input=True)
        self.decode_from_clipboard()

    def commit_output_text(self) -> None:
        text = self.box.get_commit_text().strip()
        if not text:
            self.box.set_status("待上屏文本为空。")
            return
        if self.box._on_commit_text_callback:
            self.box._on_commit_text_callback(text)
            self.box.set_status(f"已准备上屏: {text}")

    def copy_first_candidate(self) -> None:
        self.copy_candidate(0)

    def paste_first_candidate(self) -> None:
        self.select_candidate_by_index(0)

    def select_candidate_by_index(self, index: int) -> None:
        hanzi = self.box.get_candidate(index)
        if hanzi is None:
            return
        keep_focus = self.box.is_manual_input_enabled()
        self.box.append_commit_text(hanzi)
        self.box.on_select(hanzi)
        self.box.set_status(f"已加入待上屏文本: {self.box.get_commit_text()}")
        self.box.clear_input(focus_input=keep_focus)

    def copy_candidate(self, index: int) -> None:
        if self.box._on_copy_candidate_callback:
            self.box._on_copy_candidate_callback(index)

    def request_close(self) -> None:
        if self.box._on_close:
            self.box._on_close()
            return
        self.box.close()

    def request_hide(self) -> None:
        if self.box._on_hide:
            self.box._on_hide()
            return
        self.box.show_standby()
