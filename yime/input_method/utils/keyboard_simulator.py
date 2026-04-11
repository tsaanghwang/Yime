"""
键盘模拟模块

提供模拟键盘输入的功能，包括组合键、单键等
"""

import ctypes
from typing import List


# Windows API常量
VK_CONTROL = 0x11
VK_SHIFT = 0x10
VK_ALT = 0x12
VK_V = 0x56
VK_C = 0x43
VK_X = 0x58
VK_LEFT = 0x25
VK_RIGHT = 0x27
VK_BACK = 0x08
VK_RETURN = 0x0D
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_EXTENDEDKEY = 0x0001


# 加载user32.dll
user32 = ctypes.WinDLL("user32", use_last_error=True)


class KeyboardSimulator:
    """键盘模拟器"""

    @staticmethod
    def _key_press(vk_code: int) -> None:
        """
        按下按键

        Args:
            vk_code: 虚拟键码
        """
        user32.keybd_event(vk_code, 0, 0, 0)

    @staticmethod
    def _key_release(vk_code: int) -> None:
        """
        释放按键

        Args:
            vk_code: 虚拟键码
        """
        user32.keybd_event(vk_code, 0, KEYEVENTF_KEYUP, 0)

    @staticmethod
    def _key_click(vk_code: int) -> None:
        """
        点击按键（按下并释放）

        Args:
            vk_code: 虚拟键码
        """
        KeyboardSimulator._key_press(vk_code)
        KeyboardSimulator._key_release(vk_code)

    @staticmethod
    def send_ctrl_v() -> None:
        """发送Ctrl+V（粘贴）"""
        KeyboardSimulator._key_press(VK_CONTROL)
        KeyboardSimulator._key_click(VK_V)
        KeyboardSimulator._key_release(VK_CONTROL)

    @staticmethod
    def send_ctrl_c() -> None:
        """发送Ctrl+C（复制）"""
        KeyboardSimulator._key_press(VK_CONTROL)
        KeyboardSimulator._key_click(VK_C)
        KeyboardSimulator._key_release(VK_CONTROL)

    @staticmethod
    def send_ctrl_x() -> None:
        """发送Ctrl+X（剪切）"""
        KeyboardSimulator._key_press(VK_CONTROL)
        KeyboardSimulator._key_click(VK_X)
        KeyboardSimulator._key_release(VK_CONTROL)

    @staticmethod
    def send_shift_left(count: int = 1) -> None:
        """
        发送Shift+Left（向左选择）

        Args:
            count: 重复次数
        """
        for _ in range(count):
            KeyboardSimulator._key_press(VK_SHIFT)
            KeyboardSimulator._key_click(VK_LEFT)
            KeyboardSimulator._key_release(VK_SHIFT)

    @staticmethod
    def send_shift_right(count: int = 1) -> None:
        """
        发送Shift+Right（向右选择）

        Args:
            count: 重复次数
        """
        for _ in range(count):
            KeyboardSimulator._key_press(VK_SHIFT)
            KeyboardSimulator._key_click(VK_RIGHT)
            KeyboardSimulator._key_release(VK_SHIFT)

    @staticmethod
    def send_backspace(count: int = 1) -> None:
        """
        发送退格键

        Args:
            count: 重复次数
        """
        for _ in range(count):
            KeyboardSimulator._key_click(VK_BACK)

    @staticmethod
    def send_return() -> None:
        """发送回车键"""
        KeyboardSimulator._key_click(VK_RETURN)

    @staticmethod
    def send_text(text: str) -> None:
        """
        发送文本（通过剪贴板）

        Args:
            text: 要发送的文本
        """
        # 注意：这个方法需要配合剪贴板使用
        # 先将文本复制到剪贴板，然后发送Ctrl+V
        # 这里只发送Ctrl+V，复制到剪贴板由调用者负责
        KeyboardSimulator.send_ctrl_v()

    @staticmethod
    def send_key_sequence(keys: List[int]) -> None:
        """
        发送按键序列

        Args:
            keys: 虚拟键码列表
        """
        for vk_code in keys:
            KeyboardSimulator._key_click(vk_code)
