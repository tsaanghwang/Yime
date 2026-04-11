"""
剪贴板管理模块

提供剪贴板的读取、写入和清空功能
"""

import tkinter as tk


class ClipboardManager:
    """剪贴板管理器"""

    def __init__(self) -> None:
        """初始化剪贴板管理器"""
        self.root = tk.Tk()
        self.root.withdraw()  # 隐藏主窗口

    def copy(self, text: str) -> None:
        """
        复制文本到剪贴板

        Args:
            text: 要复制的文本
        """
        self.root.clipboard_clear()
        self.root.clipboard_append(text)
        self.root.update()  # 确保剪贴板更新

    def paste(self) -> str:
        """
        从剪贴板粘贴

        Returns:
            剪贴板中的文本，如果为空则返回空字符串
        """
        try:
            return self.root.clipboard_get()
        except tk.TclError:
            return ""

    def clear(self) -> None:
        """清空剪贴板"""
        self.root.clipboard_clear()
        self.root.update()
