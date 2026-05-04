"""
候选词渲染与分页混入(Mixin)模块
提取候选项的排版、渲染及翻页逻辑。
"""
import tkinter as tk
from tkinter import ttk
from typing import Callable, Optional

class CandidateRendererMixin:
    _DEFAULT_CANDIDATE_LAYOUT = "horizontal"

    def _normalize_candidate_layout(self, layout: str) -> str:
        return (
            "vertical"
            if layout.strip().lower() == "vertical"
            else self._DEFAULT_CANDIDATE_LAYOUT
        )

    def _on_previous_page_key(self, event: Optional[tk.Event] = None) -> str:
        return self.actions.on_previous_page_key(event)

    def _on_next_page_key(self, event: Optional[tk.Event] = None) -> str:
        return self.actions.on_next_page_key(event)

    def _on_page_size_change(self, event: Optional[tk.Event] = None) -> None:
        self.actions.on_page_size_change(event)

    def _page_size(self) -> int:
        try:
            return min(max(int(self.page_size_var.get()), 4), 9)
        except (tk.TclError, ValueError):
            return self.max_candidates

    def _page_count(self) -> int:
        page_size = self._page_size()
        if not self.all_candidates:
            return 1
        return max(1, (len(self.all_candidates) + page_size - 1) // page_size)

    def _create_pager_button(
        self,
        parent: ttk.Frame,
        *,
        text: str,
        command: Callable[[], None],
    ) -> ttk.Button:
        button = ttk.Button(
            parent,
            text=text,
            command=command,
            style="Yime.TButton",
            width=2,
        )
        return button

    def _sync_pager_button_layout(self) -> None:
        buttons = (
            self.first_page_button,
            self.prev_page_button,
            self.next_page_button,
            self.last_page_button,
        )

        self.pager_button_frame.pack_forget()
        for button in buttons:
            button.pack_forget()

        if self._candidate_layout == "vertical":
            self.pager_button_frame.pack(side=tk.RIGHT, fill=tk.Y, padx=(8, 0))
            for button in buttons:
                button.pack(fill=tk.X, pady=0)
            return

        self.pager_button_frame.pack(side=tk.RIGHT, fill=tk.Y, padx=(8, 0))
        for button in buttons:
            button.pack(side=tk.LEFT, padx=(0, 2))

    def _sync_candidate_text_layout(self) -> None:
        if self._candidate_layout == "vertical":
            visible_rows = max(1, len(self.current_candidates) + 1)
            self.candidate_text.pack_configure(fill=tk.BOTH, expand=True)
            self.candidate_text.configure(height=visible_rows, wrap=tk.WORD)
            return
        self.candidate_text.pack_configure(fill=tk.Y, expand=False)
        self.candidate_text.configure(
            height=1,
            width=self._horizontal_candidate_text_width_chars(),
            wrap=tk.NONE,
        )

    def _horizontal_candidate_text_width_chars(self) -> int:
        if not self.current_candidates:
            return 1
        display_width = 0
        for index, hanzi in enumerate(self.current_candidates, start=1):
            display_width += len(f"{index}. {hanzi}{self._horizontal_candidate_suffix()}")
        return max(display_width, 1)

    def _horizontal_candidate_suffix(self) -> str:
        return "  "

    def _refresh_paging_controls(self) -> None:
        page_count = self._page_count()
        current_page = min(self._current_page, page_count - 1)
        self._current_page = max(current_page, 0)
        total_candidates = len(self.all_candidates)
        page_size = self._page_size()
        start = 0 if total_candidates == 0 else self._current_page * page_size + 1
        end = min(total_candidates, (self._current_page + 1) * page_size)
        self.page_info_var.set(
            f"第 {self._current_page + 1}/{page_count} 页  候选 {start}-{end}/{total_candidates}"
        )
        first_prev_state = tk.NORMAL if self._current_page > 0 else tk.DISABLED
        next_last_state = tk.NORMAL if self._current_page < page_count - 1 else tk.DISABLED
        self.first_page_button.configure(state=first_prev_state)
        self.prev_page_button.configure(state=first_prev_state)
        self.next_page_button.configure(state=next_last_state)
        self.last_page_button.configure(state=next_last_state)

    def show_first_page(self) -> None:
        if self._current_page <= 0:
            return
        self._current_page = 0
        self._selected_candidate_index = 0
        self._render_candidates()

    def show_previous_page(self) -> None:
        if self._current_page <= 0:
            return
        self._current_page -= 1
        self._selected_candidate_index = 0
        self._render_candidates()

    def show_next_page(self) -> None:
        if self._current_page >= self._page_count() - 1:
            return
        self._current_page += 1
        self._selected_candidate_index = 0
        self._render_candidates()

    def show_last_page(self) -> None:
        page_count = self._page_count()
        if self._current_page >= page_count - 1:
            return
        self._current_page = page_count - 1
        self._selected_candidate_index = 0
        self._render_candidates()

    def set_page_size(self, page_size: int) -> None:
        """设置每页候选数量，并回到第一页重新渲染。"""
        normalized = min(max(page_size, 4), 9)
        self.page_size_var.set(normalized)
        self.max_candidates = normalized
        self._current_page = 0
        self._selected_candidate_index = 0
        self._render_candidates()

    def set_candidate_layout(self, layout: str) -> None:
        """切换候选显示方向；默认横排，可切换回竖排。"""
        normalized = self._normalize_candidate_layout(layout)
        if self._candidate_layout == normalized:
            return
        self._candidate_layout = normalized
        self._sync_pager_button_layout()
        self._render_candidates()

    def is_manual_input_active(self) -> bool:
        """候选框获得焦点时，允许输入框自行处理逐码编辑。"""
        if self._is_standby:
            return False
        if not self._manual_input_enabled:
            return False
        try:
            focused = self.root.focus_get()
        except tk.TclError:
            return False
        return focused in {
            self.input_entry,
            self.commit_entry,
            self.candidate_text,
        }

    def _should_allow_native_edit_key(self, event: Optional[tk.Event]) -> bool:
        """编辑区聚焦时，保留本地输入控件的原生按键行为。"""
        return self.actions.should_allow_native_edit_key(event)

    def _configure_candidate_text_tags(self) -> None:
        selected_foreground = "#f8fafc"
        selected_background = "#2563eb"
        self.candidate_text.tag_configure(
            "candidate_index",
            foreground="#0b57d0",
            font=self.ui_font,
        )
        self.candidate_text.tag_configure(
            "candidate_text",
            foreground="#111827",
            font=self.text_font,
        )
        self.candidate_text.tag_configure(
            "candidate_selected_index",
            foreground=selected_foreground,
            background=selected_background,
            font=self.ui_font,
        )
        self.candidate_text.tag_configure(
            "candidate_selected_text",
            foreground=selected_foreground,
            background=selected_background,
            font=self.text_font,
        )
        self.candidate_text.tag_configure(
            "pager",
            foreground="#0b57d0",
            font=self.ui_font,
        )
        self.candidate_text.tag_configure(
            "pager_disabled",
            foreground="#9ca3af",
            font=self.ui_font,
        )
        self.candidate_text.tag_configure(
            "page_info",
            foreground="#6b7280",
            font=self.ui_font,
        )
        self.candidate_text.tag_configure(
            "empty_state",
            foreground="#6b7280",
            font=self.text_font,
        )

    def _bind_candidate_text_tag(
        self,
        tag: str,
        callback: Callable[[tk.Event], None],
        enabled: bool,
    ) -> None:
        self.candidate_text.tag_unbind(tag, "<Button-1>")
        self.candidate_text.tag_unbind(tag, "<Enter>")
        self.candidate_text.tag_unbind(tag, "<Leave>")
        if not enabled:
            return
        self.candidate_text.tag_bind(tag, "<Button-1>", callback)
        self.candidate_text.tag_bind(
            tag,
            "<Enter>",
            lambda _event: self.candidate_text.configure(cursor="hand2"),
        )
        self.candidate_text.tag_bind(
            tag,
            "<Leave>",
            lambda _event: self.candidate_text.configure(cursor="arrow"),
        )

    def _render_candidate_text_item(self, index: int, hanzi: str) -> None:
        candidate_tag = f"{self._CANDIDATE_TAG_PREFIX}{index}"
        index_tags = ["candidate_index", candidate_tag]
        text_tags = ["candidate_text", candidate_tag]
        if index == self._selected_candidate_index:
            index_tags.insert(0, "candidate_selected_index")
            text_tags.insert(0, "candidate_selected_text")
        self.candidate_text.insert(
            tk.END,
            f"{index + 1}. ",
            tuple(index_tags),
        )
        suffix = "\n" if self._candidate_layout == "vertical" else self._horizontal_candidate_suffix()
        self.candidate_text.insert(
            tk.END,
            f"{hanzi}{suffix}",
            tuple(text_tags),
        )
        self._bind_candidate_text_tag(
            candidate_tag,
            lambda _event, value=index: self._click_candidate_by_index(value),
            enabled=True,
        )

    def _render_candidates(self) -> None:
        """渲染候选词"""
        page_size = self._page_size()
        page_count = self._page_count()
        self._current_page = min(self._current_page, page_count - 1)
        start = self._current_page * page_size
        end = start + page_size
        self.current_candidates = self.all_candidates[start:end]
        if self.current_candidates:
            self._selected_candidate_index = min(
                self._selected_candidate_index,
                len(self.current_candidates) - 1,
            )
        else:
            self._selected_candidate_index = 0

        self._refresh_paging_controls()
        self._sync_candidate_text_layout()
        self.candidate_text.configure(state=tk.NORMAL)
        self.candidate_text.delete("1.0", tk.END)
        self.candidate_text.configure(cursor="arrow")

        # 如果没有候选词
        if not self.current_candidates:
            self._bind_candidate_text_tag(
                self._PAGER_PREV_TAG,
                lambda _event: None,
                enabled=False,
            )
            self._bind_candidate_text_tag(
                self._PAGER_NEXT_TAG,
                lambda _event: None,
                enabled=False,
            )
            self.candidate_text.configure(state=tk.DISABLED)
            return

        # 显示候选词和内嵌翻页控件
        for index, hanzi in enumerate(self.current_candidates, start=1):
            self._render_candidate_text_item(index - 1, hanzi)
        if self._candidate_layout == "vertical":
            self.candidate_text.insert(tk.END, self.page_info_var.get(), ("page_info",))
        self.candidate_text.configure(state=tk.DISABLED)

