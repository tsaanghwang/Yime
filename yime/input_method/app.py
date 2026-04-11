"""
音元输入法主应用

整合所有模块，提供完整的输入法功能
"""

from __future__ import annotations

import argparse
import ctypes
from pathlib import Path
from typing import Optional

from .core.decoders import CompositeCandidateDecoder
from .core.keyboard_listener import KeyboardListener
from .core.input_manager import InputManager
from .ui.candidate_box import CandidateBox
from .utils.clipboard import ClipboardManager
from .utils.keyboard_simulator import KeyboardSimulator
from .utils.window_manager import WindowManager


class InputMethodApp:
    """音元输入法主应用"""

    def __init__(
        self,
        auto_paste: bool = True,
        font_family: str = "YinYuan Regular",
    ) -> None:
        """
        初始化输入法应用

        Args:
            auto_paste: 是否自动粘贴到目标窗口
            font_family: 字体名称
        """
        self.auto_paste = auto_paste
        self.font_family = font_family

        # 初始化各模块
        app_dir = Path(__file__).resolve().parent.parent
        self.decoder = CompositeCandidateDecoder(app_dir)
        self.clipboard = ClipboardManager()
        self.keyboard_simulator = KeyboardSimulator()
        self.window_manager = WindowManager()

        # 创建候选框
        self.candidate_box = CandidateBox(
            on_select=self._on_candidate_select,
            font_family=font_family,
        )

        # 重写候选框的方法
        self.candidate_box._on_input_change = self._on_input_change
        self.candidate_box._decode_from_clipboard = self._decode_from_clipboard
        self.candidate_box._copy_candidate = self._copy_candidate

        # 状态变量
        self.own_hwnd = self.candidate_box.root.winfo_id()
        self.last_external_hwnd: Optional[int] = None
        self.last_replace_length = 0
        
        # 创建输入管理器
        self.input_manager = InputManager(
            on_candidates_update=self._on_candidates_update,
            on_input_commit=self._on_input_commit,
        )
        self.input_manager.set_decoder(self.decoder)
        
        # 创建键盘监听器
        self.keyboard_listener: Optional[KeyboardListener] = None
        
        # 启动窗口焦点轮询
        self._poll_foreground_window()
        
        # 设置关闭处理
        self.candidate_box.root.protocol("WM_DELETE_WINDOW", self._close)

    def _poll_foreground_window(self) -> None:
        """轮询前台窗口"""
        foreground = self.window_manager.get_foreground_window()
        if foreground and foreground != self.own_hwnd:
            self.last_external_hwnd = foreground
        self.candidate_box.root.after(250, self._poll_foreground_window)

    def _on_input_change(self, event: Optional[object] = None) -> None:
        """输入变化处理"""
        input_text = self.candidate_box.get_input()
        if not input_text:
            self.candidate_box.update_candidates(
                [],
                "",
                "",
                '连续输入时自动取最近 4 码。请先复制编码，再点"读取剪贴板"。',
            )
            return

        # 解码
        canonical_code, active_code, pinyin, candidates, status = (
            self.decoder.decode_text(input_text)
        )

        # 记录替换长度
        self.last_replace_length = min(4, len(input_text))

        # 更新显示
        code_display = ""
        if active_code and canonical_code and active_code != canonical_code:
            code_display = f"{active_code} | 累计输入: {len(canonical_code)} 码"
        elif active_code:
            code_display = active_code

        self.candidate_box.update_candidates(
            candidates, pinyin, code_display, status
        )

    def _decode_from_clipboard(self) -> None:
        """从剪贴板读取并解码"""
        captured = self.clipboard.paste()
        if not captured:
            self.candidate_box.status_var.set("剪贴板没有可读取文本。")
            return

        self.candidate_box.set_input(captured)
        self.candidate_box.input_entry.focus_set()
        self._on_input_change()

    def _on_candidate_select(self, hanzi: str) -> None:
        """
        候选词选择处理

        Args:
            hanzi: 选中的汉字
        """
        # 复制到剪贴板
        self.clipboard.copy(hanzi)
        self.candidate_box.status_var.set(f"已复制: {hanzi}")

        # 自动粘贴
        if (
            self.auto_paste
            and self.last_external_hwnd
            and self.last_external_hwnd != self.own_hwnd
        ):
            self.candidate_box.root.after(
                50, lambda: self._paste_to_previous_window(hanzi)
            )

        # 清空输入
        self.candidate_box._clear_input()

    def _copy_candidate(self, index: int) -> None:
        """
        复制候选词

        Args:
            index: 候选词索引
        """
        candidates = self.candidate_box.current_candidates
        if 0 <= index < len(candidates):
            hanzi = candidates[index]
            self.clipboard.copy(hanzi)
            self.candidate_box.status_var.set(f"已复制: {hanzi}")

    def _paste_to_previous_window(self, hanzi: str) -> None:
        """
        粘贴到上一个窗口

        Args:
            hanzi: 要粘贴的汉字
        """
        if not self.last_external_hwnd:
            self.candidate_box.status_var.set(
                f"已复制: {hanzi}，未找到上一个窗口"
            )
            return

        # 恢复目标窗口
        self.window_manager.restore_window(self.last_external_hwnd)

        # 如果需要替换已输入的码元
        if self.last_replace_length > 0:
            self.candidate_box.root.after(
                80,
                lambda: self.keyboard_simulator.send_backspace(
                    self.last_replace_length
                ),
            )
            self.candidate_box.root.after(170, self.keyboard_simulator.send_ctrl_v)
            self.candidate_box.root.after(
                280,
                lambda: self.candidate_box.status_var.set(
                    f"已替换前一个窗口中的 {self.last_replace_length} 个编码字符: {hanzi}"
                ),
            )
            return

        # 直接粘贴
        self.candidate_box.root.after(80, self.keyboard_simulator.send_ctrl_v)
        self.candidate_box.root.after(
            180,
            lambda: self.candidate_box.status_var.set(
                f"已回贴到前一个窗口: {hanzi}"
            ),
        )

    def _close(self) -> None:
        """关闭应用"""
        # 停止键盘监听
        if self.keyboard_listener:
            self.keyboard_listener.stop()
        
        self.candidate_box._close()
    
    def _on_candidates_update(
        self,
        candidates: list,
        pinyin: str,
        code: str,
        status: str,
    ) -> None:
        """
        候选词更新回调
        
        Args:
            candidates: 候选词列表
            pinyin: 拼音
            code: 编码
            status: 状态消息
        """
        # 更新候选框显示
        self.candidate_box.update_candidates(candidates, pinyin, code, status)
        
        # 如果有候选词，显示候选框
        if candidates:
            # 获取光标位置并显示
            try:
                x, y = self.window_manager.get_cursor_position()
                self.candidate_box.show(x, y + 20)
            except:
                self.candidate_box.show()
        else:
            self.candidate_box.hide()
    
    def _on_input_commit(self, hanzi: str) -> None:
        """
        输入提交回调
        
        Args:
            hanzi: 要提交的汉字
        """
        # 复制到剪贴板
        self.clipboard.copy(hanzi)
        
        # 自动粘贴到目标窗口
        if (
            self.auto_paste
            and self.last_external_hwnd
            and self.last_external_hwnd != self.own_hwnd
        ):
            self._paste_to_previous_window(hanzi)
    
    def _on_key_press(self, key_info: dict) -> bool:
        """
        键盘按键回调
        
        Args:
            key_info: 按键信息
        
        Returns:
            True继续传递，False拦截
        """
        return self.input_manager.process_key(key_info)
    
    def run(self) -> None:
        """运行应用"""
        # 启动键盘监听
        try:
            self.keyboard_listener = KeyboardListener(
                on_key_press=self._on_key_press,
            )
            self.keyboard_listener.start()
            print("键盘监听已启动，按ESC退出")
        except Exception as e:
            print(f"启动键盘监听失败: {e}")
            print("将使用手动输入模式")
        
        # 运行候选框
        self.candidate_box.run()


def parse_args() -> argparse.Namespace:
    """解析命令行参数"""
    parser = argparse.ArgumentParser(description="音元输入法 Windows 候选框")
    parser.add_argument(
        "--copy-only",
        action="store_true",
        help="只复制候选字到剪贴板，不自动回贴到上一个窗口。",
    )
    parser.add_argument(
        "--font-family",
        default="YinYuan Regular",
        help="输入框字体名。默认: YinYuan Regular",
    )
    return parser.parse_args()


def main() -> None:
    """主函数"""
    if ctypes.sizeof(ctypes.c_void_p) == 0:
        raise SystemExit("Windows API 初始化失败")

    args = parse_args()
    app = InputMethodApp(auto_paste=not args.copy_only, font_family=args.font_family)
    app.run()


if __name__ == "__main__":
    main()
