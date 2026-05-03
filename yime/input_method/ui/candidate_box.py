"""
候选框UI模块

提供候选词显示、选择、窗口管理等功能
"""

import ctypes
import ctypes.wintypes as wintypes
import os
import tkinter as tk
from tkinter import font as tkfont
from tkinter import ttk
from typing import Callable, List, Optional

from ..utils.window_manager import WindowManager

InputChangeCallback = Callable[[Optional[object]], None]
CopyCandidateCallback = Callable[[int], None]
CommitTextCallback = Callable[[str], None]
ManualKeyOutputResolver = Callable[[str, dict[str, bool]], str]
VoidCallback = Callable[[], None]

from .candidate_box_actions import CandidateBoxActions


class CandidateBox:
    """候选词显示框"""

    _CANDIDATE_TAG_PREFIX = "candidate_"
    _PAGER_PREV_TAG = "pager_prev"
    _PAGER_NEXT_TAG = "pager_next"
    _DEFAULT_STATUS_TEXT = '连续输入时自动取最近 4 码。请先复制编码，再点"读取剪贴板"。'
    _STANDBY_WINDOW_SIZE = 54
    _PASSIVE_ALPHA = 0.42
    _ACTIVE_ALPHA = 0.97
    _DEFAULT_CANDIDATE_LAYOUT = "horizontal"

    _DEBUG_UI = os.environ.get("YIME_DEBUG_UI", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }

    _GWL_EXSTYLE = -20
    _GWL_STYLE = -16
    _WS_EX_TOOLWINDOW = 0x00000080
    _WS_EX_APPWINDOW = 0x00040000
    _WS_EX_NOACTIVATE = 0x08000000
    _WS_MAXIMIZEBOX = 0x00010000
    _SWP_NOSIZE = 0x0001
    _SWP_NOMOVE = 0x0002
    _SWP_NOACTIVATE = 0x0010
    _SWP_SHOWWINDOW = 0x0040
    _SWP_FRAMECHANGED = 0x0020
    _SWP_NOOWNERZORDER = 0x0200
    _HWND_TOPMOST = -1
    _HWND_NOTOPMOST = -2
    _SW_SHOWNOACTIVATE = 4
    _SW_SHOW = 5
    _PRINTABLE_MODIFIER_VK_CODES = {
        "shift": (0x10, 0xA0, 0xA1),
        "ctrl": (0x11, 0xA2, 0xA3),
        "alt": (0x12, 0xA4, 0xA5),
        "alt_r": (0xA5,),
        "win": (0x5B, 0x5C),
    }

    def __init__(
        self,
        on_select: Callable[[str], None],
        font_family: str = "音元",
        max_candidates: int = 5,
        candidate_layout: str = "horizontal",
        input_display_formatter: Optional[Callable[[str], str]] = None,
        projected_code_formatter: Optional[Callable[[str], str]] = None,
        manual_key_output_resolver: Optional[ManualKeyOutputResolver] = None,
        manual_input_transformer: Optional[Callable[[str], str]] = None,
        on_input_change: Optional[InputChangeCallback] = None,
        on_copy_candidate: Optional[CopyCandidateCallback] = None,
        on_commit_text: Optional[CommitTextCallback] = None,
        on_restore_from_standby: Optional[VoidCallback] = None,
        on_close: Optional[VoidCallback] = None,
    ) -> None:
        """
        初始化候选框

        Args:
            on_select: 选择候选词的回调函数
            font_family: 字体名称
            max_candidates: 最大候选词数量
            on_input_change: 输入变化回调
            on_copy_candidate: 复制候选词回调
        """
        self.on_select = on_select
        self.font_family = font_family
        self.max_candidates = max_candidates
        self.all_candidates: List[str] = []
        self.current_candidates: List[str] = []
        self._selected_candidate_index = 0
        self._is_standby = False
        self._manual_input_enabled = False
        self._current_page = 0
        self._candidate_layout = self._normalize_candidate_layout(candidate_layout)
        self._input_display_formatter = input_display_formatter
        self._projected_code_formatter = projected_code_formatter
        self._manual_key_output_resolver = manual_key_output_resolver
        self._manual_input_transformer = manual_input_transformer
        self.projected_input_text = ""
        self._last_main_geometry: Optional[tuple[int, int, int, int]] = None

        # 回调注入
        self._on_input_change_callback = on_input_change
        self._on_copy_candidate_callback = on_copy_candidate
        self._on_commit_text_callback = on_commit_text
        self._on_restore_from_standby = on_restore_from_standby
        self._on_close = on_close
        self._handling_iconify = False

        # 创建主窗口
        self.root = tk.Tk()
        self.root.title("音元拼音")
        self.font_family = self._resolve_font_family(font_family)
        self._configure_fonts()

        # 不要硬性指定宽高，让它自然展开，防止越加越多被裁剪
        self.root.attributes("-topmost", True)
        self.root.resizable(False, False)
        self.root.withdraw()  # 初始隐藏

        # 构建UI
        self._build_ui()
        self._bind_passive_reactivation_targets()
        self.actions = CandidateBoxActions(self)
        self._bind_keys()
        self._configure_window_for_global_input()
        self.root.bind("<Unmap>", self._on_window_unmap)
        self.root.protocol("WM_DELETE_WINDOW", self.actions.request_close)

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
        user32, get_window_long_ptr, set_window_long_ptr, set_window_pos = (
            self._get_window_style_api()
        )

        style = int(get_window_long_ptr(hwnd, self._GWL_STYLE) or 0)
        style &= ~self._WS_MAXIMIZEBOX
        ex_style = int(get_window_long_ptr(hwnd, self._GWL_EXSTYLE) or 0)
        ex_style |= self._WS_EX_TOOLWINDOW | self._WS_EX_NOACTIVATE
        ex_style &= ~self._WS_EX_APPWINDOW
        set_window_long_ptr(hwnd, self._GWL_STYLE, style)
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
        _user32, get_window_long_ptr, set_window_long_ptr, set_window_pos = (
            self._get_window_style_api()
        )

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

    def _get_window_style_api(self):
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
        return user32, get_window_long_ptr, set_window_long_ptr, set_window_pos

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

    def _normalize_candidate_layout(self, layout: str) -> str:
        return (
            "vertical"
            if layout.strip().lower() == "vertical"
            else self._DEFAULT_CANDIDATE_LAYOUT
        )

    def _reset_status_message(self) -> None:
        self.status_var.set(self._DEFAULT_STATUS_TEXT)

    def _resolve_activation_anchor(
        self,
        width: int,
        height: int,
        anchor_hwnd: Optional[int] = None,
    ) -> tuple[int, int]:
        foreground = anchor_hwnd or WindowManager.get_foreground_window()
        own_hwnd = self.root.winfo_id()
        if foreground and foreground != own_hwnd:
            left, top, right, bottom = WindowManager.get_window_rect(foreground)
            return right - min(96, max(24, width // 4)), bottom + min(48, max(24, height // 3))

        return self.root.winfo_vrootx() + 32, self.root.winfo_vrooty() + 32

    def _resolve_geometry(
        self,
        x: Optional[int],
        y: Optional[int],
        *,
        focus_input: bool,
        anchor_hwnd: Optional[int] = None,
    ) -> tuple[int, int]:
        self.root.update_idletasks()

        # 让Tkinter自己去根据内容撑开，不写死高度
        width = self.root.winfo_reqwidth()
        height = self.root.winfo_reqheight()

        virtual_root_x = self.root.winfo_vrootx()
        virtual_root_y = self.root.winfo_vrooty()
        screen_width = self.root.winfo_vrootwidth() or self.root.winfo_screenwidth()
        screen_height = self.root.winfo_vrootheight() or self.root.winfo_screenheight()

        if x is None or y is None:
            anchor_x, anchor_y = self._resolve_activation_anchor(
                width,
                height,
                anchor_hwnd=anchor_hwnd,
            )
            target_x = anchor_x if x is None and focus_input else (virtual_root_x + 32 if x is None else x)
            target_y = anchor_y if y is None and focus_input else (virtual_root_y + 32 if y is None else y)
        else:
            target_x = x
            target_y = y

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

    def _remember_main_geometry(
        self,
        x: int,
        y: int,
        width: Optional[int] = None,
        height: Optional[int] = None,
    ) -> None:
        """缓存主候选框最近一次正常显示的位置，避免 withdrawn 后回退到左上角兜底。"""
        resolved_width = width if width is not None else self.root.winfo_width() or self.root.winfo_reqwidth()
        resolved_height = height if height is not None else self.root.winfo_height() or self.root.winfo_reqheight()
        self._last_main_geometry = (x, y, resolved_width, resolved_height)

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

        # 输入框
        self.input_var = tk.StringVar(self.root)
        self.input_entry = ttk.Entry(
            self.main_frame, textvariable=self.input_var, font=self.text_font
        )
        self.input_entry.pack(fill=tk.X, pady=(0, 8))
        self.input_entry.focus_set()
        self.input_entry.bind("<KeyPress>", self._on_manual_input_key_press, add="+")
        self.input_entry.bind("<KeyRelease>", self._on_input_change)
        self.input_entry.bind("<Button-1>", self._activate_for_manual_input)

        self.decode_info_frame = ttk.Frame(self.main_frame)
        self.decode_info_frame.pack(fill=tk.X, pady=(0, 8))

        self.pinyin_var = tk.StringVar(self.root, value="")
        ttk.Label(
            self.decode_info_frame,
            textvariable=self.pinyin_var,
            foreground="#0b57d0",
            style="Yime.Text.TLabel",
        ).pack(anchor=tk.W)

        self.candidate_panel = ttk.Frame(self.decode_info_frame)
        self.candidate_panel.pack(fill=tk.X, pady=(4, 0))

        # 候选词与翻页控件合一的面板
        self.candidate_text = tk.Text(
            self.candidate_panel,
            height=1,
            wrap=tk.NONE,
            font=self.text_font,
            relief=tk.FLAT,
            borderwidth=0,
            highlightthickness=0,
            padx=0,
            pady=0,
            cursor="arrow",
        )
        self.candidate_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.candidate_text.configure(
            background=self.root.cget("background"),
            foreground="#111827",
            state=tk.DISABLED,
        )
        self._configure_candidate_text_tags()

        self.pager_button_frame = ttk.Frame(self.candidate_panel)
        self.pager_button_frame.pack(side=tk.RIGHT, fill=tk.Y, padx=(8, 0))
        self.first_page_button = self._create_pager_button(
            self.pager_button_frame,
            text="⏮",
            command=self.show_first_page,
        )
        self.prev_page_button = self._create_pager_button(
            self.pager_button_frame,
            text="◀",
            command=self.show_previous_page,
        )
        self.next_page_button = self._create_pager_button(
            self.pager_button_frame,
            text="▶",
            command=self.show_next_page,
        )
        self.last_page_button = self._create_pager_button(
            self.pager_button_frame,
            text="⏭",
            command=self.show_last_page,
        )
        self._sync_pager_button_layout()

        self.projected_code_var = tk.StringVar(self.root, value="")
        self.input_outline_var = tk.StringVar(self.root, value="")

        self.status_var = tk.StringVar(value=self._DEFAULT_STATUS_TEXT)

        self.page_size_var = tk.IntVar(value=self.max_candidates)
        self.page_size_spinbox = None
        self.page_info_var = tk.StringVar(self.root, value="第 1/1 页")
        self.shortcut_hint_var = tk.StringVar(
            value="Space 选首选；` - = \\ 选第2到第5候选；Home/PgUp/PgDn/End 翻页；Enter 发送已选内容。"
        )

        self.commit_var = tk.StringVar(self.root, value="")
        self.commit_entry = ttk.Entry(
            self.main_frame,
            textvariable=self.commit_var,
            font=self.text_font,
        )
        self.commit_entry.bind("<BackSpace>", self._on_commit_backspace)

        # 编码显示
        self.code_var = tk.StringVar(self.root, value="")
        if self._DEBUG_UI:
            ttk.Label(
                self.main_frame,
                textvariable=self.code_var,
                foreground="#666666",
                style="Yime.Text.TLabel",
            ).pack(anchor=tk.W, pady=(4, 0))

    def _bind_keys(self) -> None:
        """绑定快捷键"""
        self.actions.bind_keys()

    def _get_manual_key_modifiers(self) -> dict[str, bool]:
        if os.name != "nt":
            return {
                "shift": False,
                "ctrl": False,
                "alt": False,
                "alt_r": False,
                "win": False,
                "alt_gr": False,
            }

        user32 = ctypes.WinDLL("user32", use_last_error=True)
        user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
        user32.GetAsyncKeyState.restype = ctypes.c_short

        states: dict[str, bool] = {}
        for name, codes in self._PRINTABLE_MODIFIER_VK_CODES.items():
            states[name] = any(bool(user32.GetAsyncKeyState(code) & 0x8000) for code in codes)

        states["alt_gr"] = bool(states.get("ctrl") and (states.get("alt_r") or states.get("alt")))
        return states

    def _normalize_event_physical_key(self, event: tk.Event) -> str:
        keysym = str(getattr(event, "keysym", "") or "").strip()
        if len(keysym) == 1:
            return keysym.lower()

        special_keys = {
            "semicolon": ";",
            "comma": ",",
            "period": ".",
            "slash": "/",
            "backslash": "\\",
            "bracketleft": "[",
            "bracketright": "]",
            "apostrophe": "'",
            "grave": "`",
            "minus": "-",
            "equal": "=",
            "space": "space",
        }
        return special_keys.get(keysym.lower(), "")

    def _resolve_manual_input_text(self, event: tk.Event) -> str:
        if os.name != "nt":
            return ""

        vk_code = int(getattr(event, "keycode", 0) or 0)
        if vk_code <= 0:
            return ""

        modifiers = self._get_manual_key_modifiers()
        if modifiers.get("win"):
            return ""
        if modifiers.get("ctrl") and not modifiers.get("alt_gr"):
            return ""
        if modifiers.get("alt") and not modifiers.get("alt_gr"):
            return ""

        user32 = ctypes.WinDLL("user32", use_last_error=True)
        user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
        user32.GetAsyncKeyState.restype = ctypes.c_short
        user32.GetForegroundWindow.argtypes = []
        user32.GetForegroundWindow.restype = wintypes.HWND
        user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
        user32.GetWindowThreadProcessId.restype = wintypes.DWORD
        user32.GetKeyboardLayout.argtypes = [wintypes.DWORD]
        user32.GetKeyboardLayout.restype = wintypes.HKL
        user32.ToUnicodeEx.argtypes = [
            wintypes.UINT,
            wintypes.UINT,
            ctypes.POINTER(ctypes.c_ubyte),
            wintypes.LPWSTR,
            ctypes.c_int,
            wintypes.UINT,
            wintypes.HKL,
        ]
        user32.ToUnicodeEx.restype = ctypes.c_int
        user32.MapVirtualKeyW.argtypes = [wintypes.UINT, wintypes.UINT]
        user32.MapVirtualKeyW.restype = wintypes.UINT

        keyboard_state = (ctypes.c_ubyte * 256)()
        for code in range(256):
            if user32.GetAsyncKeyState(code) & 0x8000:
                keyboard_state[code] |= 0x80

        def mark_pressed(*virtual_keys: int) -> None:
            for virtual_key in virtual_keys:
                keyboard_state[virtual_key] |= 0x80

        if modifiers.get("shift"):
            mark_pressed(0x10, 0xA0, 0xA1)
        if modifiers.get("ctrl") or modifiers.get("alt_gr"):
            mark_pressed(0x11, 0xA2, 0xA3)
        if modifiers.get("alt") or modifiers.get("alt_gr"):
            mark_pressed(0x12, 0xA4, 0xA5)
        if modifiers.get("alt_r") or modifiers.get("alt_gr"):
            mark_pressed(0xA5)
        mark_pressed(vk_code)

        scan_code = int(user32.MapVirtualKeyW(vk_code, 0) or 0)
        foreground_hwnd = user32.GetForegroundWindow()
        thread_id = wintypes.DWORD(0)
        layout_thread_id = 0
        if foreground_hwnd:
            layout_thread_id = int(user32.GetWindowThreadProcessId(foreground_hwnd, ctypes.byref(thread_id)))
        keyboard_layout = user32.GetKeyboardLayout(layout_thread_id)

        text_buffer = ctypes.create_unicode_buffer(8)
        translated_length = user32.ToUnicodeEx(
            vk_code,
            scan_code,
            keyboard_state,
            text_buffer,
            len(text_buffer),
            0,
            keyboard_layout,
        )
        if translated_length > 0:
            return text_buffer.value[:translated_length]
        return ""

    def _on_manual_input_key_press(self, event: Optional[tk.Event] = None) -> Optional[str]:
        if not event or event.widget != self.input_entry or not self._manual_input_enabled:
            return None

        modifiers = self._get_manual_key_modifiers()
        translated_text = ""
        physical_key = self._normalize_event_physical_key(event)
        if self._manual_key_output_resolver and physical_key:
            translated_text = self._manual_key_output_resolver(physical_key, modifiers)

        if not translated_text:
            translated_text = self._resolve_manual_input_text(event)
        if len(translated_text) != 1 or translated_text < " ":
            return None

        if self._manual_input_transformer:
            translated_text = self._manual_input_transformer(translated_text)
        if len(translated_text) != 1 or translated_text < " ":
            return None

        native_char = getattr(event, "char", "") or ""
        should_intercept = bool(modifiers.get("alt_gr") or native_char != translated_text)
        if not should_intercept:
            return None

        self.input_entry.insert(tk.INSERT, translated_text)
        self.root.after_idle(self._on_input_change)
        return "break"

    def _bind_passive_reactivation_targets(self) -> None:
        """半透明静置态下，点击主界面任意区域都可恢复激活。"""
        self._bind_passive_reactivation_widget(self.main_frame)

    def _bind_passive_reactivation_widget(self, widget: tk.Misc) -> None:
        widget.bind("<Button-1>", self._reactivate_from_passive, add="+")
        for child in widget.winfo_children():
            self._bind_passive_reactivation_widget(child)

    def _on_window_focus_in(self, event: object) -> None:
        """当输入候选框获得焦点时，把光标输入插入点（cursor焦点）跳转到输入框输入点。"""
        self.actions.on_window_focus_in(event)

    def _reactivate_from_passive(self, event: Optional[tk.Event] = None) -> None:
        """半透明静置态点击后恢复可输入状态。"""
        if self._is_standby or self._manual_input_enabled:
            return
        if self._on_restore_from_standby:
            self.actions.restore_from_standby(event)
            return
        self.actions.activate_for_manual_input(event)

    def _on_window_unmap(self, event: Optional[tk.Event] = None) -> None:
        """仅在用户显式最小化时，转成右下角待命图标。"""
        if getattr(event, "widget", self.root) != self.root:
            return
        if self._handling_iconify:
            return
        try:
            if self.root.state() != "iconic":
                return
        except tk.TclError:
            return
        self._handling_iconify = True
        self.root.after(0, self._convert_iconify_to_standby)

    def _convert_iconify_to_standby(self) -> None:
        try:
            self.show_standby()
        finally:
            self._handling_iconify = False

    def _on_input_change(self, event: Optional[tk.Event] = None) -> None:
        """输入变化事件处理"""
        self.actions.on_input_change(event)

    def _format_codepoints(self, text: str) -> str:
        if not text:
            return ""
        return " ".join(
            f"U+{ord(char):06X}" if ord(char) > 0xFFFF else f"U+{ord(char):04X}"
            for char in text
        )

    def _refresh_input_outline(self, text: str) -> None:
        # 暂时收起投影编码和音元音符，只保留标准拼音作为主参照。
        self.projected_code_var.set("")
        self.input_outline_var.set("")
        self._resize_to_content_if_visible()

    def _activate_for_manual_input(self, event: Optional[tk.Event] = None) -> None:
        """鼠标点入输入框时允许窗口激活，便于手动粘贴测试编码。"""
        self.actions.activate_for_manual_input(event)

    def _restore_from_standby(self, event: Optional[tk.Event] = None) -> None:
        """从待命小图标恢复主候选框。"""
        self.actions.restore_from_standby(event)

    def set_manual_input_enabled(self, enabled: bool) -> None:
        """切换候选框是否允许手动输入模式。"""
        self._manual_input_enabled = enabled
        if enabled:
            self.input_entry.state(["!readonly"])
        else:
            self.input_entry.state(["readonly"])

    def is_manual_input_enabled(self) -> bool:
        """返回候选框是否处于手动输入模式。"""
        return self._manual_input_enabled

    def is_standby(self) -> bool:
        """返回候选框是否处于待命模式。"""
        return self._is_standby

    def focus_input_cursor(self) -> None:
        """将焦点和光标移动到输入框末尾。"""
        self.input_entry.focus_set()
        self.input_entry.icursor("end")

    def normalize_input_entry_state(self) -> None:
        """清除输入框残留选区，并将插入点固定到末尾。"""
        self.input_entry.selection_clear()
        self.input_entry.icursor(tk.END)

    def set_status(self, text: str) -> None:
        """更新状态栏文案。"""
        self.status_var.set(text)

    def _show_main_frame(self) -> None:
        if self._is_standby:
            self.standby_frame.pack_forget()
            self.main_frame.pack(fill=tk.BOTH, expand=True)
            self.root.geometry("")  # 清除可能遗留的 54x54 写死尺寸，让布局重新被内部组件撑开
            self.root.update_idletasks()
            self._is_standby = False
        self.root.attributes("-alpha", self._ACTIVE_ALPHA)
        self.root.title("音元拼音")

    def _resolve_standby_geometry(self) -> tuple[int, int, int, int]:
        self.root.update_idletasks()
        width = self._STANDBY_WINDOW_SIZE
        height = self._STANDBY_WINDOW_SIZE
        virtual_root_x = self.root.winfo_vrootx()
        virtual_root_y = self.root.winfo_vrooty()
        screen_width = self.root.winfo_vrootwidth() or self.root.winfo_screenwidth()
        screen_height = self.root.winfo_vrootheight() or self.root.winfo_screenheight()
        target_x = virtual_root_x + screen_width - width - 18
        target_y = virtual_root_y + screen_height - height - 56
        return target_x, target_y, width, height

    def _on_confirm_key(self, event: Optional[tk.Event] = None) -> str:
        """有候选时先将首选加入缓冲区，否则发送缓冲区到外部编辑器。"""
        return self.actions.on_confirm_key(event)

    def _on_digit_shortcut(self, event: Optional[tk.Event], value: int) -> str:
        """数字键在非编辑态下用于选择当前页候选。"""
        return self.actions.on_digit_shortcut(event, value)

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
            foreground="#0b57d0",
            font=self.ui_font,
        )
        self.candidate_text.tag_configure(
            "candidate_selected_text",
            foreground="#0b57d0",
            background="#fef3c7",
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

    def _clear_input(self, focus_input: bool = True) -> None:
        """清空输入"""
        self.input_var.set("")
        self.pinyin_var.set("")
        self.code_var.set("")
        self.all_candidates = []
        self.current_candidates = []
        self._selected_candidate_index = 0
        self._current_page = 0
        self._reset_status_message()
        self.projected_input_text = ""
        self.projected_code_var.set("")
        self.input_outline_var.set("")
        self._render_candidates()
        if focus_input:
            self.input_entry.focus_set()

    def clear_input(self, focus_input: bool = True) -> None:
        """公开的清空输入入口。"""
        self._clear_input(focus_input=focus_input)

    def clear_commit_text(self) -> None:
        """清空缓冲区文本。"""
        self.commit_var.set("")
        self.status_var.set("已清空缓冲区。")

    def remove_last_commit_char(self) -> None:
        """撤销缓冲区中的最后一个字符。"""
        current = self.commit_var.get()
        if not current:
            self.status_var.set("缓冲区为空，无可撤销内容。")
            return
        self.commit_var.set(current[:-1])
        if self.commit_var.get():
            self.status_var.set(f"已撤销最后一字，缓冲区: {self.commit_var.get()}")
        else:
            self.status_var.set("已撤销最后一字，缓冲区已清空。")

    def append_commit_text(self, text: str) -> None:
        """向缓冲区追加已选候选。"""
        if not text:
            return
        self.commit_var.set(f"{self.commit_var.get()}{text}")

    def get_candidate(self, index: int) -> Optional[str]:
        """按当前页索引读取候选。"""
        if 0 <= index < len(self.current_candidates):
            return self.current_candidates[index]
        return None

    def get_commit_text(self) -> str:
        """获取缓冲区文本。"""
        return self.commit_var.get()

    def get_selected_candidate_index(self) -> int:
        """返回当前高亮候选在当前页内的索引。"""
        if not self.current_candidates:
            return 0
        return min(self._selected_candidate_index, len(self.current_candidates) - 1)

    def move_selection(self, delta: int) -> None:
        """在当前页内移动高亮候选，不触发提交。"""
        if not self.current_candidates:
            self._selected_candidate_index = 0
            return
        current_index = self.get_selected_candidate_index()
        self._selected_candidate_index = (current_index + delta) % len(self.current_candidates)
        self._render_candidates()

    def _on_commit_backspace(self, event: Optional[tk.Event] = None) -> str:
        """缓冲区为空时，退格回退最近一次已选字。"""
        return self.actions.on_commit_backspace(event)

    def _select_candidate_by_index(self, index: int) -> None:
        """
        选择候选词

        Args:
            index: 候选词索引
        """
        self.actions.select_candidate_by_index(index)

    def _click_candidate_by_index(self, index: int) -> None:
        """鼠标点击候选时立即提交到外部编辑器。"""
        self.actions.on_candidate_click(index)

    def _copy_candidate(self, index: int) -> None:
        """
        复制候选词

        Args:
            index: 候选词索引
        """
        self.actions.copy_candidate(index)

    def _close(self) -> None:
        """关闭窗口"""
        try:
            if self.root.winfo_exists():
                self.root.quit()
                self.root.destroy()
        except tk.TclError:
            pass

    def close(self) -> None:
        """公开的关闭窗口入口。"""
        self._close()

    def show(
        self,
        x: Optional[int] = None,
        y: Optional[int] = None,
        focus_input: bool = True,
        anchor_hwnd: Optional[int] = None,
    ) -> None:
        """
        显示候选框

        Args:
            x: X坐标（可选）
            y: Y坐标（可选）
            focus_input: 是否将焦点切回候选框输入框
        """
        self._show_main_frame()
        self.set_manual_input_enabled(focus_input)
        target_x, target_y = self._resolve_geometry(
            x,
            y,
            focus_input=focus_input,
            anchor_hwnd=anchor_hwnd,
        )

        # 移除显式指定尺寸的设定，使用Tkinter自适应
        self.root.geometry(f"+{target_x}+{target_y}")
        hwnd = self.root.winfo_id()
        user32 = self._get_user32()
        if not focus_input:
            self._set_noactivate(True)
            self.root.attributes("-topmost", True)
            self.root.deiconify()
            self.root.update_idletasks()
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
            self.root.state("normal")
            self.root.deiconify()
            self.root.attributes("-topmost", True)
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
            WindowManager.restore_window(hwnd)
        self.root.update()
        self._remember_main_geometry(target_x, target_y)
        if self._DEBUG_UI:
            is_visible = bool(user32.IsWindowVisible(hwnd))
            print(
                f"[CandidateBox.show] hwnd={hwnd} visible={is_visible} focus_input={focus_input} geometry=auto+{target_x}+{target_y} state={self.root.state()}"
            )
        if focus_input:
            # Avoid forcing foreground activation on Windows; a normal focus request
            # is enough when the user intentionally entered manual-input mode.
            self.input_entry.focus_set()
        self.normalize_input_entry_state()

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

    def show_passive(self) -> None:
        """显示半透明主界面，保留当前位置与尺寸，不退成角落图标。"""
        self._show_main_frame()
        self.set_manual_input_enabled(False)
        self.root.update_idletasks()

        if self.root.state() == "withdrawn":
            if self._last_main_geometry is not None:
                target_x, target_y, width, height = self._last_main_geometry
            else:
                target_x, target_y = self._resolve_geometry(None, None, focus_input=False)
                width = self.root.winfo_reqwidth()
                height = self.root.winfo_reqheight()
        else:
            target_x = self.root.winfo_x()
            target_y = self.root.winfo_y()
            width = self.root.winfo_width() or self.root.winfo_reqwidth()
            height = self.root.winfo_height() or self.root.winfo_reqheight()

        self.root.geometry(f"{width}x{height}+{target_x}+{target_y}")
        self.root.attributes("-alpha", self._PASSIVE_ALPHA)
        self.root.attributes("-topmost", False)
        self.root.deiconify()
        self.root.update_idletasks()

        hwnd = self.root.winfo_id()
        user32 = self._get_user32()
        self._set_noactivate(True)
        user32.ShowWindow(hwnd, self._SW_SHOWNOACTIVATE)
        user32.SetWindowPos(
            hwnd,
            self._HWND_NOTOPMOST,
            target_x,
            target_y,
            width,
            height,
            self._SWP_NOACTIVATE
            | self._SWP_SHOWWINDOW
            | self._SWP_NOOWNERZORDER,
        )
        self.root.update()
        self._remember_main_geometry(target_x, target_y, width, height)

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
        self.code_var.set("")

        # 解码 4 码暂时不进入常态信息层级，需要排查时再打开调试 UI。
        if self._DEBUG_UI:
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
        self.normalize_input_entry_state()

    def run(self) -> None:
        """运行主循环"""
        self._render_candidates()
        self.root.mainloop()
