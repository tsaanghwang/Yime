"""
音元输入法 - 改进版

添加全局快捷键功能，优化输入流程
"""

from __future__ import annotations

import sys
import argparse
import ctypes
from pathlib import Path
from typing import Optional

# 添加项目根目录到路径
project_root = Path(__file__).resolve().parent.parent.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

from yime.input_method.core.decoders import (
    CompositeCandidateDecoder,
    build_code_display,
    build_input_outline,
    build_input_visual_map,
    build_physical_input_map,
    project_physical_input,
)
from yime.input_method.ui.candidate_box import CandidateBox
from yime.input_method.utils.clipboard import ClipboardManager
from yime.input_method.utils.keyboard_simulator import KeyboardSimulator
from yime.input_method.utils.window_manager import WindowManager


class InputMethodAppV2:
    """音元输入法 - 改进版（带快捷键）"""

    def __init__(
        self,
        auto_paste: bool = True,
        font_family: str = "YinYuan Regular",
        hotkey: str = "<ctrl>+<shift>+y",
    ) -> None:
        """
        初始化输入法应用

        Args:
            auto_paste: 是否自动粘贴
            font_family: 字体名称
            hotkey: 唤出快捷键
        """
        self.auto_paste = auto_paste
        self.font_family = font_family
        self.hotkey = hotkey

        # 初始化模块
        app_dir = Path(__file__).resolve().parent.parent
        self.decoder = CompositeCandidateDecoder(app_dir)
        self.input_visual_map = build_input_visual_map(app_dir.parent)
        self.physical_input_map = build_physical_input_map(app_dir.parent)
        self.clipboard = ClipboardManager()
        self.keyboard_simulator = KeyboardSimulator()
        self.window_manager = WindowManager()

        # 创建候选框
        self.candidate_box = CandidateBox(
            on_select=self._on_candidate_select,
            font_family=font_family,
            input_display_formatter=self._format_input_outline,
            on_input_change=self._on_input_change,
            on_decode_from_clipboard=self._decode_from_clipboard,
            on_copy_candidate=self._copy_candidate,
            on_close=self._close,
        )

        # 状态变量
        self.own_hwnd = self.candidate_box.root.winfo_id()
        self.last_external_hwnd: Optional[int] = None
        self.last_replace_length = 0

        # 默认为显示状态以便于直接输入测试
        self.candidate_box.show(focus_input=True)

        # 窗口焦点轮询
        self._poll_foreground_window()

        # 设置关闭处理
        self.candidate_box.root.protocol("WM_DELETE_WINDOW", self._close)

        # 快捷键监听器
        self.hotkey_listener = None
        self._setup_hotkey()

    def _format_input_outline(self, text: str) -> str:
        return build_input_outline(text, self.input_visual_map)

    def _format_visible_input(self, text: str) -> str:
        if not text:
            return ""
        if all(ord(char) < 128 for char in text):
            return text
        return build_input_outline(text, self.input_visual_map)

    def _setup_hotkey(self) -> None:
        """设置全局快捷键"""
        try:
            from pynput import keyboard

            def on_activate():
                """快捷键激活"""
                print("快捷键激活：显示候选框")
                self._show_and_focus()

            # 创建快捷键监听器
            self.hotkey_listener = keyboard.GlobalHotKeys({
                self.hotkey: on_activate,
            })

            print(f"全局快捷键已设置: {self.hotkey}")

        except Exception as e:
            print(f"设置快捷键失败: {e}")
            print("将使用手动模式")

    def _show_and_focus(self) -> None:
        """显示候选框并聚焦"""
        # 在主线程中执行
        self.candidate_box.root.after(0, self._do_show_and_focus)

    def _do_show_and_focus(self) -> None:
        """实际显示和聚焦操作"""
        self.candidate_box.show()
        self.candidate_box.input_entry.focus_set()
        self.candidate_box.input_entry.select_range(0, 'end')

    def _poll_foreground_window(self) -> None:
        """轮询前台窗口"""
        foreground = self.window_manager.get_foreground_window()
        if foreground and foreground != self.own_hwnd:
            self.last_external_hwnd = foreground
        self.candidate_box.root.after(250, self._poll_foreground_window)

    def _on_input_change(self, event: Optional[object] = None) -> None:
        """输入变化处理"""
        display_input = self.candidate_box.get_input()
        projected_input = self.candidate_box.get_projected_input()
        if projected_input == display_input:
            projected_input = project_physical_input(display_input, self.physical_input_map)
            self.candidate_box.set_projected_input(projected_input)
        input_text = projected_input
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
        code_display = build_code_display(input_text, canonical_code, active_code)

        self.candidate_box.update_candidates(
            candidates, pinyin, code_display, status
        )

    def _decode_from_clipboard(self) -> None:
        """从剪贴板读取并解码"""
        captured = self.clipboard.paste()
        if not captured:
            self.candidate_box.status_var.set("剪贴板没有可读取文本。")
            return

        self.candidate_box.set_input(
            self._format_visible_input(captured),
            projected_text=captured,
        )
        self.candidate_box.input_entry.focus_set()
        self._on_input_change()

    def _on_candidate_select(self, hanzi: str) -> None:
        """候选词选择处理"""
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

        # 调试期间禁用自动隐藏变成图标，便于直接查看完整 UI
        self.candidate_box._clear_input()
        self.candidate_box.root.after(100, lambda: self.candidate_box.show(focus_input=True))

    def _copy_candidate(self, index: int) -> None:
        """复制候选词"""
        candidates = self.candidate_box.current_candidates
        if 0 <= index < len(candidates):
            hanzi = candidates[index]
            self.clipboard.copy(hanzi)
            self.candidate_box.status_var.set(f"已复制: {hanzi}")

    def _paste_to_previous_window(self, hanzi: str) -> None:
        """粘贴到上一个窗口"""
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
            self.candidate_box.root.after(360, self._refocus_candidate_input)
            return

        # 直接粘贴
        self.candidate_box.root.after(80, self.keyboard_simulator.send_ctrl_v)
        self.candidate_box.root.after(
            180,
            lambda: self.candidate_box.status_var.set(
                f"已回贴到前一个窗口: {hanzi}"
            ),
        )
        self.candidate_box.root.after(240, self._refocus_candidate_input)

    def _refocus_candidate_input(self) -> None:
        """外部编辑动作完成后，将焦点拉回编码输入框。"""
        self.candidate_box.show(focus_input=True)
        self.candidate_box.input_entry.icursor("end")
        self.candidate_box.input_entry.selection_clear()

    def _close(self) -> None:
        """关闭应用"""
        # 停止快捷键监听
        if self.hotkey_listener:
            self.hotkey_listener.stop()

        self.candidate_box._close()

    def run(self) -> None:
        """运行应用"""
        # 启动快捷键监听
        if self.hotkey_listener:
            try:
                self.hotkey_listener.start()
                print(f"快捷键监听已启动: {self.hotkey}")
                print("按快捷键唤出候选框")
            except Exception as e:
                print(f"启动快捷键监听失败: {e}")

        # 显示使用说明
        print("\n使用方法:")
        print(f"1. 按 {self.hotkey.replace('<', '').replace('>', ' ')}唤出候选框")
        print("2. 在输入框中输入音元编码")
        print("3. 选择候选词（数字键或鼠标点击）")
        print("4. 自动复制到剪贴板并粘贴到目标窗口")
        print("5. 或在其他应用输入编码后，复制并点击'读取剪贴板'")
        print("\n按 ESC 清空输入，关闭窗口退出")

        # 运行候选框
        self.candidate_box.run()


def parse_args() -> argparse.Namespace:
    """解析命令行参数"""
    parser = argparse.ArgumentParser(description="音元输入法 - 改进版")
    parser.add_argument(
        "--copy-only",
        action="store_true",
        help="只复制候选字到剪贴板，不自动回贴到上一个窗口。",
    )
    parser.add_argument(
        "--font-family",
        default="Noto Sans",
        help="输入框字体名。默认: Noto Sans",
    )
    parser.add_argument(
        "--hotkey",
        default="<ctrl>+<shift>+y",
        help="唤出快捷键。默认: Ctrl+Shift+Y",
    )
    return parser.parse_args()


def main() -> None:
    """主函数"""
    if ctypes.sizeof(ctypes.c_void_p) == 0:
        raise SystemExit("Windows API 初始化失败")

    args = parse_args()
    app = InputMethodAppV2(
        auto_paste=not args.copy_only,
        font_family=args.font_family,
        hotkey=args.hotkey,
    )
    app.run()


if __name__ == "__main__":
    main()
