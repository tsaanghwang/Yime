from __future__ import annotations

import tkinter as tk
from typing import TYPE_CHECKING, Optional

if TYPE_CHECKING:
    from .candidate_box import CandidateBox


class CandidateBoxActions:
    """Event and command handlers for CandidateBox."""

    _SYMBOL_SHORTCUT_BINDINGS = {
        "<grave>": 1,
        "<minus>": 2,
        "<equal>": 3,
        "<backslash>": 4,
    }

    _SYMBOL_SHORTCUT_TO_INDEX = {
        "`": 1,
        "-": 2,
        "=": 3,
        "\\": 4,
    }

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
        self.box.root.bind("<Home>", self.on_first_page_key)
        self.box.root.bind("<Prior>", self.on_previous_page_key)
        self.box.root.bind("<Next>", self.on_next_page_key)
        self.box.root.bind("<End>", self.on_last_page_key)
        self.box.root.bind("<Left>", self.on_move_selection_previous)
        self.box.root.bind("<Right>", self.on_move_selection_next)
        self.box.root.bind("<Up>", self.on_move_selection_previous)
        self.box.root.bind("<Down>", self.on_move_selection_next)
        self.box.root.bind("<FocusIn>", self.on_window_focus_in)
        self.box.input_entry.bind("<Home>", self.on_first_page_key)
        self.box.input_entry.bind("<Prior>", self.on_previous_page_key)
        self.box.input_entry.bind("<Next>", self.on_next_page_key)
        self.box.input_entry.bind("<End>", self.on_last_page_key)
        self.box.input_entry.bind("<Left>", self.on_move_selection_previous)
        self.box.input_entry.bind("<Right>", self.on_move_selection_next)
        self.box.input_entry.bind("<Up>", self.on_move_selection_previous)
        self.box.input_entry.bind("<Down>", self.on_move_selection_next)
        self.box.commit_entry.bind("<Home>", self.on_first_page_key)
        self.box.commit_entry.bind("<Prior>", self.on_previous_page_key)
        self.box.commit_entry.bind("<Next>", self.on_next_page_key)
        self.box.commit_entry.bind("<End>", self.on_last_page_key)
        self.box.commit_entry.bind("<Left>", self.on_move_selection_previous)
        self.box.commit_entry.bind("<Right>", self.on_move_selection_next)
        self.box.commit_entry.bind("<Up>", self.on_move_selection_previous)
        self.box.commit_entry.bind("<Down>", self.on_move_selection_next)

        for widget in (self.box.root, self.box.input_entry, self.box.commit_entry):
            for sequence, index in self._SYMBOL_SHORTCUT_BINDINGS.items():
                widget.bind(
                    sequence,
                    lambda event, value=index: self.on_candidate_shortcut(event, value),
                )

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
            return
        self.box.set_manual_input_enabled(True)
        self.box.show(focus_input=True)

    def on_confirm_key(self, event: Optional[tk.Event] = None) -> str:
        if self.box.current_candidates:
            self.select_candidate_by_index(self.box.get_selected_candidate_index())
            self.commit_output_text()
        else:
            self.commit_output_text()
        return "break"

    def on_digit_shortcut(self, event: Optional[tk.Event], value: int) -> str:
        if self.should_allow_native_edit_key(event):
            return ""
        self.select_candidate_by_index(value - 1)
        return "break"

    def on_candidate_shortcut(self, event: Optional[tk.Event], index: int) -> str:
        self.select_candidate_by_index(index)
        self.commit_output_text()
        return "break"

    def on_candidate_click(self, index: int) -> None:
        self.select_candidate_by_index(index)
        self.commit_output_text()

    def on_move_selection_previous(self, event: Optional[tk.Event] = None) -> str:
        if not self.box.current_candidates:
            return ""
        self.box.move_selection(-1)
        return "break"

    def on_move_selection_next(self, event: Optional[tk.Event] = None) -> str:
        if not self.box.current_candidates:
            return ""
        self.box.move_selection(1)
        return "break"

    def on_symbol_shortcut_key(self, event: Optional[tk.Event] = None) -> Optional[str]:
        if not event:
            return None
        shortcut = getattr(event, "char", "")
        index = self._SYMBOL_SHORTCUT_TO_INDEX.get(shortcut)
        if index is None:
            return None
        return self.on_candidate_shortcut(event, index)

    def on_previous_page_key(self, event: Optional[tk.Event] = None) -> str:
        self.box.show_previous_page()
        return "break"

    def on_next_page_key(self, event: Optional[tk.Event] = None) -> str:
        self.box.show_next_page()
        return "break"

    def on_first_page_key(self, event: Optional[tk.Event] = None) -> str:
        self.box.show_first_page()
        return "break"

    def on_last_page_key(self, event: Optional[tk.Event] = None) -> str:
        self.box.show_last_page()
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
            self.box.candidate_text,
        }

    def on_commit_backspace(self, event: Optional[tk.Event] = None) -> str:
        selection = self.box.commit_entry.selection_present()
        if self.box.commit_var.get() or selection:
            return ""
        self.box.remove_last_commit_char()
        return "break"

    def commit_output_text(self) -> None:
        text = self.box.get_commit_text().strip()
        if not text:
            self.box.set_status("缓冲区为空。")
            return
        if self.box._on_commit_text_callback:
            self.box._on_commit_text_callback(text)
            self.box.set_status(f"已发送缓冲区内容: {text}")

    def select_candidate_by_index(self, index: int) -> None:
        hanzi = self.box.get_candidate(index)
        if hanzi is None:
            return
        keep_focus = self.box.is_manual_input_enabled()
        self.box.append_commit_text(hanzi)
        self.box.on_select(hanzi)
        self.box.clear_input(focus_input=keep_focus)
        self.box.set_status(f"已加入缓冲区: {self.box.get_commit_text()}")

    def copy_candidate(self, index: int) -> None:
        if self.box._on_copy_candidate_callback:
            self.box._on_copy_candidate_callback(index)

    def request_close(self) -> None:
        if self.box._on_close:
            self.box._on_close()
            return
        self.box.close()
