"""
候选框UI模块

提供候选词显示、选择、窗口管理等功能
"""

import ctypes
import os
import tkinter as tk
from tkinter import font as tkfont
from tkinter import ttk
from typing import Callable, List, Optional


class CandidateBox:
    """候选词显示框"""

    _DEBUG_UI = os.environ.get("YIME_DEBUG_UI", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }

    _GWL_EXSTYLE = -20
    _WS_EX_TOOLWINDOW = 0x00000080
    _WS_EX_APPWINDOW = 0x00040000
    _WS_EX_NOACTIVATE = 0x08000000
    _SWP_NOSIZE = 0x0001
    _SWP_NOMOVE = 0x0002
    _SWP_NOACTIVATE = 0x0010
    _SWP_SHOWWINDOW = 0x0040
    _SWP_FRAMECHANGED = 0x0020
    _SWP_NOOWNERZORDER = 0x0200
    _HWND_TOPMOST = -1
    _SW_SHOWNOACTIVATE = 4
    _SW_SHOW = 5

    def __init__(
        self,
        on_select: Callable[[str], None],
        font_family: str = "音元",
        max_candidates: int = 9,
        input_display_formatter: Optional[Callable[[str], str]] = None,
        on_input_change: Optional[Callable] = None,
        on_decode_from_clipboard: Optional[Callable] = None,
        on_copy_candidate: Optional[Callable[[int], None]] = None,
        on_commit_text: Optional[Callable[[str], None]] = None,
        on_hide: Optional[Callable[[], None]] = None,
        on_close: Optional[Callable[[], None]] = None,
    ) -> None:
        """
        初始化候选框

        Args:
            on_select: 选择候选词的回调函数
            font_family: 字体名称
            max_candidates: 最大候选词数量
            on_input_change: 输入变化回调
            on_decode_from_clipboard: 读取剪贴板回调
            on_copy_candidate: 复制候选词回调
        """
        self.on_select = on_select
        self.font_family = font_family
        self.max_candidates = max_candidates
        self.all_candidates: List[str] = []
        self.current_candidates: List[str] = []
        self._is_standby = False
        self._manual_input_enabled = False
        self._current_page = 0
        self._input_display_formatter = input_display_formatter
        self.projected_input_text = ""

        # 回调注入
        self._on_input_change_callback = on_input_change
        self._decode_from_clipboard = on_decode_from_clipboard
        self._copy_candidate = on_copy_candidate
        self._on_commit_text = on_commit_text
        self._on_hide = on_hide
        self._on_close = on_close

        # 创建主窗口
        self.root = tk.Tk()
        self.root.title("音元候选框")
        self.font_family = self._resolve_font_family(font_family)
        self._configure_fonts()

        # 不要硬性指定宽高，让它自然展开，防止越加越多被裁剪
        self.root.attributes("-topmost", True)
        self.root.withdraw()  # 初始隐藏

        # 构建UI
        self._build_ui()
        self._bind_keys()
        self._configure_window_for_global_input()
        self.root.protocol("WM_DELETE_WINDOW", self._request_close)

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

    def _configure_window_for_global_input(self) -> None:
        """将候选框配置为不抢焦点的 Windows 浮窗。"""
        if ctypes.sizeof(ctypes.c_void_p) == 0:
            return

        self.root.update_idletasks()
        hwnd = self.root.winfo_id()
        user32 = ctypes.WinDLL("user32", use_last_error=True)

        get_window_long_ptr = user32.GetWindowLongPtrW
        set_window_long_ptr = user32.SetWindowLongPtrW
        set_window_pos = user32.SetWindowPos

        get_window_long_ptr.argtypes = [ctypes.c_void_p, ctypes.c_int]
        get_window_long_ptr.restype = ctypes.c_void_p
        set_window_long_ptr.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        set_window_long_ptr.restype = ctypes.c_void_p
        set_window_pos.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_uint,
        ]
        set_window_pos.restype = ctypes.c_int

        ex_style = int(get_window_long_ptr(hwnd, self._GWL_EXSTYLE) or 0)
        ex_style |= self._WS_EX_TOOLWINDOW | self._WS_EX_NOACTIVATE
        ex_style &= ~self._WS_EX_APPWINDOW
        set_window_long_ptr(hwnd, self._GWL_EXSTYLE, ex_style)
        set_window_pos(
            hwnd,
            self._HWND_TOPMOST,
            0,
            0,
            0,
            0,
            self._SWP_NOMOVE
            | self._SWP_NOSIZE
            | self._SWP_NOACTIVATE
            | self._SWP_FRAMECHANGED,
        )

    def _set_noactivate(self, enabled: bool) -> None:
        """按需切换窗口是否允许获取焦点，便于手工粘贴编码。"""
        self.root.update_idletasks()
        hwnd = self.root.winfo_id()
        user32 = ctypes.WinDLL("user32", use_last_error=True)
        get_window_long_ptr = user32.GetWindowLongPtrW
        set_window_long_ptr = user32.SetWindowLongPtrW
        set_window_pos = user32.SetWindowPos

        get_window_long_ptr.argtypes = [ctypes.c_void_p, ctypes.c_int]
        get_window_long_ptr.restype = ctypes.c_void_p
        set_window_long_ptr.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        set_window_long_ptr.restype = ctypes.c_void_p
        set_window_pos.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_uint,
        ]
        set_window_pos.restype = ctypes.c_int

        ex_style = int(get_window_long_ptr(hwnd, self._GWL_EXSTYLE) or 0)
        if enabled:
            ex_style |= self._WS_EX_NOACTIVATE
        else:
            ex_style &= ~self._WS_EX_NOACTIVATE

        set_window_long_ptr(hwnd, self._GWL_EXSTYLE, ex_style)
        set_window_pos(
            hwnd,
            self._HWND_TOPMOST,
            0,
            0,
            0,
            0,
            self._SWP_NOMOVE
            | self._SWP_NOSIZE
            | self._SWP_FRAMECHANGED
            | (self._SWP_NOACTIVATE if enabled else 0),
        )

    def _get_user32(self):
        user32 = ctypes.WinDLL("user32", use_last_error=True)
        user32.SetWindowPos.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_uint,
        ]
        user32.SetWindowPos.restype = ctypes.c_int
        user32.ShowWindow.argtypes = [ctypes.c_void_p, ctypes.c_int]
        user32.ShowWindow.restype = ctypes.c_int
        user32.IsWindowVisible.argtypes = [ctypes.c_void_p]
        user32.IsWindowVisible.restype = ctypes.c_int
        return user32

    def _resolve_geometry(self, x: Optional[int], y: Optional[int]) -> tuple[int, int]:
        self.root.update_idletasks()

        # 让Tkinter自己去根据内容撑开，不写死高度
        width = self.root.winfo_reqwidth()
        height = self.root.winfo_reqheight()

        virtual_root_x = self.root.winfo_vrootx()
        virtual_root_y = self.root.winfo_vrooty()
        screen_width = self.root.winfo_vrootwidth() or self.root.winfo_screenwidth()
        screen_height = self.root.winfo_vrootheight() or self.root.winfo_screenheight()

        target_x = virtual_root_x + 32 if x is None else x
        target_y = virtual_root_y + 32 if y is None else y

        min_x = virtual_root_x
        min_y = virtual_root_y
        max_x = max(min_x, virtual_root_x + screen_width - width - 8)
        max_y = max(min_y, virtual_root_y + screen_height - height - 8)
        target_x = min(max(target_x, min_x), max_x)
        target_y = min(max(target_y, min_y), max_y)
        return target_x, target_y

    def get_pointer_position(self) -> tuple[int, int]:
        """使用 Tk 提供的指针坐标，避免 Win32/Tk 在 DPI 缩放下坐标系不一致。"""
        self.root.update_idletasks()
        return self.root.winfo_pointerx(), self.root.winfo_pointery()

    def _resize_to_content_if_visible(self) -> None:
        """窗口已显示时，按当前内容请求尺寸自动放大，避免新增说明区被裁掉。"""
        if self._is_standby:
            return
        try:
            if self.root.state() == "withdrawn":
                return
        except tk.TclError:
            return

        self.root.update_idletasks()
        current_x = self.root.winfo_x()
        current_y = self.root.winfo_y()
        self.root.geometry(f"+{current_x}+{current_y}")
        self.root.update_idletasks()

    def _build_ui(self) -> None:
        """构建UI界面"""
        self.main_frame = ttk.Frame(self.root, padding=12)
        self.main_frame.pack(fill=tk.BOTH, expand=True)

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
        self.standby_icon.bind("<Button-1>", self._restore_from_standby)
        self.standby_frame.bind("<Button-1>", self._restore_from_standby)

        # 输入框标签
        ttk.Label(self.main_frame, text="输入音元", style="Yime.TLabel").pack(
            anchor=tk.W
        )

        # 输入框
        self.input_var = tk.StringVar(self.root)
        self.input_entry = ttk.Entry(
            self.main_frame, textvariable=self.input_var, font=self.text_font
        )
        self.input_entry.pack(fill=tk.X, pady=(4, 8))
        self.input_entry.focus_set()
        self.input_entry.bind("<KeyRelease>", self._on_input_change)
        self.input_entry.bind("<Button-1>", self._activate_for_manual_input)

        ttk.Label(
            self.main_frame, text="投影编码 ", style="Yime.TLabel"
        ).pack(anchor=tk.W)

        self.projected_code_var = tk.StringVar(self.root, value="")
        ttk.Label(
            self.main_frame,
            textvariable=self.projected_code_var,
            justify=tk.LEFT,
            font=self.text_font,
            foreground="#666666",
        ).pack(anchor=tk.W, fill=tk.X)

        ttk.Label(
            self.main_frame, text="码元轮廓", style="Yime.TLabel"
        ).pack(anchor=tk.W)

        self.input_outline_var = tk.StringVar(self.root, value="")
        ttk.Label(
            self.main_frame,
            textvariable=self.input_outline_var,
            justify=tk.LEFT,
            wraplength=600,
            font=self.text_font,
            foreground="#666666",
        ).pack(anchor=tk.W, fill=tk.X, pady=(0, 8))

        paging_row = ttk.Frame(self.main_frame)
        paging_row.pack(fill=tk.X, pady=(0, 8))
        ttk.Label(paging_row, text="每页候选", style="Yime.TLabel").pack(side=tk.LEFT)
        self.page_size_var = tk.IntVar(value=self.max_candidates)
        self.page_size_spinbox = tk.Spinbox(
            paging_row,
            from_=4,
            to=9,
            width=4,
            textvariable=self.page_size_var,
            command=self._on_page_size_change,
            font=self.ui_font,
        )
        self.page_size_spinbox.pack(side=tk.LEFT, padx=(6, 12))
        self.page_size_spinbox.bind("<KeyRelease>", self._on_page_size_change)
        self.prev_button = ttk.Button(
            paging_row,
            text="上一页",
            command=self.show_previous_page,
            style="Yime.TButton",
        )
        self.prev_button.pack(side=tk.LEFT)
        self.next_button = ttk.Button(
            paging_row,
            text="下一页",
            command=self.show_next_page,
            style="Yime.TButton",
        )
        self.next_button.pack(side=tk.LEFT, padx=8)
        self.page_info_var = tk.StringVar(self.root, value="第 1/1 页")
        ttk.Label(
            paging_row, textvariable=self.page_info_var, style="Yime.TLabel"
        ).pack(side=tk.LEFT)
        self.shortcut_hint_var = tk.StringVar(
            value="数字键选当前页；PgUp/PgDn 翻页；Ctrl+Shift+C 复制原始编码字符；编码区支持 Left/Right/Home/End/Delete/Backspace 编辑；待上屏区可撤销一字。"
        )
        ttk.Label(
            self.main_frame,
            textvariable=self.shortcut_hint_var,
            foreground="#666666",
            style="Yime.TLabel",
        ).pack(anchor=tk.W, pady=(0, 8))

        ttk.Label(self.main_frame, text="待上屏文本", style="Yime.TLabel").pack(
            anchor=tk.W, pady=(8, 0)
        )
        self.commit_var = tk.StringVar(self.root, value="")
        self.commit_entry = ttk.Entry(
            self.main_frame,
            textvariable=self.commit_var,
            font=self.text_font,
        )
        self.commit_entry.pack(fill=tk.X, pady=(4, 8))
        self.commit_entry.bind("<BackSpace>", self._on_commit_backspace)

        commit_edit_row = ttk.Frame(self.main_frame)
        commit_edit_row.pack(fill=tk.X, pady=(0, 8))
        ttk.Button(
            commit_edit_row,
            text="撤销一字",
            command=self.remove_last_commit_char,
            style="Yime.TButton",
        ).pack(side=tk.LEFT)
        ttk.Button(
            commit_edit_row,
            text="清空待上屏",
            command=self.clear_commit_text,
            style="Yime.TButton",
        ).pack(side=tk.LEFT, padx=8)

        # 拼音显示
        self.pinyin_var = tk.StringVar(self.root, value="")
        ttk.Label(
            self.main_frame,
            textvariable=self.pinyin_var,
            foreground="#0b57d0",
            style="Yime.Text.TLabel",
        ).pack(anchor=tk.W)

        # 编码显示
        self.code_var = tk.StringVar(self.root, value="")
        ttk.Label(
            self.main_frame,
            textvariable=self.code_var,
            foreground="#666666",
            style="Yime.Text.TLabel",
        ).pack(anchor=tk.W, pady=(4, 0))

        # 候选词标签
        ttk.Label(self.main_frame, text="候选汉字", style="Yime.TLabel").pack(
            anchor=tk.W, pady=(10, 4)
        )

        # 候选词容器
        self.candidate_frame = ttk.Frame(self.main_frame)
        self.candidate_frame.pack(fill=tk.X)

        # 状态显示
        self.status_var = tk.StringVar(
            value='连续输入时自动取最近 4 码。请先复制编码，再点"读取剪贴板"。'
        )
        ttk.Label(
            self.main_frame,
            textvariable=self.status_var,
            foreground="#666666",
            style="Yime.TLabel",
        ).pack(anchor=tk.W, pady=(12, 0))

        # 按钮行
        button_row = ttk.Frame(self.main_frame)
        button_row.pack(fill=tk.X, pady=(12, 0))

        ttk.Button(
            button_row,
            text="粘贴编码",
            command=self._paste_code_from_clipboard,
            style="Yime.TButton",
        ).pack(side=tk.LEFT, padx=8)
        ttk.Button(
            button_row,
            text="复制原始编码",
            command=self.copy_input_text,
            style="Yime.TButton",
        ).pack(side=tk.LEFT)
        ttk.Button(
            button_row,
            text="上屏",
            command=self._commit_output_text,
            style="Yime.TButton",
        ).pack(side=tk.LEFT, padx=8)
        ttk.Button(
            button_row,
            text="复制首选",
            command=self._copy_first_candidate,
            style="Yime.TButton",
        ).pack(side=tk.LEFT)
        ttk.Button(
            button_row,
            text="粘贴首选",
            command=self._paste_first_candidate,
            style="Yime.TButton",
        ).pack(side=tk.LEFT, padx=8)
        ttk.Button(
            button_row, text="清空", command=self._clear_input, style="Yime.TButton"
        ).pack(side=tk.LEFT)
        ttk.Button(
            button_row, text="隐藏", command=self._request_hide, style="Yime.TButton"
        ).pack(side=tk.LEFT, padx=8)
        ttk.Button(
            button_row,
            text="退出程序",
            command=self._request_close,
            style="Yime.TButton",
        ).pack(side=tk.LEFT, padx=8)

    def _bind_keys(self) -> None:
        """绑定快捷键"""
        # 数字键选择候选词
        for index in range(1, 10):
            self.root.bind(
                str(index),
                lambda event, value=index: self._on_digit_shortcut(event, value),
            )

        # 回车键选择首选
        self.root.bind("<Return>", self._on_confirm_key)
        self.input_entry.bind("<Return>", self._on_confirm_key)
        self.commit_entry.bind("<Return>", self._on_confirm_key)
        self.root.bind("<space>", self._on_confirm_key)
        self.input_entry.bind("<space>", self._on_confirm_key)
        self.commit_entry.bind("<space>", self._on_confirm_key)

        # ESC键清空
        self.root.bind("<Escape>", lambda event: self._clear_input())

        # Ctrl+Q退出
        self.root.bind("<Control-q>", lambda event: self._request_close())
        self.root.bind("<Control-v>", self._on_ctrl_v)
        self.input_entry.bind("<Control-v>", self._on_ctrl_v)
        self.commit_entry.bind("<Control-v>", self._on_ctrl_v)
        self.root.bind("<Control-Shift-C>", self._on_copy_input_shortcut)
        self.input_entry.bind("<Control-Shift-C>", self._on_copy_input_shortcut)
        self.commit_entry.bind("<Control-Shift-C>", self._on_copy_input_shortcut)
        self.root.bind("<Prior>", self._on_previous_page_key)
        self.root.bind("<Next>", self._on_next_page_key)
        self.root.bind("<FocusIn>", self._on_window_focus_in)
        self.input_entry.bind("<Prior>", self._on_previous_page_key)
        self.input_entry.bind("<Next>", self._on_next_page_key)
        self.commit_entry.bind("<Prior>", self._on_previous_page_key)
        self.commit_entry.bind("<Next>", self._on_next_page_key)

    def _on_window_focus_in(self, event: __import__('tkinter').Event) -> None:
        """当输入候选框获得焦点时，把光标输入插入点（cursor焦点）跳转到输入框输入点。"""
        if getattr(event, "widget", None) == self.root and not self._is_standby:
            self.input_entry.focus_set()
            self.input_entry.icursor("end")

    def _on_input_change(self, event: Optional[tk.Event] = None) -> None:
        """输入变化事件处理"""
        self.projected_input_text = self.input_var.get()
        self._refresh_input_outline(self.projected_input_text)
        if self._on_input_change_callback:
            self._on_input_change_callback(event)

    def _format_codepoints(self, text: str) -> str:
        if not text:
            return ""
        return " ".join(
            f"U+{ord(char):06X}" if ord(char) > 0xFFFF else f"U+{ord(char):04X}"
            for char in text
        )

    def _refresh_input_outline(self, text: str) -> None:
        if not text:
            self.projected_code_var.set("")
            self.input_outline_var.set("")
            self._resize_to_content_if_visible()
            return

        self.projected_code_var.set(text)

        if not self._input_display_formatter:
            self.input_outline_var.set("")
            self._resize_to_content_if_visible()
            return
        display_text = self._input_display_formatter(text)
        self.input_outline_var.set(f"{display_text}" if display_text else "")
        self._resize_to_content_if_visible()

    def _activate_for_manual_input(self, event: Optional[tk.Event] = None) -> None:
        """鼠标点入输入框时允许窗口激活，便于手动粘贴测试编码。"""
        self._manual_input_enabled = True
        self.show(focus_input=True)

    def _restore_from_standby(self, event: Optional[tk.Event] = None) -> None:
        """从待命小图标恢复主候选框。"""
        self._manual_input_enabled = True
        self.show(focus_input=True)

    def _show_main_frame(self) -> None:
        if self._is_standby:
            self.standby_frame.pack_forget()
            self.main_frame.pack(fill=tk.BOTH, expand=True)
            self.root.attributes("-alpha", 0.97)
            self.root.title("音元候选框")
            self.root.geometry("")  # 清除可能遗留的 54x54 写死尺寸，让布局重新被内部组件撑开
            self.root.update_idletasks()
            self._is_standby = False

    def _resolve_standby_geometry(self) -> tuple[int, int, int, int]:
        self.root.update_idletasks()
        width = 54
        height = 54
        virtual_root_x = self.root.winfo_vrootx()
        virtual_root_y = self.root.winfo_vrooty()
        screen_width = self.root.winfo_vrootwidth() or self.root.winfo_screenwidth()
        screen_height = self.root.winfo_vrootheight() or self.root.winfo_screenheight()
        target_x = virtual_root_x + screen_width - width - 18
        target_y = virtual_root_y + screen_height - height - 56
        return target_x, target_y, width, height

    def _on_ctrl_v(self, event: Optional[tk.Event] = None) -> str:
        """支持在候选框内直接粘贴编码。"""
        self._paste_code_from_clipboard()
        return "break"

    def _on_copy_input_shortcut(self, event: Optional[tk.Event] = None) -> str:
        """复制当前原始输入字符，便于外部程序核对渲染。"""
        self.copy_input_text()
        return "break"

    def _on_confirm_key(self, event: Optional[tk.Event] = None) -> str:
        """有候选时先选首选，否则将待上屏文本送回编辑区。"""
        if self._should_allow_native_edit_key(event):
            return ""
        if self.current_candidates:
            self._select_candidate_by_index(0)
        else:
            self._commit_output_text()
        return "break"

    def _on_digit_shortcut(self, event: Optional[tk.Event], value: int) -> str:
        """数字键在非编辑态下用于选择当前页候选。"""
        if self._should_allow_native_edit_key(event):
            return ""
        self._select_candidate_by_index(value - 1)
        return "break"

    def _on_previous_page_key(self, event: Optional[tk.Event] = None) -> str:
        self.show_previous_page()
        return "break"

    def _on_next_page_key(self, event: Optional[tk.Event] = None) -> str:
        self.show_next_page()
        return "break"

    def _on_page_size_change(self, event: Optional[tk.Event] = None) -> None:
        try:
            page_size = int(self.page_size_var.get())
        except (tk.TclError, ValueError):
            return
        page_size = min(max(page_size, 4), 9)
        self.page_size_var.set(page_size)
        self.max_candidates = page_size
        self._current_page = 0
        self._render_candidates()

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
        prev_state = tk.NORMAL if self._current_page > 0 else tk.DISABLED
        next_state = tk.NORMAL if self._current_page < page_count - 1 else tk.DISABLED
        self.prev_button.configure(state=prev_state)
        self.next_button.configure(state=next_state)

    def show_previous_page(self) -> None:
        if self._current_page <= 0:
            return
        self._current_page -= 1
        self._render_candidates()

    def show_next_page(self) -> None:
        if self._current_page >= self._page_count() - 1:
            return
        self._current_page += 1
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
        return focused in {self.input_entry, self.commit_entry, self.page_size_spinbox}

    def _should_allow_native_edit_key(self, event: Optional[tk.Event]) -> bool:
        """编辑区聚焦时，保留本地输入控件的原生按键行为。"""
        if not event:
            return False
        widget = getattr(event, "widget", None)
        return widget in {self.input_entry, self.commit_entry, self.page_size_spinbox}

    def _render_candidates(self) -> None:
        """渲染候选词"""
        page_size = self._page_size()
        page_count = self._page_count()
        self._current_page = min(self._current_page, page_count - 1)
        start = self._current_page * page_size
        end = start + page_size
        self.current_candidates = self.all_candidates[start:end]

        # 清空现有候选词
        for child in self.candidate_frame.winfo_children():
            child.destroy()

        self._refresh_paging_controls()

        # 如果没有候选词
        if not self.current_candidates:
            ttk.Label(
                self.candidate_frame, text="无候选", style="Yime.Text.TLabel"
            ).pack(anchor=tk.W)
            return

        # 显示候选词按钮
        for index, hanzi in enumerate(self.current_candidates, start=1):
            button = ttk.Button(
                self.candidate_frame,
                text=f"{index}.{hanzi}",
                command=lambda value=index
                - 1: self._select_candidate_by_index(value),
                style="Yime.Candidate.TButton",
                width=6,
            )
            button.pack(side=tk.LEFT, padx=(0, 6))

    def _clear_input(self, focus_input: bool = True) -> None:
        """清空输入"""
        self.input_var.set("")
        self.pinyin_var.set("")
        self.code_var.set("")
        self.all_candidates = []
        self.current_candidates = []
        self._current_page = 0
        self.status_var.set(
            '连续输入时自动取最近 4 码。请先复制编码，再点"读取剪贴板"。'
        )
        self.projected_input_text = ""
        self.projected_code_var.set("")
        self.input_outline_var.set("")
        self._render_candidates()
        if focus_input:
            self.input_entry.focus_set()

    def clear_commit_text(self) -> None:
        """清空待上屏文本。"""
        self.commit_var.set("")
        self.status_var.set("已清空待上屏文本。")

    def remove_last_commit_char(self) -> None:
        """撤销待上屏文本中的最后一个字符。"""
        current = self.commit_var.get()
        if not current:
            self.status_var.set("待上屏文本为空，无可撤销内容。")
            return
        self.commit_var.set(current[:-1])
        if self.commit_var.get():
            self.status_var.set(f"已撤销最后一字，待上屏文本: {self.commit_var.get()}")
        else:
            self.status_var.set("已撤销最后一字，待上屏文本已清空。")

    def append_commit_text(self, text: str) -> None:
        """向待上屏文本追加已选候选。"""
        if not text:
            return
        self.commit_var.set(f"{self.commit_var.get()}{text}")

    def get_commit_text(self) -> str:
        """获取待上屏文本。"""
        return self.commit_var.get()

    def _on_commit_backspace(self, event: Optional[tk.Event] = None) -> str:
        """待上屏区为空时，退格回退最近一次已选字。"""
        selection = self.commit_entry.selection_present()
        if self.commit_var.get() or selection:
            return ""
        self.remove_last_commit_char()
        return "break"

    def _decode_from_clipboard(self) -> None:
        """从剪贴板读取"""
        if self._decode_from_clipboard:
            self._decode_from_clipboard()

    def _paste_code_from_clipboard(self) -> None:
        """将剪贴板内容贴入输入框并立即触发解码。"""
        self.show(focus_input=True)
        self._decode_from_clipboard()

    def copy_input_text(self) -> None:
        """复制当前输入框中的原始编码字符。"""
        text = self.projected_input_text or self.input_var.get()
        if not text:
            self.status_var.set("当前没有可复制的编码字符。")
            return
        self.root.clipboard_clear()
        self.root.clipboard_append(text)
        self.root.update_idletasks()
        self.status_var.set("已复制原始编码字符，可粘贴到 Word 或记事本查看渲染。")

    def _commit_output_text(self) -> None:
        """将待上屏文本提交到外部编辑区。"""
        text = self.get_commit_text().strip()
        if not text:
            self.status_var.set("待上屏文本为空。")
            return
        if self._on_commit_text:
            self._on_commit_text(text)
            self.status_var.set(f"已准备上屏: {text}")

    def _copy_first_candidate(self) -> None:
        """复制首选候选词"""
        self._copy_candidate(0)

    def _paste_first_candidate(self) -> None:
        """粘贴首选候选词"""
        self._select_candidate_by_index(0)

    def _select_candidate_by_index(self, index: int) -> None:
        """
        选择候选词

        Args:
            index: 候选词索引
        """
        if 0 <= index < len(self.current_candidates):
            hanzi = self.current_candidates[index]
            self.append_commit_text(hanzi)
            self.on_select(hanzi)
            self.status_var.set(f"已加入待上屏文本: {self.get_commit_text()}")
            self._clear_input(focus_input=True)

    def _copy_candidate(self, index: int) -> None:
        """
        复制候选词

        Args:
            index: 候选词索引
        """
        if self._copy_candidate:
            self._copy_candidate(index)

    def _request_close(self) -> None:
        """请求退出整个输入辅助器。"""
        if self._on_close:
            self._on_close()
            return
        self._close()

    def _request_hide(self) -> None:
        """隐藏窗口但不退出进程，便于后续再次弹出。"""
        if self._on_hide:
            self._on_hide()
            return
        self.show_standby()

    def _close(self) -> None:
        """关闭窗口"""
        try:
            if self.root.winfo_exists():
                self.root.quit()
                self.root.destroy()
        except tk.TclError:
            pass

    def show(
        self,
        x: Optional[int] = None,
        y: Optional[int] = None,
        focus_input: bool = True,
    ) -> None:
        """
        显示候选框

        Args:
            x: X坐标（可选）
            y: Y坐标（可选）
            focus_input: 是否将焦点切回候选框输入框
        """
        self._show_main_frame()
        self._manual_input_enabled = focus_input
        target_x, target_y = self._resolve_geometry(x, y)

        # 移除显式指定尺寸的设定，使用Tkinter自适应
        self.root.geometry(f"+{target_x}+{target_y}")
        self.root.state("normal")
        self.root.deiconify()
        self.root.attributes("-topmost", True)
        self.root.lift()
        self.root.update_idletasks()
        hwnd = self.root.winfo_id()
        user32 = self._get_user32()
        if not focus_input:
            self._set_noactivate(True)
            user32.ShowWindow(hwnd, self._SW_SHOWNOACTIVATE)
            user32.SetWindowPos(
                hwnd,
                self._HWND_TOPMOST,
                target_x,
                target_y,
                0,
                0,
                self._SWP_NOSIZE
                | self._SWP_NOACTIVATE
                | self._SWP_SHOWWINDOW
                | self._SWP_NOOWNERZORDER,
            )
        else:
            self._set_noactivate(False)
            user32.ShowWindow(hwnd, self._SW_SHOW)
            user32.SetWindowPos(
                hwnd,
                self._HWND_TOPMOST,
                target_x,
                target_y,
                0,
                0,
                self._SWP_NOSIZE
                | self._SWP_SHOWWINDOW
                | self._SWP_NOOWNERZORDER,
            )
            self.root.lift()
        self.root.update()
        if self._DEBUG_UI:
            is_visible = bool(user32.IsWindowVisible(hwnd))
            print(
                f"[CandidateBox.show] hwnd={hwnd} visible={is_visible} focus_input={focus_input} geometry=auto+{target_x}+{target_y} state={self.root.state()}"
            )
        if focus_input:
            self.input_entry.focus_force()

    def show_standby(self) -> None:
        """显示右下角半透明待命图标，保持输入法处于可再次触发状态。"""
        if not self._is_standby:
            self.main_frame.pack_forget()
            self.standby_frame.pack(fill=tk.BOTH, expand=True)
            self._is_standby = True

        target_x, target_y, width, height = self._resolve_standby_geometry()
        self.root.geometry(f"{width}x{height}+{target_x}+{target_y}")
        self.root.title("音")
        self.root.attributes("-alpha", 0.58)
        self.root.deiconify()
        self.root.update_idletasks()
        hwnd = self.root.winfo_id()
        user32 = self._get_user32()
        self._set_noactivate(True)
        user32.ShowWindow(hwnd, self._SW_SHOWNOACTIVATE)
        user32.SetWindowPos(
            hwnd,
            self._HWND_TOPMOST,
            target_x,
            target_y,
            width,
            height,
            self._SWP_NOACTIVATE
            | self._SWP_SHOWWINDOW
            | self._SWP_NOOWNERZORDER,
        )
        self.root.update()

    def hide(self) -> None:
        """隐藏候选框"""
        if self._DEBUG_UI:
            print("[CandidateBox.hide] withdraw")
        self.root.withdraw()

    def update_candidates(
        self,
        candidates: List[str],
        pinyin: str = "",
        code: str = "",
        status: str = "",
    ) -> None:
        """
        更新候选词显示

        Args:
            candidates: 候选词列表
            pinyin: 拼音显示
            code: 编码显示
            status: 状态消息
        """
        previous_count = len(self.all_candidates)
        self.all_candidates = list(candidates)
        if previous_count != len(self.all_candidates):
            self._current_page = 0
        self.pinyin_var.set(f"拼音: {pinyin}" if pinyin else "")
        if code:
            self.code_var.set(f"当前解码 4 码: {code}")
        else:
            self.code_var.set("当前解码 4 码: [等待输入...]")

        self.status_var.set(status)
        self._render_candidates()
        self._resize_to_content_if_visible()

    def get_input(self) -> str:
        """
        获取当前输入

        Returns:
            当前输入的文本
        """
        return self.input_var.get()

    def get_projected_input(self) -> str:
        """获取当前投影后的编码字符。"""
        return self.projected_input_text

    def set_projected_input(self, text: str) -> None:
        """设置当前投影后的编码字符，并刷新说明区。"""
        self.projected_input_text = text
        self._refresh_input_outline(text)

    def set_input(self, text: str, projected_text: Optional[str] = None) -> None:
        """
        设置输入框内容

        Args:
            text: 要设置的文本
        """
        self.input_var.set(text)
        self.projected_input_text = text if projected_text is None else projected_text
        self._refresh_input_outline(self.projected_input_text)

    def run(self) -> None:
        """运行主循环"""
        self._render_candidates()
        self.root.mainloop()
