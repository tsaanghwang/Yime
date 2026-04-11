"""
窗口管理模块

提供Windows窗口的获取、恢复、焦点管理等功能
"""

import ctypes
from ctypes import wintypes
from typing import Optional, Tuple


# Windows API常量
SW_RESTORE = 9
GWL_EXSTYLE = -20
WS_EX_TOOLWINDOW = 0x00000080
WS_EX_APPWINDOW = 0x00040000


# 加载user32.dll
user32 = ctypes.WinDLL("user32", use_last_error=True)


class WindowManager:
    """窗口管理器"""

    @staticmethod
    def get_foreground_window() -> Optional[int]:
        """
        获取前台窗口句柄

        Returns:
            前台窗口句柄，如果没有则返回None
        """
        hwnd = user32.GetForegroundWindow()
        return int(hwnd) if hwnd else None

    @staticmethod
    def restore_window(hwnd: int) -> None:
        """
        恢复并激活窗口

        Args:
            hwnd: 窗口句柄
        """
        user32.ShowWindow(wintypes.HWND(hwnd), SW_RESTORE)
        user32.SetForegroundWindow(wintypes.HWND(hwnd))

    @staticmethod
    def get_window_rect(hwnd: int) -> Tuple[int, int, int, int]:
        """
        获取窗口矩形区域

        Args:
            hwnd: 窗口句柄

        Returns:
            (left, top, right, bottom) 窗口坐标
        """
        rect = wintypes.RECT()
        user32.GetWindowRect(wintypes.HWND(hwnd), ctypes.byref(rect))
        return (rect.left, rect.top, rect.right, rect.bottom)

    @staticmethod
    def get_cursor_position() -> Tuple[int, int]:
        """
        获取光标位置

        Returns:
            (x, y) 光标坐标
        """
        class POINT(ctypes.Structure):
            _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]

        point = POINT()
        user32.GetCursorPos(ctypes.byref(point))
        return (point.x, point.y)

    @staticmethod
    def is_window_visible(hwnd: int) -> bool:
        """
        检查窗口是否可见

        Args:
            hwnd: 窗口句柄

        Returns:
            True如果窗口可见，否则False
        """
        return bool(user32.IsWindowVisible(wintypes.HWND(hwnd)))

    @staticmethod
    def set_window_pos(
        hwnd: int,
        x: int,
        y: int,
        width: Optional[int] = None,
        height: Optional[int] = None,
    ) -> None:
        """
        设置窗口位置和大小

        Args:
            hwnd: 窗口句柄
            x: X坐标
            y: Y坐标
            width: 宽度（可选）
            height: 高度（可选）
        """
        SWP_NOSIZE = 0x0001
        SWP_NOZORDER = 0x0004

        flags = SWP_NOZORDER
        if width is None or height is None:
            flags |= SWP_NOSIZE
            width = 0
            height = 0

        user32.SetWindowPos(
            wintypes.HWND(hwnd),
            0,  # HWND_TOP
            x,
            y,
            width,
            height,
            flags,
        )
