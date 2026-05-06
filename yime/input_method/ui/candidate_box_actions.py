from __future__ import annotations

import re
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, simpledialog
from typing import TYPE_CHECKING, Optional

if TYPE_CHECKING:
    from .candidate_box import CandidateBox


class CandidateBoxActions:
    """Event and command handlers for CandidateBox."""

    _HELP_DOC_PATH = Path(__file__).resolve().parents[3] / "docs" / "USER_HELP.md"

    _FOREGROUND_COLOR_OPTIONS = (
        ("默认前景", "#111827"),
        ("石墨黑", "#111827"),
        ("靛青蓝", "#1d4ed8"),
        ("墨绿色", "#166534"),
        ("赤陶棕", "#9a3412"),
        ("紫檀色", "#6d28d9"),
    )
    _BACKGROUND_COLOR_OPTIONS = (
        ("默认背景", "#f0f0f0"),
        ("云雾灰", "#f0f0f0"),
        ("米白", "#f7f3e8"),
        ("浅青灰", "#e8f1ef"),
        ("淡蓝灰", "#eaf0f8"),
        ("浅杏色", "#f8eee6"),
    )

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
        self._toolbar_menu: Optional[tk.Menu] = None
        self._settings_menu: Optional[tk.Menu] = None
        self._candidate_list_menu: Optional[tk.Menu] = None
        self._interaction_menu: Optional[tk.Menu] = None
        self._wake_mode_menu: Optional[tk.Menu] = None
        self._standby_mode_menu: Optional[tk.Menu] = None
        self._appearance_menu: Optional[tk.Menu] = None
        self._font_scale_menu: Optional[tk.Menu] = None
        self._alpha_menu: Optional[tk.Menu] = None
        self._foreground_color_menu: Optional[tk.Menu] = None
        self._background_color_menu: Optional[tk.Menu] = None
        self._tools_menu: Optional[tk.Menu] = None
        self._user_lexicon_menu: Optional[tk.Menu] = None
        self._user_lexicon_edit_reload_menu: Optional[tk.Menu] = None
        self._user_lexicon_import_export_menu: Optional[tk.Menu] = None

    def _emit_feedback(
        self,
        title: str,
        message: str,
        *,
        level: str = "info",
        dialog: bool = False,
    ) -> None:
        feedback_callback = getattr(self.box, "feedback_callback", None)
        if callable(feedback_callback):
            try:
                feedback_callback(title, message, level=level, dialog=dialog)
            except TypeError:
                feedback_callback(title, message)
            return
        if level == "warning":
            messagebox.showwarning(title, message, parent=self.box.root)
            return
        if level == "error":
            messagebox.showerror(title, message, parent=self.box.root)
            return
        messagebox.showinfo(title, message, parent=self.box.root)

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
        if hasattr(self.box, "toolbar_menu_button") and self.box.toolbar_menu_button:
            self.box.toolbar_menu_button.bind("<Button-1>", self.show_toolbar_menu)

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

    def show_toolbar_menu(self, event: Optional[tk.Event] = None) -> str:
        menu = self._get_toolbar_menu()
        if event is not None:
            x_root = event.x_root
            y_root = event.y_root
        else:
            widget = getattr(self.box, "toolbar_menu_button", None)
            if widget is None:
                return "break"
            x_root = widget.winfo_rootx()
            y_root = widget.winfo_rooty() + widget.winfo_height()

        menu.tk_popup(x_root, y_root)
        menu.grab_release()
        return "break"

    def _get_toolbar_menu(self) -> tk.Menu:
        if self._toolbar_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            menu.add_cascade(label="设置", menu=self._get_settings_menu())
            menu.add_cascade(label="工具", menu=self._get_tools_menu())
            menu.add_command(label="帮助", command=self.show_help)
            menu.add_command(label="关于", command=self.show_about)
            self._toolbar_menu = menu
        return self._toolbar_menu

    def _get_settings_menu(self) -> tk.Menu:
        if self._settings_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            menu.add_cascade(label="候选列表", menu=self._get_candidate_list_menu())
            menu.add_cascade(label="交互", menu=self._get_interaction_menu())
            menu.add_cascade(label="外观", menu=self._get_appearance_menu())
            self._settings_menu = menu
        return self._settings_menu

    def _get_candidate_list_menu(self) -> tk.Menu:
        if self._candidate_list_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            for page_size in range(5, 10):
                menu.add_radiobutton(
                    label=f"每页 {page_size} 个",
                    value=page_size,
                    variable=self.box.page_size_var,
                    command=lambda value=page_size: self.set_candidate_page_size(value),
                )
            menu.add_separator()
            menu.add_radiobutton(
                label="横排显示",
                value="horizontal",
                variable=self.box.candidate_layout_var,
                command=lambda: self.set_candidate_layout("horizontal"),
            )
            menu.add_radiobutton(
                label="竖排显示",
                value="vertical",
                variable=self.box.candidate_layout_var,
                command=lambda: self.set_candidate_layout("vertical"),
            )
            self._candidate_list_menu = menu
        return self._candidate_list_menu

    def _get_interaction_menu(self) -> tk.Menu:
        if self._interaction_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            menu.add_command(label=self._current_hotkey_menu_label(), command=self.show_hotkey_info)
            menu.add_command(label="修改热键", command=self.edit_hotkey)
            menu.add_separator()
            menu.add_cascade(label="唤起方式", menu=self._get_wake_mode_menu())
            menu.add_cascade(label="休眠方式", menu=self._get_standby_mode_menu())
            self._interaction_menu = menu
        return self._interaction_menu

    def _current_hotkey_label(self) -> str:
        callback = getattr(self.box, "hotkey_label_callback", None)
        label = callback() if callable(callback) else None
        if isinstance(label, str) and label.strip():
            return label.strip()

        summary_callback = getattr(self.box, "hotkey_summary_callback", None)
        summary = summary_callback() if callable(summary_callback) else None
        if isinstance(summary, str):
            first_line = summary.strip().splitlines()[0] if summary.strip() else ""
            for separator in ("：", ":"):
                if separator in first_line:
                    value = first_line.split(separator, 1)[1].strip()
                    if value:
                        return value
        return "未配置"

    def _current_hotkey_menu_label(self) -> str:
        return f"当前唤起热键：{self._current_hotkey_label()}"

    def _invalidate_toolbar_menus(self) -> None:
        self._interaction_menu = None
        self._settings_menu = None
        self._toolbar_menu = None

    def _get_wake_mode_menu(self) -> tk.Menu:
        if self._wake_mode_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            menu.add_radiobutton(
                label="仅热键",
                value="hotkey",
                variable=self.box.wake_trigger_mode_var,
                command=lambda: self.set_wake_trigger_mode("hotkey"),
            )
            menu.add_radiobutton(
                label="仅鼠标",
                value="mouse",
                variable=self.box.wake_trigger_mode_var,
                command=lambda: self.set_wake_trigger_mode("mouse"),
            )
            menu.add_radiobutton(
                label="热键 + 鼠标",
                value="both",
                variable=self.box.wake_trigger_mode_var,
                command=lambda: self.set_wake_trigger_mode("both"),
            )
            self._wake_mode_menu = menu
        return self._wake_mode_menu

    def _get_standby_mode_menu(self) -> tk.Menu:
        if self._standby_mode_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            menu.add_radiobutton(
                label="仅热键",
                value="hotkey",
                variable=self.box.standby_trigger_mode_var,
                command=lambda: self.set_standby_trigger_mode("hotkey"),
            )
            menu.add_radiobutton(
                label="仅鼠标",
                value="mouse",
                variable=self.box.standby_trigger_mode_var,
                command=lambda: self.set_standby_trigger_mode("mouse"),
            )
            menu.add_radiobutton(
                label="热键 + 鼠标",
                value="both",
                variable=self.box.standby_trigger_mode_var,
                command=lambda: self.set_standby_trigger_mode("both"),
            )
            self._standby_mode_menu = menu
        return self._standby_mode_menu

    def _get_appearance_menu(self) -> tk.Menu:
        if self._appearance_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            menu.add_cascade(label="前景颜色", menu=self._get_foreground_color_menu())
            menu.add_cascade(label="背景颜色", menu=self._get_background_color_menu())
            menu.add_cascade(label="字体大小", menu=self._get_font_scale_menu())
            menu.add_cascade(label="主界面透明度", menu=self._get_alpha_menu())
            menu.add_checkbutton(
                label="活动窗始终置顶",
                variable=self.box.active_topmost_var,
                command=self.toggle_active_topmost,
            )
            self._appearance_menu = menu
        return self._appearance_menu

    def _get_foreground_color_menu(self) -> tk.Menu:
        if self._foreground_color_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            for label, color in self._FOREGROUND_COLOR_OPTIONS:
                menu.add_radiobutton(
                    label=label,
                    value=color,
                    variable=self.box.foreground_color_var,
                    command=lambda value=color: self.set_foreground_color(value),
                )
            self._foreground_color_menu = menu
        return self._foreground_color_menu

    def _get_background_color_menu(self) -> tk.Menu:
        if self._background_color_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            for label, color in self._BACKGROUND_COLOR_OPTIONS:
                menu.add_radiobutton(
                    label=label,
                    value=color,
                    variable=self.box.background_color_var,
                    command=lambda value=color: self.set_background_color(value),
                )
            self._background_color_menu = menu
        return self._background_color_menu

    def _get_font_scale_menu(self) -> tk.Menu:
        if self._font_scale_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            for scale_percent, label in (
                (90, "紧凑 90%"),
                (100, "标准 100%"),
                (110, "稍大 110%"),
                (120, "更大 120%"),
            ):
                menu.add_radiobutton(
                    label=label,
                    value=scale_percent,
                    variable=self.box.ui_scale_var,
                    command=lambda value=scale_percent: self.set_ui_scale(value),
                )
            self._font_scale_menu = menu
        return self._font_scale_menu

    def _get_alpha_menu(self) -> tk.Menu:
        if self._alpha_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            for alpha_percent in (85, 92, 97):
                menu.add_radiobutton(
                    label=f"{alpha_percent}%",
                    value=alpha_percent,
                    variable=self.box.active_alpha_var,
                    command=lambda value=alpha_percent: self.set_active_alpha(value),
                )
            self._alpha_menu = menu
        return self._alpha_menu

    def _get_tools_menu(self) -> tk.Menu:
        if self._tools_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            menu.add_cascade(label="用户词库", menu=self._get_user_lexicon_menu())
            self._tools_menu = menu
        return self._tools_menu

    def _get_user_lexicon_menu(self) -> tk.Menu:
        if self._user_lexicon_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            menu.add_command(label="加入当前词条", command=self.add_current_input_to_user_lexicon)
            menu.add_command(label="删除当前词条", command=self.delete_current_input_from_user_lexicon)
            menu.add_separator()
            menu.add_cascade(label="编辑与重载", menu=self._get_user_lexicon_edit_reload_menu())
            menu.add_cascade(label="导入与导出", menu=self._get_user_lexicon_import_export_menu())
            self._user_lexicon_menu = menu
        return self._user_lexicon_menu

    def _get_user_lexicon_edit_reload_menu(self) -> tk.Menu:
        if self._user_lexicon_edit_reload_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            menu.add_command(label="编辑用户词库", command=self.edit_user_lexicon)
            menu.add_command(label="应用用户词库", command=self.reload_user_lexicon)
            self._user_lexicon_edit_reload_menu = menu
        return self._user_lexicon_edit_reload_menu

    def _get_user_lexicon_import_export_menu(self) -> tk.Menu:
        if self._user_lexicon_import_export_menu is None:
            menu = tk.Menu(self.box.root, tearoff=False)
            menu.add_command(label="导入用户词库", command=self.import_user_lexicon)
            menu.add_command(label="导出用户词库", command=self.export_user_lexicon)
            self._user_lexicon_import_export_menu = menu
        return self._user_lexicon_import_export_menu

    def set_candidate_page_size(self, page_size: int) -> None:
        callback = getattr(self.box, "candidate_page_size_change_callback", None)
        if callable(callback) and callback(page_size):
            normalized = self.box.page_size_var.get()
        else:
            self.box.set_page_size(page_size)
            normalized = self.box.page_size_var.get()
        self._set_local_status(f"候选列表已设为每页 {normalized} 个。")

    def set_candidate_layout(self, layout: str) -> None:
        callback = getattr(self.box, "candidate_layout_change_callback", None)
        if callable(callback) and callback(layout):
            normalized = self.box.candidate_layout_var.get()
        else:
            self.box.set_candidate_layout(layout)
            normalized = self.box.candidate_layout_var.get()
        label = "竖排" if normalized == "vertical" else "横排"
        self._set_local_status(f"候选列表已切换为{label}。")

    def set_wake_trigger_mode(self, mode: str) -> None:
        callback = getattr(self.box, "wake_trigger_mode_change_callback", None)
        if callable(callback) and callback(mode):
            normalized = self.box.wake_trigger_mode_var.get()
        else:
            normalized = mode
            self.box.wake_trigger_mode_var.set(mode)
        label = self._trigger_mode_label(normalized)
        self._set_local_status(f"唤起方式已设为{label}。")

    def set_standby_trigger_mode(self, mode: str) -> None:
        callback = getattr(self.box, "standby_trigger_mode_change_callback", None)
        if callable(callback) and callback(mode):
            normalized = self.box.standby_trigger_mode_var.get()
        else:
            normalized = mode
            self.box.standby_trigger_mode_var.set(mode)
        label = self._trigger_mode_label(normalized)
        self._set_local_status(f"休眠方式已设为{label}。")

    def _trigger_mode_label(self, mode: str) -> str:
        if mode == "hotkey":
            return "仅热键"
        if mode == "mouse":
            return "仅鼠标"
        return "热键 + 鼠标"

    def set_ui_scale(self, scale_percent: int) -> None:
        callback = getattr(self.box, "ui_scale_change_callback", None)
        if callable(callback) and callback(scale_percent):
            normalized = int(self.box.ui_scale_var.get())
        else:
            self.box.set_ui_scale(scale_percent)
            normalized = int(self.box.ui_scale_var.get())
        self._set_local_status(f"字体大小已设为 {normalized}% 。")

    def set_active_alpha(self, alpha_percent: int) -> None:
        callback = getattr(self.box, "active_alpha_change_callback", None)
        if callable(callback) and callback(alpha_percent):
            normalized = int(self.box.active_alpha_var.get())
        else:
            self.box.set_active_alpha_percent(alpha_percent)
            normalized = int(self.box.active_alpha_var.get())
        self._set_local_status(f"主界面透明度已设为 {normalized}% 。")

    def set_foreground_color(self, color: str) -> None:
        callback = getattr(self.box, "foreground_color_change_callback", None)
        if callable(callback) and callback(color):
            normalized = str(self.box.foreground_color_var.get())
        else:
            self.box.set_foreground_color(color)
            normalized = str(self.box.foreground_color_var.get())
        self._set_local_status(f"前景颜色已设为{self._foreground_color_label(normalized)}。")

    def set_background_color(self, color: str) -> None:
        callback = getattr(self.box, "background_color_change_callback", None)
        if callable(callback) and callback(color):
            normalized = str(self.box.background_color_var.get())
        else:
            self.box.set_background_color(color)
            normalized = str(self.box.background_color_var.get())
        self._set_local_status(f"背景颜色已设为{self._background_color_label(normalized)}。")

    def toggle_active_topmost(self) -> None:
        enabled = bool(self.box.active_topmost_var.get())
        callback = getattr(self.box, "active_topmost_change_callback", None)
        if callable(callback) and callback(enabled):
            enabled = bool(self.box.active_topmost_var.get())
        else:
            self.box.set_active_topmost_enabled(enabled)
        self._set_local_status(f"活动窗置顶已{'开启' if enabled else '关闭'}。")

    def _foreground_color_label(self, color: str) -> str:
        for label, value in self._FOREGROUND_COLOR_OPTIONS:
            if value == color:
                return label
        return color

    def _background_color_label(self, color: str) -> str:
        for label, value in self._BACKGROUND_COLOR_OPTIONS:
            if value == color:
                return label
        return color

    def reload_user_lexicon(self) -> None:
        callback = getattr(self.box, "reload_user_lexicon_callback", None)
        if callable(callback) and callback():
            return
        self._emit_feedback("用户词库", "当前未配置用户词库应用入口。")

    def edit_user_lexicon(self) -> None:
        callback = getattr(self.box, "edit_user_lexicon_callback", None)
        if callable(callback) and callback():
            return
        self._emit_feedback("用户词库", "当前未配置用户词库编辑入口。")

    def open_user_data_dir(self) -> None:
        callback = getattr(self.box, "open_user_data_dir_callback", None)
        if callable(callback) and callback():
            return
        self._emit_feedback("设置文件", "当前未配置设置文件入口。")

    def import_user_lexicon(self) -> None:
        callback = getattr(self.box, "import_user_lexicon_callback", None)
        if callable(callback) and callback():
            return
        self._emit_feedback("用户词库", "当前未配置用户词库导入入口。")

    def export_user_lexicon(self) -> None:
        callback = getattr(self.box, "export_user_lexicon_callback", None)
        if callable(callback) and callback():
            return
        self._emit_feedback("用户词库", "当前未配置用户词库导出入口。")

    def show_hotkey_info(self) -> None:
        callback = getattr(self.box, "hotkey_summary_callback", None)
        summary = callback() if callable(callback) else None
        if not summary:
            summary = "当前未提供快捷键信息。"
        self._emit_feedback("快捷键", summary)

    def edit_hotkey(self) -> None:
        current_hotkey = self._current_hotkey_label()
        updated_hotkey = simpledialog.askstring(
            "修改热键",
            "请输入新的唤起热键，例如 Ctrl+Alt+Insert。",
            initialvalue=current_hotkey,
            parent=self.box.root,
        )
        if updated_hotkey is None:
            return

        callback = getattr(self.box, "hotkey_change_callback", None)
        if not callable(callback):
            self._emit_feedback("快捷键", "当前未配置热键修改入口。")
            return
        if not callback(updated_hotkey):
            return

        self._invalidate_toolbar_menus()
        self._set_local_status(f"唤起热键已改为{self._current_hotkey_label()}。")

    @classmethod
    def _load_help_document_text(cls) -> str:
        try:
            raw_text = cls._HELP_DOC_PATH.read_text(encoding="utf-8")
        except OSError:
            return (
                "当前推荐入口：python -m yime.input_method.app 或 python run_input_method.py。\n\n"
                "基本操作：数字键选词，Space/Enter 上屏，Home/PgUp/PgDn/End 翻页，Ctrl+Q 关闭窗口。\n\n"
                "用户词库：可通过编辑、应用、导入、导出几个入口维护。\n\n"
                "更多说明请查看 docs/USER_HELP.md。"
            )

        lines: list[str] = []
        in_code_block = False
        for raw_line in raw_text.splitlines():
            stripped = raw_line.strip()
            if stripped.startswith("```"):
                in_code_block = not in_code_block
                continue
            if in_code_block:
                lines.append(stripped)
                continue

            line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", stripped)
            if line.startswith("#"):
                line = line.lstrip("#").strip()
            lines.append(line)

        normalized_lines: list[str] = []
        previous_blank = False
        for line in lines:
            is_blank = line == ""
            if is_blank and previous_blank:
                continue
            normalized_lines.append(line)
            previous_blank = is_blank

        return "\n".join(normalized_lines).strip()

    def show_help(self) -> None:
        callback = getattr(self.box, "hotkey_summary_callback", None)
        summary = callback() if callable(callback) else None
        message = self._load_help_document_text()
        if summary:
            message = f"{message}\n\n{summary}"
        self._emit_feedback(
            "帮助",
            message,
            dialog=True,
        )

    def show_about(self) -> None:
        self._emit_feedback(
            "关于",
            "音元拼音输入法当前使用轻量候选窗界面。这个菜单入口用于集中承载设置、帮助和后续扩展功能。",
            dialog=True,
        )

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
