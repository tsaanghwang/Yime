"""
候选框UI模块

提供候选词显示、选择、窗口管理等功能
"""

import tkinter as tk
from tkinter import ttk
from typing import Callable, List, Optional


class CandidateBox:
    """候选词显示框"""

    def __init__(
        self,
        on_select: Callable[[str], None],
        font_family: str = "YinYuan Regular",
        max_candidates: int = 9,
    ) -> None:
        """
        初始化候选框

        Args:
            on_select: 选择候选词的回调函数
            font_family: 字体名称
            max_candidates: 最大候选词数量
        """
        self.on_select = on_select
        self.font_family = font_family
        self.max_candidates = max_candidates
        self.current_candidates: List[str] = []

        # 创建主窗口
        self.root = tk.Tk()
        self.root.title("音元候选框")
        self.root.geometry("640x280")
        self.root.attributes("-topmost", True)
        self.root.withdraw()  # 初始隐藏

        # 构建UI
        self._build_ui()
        self._bind_keys()

    def _build_ui(self) -> None:
        """构建UI界面"""
        frame = ttk.Frame(self.root, padding=12)
        frame.pack(fill=tk.BOTH, expand=True)

        # 输入框标签
        ttk.Label(frame, text="输入音元码元").pack(anchor=tk.W)

        # 输入框
        self.input_var = tk.StringVar()
        self.input_entry = ttk.Entry(
            frame, textvariable=self.input_var, font=(self.font_family, 14)
        )
        self.input_entry.pack(fill=tk.X, pady=(4, 8))
        self.input_entry.focus_set()
        self.input_entry.bind("<KeyRelease>", self._on_input_change)

        # 拼音显示
        self.pinyin_var = tk.StringVar(value="")
        ttk.Label(
            frame, textvariable=self.pinyin_var, foreground="#0b57d0"
        ).pack(anchor=tk.W)

        # 编码显示
        self.code_var = tk.StringVar(value="")
        ttk.Label(
            frame, textvariable=self.code_var, foreground="#666666"
        ).pack(anchor=tk.W, pady=(4, 0))

        # 候选词标签
        ttk.Label(frame, text="候选汉字").pack(anchor=tk.W, pady=(10, 4))

        # 候选词容器
        self.candidate_frame = ttk.Frame(frame)
        self.candidate_frame.pack(fill=tk.X)

        # 状态显示
        self.status_var = tk.StringVar(
            value='连续输入时自动取最近 4 码。请先复制编码，再点"读取剪贴板"。'
        )
        ttk.Label(
            frame, textvariable=self.status_var, foreground="#666666"
        ).pack(anchor=tk.W, pady=(12, 0))

        # 按钮行
        button_row = ttk.Frame(frame)
        button_row.pack(fill=tk.X, pady=(12, 0))

        ttk.Button(
            button_row, text="读取剪贴板", command=self._decode_from_clipboard
        ).pack(side=tk.LEFT, padx=8)
        ttk.Button(
            button_row, text="复制首选", command=self._copy_first_candidate
        ).pack(side=tk.LEFT)
        ttk.Button(
            button_row, text="粘贴首选", command=self._paste_first_candidate
        ).pack(side=tk.LEFT, padx=8)
        ttk.Button(button_row, text="清空", command=self._clear_input).pack(
            side=tk.LEFT
        )
        ttk.Button(button_row, text="退出", command=self._close).pack(
            side=tk.LEFT, padx=8
        )

    def _bind_keys(self) -> None:
        """绑定快捷键"""
        # 数字键选择候选词
        for index in range(1, 10):
            self.root.bind(
                str(index),
                lambda event, value=index: self._select_candidate_by_index(value - 1),
            )

        # 回车键选择首选
        self.root.bind(
            "<Return>", lambda event: self._select_candidate_by_index(0)
        )

        # ESC键清空
        self.root.bind("<Escape>", lambda event: self._clear_input())

        # Ctrl+Q退出
        self.root.bind("<Control-q>", lambda event: self._close())

    def _on_input_change(self, event: Optional[tk.Event] = None) -> None:
        """输入变化事件处理"""
        # 这个方法由主应用重写
        pass

    def _render_candidates(self) -> None:
        """渲染候选词"""
        # 清空现有候选词
        for child in self.candidate_frame.winfo_children():
            child.destroy()

        # 如果没有候选词
        if not self.current_candidates:
            ttk.Label(self.candidate_frame, text="无候选").pack(anchor=tk.W)
            return

        # 显示候选词按钮
        for index, hanzi in enumerate(self.current_candidates, start=1):
            button = ttk.Button(
                self.candidate_frame,
                text=f"{index}.{hanzi}",
                command=lambda value=index
                - 1: self._select_candidate_by_index(value),
                width=6,
            )
            button.pack(side=tk.LEFT, padx=(0, 6))

    def _clear_input(self) -> None:
        """清空输入"""
        self.input_var.set("")
        self.pinyin_var.set("")
        self.code_var.set("")
        self.current_candidates = []
        self.status_var.set(
            '连续输入时自动取最近 4 码。请先复制编码，再点"读取剪贴板"。'
        )
        self._render_candidates()
        self.input_entry.focus_set()

    def _decode_from_clipboard(self) -> None:
        """从剪贴板读取"""
        # 这个方法由主应用重写
        pass

    def _copy_first_candidate(self) -> None:
        """复制首选候选词"""
        self._copy_candidate(0)

    def _paste_first_candidate(self) -> None:
        """粘贴首选候选词"""
        self._select_candidate_by_index(0)

    def _select_candidate_by_index(self, index: int) -> None:
        """
        选择候选词

        Args:
            index: 候选词索引
        """
        if 0 <= index < len(self.current_candidates):
            hanzi = self.current_candidates[index]
            self.on_select(hanzi)
            self.hide()

    def _copy_candidate(self, index: int) -> None:
        """
        复制候选词

        Args:
            index: 候选词索引
        """
        # 这个方法由主应用重写
        pass

    def _close(self) -> None:
        """关闭窗口"""
        self.root.destroy()

    def show(self, x: Optional[int] = None, y: Optional[int] = None) -> None:
        """
        显示候选框

        Args:
            x: X坐标（可选）
            y: Y坐标（可选）
        """
        if x is not None and y is not None:
            self.root.geometry(f"+{x}+{y}")
        self.root.deiconify()
        self.root.lift()
        self.input_entry.focus_set()

    def hide(self) -> None:
        """隐藏候选框"""
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
        self.current_candidates = candidates[: self.max_candidates]
        self.pinyin_var.set(f"拼音: {pinyin}" if pinyin else "")
        self.code_var.set(f"当前解码 4 码: {code}" if code else "")
        self.status_var.set(status)
        self._render_candidates()

    def get_input(self) -> str:
        """
        获取当前输入

        Returns:
            当前输入的文本
        """
        return self.input_var.get()

    def set_input(self, text: str) -> None:
        """
        设置输入框内容

        Args:
            text: 要设置的文本
        """
        self.input_var.set(text)

    def run(self) -> None:
        """运行主循环"""
        self._render_candidates()
        self.root.mainloop()
