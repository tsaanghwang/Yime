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
GA_ROOT = 2


# 加载user32.dll
user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)


class WindowManager:
    """窗口管理器"""

    _user32 = user32
    _kernel32 = kernel32

    @staticmethod
    def _hwnd_to_int(hwnd: object) -> int:
        value = getattr(hwnd, "value", hwnd)
        return int(value) if value else 0

    @classmethod
    def normalize_window_handle(cls, hwnd: Optional[int]) -> Optional[int]:
        """将窗口句柄归一化到顶层窗口，避免抓到子控件句柄。"""
        normalized = cls._hwnd_to_int(hwnd)
        if not normalized:
            return None

        root = cls._user32.GetAncestor(wintypes.HWND(normalized), GA_ROOT)
        root_normalized = cls._hwnd_to_int(root)
        return root_normalized or normalized

    @classmethod
    def get_foreground_window(cls) -> Optional[int]:
        """
        获取前台窗口句柄

        Returns:
            前台窗口句柄，如果没有则返回None
        """
        hwnd = cls._user32.GetForegroundWindow()
        return cls.normalize_window_handle(hwnd)

    @classmethod
    def restore_window(cls, hwnd: int) -> bool:
        """
        恢复并激活窗口

        Args:
            hwnd: 窗口句柄
        """
        if not hwnd:
            return False

        normalized_target = cls.normalize_window_handle(hwnd)
        if not normalized_target:
            return False

        target_hwnd = int(normalized_target)
        hwnd_value = wintypes.HWND(target_hwnd)
        foreground = cls._user32.GetForegroundWindow()
        if cls._hwnd_to_int(foreground) == target_hwnd:
            cls._user32.ShowWindow(hwnd_value, SW_RESTORE)
            return True

        current_thread_id = cls._kernel32.GetCurrentThreadId()
        foreground_thread_id = 0
        target_thread_id = 0
        attached_threads: list[int] = []

        if foreground:
            foreground_thread_id = cls._user32.GetWindowThreadProcessId(
                foreground,
                None,
            )
        target_thread_id = cls._user32.GetWindowThreadProcessId(hwnd_value, None)

        try:
            for thread_id in (foreground_thread_id, target_thread_id):
                if (
                    thread_id
                    and thread_id != current_thread_id
                    and thread_id not in attached_threads
                ):
                    if cls._user32.AttachThreadInput(current_thread_id, thread_id, True):
                        attached_threads.append(thread_id)

            cls._user32.ShowWindow(hwnd_value, SW_RESTORE)
            cls._user32.BringWindowToTop(hwnd_value)
            cls._user32.SetForegroundWindow(hwnd_value)
            cls._user32.SetActiveWindow(hwnd_value)
            cls._user32.SetFocus(hwnd_value)
        finally:
            for thread_id in reversed(attached_threads):
                cls._user32.AttachThreadInput(current_thread_id, thread_id, False)

        return cls._hwnd_to_int(cls._user32.GetForegroundWindow()) == target_hwnd

    @classmethod
    def get_window_text(cls, hwnd: Optional[int]) -> str:
        normalized = cls.normalize_window_handle(hwnd)
        if not normalized:
            return ""

        buffer = ctypes.create_unicode_buffer(512)
        cls._user32.GetWindowTextW(wintypes.HWND(normalized), buffer, len(buffer))
        return buffer.value.strip()

    @classmethod
    def get_window_class_name(cls, hwnd: Optional[int]) -> str:
        normalized = cls.normalize_window_handle(hwnd)
        if not normalized:
            return ""

        buffer = ctypes.create_unicode_buffer(256)
        cls._user32.GetClassNameW(wintypes.HWND(normalized), buffer, len(buffer))
        return buffer.value.strip()

    @classmethod
    def describe_window(cls, hwnd: Optional[int]) -> str:
        normalized = cls.normalize_window_handle(hwnd)
        if not normalized:
            return "无"

        title = cls.get_window_text(normalized) or "<无标题>"
        class_name = cls.get_window_class_name(normalized) or "<无类名>"
        return f"hwnd={normalized} 标题={title} 类={class_name}"

    @classmethod
    def get_window_keyboard_layout(cls, hwnd: int) -> Optional[int]:
        """获取指定窗口线程当前使用的键盘布局 HKL。"""
        if not hwnd:
            return None

        process_id = wintypes.DWORD(0)
        thread_id = cls._user32.GetWindowThreadProcessId(
            wintypes.HWND(hwnd), ctypes.byref(process_id)
        )
        if not thread_id:
            return None

        layout = cls._user32.GetKeyboardLayout(thread_id)
        return int(layout) if layout else None

    @staticmethod
    def get_layout_language_id(layout: Optional[int]) -> Optional[int]:
        """从 HKL 里取低 16 位语言 ID。"""
        if layout is None:
            return None
        return int(layout) & 0xFFFF

    @classmethod
    def is_english_layout(cls, layout: Optional[int]) -> bool:
        """判断前台窗口是否处于英文键盘布局。"""
        return cls.get_layout_language_id(layout) == 0x0409

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
