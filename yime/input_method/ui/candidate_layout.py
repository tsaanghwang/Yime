"""
候选框 UI 布局与控件管理模块
负责创建界面元素、配置字体/样式结构。
"""
import tkinter as tk
from tkinter import ttk
from tkinter import font as tkfont


class CandidateLayoutBuilder:
    """封装候选框所需的内部控件、变量和字体初始化"""
    def __init__(self, root: tk.Tk, font_family: str):
        self.root = root
        self.font_family = self._resolve_font_family(font_family)

        self.ui_font = None
        self.text_font = None
        self.icon_font = None
        self.style = None

        self.main_frame = None
        self.standby_frame = None
        self.standby_icon = None

        self.input_var = tk.StringVar(self.root)
        self.input_entry = None

        self.commit_var = tk.StringVar(self.root, value="")
        self.commit_entry = None

        self.decode_info_frame = None
        self.pinyin_var = tk.StringVar(self.root, value="")

        self.candidate_panel = None
        self.candidate_text = None

        self.pager_frame = None
        self.first_page_button = None
        self.prev_button = None
        self.next_button = None
        self.last_page_button = None

        self.manual_key_layout_label = None

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

        self.root.option_add("*Font", self.ui_font)
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
        self.style.configure("Yime.TLabel", font=self.ui_font)
        self.style.configure("Yime.Text.TLabel", font=self.text_font)
        self.style.configure("Yime.TButton", font=self.ui_font)
        self.style.configure("Yime.Candidate.TButton", font=self.text_font)

    def build_ui(self) -> None:
        """构建UI界面并赋值给对应的属性"""
        # 主界面容器（正常输入模式下可见）
        self.main_frame = ttk.Frame(self.root, padding=12)
        self.main_frame.pack(fill=tk.BOTH, expand=True)

        # 待命状态容器（通常在不输入时，缩成右下角一个“音”字图标）
        self.standby_frame = tk.Frame(self.root, bg="#1f2937")
        self.standby_icon = tk.Label(
            self.standby_frame,
            text="音",
            bg="#1f2937",
            fg="#f8fafc",
            font=self.icon_font,
            width=3,
            height=1,
            cursor="hand2",
        )
        self.standby_icon.pack(fill=tk.BOTH, expand=True)

        # 显式的用户编码主输入框
        self.input_entry = ttk.Entry(
            self.main_frame, textvariable=self.input_var, font=self.text_font
        )
        self.input_entry.pack(fill=tk.X, pady=(0, 8))
        self.input_entry.focus_set()

        # 隐藏的提交框：用于当焦点偏离主输入框，或者处理特定的快捷键回贴 / 焦点暂存时承接键入。
        # 注意它并没有调用 .pack()，所以在 UI 树中实际不可见
        self.commit_entry = ttk.Entry(
            self.main_frame, textvariable=self.commit_var, font=self.text_font
        )

        # 包含拼音反馈与候选词列表的信息框架
        self.decode_info_frame = ttk.Frame(self.main_frame)
        self.decode_info_frame.pack(fill=tk.X, pady=(0, 8))

        # 隐藏/动态显示的规范拼音标签：只在有对应编码被成功解析成拼音时会借助 pinyin_var 出现文字
        ttk.Label(
            self.decode_info_frame,
            textvariable=self.pinyin_var,
            foreground="#0b57d0",
            style="Yime.Text.TLabel",
        ).pack(anchor=tk.W)

        self.candidate_panel = ttk.Frame(self.decode_info_frame)
        self.candidate_panel.pack(fill=tk.X, pady=(4, 0))

        # 候选词列表文本框
        self.candidate_text = tk.Text(
            self.candidate_panel,
            height=1,
            wrap=tk.NONE,
            font=self.text_font,
            bg=self.style.lookup("TFrame", "background"),
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
        self.pager_frame = ttk.Frame(self.candidate_panel)
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

        # 动态隐藏的手工按键布局说明：在使用键盘图等特定模式下通过修改 text 属性令其被看到，平时保持为空
        self.manual_key_layout_label = ttk.Label(
            self.main_frame, text="", foreground="#e37400", style="Yime.TLabel"
        )
