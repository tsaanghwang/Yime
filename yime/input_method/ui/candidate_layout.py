"""
候选框 UI 布局与控件管理模块
负责创建界面元素、配置字体/样式结构。
"""
from __future__ import annotations

import tkinter as tk
from tkinter import ttk
from tkinter import font as tkfont
from typing import Callable, cast


class CandidateLayoutBuilder:
    """封装候选框所需的内部控件、变量和字体初始化"""

    _DEFAULT_FOREGROUND_COLOR = "#111827"
    _DEFAULT_BACKGROUND_COLOR = "#f0f0f0"
    _DEFAULT_SECONDARY_FOREGROUND_COLOR = "#60a5fa"

    def __init__(self, root: tk.Tk, font_family: str):
        self.root = root
        self.font_family = self._resolve_font_family(font_family)
        self.foreground_color = self._DEFAULT_FOREGROUND_COLOR
        self.background_color = self._DEFAULT_BACKGROUND_COLOR

        self.ui_font: tkfont.Font
        self.text_font: tkfont.Font
        self.icon_font: tkfont.Font
        self.style: ttk.Style

        self.main_frame: ttk.Frame
        self.standby_frame: tk.Frame
        self.standby_icon: tk.Label

        self.input_var = tk.StringVar(self.root)
        self.input_entry: ttk.Entry

        self.commit_var = tk.StringVar(self.root, value="")
        self.commit_entry: ttk.Entry

        self.decode_info_frame: ttk.Frame
        self.pinyin_var = tk.StringVar(self.root, value="")
        self.pinyin_label: ttk.Label

        self.candidate_panel: ttk.Frame
        self.candidate_text: tk.Text

        self.pager_frame: ttk.Frame
        self.first_page_button: ttk.Label
        self.prev_button: ttk.Label
        self.next_button: ttk.Label
        self.last_page_button: ttk.Label
        self.toolbar_menu_button: ttk.Label

        self.manual_key_layout_label: ttk.Label

        self._configure_fonts()

    def _resolve_font_family(self, requested_family: str) -> str:
        available_families = set(tkfont.families(self.root))
        for candidate in (requested_family, "音元", "Noto Sans", "Noto Sans SC"):
            if candidate in available_families:
                return candidate
        return requested_family

    def _configure_fonts(self) -> None:
        self.ui_font = tkfont.Font(self.root, family=self.font_family, size=10)
        self.text_font = tkfont.Font(self.root, family=self.font_family, size=14)
        self.icon_font = tkfont.Font(
            self.root, family=self.font_family, size=16, weight="bold"
        )

        option_add = cast(Callable[[str, object], None], getattr(self.root, "option_add"))
        option_add("*Font", self.ui_font)
        for named_font in (
            "TkDefaultFont",
            "TkTextFont",
            "TkMenuFont",
            "TkHeadingFont",
            "TkCaptionFont",
            "TkSmallCaptionFont",
            "TkIconFont",
            "TkTooltipFont",
        ):
            try:
                tkfont.nametofont(named_font).configure(family=self.font_family)
            except tk.TclError:
                pass

        self.style = ttk.Style(self.root)
        self.style.configure(
            "Yime.TFrame",
            background=self.background_color,
        )
        self.style.configure(
            "Yime.TLabel",
            font=self.ui_font,
            foreground=self.foreground_color,
            background=self.background_color,
        )
        self.style.configure(
            "Yime.Text.TLabel",
            font=self.text_font,
            foreground=self.foreground_color,
            background=self.background_color,
        )
        self.style.configure(
            "Yime.AccentText.TLabel",
            font=self.text_font,
            foreground=self._DEFAULT_SECONDARY_FOREGROUND_COLOR,
            background=self.background_color,
        )
        self.style.configure(
            "Yime.Secondary.TLabel",
            font=self.ui_font,
            foreground=self._DEFAULT_SECONDARY_FOREGROUND_COLOR,
            background=self.background_color,
        )
        self.style.configure(
            "Yime.TButton",
            font=self.ui_font,
            foreground=self.foreground_color,
            background=self.background_color,
        )
        self.style.configure(
            "Yime.Candidate.TButton",
            font=self.text_font,
            foreground=self.foreground_color,
            background=self.background_color,
        )
        self.style.configure(
            "Yime.TEntry",
            font=self.text_font,
            foreground=self.foreground_color,
            fieldforeground=self.foreground_color,
            fieldbackground=self.background_color,
            background=self.background_color,
        )

    def build_ui(self) -> None:
        """构建UI界面并赋值给对应的属性"""
        # 主界面容器（正常输入模式下可见）
        self.root.configure(bg=self.background_color)

        self.main_frame = ttk.Frame(self.root, padding=(6, 12, 12, 12), style="Yime.TFrame")
        self.main_frame.pack(fill=tk.BOTH, expand=True)

        self.content_frame = ttk.Frame(self.main_frame, style="Yime.TFrame")
        self.content_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        # 待命状态容器（通常在不输入时，缩成右下角一个“音”字图标）
        self.standby_frame = tk.Frame(self.root, bg=self.background_color)
        self.standby_icon = tk.Label(
            self.standby_frame,
            text="音",
            bg=self.background_color,
            fg=self.foreground_color,
            font=self.icon_font,
            width=3,
            height=1,
            cursor="hand2",
        )
        self.standby_icon.pack(fill=tk.BOTH, expand=True)

        # 显式的用户编码主输入框
        self.input_entry = ttk.Entry(
            self.content_frame,
            textvariable=self.input_var,
            font=self.text_font,
            style="Yime.TEntry",
        )
        self.input_entry.pack(fill=tk.X, pady=(0, 8))
        self.input_entry.focus_set()

        # 隐藏的提交框：用于当焦点偏离主输入框，或者处理特定的快捷键回贴 / 焦点暂存时承接键入。
        # 注意它并没有调用 .pack()，所以在 UI 树中实际不可见
        self.commit_entry = ttk.Entry(
            self.content_frame,
            textvariable=self.commit_var,
            font=self.text_font,
            style="Yime.TEntry",
        )

        # 包含拼音反馈与候选词列表的信息框架
        self.decode_info_frame = ttk.Frame(self.content_frame, style="Yime.TFrame")
        self.decode_info_frame.pack(fill=tk.X, pady=(0, 8))

        # 隐藏/动态显示的规范拼音标签：只在有对应编码被成功解析成拼音时会借助 pinyin_var 出现文字
        self.pinyin_label = ttk.Label(
            self.decode_info_frame,
            textvariable=self.pinyin_var,
            style="Yime.AccentText.TLabel",
        )
        self.pinyin_label.pack(anchor=tk.W)

        self.candidate_panel = ttk.Frame(self.decode_info_frame, style="Yime.TFrame")
        self.candidate_panel.pack(fill=tk.X, pady=(4, 0))

        # 候选词列表文本框
        self.candidate_text = tk.Text(
            self.candidate_panel,
            height=1,
            wrap=tk.NONE,
            font=self.text_font,
            bg=self.background_color,
            fg=self.foreground_color,
            insertbackground=self.foreground_color,
            bd=0,
            highlightthickness=0,
            cursor="arrow",
        )
        self.candidate_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        # 取消Text控件本身的全部默认行为（阻止选中、阻止多余事件传播）
        self.candidate_text.bind("<1>", lambda e: "break")
        self.candidate_text.bind("<B1-Motion>", lambda e: "break")
        self.candidate_text.bind("<B1-Leave>", lambda e: "break")

        # 翻页按钮容器与四个翻页按钮
        self.pager_frame = ttk.Frame(self.candidate_panel, style="Yime.TFrame")
        self.pager_frame.pack(side=tk.RIGHT, fill=tk.Y, padx=(8, 0))

        self.first_page_button = ttk.Label(
            self.pager_frame, text="⏮", cursor="hand2", foreground="#5f6368"
        )
        self.first_page_button.pack(side=tk.LEFT, padx=2)

        self.prev_button = ttk.Label(
            self.pager_frame, text="▲", cursor="hand2", foreground="#5f6368"
        )
        self.prev_button.pack(side=tk.LEFT, padx=2)

        self.next_button = ttk.Label(
            self.pager_frame, text="▼", cursor="hand2", foreground="#5f6368"
        )
        self.next_button.pack(side=tk.LEFT, padx=2)

        self.last_page_button = ttk.Label(
            self.pager_frame, text="⏭", cursor="hand2", foreground="#5f6368"
        )
        self.last_page_button.pack(side=tk.LEFT, padx=2)

        self.toolbar_menu_button = ttk.Label(
            self.pager_frame, text="≡", cursor="hand2", foreground="#5f6368"
        )
        self.toolbar_menu_button.pack(side=tk.LEFT, padx=(6, 2))

        self.drag_grip = ttk.Label(
            self.pager_frame, text="⋮⋮", font=self.ui_font, cursor="fleur", foreground="#9aa0a6"
        )
        self.drag_grip.pack(side=tk.LEFT, fill=tk.Y, padx=(6, 2))

        # 动态隐藏的手工按键布局说明：在使用键盘图等特定模式下通过修改 text 属性令其被看到，平时保持为空
        self.manual_key_layout_label = ttk.Label(
            self.content_frame,
            text="",
            style="Yime.Secondary.TLabel",
        )

    def set_foreground_color(self, color: str) -> None:
        self.foreground_color = color
        self.style.configure("Yime.TLabel", foreground=color)
        self.style.configure("Yime.Text.TLabel", foreground=color)
        self.style.configure("Yime.TButton", foreground=color)
        self.style.configure("Yime.Candidate.TButton", foreground=color)
        self.style.configure("Yime.TEntry", foreground=color, fieldforeground=color)

    def set_background_color(self, color: str) -> None:
        self.background_color = color
        self.root.configure(bg=color)
        self.style.configure("Yime.TFrame", background=color)
        self.style.configure("Yime.TLabel", background=color)
        self.style.configure("Yime.Text.TLabel", background=color)
        self.style.configure("Yime.AccentText.TLabel", background=color)
        self.style.configure("Yime.Secondary.TLabel", background=color)
        self.style.configure("Yime.TButton", background=color)
        self.style.configure("Yime.Candidate.TButton", background=color)
        self.style.configure("Yime.TEntry", background=color, fieldbackground=color)
