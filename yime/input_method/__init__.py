"""
音元输入法 Windows 桌面应用

这个包提供完整的Windows桌面输入法功能，包括：
- 全局键盘监听
- 候选词显示
- 输入处理
- 系统集成
"""

from .app import InputMethodApp, main

__version__ = "1.0.0"
__author__ = "Yime Team"

__all__ = ["InputMethodApp", "main"]
