"""工具模块：剪贴板、窗口管理、键盘模拟。"""

from __future__ import annotations

from importlib import import_module
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from .clipboard import ClipboardManager
    from .keyboard_simulator import KeyboardSimulator
    from .window_manager import WindowManager

__all__ = ["ClipboardManager", "WindowManager", "KeyboardSimulator"]


def __getattr__(name: str) -> Any:
    if name == "ClipboardManager":
        module = import_module(".clipboard", __name__)
        return getattr(module, name)
    if name == "WindowManager":
        module = import_module(".window_manager", __name__)
        return getattr(module, name)
    if name == "KeyboardSimulator":
        module = import_module(".keyboard_simulator", __name__)
        return getattr(module, name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
