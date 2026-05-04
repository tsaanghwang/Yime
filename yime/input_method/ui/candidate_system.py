"""
候选框底层窗口系统模块
负责处理 Windows API 调用、透明度、置顶和防抢焦点(NoActivate)设置。
"""
import ctypes
import tkinter as tk

class CandidateWindowSystem:
    _GWL_EXSTYLE = -20
    _GWL_STYLE = -16
    _WS_EX_TOOLWINDOW = 0x00000080
    _WS_EX_APPWINDOW = 0x00040000
    _WS_EX_NOACTIVATE = 0x08000000
    _WS_MAXIMIZEBOX = 0x00010000
    _HWND_TOPMOST = -1
    _SWP_NOMOVE = 0x0002
    _SWP_NOSIZE = 0x0001
    _SWP_NOACTIVATE = 0x0010
    _SWP_FRAMECHANGED = 0x0020

    def __init__(self, root: tk.Tk):
        self.root = root
        self._user32 = None

    def _get_user32(self):
        if self._user32 is None:
            self._user32 = ctypes.windll.user32
        return self._user32

    def get_user32(self):
        return self._get_user32()

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

        self.root.update_idletasks()
        hwnd = self.root.winfo_id()
        user32, get_window_long_ptr, set_window_long_ptr, set_window_pos = self._get_window_style_api()

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
