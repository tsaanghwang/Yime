from __future__ import annotations

import tkinter as tk
from tkinter import messagebox
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
        self._input_context_menu: Optional[tk.Menu] = None

    def _emit_feedback(self, title: str, message: str) -> None:
        feedback_callback = getattr(self.box, "feedback_callback", None)
        if callable(feedback_callback):
            feedback_callback(title, message)
            return
        messagebox.showinfo("音元拼音", message, parent=self.box.root)

    def _set_local_status(self, message: str) -> None:
        self.box.set_status(message)

    def bind_keys(self) -> None:
        def bind_if_possible(widget: object, sequence: str, handler: object) -> None:
            binder = getattr(widget, "bind", None)
            if callable(binder):
                binder(sequence, handler)

        def candidate_shortcut_handler(index: int):
            def handler(event: Optional[tk.Event] = None) -> str:
                return self.on_candidate_shortcut(event, index)
            return handler

        for index in range(1, 10):
            self.box.root.bind(
                str(index),
                lambda event, value=index: self.on_digit_shortcut(event, value),
            )

        self.box.root.bind("<Return>", self.on_confirm_key)
        manual_input_keypress_handler = getattr(self.box, "_on_manual_input_key_press", None)
        bind_if_possible(self.box.input_entry, "<KeyPress>", manual_input_keypress_handler)
        bind_if_possible(self.box.input_entry, "<KeyRelease>", self.on_input_change)
        bind_if_possible(self.box.input_entry, "<<Paste>>", self.on_paste)
        bind_if_possible(self.box.input_entry, "<Shift-Insert>", self.on_paste)
        bind_if_possible(self.box.input_entry, "<Button-3>", self.show_input_context_menu)
        bind_if_possible(self.box.input_entry, "<Return>", self.on_confirm_key)
        bind_if_possible(self.box.commit_entry, "<Return>", self.on_confirm_key)
        bind_if_possible(self.box.candidate_text, "<Return>", self.on_confirm_key)
        self.box.root.bind("<space>", self.on_confirm_key)
        bind_if_possible(self.box.input_entry, "<space>", self.on_confirm_key)
        bind_if_possible(self.box.commit_entry, "<space>", self.on_confirm_key)
        bind_if_possible(self.box.candidate_text, "<space>", self.on_confirm_key)

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
        bind_if_possible(self.box.input_entry, "<Home>", self.on_first_page_key)
        bind_if_possible(self.box.input_entry, "<Prior>", self.on_previous_page_key)
        bind_if_possible(self.box.input_entry, "<Next>", self.on_next_page_key)
        bind_if_possible(self.box.input_entry, "<End>", self.on_last_page_key)
        bind_if_possible(self.box.input_entry, "<Left>", self.on_move_selection_previous)
        bind_if_possible(self.box.input_entry, "<Right>", self.on_move_selection_next)
        bind_if_possible(self.box.input_entry, "<Up>", self.on_move_selection_previous)
        bind_if_possible(self.box.input_entry, "<Down>", self.on_move_selection_next)
        bind_if_possible(self.box.commit_entry, "<Home>", self.on_first_page_key)
        bind_if_possible(self.box.commit_entry, "<Prior>", self.on_previous_page_key)
        bind_if_possible(self.box.commit_entry, "<Next>", self.on_next_page_key)
        bind_if_possible(self.box.commit_entry, "<End>", self.on_last_page_key)
        bind_if_possible(self.box.commit_entry, "<Left>", self.on_move_selection_previous)
        bind_if_possible(self.box.commit_entry, "<Right>", self.on_move_selection_next)
        bind_if_possible(self.box.commit_entry, "<Up>", self.on_move_selection_previous)
        bind_if_possible(self.box.commit_entry, "<Down>", self.on_move_selection_next)
        bind_if_possible(self.box.candidate_text, "<Home>", self.on_first_page_key)
        bind_if_possible(self.box.candidate_text, "<Prior>", self.on_previous_page_key)
        bind_if_possible(self.box.candidate_text, "<Next>", self.on_next_page_key)
        bind_if_possible(self.box.candidate_text, "<End>", self.on_last_page_key)
        bind_if_possible(self.box.candidate_text, "<Left>", self.on_move_selection_previous)
        bind_if_possible(self.box.candidate_text, "<Right>", self.on_move_selection_next)
        bind_if_possible(self.box.candidate_text, "<Up>", self.on_move_selection_previous)
        bind_if_possible(self.box.candidate_text, "<Down>", self.on_move_selection_next)

        for widget in (self.box.root, self.box.input_entry, self.box.commit_entry):
            for sequence, index in self._SYMBOL_SHORTCUT_BINDINGS.items():
                bind_if_possible(
                    widget,
                    sequence,
                    candidate_shortcut_handler(index),
                )

        # Bind mouse clicks to the UI pager controls
        if hasattr(self.box, "first_page_button") and self.box.first_page_button:
            self.box.first_page_button.bind("<Button-1>", lambda e: self.on_first_page_key())
        if hasattr(self.box, "prev_button") and self.box.prev_button:
            self.box.prev_button.bind("<Button-1>", lambda e: self.on_previous_page_key())
        if hasattr(self.box, "next_button") and self.box.next_button:
            self.box.next_button.bind("<Button-1>", lambda e: self.on_next_page_key())
        if hasattr(self.box, "last_page_button") and self.box.last_page_button:
            self.box.last_page_button.bind("<Button-1>", lambda e: self.on_last_page_key())

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
        notify_input_change = getattr(self.box, "notify_input_change", None)
        if callable(notify_input_change):
            notify_input_change(event)
            return
        callback = getattr(self.box, "_on_input_change_callback", None)
        if callable(callback):
            callback(event)

    def on_paste(self, event: Optional[tk.Event] = None) -> None:
        scheduler = getattr(getattr(self.box, "root", None), "after_idle", None)
        if callable(scheduler):
            scheduler(lambda: self.on_input_change(event))
            return
        self.on_input_change(event)

    def show_input_context_menu(self, event: Optional[tk.Event] = None) -> str:
        if not event:
            return "break"

        focus_set = getattr(self.box.input_entry, "focus_set", None)
        if callable(focus_set):
            focus_set()

        menu = self._get_input_context_menu()
        menu.tk_popup(event.x_root, event.y_root)
        menu.grab_release()
        return "break"

    def _get_input_context_menu(self) -> tk.Menu:
        if self._input_context_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            menu.add_command(
                label="粘贴",
                command=lambda: self.box.input_entry.event_generate("<<Paste>>"),
            )
            menu.add_command(
                label="复制",
                command=lambda: self.box.input_entry.event_generate("<<Copy>>"),
            )
            menu.add_command(
                label="全选",
                command=self.select_all_input_text,
            )
            menu.add_command(
                label="加入用户词库",
                command=self.add_current_input_to_user_lexicon,
            )
            menu.add_command(
                label="从用户词库中删除",
                command=self.delete_current_input_from_user_lexicon,
            )
            self._input_context_menu = menu
        return self._input_context_menu

    def select_all_input_text(self) -> None:
        selection_range = getattr(self.box.input_entry, "selection_range", None)
        if callable(selection_range):
            selection_range(0, tk.END)
        icursor = getattr(self.box.input_entry, "icursor", None)
        if callable(icursor):
            icursor(tk.END)
        focus_set = getattr(self.box.input_entry, "focus_set", None)
        if callable(focus_set):
            focus_set()

    def add_current_input_to_user_lexicon(self) -> None:
        callback = getattr(self.box, "add_input_to_user_lexicon_callback", None)
        if callable(callback) and callback():
            return
        legacy_callback = getattr(self.box, "_on_add_input_to_user_lexicon", None)
        if callable(legacy_callback):
            legacy_callback()
            return
        self._emit_feedback("用户词库", "当前未配置用户词库写入入口。")

    def delete_current_input_from_user_lexicon(self) -> None:
        callback = getattr(self.box, "delete_input_from_user_lexicon_callback", None)
        if callable(callback) and callback():
            return
        legacy_callback = getattr(self.box, "_on_delete_input_from_user_lexicon", None)
        if callable(legacy_callback):
            legacy_callback()
            return
        self._emit_feedback("用户词库", "当前未配置用户词库删除入口。")

    def activate_for_manual_input(self, event: Optional[tk.Event] = None) -> None:
        self.box.set_manual_input_enabled(True)
        self.box.show(focus_input=True)

    def restore_from_standby(self, event: Optional[tk.Event] = None) -> str:
        def restore() -> None:
            restore_callback = getattr(self.box, "restore_from_standby_callback", None)
            if callable(restore_callback) and restore_callback():
                return
            legacy_callback = getattr(self.box, "_on_restore_from_standby", None)
            if callable(legacy_callback):
                legacy_callback()
                return
            self.box.set_manual_input_enabled(True)
            self.box.show(focus_input=True)

        scheduler = getattr(getattr(self.box, "root", None), "after", None)
        if callable(scheduler):
            scheduler(0, restore)
        else:
            restore()

        return "break"

    def request_standby(self, event: Optional[tk.Event] = None) -> str:
        toggle_callback = getattr(self.box, "toggle_standby_callback", None)
        if callable(toggle_callback) and toggle_callback():
            return "break"
        legacy_callback = getattr(self.box, "_on_toggle_standby", None)
        if callable(legacy_callback):
            legacy_callback()
            return "break"
        self.box.show_standby()
        return "break"

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
        if self.select_candidate_by_index(value - 1):
            self.commit_output_text()
        return "break"

    def on_candidate_shortcut(self, event: Optional[tk.Event], index: int) -> str:
        if self.should_allow_native_edit_key(event):
            # Check if Focus is in Input entry, allowing typing if needed?
            # Oh wait, if these are NOT used as pinyin keys, maybe it should NOT type.
            pass

        if self.select_candidate_by_index(index):
            self.commit_output_text()
        return "break"

    def on_candidate_click(self, index: int) -> None:
        if self.select_candidate_by_index(index):
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
            self._set_local_status("缓冲区为空。")
            return
        commit_callback = getattr(self.box, "commit_text_callback", None)
        if callable(commit_callback) and commit_callback(text):
            self._set_local_status(f"已发送缓冲区内容: {text}")
            return
        legacy_callback = getattr(self.box, "_on_commit_text_callback", None)
        if callable(legacy_callback):
            legacy_callback(text)
            self._set_local_status(f"已发送缓冲区内容: {text}")

    def select_candidate_by_index(self, index: int) -> bool:
        hanzi = self.box.get_candidate(index)
        if hanzi is None:
            return False
        keep_focus = self.box.is_manual_input_enabled()
        self.box.append_commit_text(hanzi)
        self.box.on_select(hanzi)
        self.box.clear_input(focus_input=keep_focus)
        self._set_local_status(f"已加入缓冲区: {self.box.get_commit_text()}")
        return True

    def copy_candidate(self, index: int) -> None:
        copy_callback = getattr(self.box, "copy_candidate_callback", None)
        if callable(copy_callback):
            copy_callback(index)
            return
        legacy_callback = getattr(self.box, "_on_copy_candidate_callback", None)
        if callable(legacy_callback):
            legacy_callback(index)

    def request_close(self) -> None:
        close_callback = getattr(self.box, "close_callback", None)
        if callable(close_callback) and close_callback():
            return
        legacy_callback = getattr(self.box, "_on_close", None)
        if callable(legacy_callback):
            legacy_callback()
            return
        self.box.close()
