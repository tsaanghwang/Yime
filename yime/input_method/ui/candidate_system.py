"""
候选框底层窗口系统模块
负责处理 Windows API 调用、透明度、置顶和防抢焦点(NoActivate)设置。
"""
import ctypes
import tkinter as tk
from ctypes import wintypes

class CandidateWindowSystem:
    _GWL_EXSTYLE = -20
    _GWL_STYLE = -16
    _GWL_WNDPROC = -4
    _WS_EX_TOOLWINDOW = 0x00000080
    _WS_EX_APPWINDOW = 0x00040000
    _WS_EX_NOACTIVATE = 0x08000000
    _WS_MAXIMIZEBOX = 0x00010000
    _HWND_TOPMOST = -1
    _SWP_NOMOVE = 0x0002
    _SWP_NOSIZE = 0x0001
    _SWP_NOACTIVATE = 0x0010
    _SWP_FRAMECHANGED = 0x0020
    _WM_NCRBUTTONDOWN = 0x00A4
    _WM_SYSCOMMAND = 0x0112
    _SC_MOVE = 0xF010
    _HTCAPTION = 2
    _HTSYSMENU = 3
    _HTMAXBUTTON = 9

    _VK_RBUTTON = 0x02

    _WM_MOUSEMOVE = 0x0200
    _WM_RBUTTONUP = 0x0205
    _WM_NCRBUTTONUP = 0x00A5
    _SWP_NOZORDER = 0x0004
    _SWP_SHOWWINDOW = 0x0040

    def __init__(self, root: tk.Tk):
        self.root = root
        self._user32 = None
        self._wndproc_ref = None
        self._default_wndproc = None
        self._subclassed_hwnd = None
        self._custom_drag_active = False
        self._custom_drag_start_x = 0
        self._custom_drag_start_y = 0
        self._custom_drag_win_x = 0
        self._custom_drag_win_y = 0
        self._drag_on_complete = None

    def _get_user32(self):
        if self._user32 is None:
            self._user32 = ctypes.windll.user32
        return self._user32

    def get_user32(self):
        return self._get_user32()

    @classmethod
    def _should_start_nonclient_right_drag(cls, hit_test: int) -> bool:
        return hit_test in {cls._HTCAPTION, cls._HTSYSMENU, cls._HTMAXBUTTON}

    def _handle_wndproc_message(
        self,
        hwnd: int,
        message: int,
        wparam: int,
        lparam: int,
    ) -> bool:
        if message == self._WM_NCRBUTTONDOWN and self._should_start_nonclient_right_drag(wparam):
            return True

        return False
    def enable_nonclient_right_drag(self) -> None:
        self.root.update_idletasks()
        hwnd = int(self.root.winfo_id())
        if not hwnd or self._subclassed_hwnd == hwnd:
            return

        user32 = self._get_user32()
        _user32, get_window_long_ptr, set_window_long_ptr, _set_window_pos = self._get_window_style_api()
        call_window_proc = user32.CallWindowProcW

        lresult_type = ctypes.c_longlong if ctypes.sizeof(ctypes.c_void_p) == 8 else ctypes.c_long
        wndproc_type = ctypes.WINFUNCTYPE(
            lresult_type,
            wintypes.HWND,
            wintypes.UINT,
            wintypes.WPARAM,
            wintypes.LPARAM,
        )
        call_window_proc.restype = lresult_type
        call_window_proc.argtypes = [
            ctypes.c_void_p,
            wintypes.HWND,
            wintypes.UINT,
            wintypes.WPARAM,
            wintypes.LPARAM,
        ]

        default_wndproc = get_window_long_ptr(hwnd, self._GWL_WNDPROC)
        if not default_wndproc:
            return

        self._default_wndproc = default_wndproc

        @wndproc_type
        def window_proc(
            window_handle: wintypes.HWND,
            message: wintypes.UINT,
            wparam: wintypes.WPARAM,
            lparam: wintypes.LPARAM,
        ) -> int:
            if self._handle_wndproc_message(
                int(window_handle),
                int(message),
                int(wparam),
                int(lparam),
            ):
                return 0
            return call_window_proc(
                ctypes.c_void_p(self._default_wndproc),
                window_handle,
                message,
                wparam,
                lparam,
            )

        self._wndproc_ref = window_proc
        set_window_long_ptr(
            hwnd,
            self._GWL_WNDPROC,
            ctypes.cast(window_proc, ctypes.c_void_p),
        )
        self._subclassed_hwnd = hwnd

    def _get_window_style_api(self):
        user32 = self._get_user32()
        if ctypes.sizeof(ctypes.c_void_p) == 8:
            get_window_long_ptr = user32.GetWindowLongPtrW
            set_window_long_ptr = user32.SetWindowLongPtrW
        else:
            get_window_long_ptr = user32.GetWindowLongW
            set_window_long_ptr = user32.SetWindowLongW

        get_window_long_ptr.restype = ctypes.c_void_p
        get_window_long_ptr.argtypes = [ctypes.c_void_p, ctypes.c_int]
        set_window_long_ptr.restype = ctypes.c_void_p
        set_window_long_ptr.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]

        set_window_pos = user32.SetWindowPos
        set_window_pos.restype = ctypes.c_bool
        set_window_pos.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_uint,
        ]

        return user32, get_window_long_ptr, set_window_long_ptr, set_window_pos

    def configure_window_for_global_input(self) -> None:
        if ctypes.sizeof(ctypes.c_void_p) == 0:
            return

        self.enable_nonclient_right_drag()
        self.root.update_idletasks()
        hwnd = self.root.winfo_id()
        _user32, get_window_long_ptr, set_window_long_ptr, set_window_pos = self._get_window_style_api()

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
            0, 0, 0, 0,
            self._SWP_NOMOVE | self._SWP_NOSIZE | self._SWP_NOACTIVATE | self._SWP_FRAMECHANGED
        )

    def set_noactivate(self, enabled: bool) -> None:
        self.enable_nonclient_right_drag()
        self.root.update_idletasks()
        hwnd = self.root.winfo_id()
        _user32, get_window_long_ptr, set_window_long_ptr, set_window_pos = self._get_window_style_api()

        ex_style = int(get_window_long_ptr(hwnd, self._GWL_EXSTYLE) or 0)
        if enabled:
            ex_style |= self._WS_EX_NOACTIVATE
        else:
            ex_style &= ~self._WS_EX_NOACTIVATE

        set_window_long_ptr(hwnd, self._GWL_EXSTYLE, ex_style)
        set_window_pos(
            hwnd,
            self._HWND_TOPMOST,
            0, 0, 0, 0,
            self._SWP_NOMOVE | self._SWP_NOSIZE | self._SWP_NOACTIVATE | self._SWP_FRAMECHANGED
        )
