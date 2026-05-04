"""
手工输入键位解析模块
负责将 Tkinter 事件结合 Win32 键盘布局信息，翻译为物理字符。
"""
import os
import ctypes
from ctypes import wintypes
import tkinter as tk

from ..utils.modifier_state import is_alt_gr_active

class ManualInputResolver:
    _PRINTABLE_MODIFIER_VK_CODES = {
        "shift": [0x10, 0xA0, 0xA1],
        "ctrl": [0x11, 0xA2, 0xA3],
        "alt": [0x12, 0xA4, 0xA5],
        "alt_r": [0xA5],
        "win": [0x5b, 0x5c],
    }
    _PRINTABLE_VK_TO_PHYSICAL_KEY = {
        **{code: chr(code + 32) for code in range(0x41, 0x5B)},
        **{code: chr(code) for code in range(0x30, 0x3A)},
        0xBA: ";",
        0xBB: "=",
        0xBC: ",",
        0xBD: "-",
        0xBE: ".",
        0xBF: "/",
        0xC0: "`",
        0xDB: "[",
        0xDC: "\\",
        0xDD: "]",
        0xDE: "'",
        0x20: "space",
    }

    @classmethod
    def get_manual_key_modifiers(cls) -> dict[str, bool]:
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
        for name, codes in cls._PRINTABLE_MODIFIER_VK_CODES.items():
            states[name] = any(bool(user32.GetAsyncKeyState(code) & 0x8000) for code in codes)

        states["alt_gr"] = is_alt_gr_active(states)
        return states

    @classmethod
    def normalize_event_physical_key(cls, event: tk.Event) -> str:
        vk_code = int(getattr(event, "keycode", 0) or 0)
        if vk_code in cls._PRINTABLE_VK_TO_PHYSICAL_KEY:
            return cls._PRINTABLE_VK_TO_PHYSICAL_KEY[vk_code]

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

    @classmethod
    def resolve_manual_input_text(cls, event: tk.Event) -> str:
        if os.name != "nt":
            return ""

        vk_code = int(getattr(event, "keycode", 0) or 0)
        if vk_code <= 0:
            return ""

        modifiers = cls.get_manual_key_modifiers()
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
