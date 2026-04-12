"""
输入管理模块

管理输入状态、累积输入、触发解码等
"""

import time
from typing import Callable, Optional, List, Dict, Any
from dataclasses import dataclass, field


@dataclass
class InputState:
    """输入状态"""
    buffer: str = ""  # 输入缓冲区
    last_key_time: float = 0  # 最后按键时间
    is_composing: bool = False  # 是否正在组合
    total_keys: int = 0  # 总按键数


class InputManager:
    """
    输入管理器

    负责管理输入状态、累积输入、触发解码等
    """

    def __init__(
        self,
        on_candidates_update: Callable[[List[str], str, str, str], None],
        on_input_commit: Callable[[str], None],
        timeout: float = 3.0,
        max_buffer_length: int = 20,
    ) -> None:
        """
        初始化输入管理器

        Args:
            on_candidates_update: 候选词更新回调
                参数：(candidates, pinyin, code, status)
            on_input_commit: 输入提交回调
                参数：(hanzi)
            timeout: 输入超时时间（秒）
            max_buffer_length: 最大缓冲区长度
        """
        self.on_candidates_update = on_candidates_update
        self.on_input_commit = on_input_commit
        self.timeout = timeout
        self.max_buffer_length = max_buffer_length
        self.state = InputState()

        # 候选词列表
        self.current_candidates: List[str] = []

        # 解码器（由主应用设置）
        self.decoder = None

    def set_decoder(self, decoder: Any) -> None:
        """
        设置解码器

        Args:
            decoder: 解码器对象
        """
        self.decoder = decoder

    def process_key(self, key_info: Dict[str, Any]) -> bool:
        """
        处理按键

        Args:
            key_info: 按键信息字典

        Returns:
            True继续传递按键，False拦截按键
        """
        # 检查是否超时
        current_time = time.time()
        if (current_time - self.state.last_key_time) > self.timeout:
            # 超时，清空缓冲区
            self.clear_buffer(notify=False)

        self.state.last_key_time = current_time
        self.state.total_keys += 1

        # 获取按键信息
        key = key_info.get('key', '')
        ascii_char = key_info.get('ascii')
        modifiers = key_info.get('modifiers', {}) or {}

        # 系统快捷键和窗口管理组合键必须直接放行，避免破坏复制、切窗等行为。
        if modifiers.get('ctrl') or modifiers.get('alt') or modifiers.get('win'):
            return True

        # 处理特殊键
        if self._handle_special_key(key):
            return False  # 拦截特殊键

        # 处理数字键选择候选词
        if self._handle_digit_selection(key):
            return False  # 拦截数字键

        # 处理普通字符输入
        if ascii_char is not None:
            # 确保ascii_char是整数
            if isinstance(ascii_char, str):
                if len(ascii_char) == 1:
                    ascii_char = ord(ascii_char)
                else:
                    ascii_char = None

            if ascii_char and 32 <= ascii_char <= 126:
                # 可打印ASCII字符
                self.add_char(chr(ascii_char))
                return False  # 拦截输入字符

        # 其他键继续传递
        return True

    def _handle_special_key(self, key: str) -> bool:
        """
        处理特殊键

        Args:
            key: 按键字符串

        Returns:
            True如果处理了，False否则
        """
        is_composing = bool(self.state.buffer or self.current_candidates)

        # Escape - 清空输入
        if key in ('Escape', 'esc'):
            if is_composing:
                self.clear_buffer()
                return True
            return False

        # Backspace - 删除最后一个字符
        if key in ('Backspace', 'backspace'):
            if self.state.buffer:
                self.backspace()
                return True
            return False

        # Enter/Return - 提交首选候选词
        if key in ('Return', 'Enter', 'enter'):
            if self.current_candidates:
                self.commit_first_candidate()
                return True
            if self.state.buffer:
                self.clear_buffer()
                return True
            return False

        # Space - 提交首选或添加空格
        if key in ('space', 'Space'):
            if self.current_candidates:
                self.commit_first_candidate()
                return True
            # 如果没有候选词，继续传递空格
            return False

        return False

    def _handle_digit_selection(self, key: str) -> bool:
        """
        处理数字键选择候选词

        Args:
            key: 按键字符串

        Returns:
            True如果处理了，False否则
        """
        # 检查是否是数字键
        if key.isdigit() and int(key) > 0:
            index = int(key) - 1
            if index < len(self.current_candidates):
                self.select_candidate(index)
                return True

        return False

    def add_char(self, char: str) -> None:
        """
        添加字符到缓冲区

        Args:
            char: 字符
        """
        # 检查缓冲区长度
        if len(self.state.buffer) >= self.max_buffer_length:
            self.clear_buffer(notify=False)

        self.state.buffer += char
        self.state.is_composing = True

        # 触发候选词更新
        self._update_candidates()

    def backspace(self) -> None:
        """删除最后一个字符"""
        if self.state.buffer:
            self.state.buffer = self.state.buffer[:-1]

            if self.state.buffer:
                self._update_candidates()
            else:
                self.clear_buffer()

    def clear_buffer(self, notify: bool = True) -> None:
        """清空缓冲区"""
        self.state.buffer = ""
        self.state.is_composing = False
        self.current_candidates = []

        # 通知清空候选词
        if notify:
            self.on_candidates_update([], "", "", "输入已清空")

    def select_candidate(self, index: int) -> None:
        """
        选择候选词

        Args:
            index: 候选词索引
        """
        if 0 <= index < len(self.current_candidates):
            hanzi = self.current_candidates[index]

            # 提交输入
            self.on_input_commit(hanzi)

            # 清空缓冲区
            self.clear_buffer()

    def commit_first_candidate(self) -> None:
        """提交首选候选词"""
        if self.current_candidates:
            self.select_candidate(0)

    def get_buffer(self) -> str:
        """
        获取当前缓冲区

        Returns:
            当前输入缓冲区
        """
        return self.state.buffer

    def is_composing(self) -> bool:
        """
        是否正在组合输入

        Returns:
            True如果正在组合，False否则
        """
        return self.state.is_composing

    def get_candidates(self) -> List[str]:
        """
        获取当前候选词列表

        Returns:
            候选词列表
        """
        return self.current_candidates

    def _update_candidates(self) -> None:
        """更新候选词"""
        if not self.decoder:
            self.on_candidates_update([], "", "", "解码器未设置")
            return

        if not self.state.buffer:
            self.on_candidates_update([], "", "", "")
            return

        try:
            # 调用解码器
            canonical_code, active_code, pinyin, candidates, status = (
                self.decoder.decode_text(self.state.buffer)
            )

            # 保存候选词，分页由 UI 层处理
            self.current_candidates = candidates

            # 更新显示
            code_display = ""
            if active_code and canonical_code and active_code != canonical_code:
                code_display = f"{active_code} | 累计: {len(canonical_code)} 码"
            elif active_code:
                code_display = active_code

            self.on_candidates_update(
                self.current_candidates,
                pinyin,
                code_display,
                status,
            )

        except Exception as e:
            self.on_candidates_update([], "", "", f"解码出错: {e}")
